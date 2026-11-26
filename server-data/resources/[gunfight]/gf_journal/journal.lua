-- =============================================================================
--  gf_journal - JOURNAL (module serveur pur)
--  Aucune native FiveM ici : le serveur (server.lua) se charge d'écrire les
--  lots de lignes et de les envoyer à la base. Ce module ne fait que valider,
--  tamponner, encoder en JSON et fabriquer des identifiants : il peut donc
--  être testé avec un simple interpréteur Lua 5.4.
-- =============================================================================

Journal = {}

local PROFONDEUR_MAX = 32

--- Vrai pour un nombre fini (ni NaN, ni infini).
--- @param valeur any
--- @return boolean
local function estNombreFini(valeur)
    return type(valeur) == 'number' and valeur == valeur and valeur ~= math.huge and valeur ~= -math.huge
end

--- Vrai pour une chaîne non vide (après élimination des espaces autour).
--- @param valeur any
--- @return boolean
local function estChaineUtile(valeur)
    return type(valeur) == 'string' and valeur:match('%S') ~= nil
end

-- ---------------------------------------------------------------------------
-- Tampon de lignes
-- ---------------------------------------------------------------------------

--- Crée un tampon vide : `lignes` dans l'ordre d'arrivée, `rejetees` pour les
--- lignes refusées.
--- @return table
function Journal.nouveau()
    return { lignes = {}, rejetees = 0 }
end

--- Ajoute une ligne valide au tampon.
---
--- Une ligne est `{ match_id, mode, manche, t_ms, type, donnees = table }`.
--- Sont refusées : une ligne qui n'est pas une table, un `mode` ou un `type`
--- qui n'est pas une chaîne non vide, et un `t_ms` qui n'est pas un nombre
--- fini. `match_id` et `manche` peuvent être nil ; `donnees` nil devient `{}`.
--- La ligne fournie n'est modifiée que pour son champ `donnees` (une copie
--- est stockée dans le tampon).
---
--- @param tampon table
--- @param ligne any
--- @return boolean accepte
function Journal.ajouter(tampon, ligne)
    if type(tampon) ~= 'table' or type(tampon.lignes) ~= 'table' then return false end
    if type(ligne) ~= 'table' then
        if type(tampon.rejetees) == 'number' then
            tampon.rejetees = tampon.rejetees + 1
        end
        return false
    end

    if not estChaineUtile(ligne.mode) or not estChaineUtile(ligne.type) or not estNombreFini(ligne.t_ms) then
        tampon.rejetees = (type(tampon.rejetees) == 'number' and tampon.rejetees or 0) + 1
        return false
    end

    local copie = {
        match_id = ligne.match_id,
        mode = ligne.mode,
        manche = ligne.manche,
        t_ms = ligne.t_ms,
        type = ligne.type,
        donnees = ligne.donnees,
    }
    if copie.donnees == nil then copie.donnees = {} end

    tampon.lignes[#tampon.lignes + 1] = copie
    return true
end

--- Retire et retourne au plus `max` lignes du tampon, dans l'ordre d'arrivée.
--- Un `max` qui n'est pas un entier strictement positif donne une liste vide.
--- @param tampon table
--- @param max any
--- @return table
function Journal.extraireLot(tampon, max)
    local lot = {}
    if type(tampon) ~= 'table' or type(tampon.lignes) ~= 'table' then return lot end

    -- `max` doit être un nombre entier : une chaîne même numérique est refusée.
    if type(max) ~= 'number' then return lot end
    local entier = math.tointeger(max)
    if not entier or entier <= 0 then return lot end

    local restant = #tampon.lignes
    local aPrendre = entier < restant and entier or restant
    for _ = 1, aPrendre do
        lot[#lot + 1] = table.remove(tampon.lignes, 1)
    end
    return lot
end

-- ---------------------------------------------------------------------------
-- Encodage JSON (déterministe, sans cycles)
-- ---------------------------------------------------------------------------

local ECHAPPEMENTS = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

--- Échappe une chaîne pour JSON. Les octets UTF-8 (>= 0x20) passent tels
--- quels ; seuls les caractères de contrôle sont transformés en `\u00XX`.
--- @param chaine string
--- @return string
local function encoderChaine(chaine)
    return (chaine:gsub('[\0\1-\31\\"]', function(caractere)
        local remplacement = ECHAPPEMENTS[caractere]
        if remplacement then return remplacement end
        return ('\\u%04X'):format(caractere:byte())
    end))
end

--- Formate un nombre JSON : les entiers n'ont pas de décimale, les flottants
--- gardent un point (avec un `0` final si nécessaire).
--- @param nombre number
--- @return string
local function encoderNombre(nombre)
    -- `math.type` distingue les entiers Lua des flottants, y compris 0.0.
    if math.type(nombre) == 'integer' then return tostring(nombre) end

    local texte = ('%.14g'):format(nombre)
    -- Garantit un point décimal pour les flottants, même après 'g'.
    if not texte:match('[%.eE]') then texte = texte .. '.0' end
    return texte
end

--- Vrai si la table est un tableau séquentiel sans trou (clés 1..n).
--- @param tableValeur table
--- @return boolean
local function estTableau(tableValeur)
    -- Une table vide est un objet vide `{}`, pas une liste `[]`.
    if next(tableValeur) == nil then return false end
    local compteur = 0
    for cle, _ in pairs(tableValeur) do
        if type(cle) ~= 'number' or math.type(cle) ~= 'integer' or cle < 1 then return false end
        compteur = compteur + 1
    end
    return compteur == #tableValeur
end

--- Clés d'un objet, triées pour rendre l'encodage déterministe.
--- @param tableValeur table
--- @return table
local function clefsTriees(tableValeur)
    local cles = {}
    for cle, _ in pairs(tableValeur) do cles[#cles + 1] = cle end
    table.sort(cles, function(a, b) return tostring(a) < tostring(b) end)
    return cles
end

--- Encode récursivement une valeur JSON.
--- @param valeur any
--- @param profondeur integer
--- @param enCours table tables déjà en cours d'encodage (détection de cycles)
--- @return string
local function encoderRecursif(valeur, profondeur, enCours)
    if valeur == nil then return 'null' end

    local genre = type(valeur)
    if genre == 'boolean' then
        return valeur and 'true' or 'false'
    elseif genre == 'number' then
        if not estNombreFini(valeur) then return 'null' end
        return encoderNombre(valeur)
    elseif genre == 'string' then
        return '"' .. encoderChaine(valeur) .. '"'
    elseif genre ~= 'table' then
        -- Fonction, thread, userdata : type non prévu par JSON.
        return 'null'
    end

    if profondeur > PROFONDEUR_MAX then return 'null' end
    if enCours[valeur] then return 'null' end
    enCours[valeur] = true

    local resultat
    if estTableau(valeur) then
        local morceaux = {}
        for i = 1, #valeur do
            morceaux[i] = encoderRecursif(valeur[i], profondeur + 1, enCours)
        end
        resultat = '[' .. table.concat(morceaux, ',') .. ']'
    else
        local cles = clefsTriees(valeur)
        local morceaux = {}
        for i = 1, #cles do
            local cle = cles[i]
            morceaux[i] = ('"%s":%s'):format(
                encoderChaine(tostring(cle)),
                encoderRecursif(valeur[cle], profondeur + 1, enCours)
            )
        end
        resultat = '{' .. table.concat(morceaux, ',') .. '}'
    end

    enCours[valeur] = nil
    return resultat
end

--- Encode une valeur en JSON valide. Protège contre les cycles et limite la
--- profondeur ; les types non prévus deviennent `null`.
--- @param valeur any
--- @return string
function Journal.encoderJson(valeur)
    local ok, resultat = pcall(encoderRecursif, valeur, 1, {})
    if not ok then return 'null' end
    return resultat
end

-- ---------------------------------------------------------------------------
-- Identifiants de match
-- ---------------------------------------------------------------------------

--- Fabrique un identifiant de match court et lisible, par exemple
--- `attack-1764150000-3`. Le mode est nettoyé (lettres, chiffres, `_` et `-`
--- seulement), avec `match` comme repli ; le résultat est tronqué à 40
--- caractères. Les nombres sont convertis avec `math.floor(tonumber(x) or 0)` ;
--- les valeurs non finies (NaN, infinis) sont ramenées à zéro.
--- Retourne toujours une chaîne, quelles que soient les entrées.
--- @param mode any
--- @param horodatageSecondes any
--- @param compteur any
--- @return string
function Journal.nouvelIdMatch(mode, horodatageSecondes, compteur)
    local propre = type(mode) == 'string' and mode:gsub('[^%w_%-]', '') or ''
    if propre == '' then propre = 'match' end

    -- Les nombres non finis (NaN, infinis) sont ramenés à zéro pour que le
    -- formatage avec %d ne puisse jamais lever d'erreur.
    local function entierOuZero(valeur)
        local nombre = tonumber(valeur)
        if not estNombreFini(nombre) then return 0 end
        return math.floor(nombre)
    end

    local horodatage = entierOuZero(horodatageSecondes)
    local index = entierOuZero(compteur)

    local ok, identifiant = pcall(string.format, '%s-%d-%d', propre, horodatage, index)
    if not ok then return 'match-0-0' end
    return identifiant:sub(1, 40)
end

return Journal
