-- =============================================================================
--  gf_core - SHOT VALIDATION (module serveur pur)
--  Validation des tirs reçus via `weaponDamageEvent` : hachage des armes,
--  normalisation des identifiants, préparation des ensembles de loadout et
--  contrôle des dégâts (plafonds, cadence).
--
--  Aucune native FiveM ici : ce module ne lit jamais l'horloge et ne touche
--  qu'aux données qui lui sont fournies. L'appelant (server.lua) injecte
--  `touche.instant` (typiquement GetGameTimer()) et les règles de Config.
--  Cela permet de tester toutes ces règles avec un simple interpréteur Lua.
-- =============================================================================

ShotValidation = {}

local MASQUE_32 = 0xFFFFFFFF

--- Nombre fini, éventuellement entier ou flottant (NaN et infinis exclus).
--- @param valeur any
--- @return boolean
local function estNombreFini(valeur)
    return type(valeur) == 'number' and valeur == valeur and valeur ~= math.huge and valeur ~= -math.huge
end

--- Hache une chaîne avec l'algorithme Jenkins one-at-a-time utilisé par GTA.
--- La casse est ignorée (les majuscules ASCII sont minusculisées avant le
--- hachage) : 'WEAPON_PISTOL' et 'weapon_pistol' donnent le même hash.
--- Chaque étape est masquée sur 32 bits ; le résultat est un entier non signé
--- compris dans [0, 2^32 - 1].
--- @param nom string
--- @return integer hash non signé sur 32 bits
function ShotValidation.joaat(nom)
    if type(nom) ~= 'string' then return 0 end

    local hash = 0
    for i = 1, #nom do
        local octet = nom:byte(i)
        -- Minusculisation ASCII : 'A' (65) .. 'Z' (90) -> 'a' .. 'z'.
        if octet >= 65 and octet <= 90 then octet = octet + 32 end

        hash = (hash + octet) & MASQUE_32
        hash = (hash + (hash << 10)) & MASQUE_32
        hash = hash ~ (hash >> 6)
    end

    hash = (hash + (hash << 3)) & MASQUE_32
    hash = hash ~ (hash >> 11)
    hash = (hash + (hash << 15)) & MASQUE_32
    return hash
end

--- Convertit un hash d'arme (signé ou non) en entier non signé sur 32 bits.
--- Refuse nil, les chaînes, les booléens, les tables, les décimaux, NaN et
--- les infinis. Exemple : -1569615261 -> 2725352035 (WEAPON_UNARMED).
--- @param valeur any
--- @return integer|nil
function ShotValidation.normaliserHash(valeur)
    if not estNombreFini(valeur) then return nil end
    local entier = math.tointeger(valeur)
    if not entier then return nil end
    return entier & MASQUE_32
end

--- Construit un ensemble de hashes d'armes à partir d'une liste de noms.
--- Les entrées qui ne sont pas des chaînes sont ignorées, et une valeur qui
--- n'est pas une table donne une table vide.
--- @param noms table|nil
--- @return table ensemble [hash] = true
function ShotValidation.ensembleArmes(noms)
    local ensemble = {}
    if type(noms) ~= 'table' then return ensemble end

    for _, nom in pairs(noms) do
        if type(nom) == 'string' then
            ensemble[ShotValidation.joaat(nom)] = true
        end
    end
    return ensemble
end

--- Vérifie une touche d'arme.
---
--- `touche` = {
---   arme = data.weaponType,
---   degat = data.weaponDamage,
---   composant = data.hitComponent,
---   instant = data.damageTime ou GetGameTimer() fourni par l'appelant,
--- }
---
--- `regles` = {
---   autorisees = ensemble de hashes ou nil (loadout),
---   toujoursAutorisees = ensemble de hashes (poings, véhicule…),
---   plafonds = { [hash] = { corps = n, tete = n } },
---   composantsTete = { [n] = true },
---   cadences = { [hash] = millisecondes },
---   toleranceMs = n,
--- }
---
--- L'état `etat` est une table indexée par tireur, dont chaque entrée est
--- { arme = hash, instant = nombre }. Il n'est modifié que si la touche est
--- acceptée par la cadence (les armes toujours autorisées ne le sont pas).
---
--- Retourne (ok, raison). `raison` vaut 'ok' quand ok est vrai, sinon
--- 'arme-invalide', 'degat-invalide', 'arme-hors-loadout', 'degat-plafond'
--- ou 'cadence'.
--- @param etat table
--- @param tireur any
--- @param touche table
--- @param regles table|nil
--- @return boolean, string
function ShotValidation.verifierTouche(etat, tireur, touche, regles)
    if type(touche) ~= 'table' then return false, 'arme-invalide' end

    local arme = ShotValidation.normaliserHash(touche.arme)
    if not arme then return false, 'arme-invalide' end

    local degat = touche.degat
    if not estNombreFini(degat) or degat < 0 then return false, 'degat-invalide' end

    regles = type(regles) == 'table' and regles or {}

    -- Poings, véhicule, etc. : contrôlés nulle part, état inchangé.
    if type(regles.toujoursAutorisees) == 'table' and regles.toujoursAutorisees[arme] then
        return true, 'ok'
    end

    -- Un loadout vide (nil) signifie "aucun équipement enregistré" : on ne
    -- filtre pas dans ce cas, pour ne pas bloquer les tirs légitimes.
    if regles.autorisees ~= nil then
        if type(regles.autorisees) ~= 'table' or not regles.autorisees[arme] then
            return false, 'arme-hors-loadout'
        end
    end

    -- Plafond de dégât : la tête utilise son propre plafond lorsqu'il est
    -- défini, et retombe sur le plafond corps sinon.
    if type(regles.plafonds) == 'table' then
        local plafondArme = regles.plafonds[arme]
        if type(plafondArme) == 'table' then
            local estTete = type(regles.composantsTete) == 'table'
                and regles.composantsTete[touche.composant] and true or false
            local maximum = estTete and plafondArme.tete or nil
            if maximum == nil then maximum = plafondArme.corps end

            if estNombreFini(maximum) and degat > maximum then
                return false, 'degat-plafond'
            end
        end
    end

    -- Cadence : on compare uniquement deux touches acceptées consécutives du
    -- même tireur avec la même arme. Un intervalle nul (plusieurs projectiles
    -- d'un même tir) est toléré, un intervalle négatif (désordre réseau) est
    -- accepté sans écraser l'état.
    local precedent = type(etat) == 'table' and etat[tireur] or nil
    local tolerance = estNombreFini(regles.toleranceMs) and regles.toleranceMs or 0
    local instantValide = estNombreFini(touche.instant)
    if type(regles.cadences) == 'table' then
        local cadence = regles.cadences[arme]
        -- Aucune soustraction si un des deux instants n'est pas un nombre fini
        -- (champ réseau inattendu) : la touche est acceptée sans contrôle.
        if estNombreFini(cadence) and type(precedent) == 'table' and precedent.arme == arme
            and instantValide and estNombreFini(precedent.instant) then
            local intervalle = touche.instant - precedent.instant
            if intervalle > 0 and intervalle < cadence - tolerance then
                return false, 'cadence'
            end
            if intervalle < 0 then
                -- Désordre réseau : on ne met pas à jour l'état.
                return true, 'ok'
            end
        end
    end

    -- On ne mémorise qu'un instant fini, sous peine de corrompre l'état pour
    -- les touches suivantes (et de lever une erreur sur la soustraction).
    if not instantValide then return true, 'ok' end
    if type(etat) == 'table' then
        etat[tireur] = { arme = arme, instant = touche.instant }
    end
    return true, 'ok'
end

--- Oublie la dernière touche acceptée d'un tireur (mort, changement de mode…).
--- Ne fait rien quand `etat` n'est pas une table.
--- @param etat table|nil
--- @param tireur any
function ShotValidation.oublier(etat, tireur)
    if type(etat) ~= 'table' then return end
    etat[tireur] = nil
end
