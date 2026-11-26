-- =============================================================================
--  gf_core - GARDE DES STATE BAGS (module serveur pur)
--  Aucune native FiveM ici : ce module ne lit aucun state bag, il décide
--  seulement quoi faire d'une valeur reçue par rapport à la vérité du serveur.
--  `decider` compare la valeur annoncée (state bag, potentiellement forgée par
--  le client) à la valeur tenue par le serveur, et dit s'il faut l'accepter ou
--  rétablir la valeur serveur. Aucun effet de bord : testable avec Lua seul.
--
--  Signalement : `signalable` limite en débit les signalements d'anomalie
--  (événement `gf:anomalie` et print), par joueur et par clé. Le rétablissement
--  de la valeur serveur, lui, reste SYSTÉMATIQUE et IMMÉDIAT : cette fonction
--  ne décide que du journal, jamais de la correction. Elle tient le compte des
--  rétablissements non signalés pour les restituer au prochain signalement.
-- =============================================================================

GardeEtat = {}

-- Types de normalisation par clé de state bag connue :
--   'booleen' : true si la valeur est vraie au sens Lua (nil et false sont faux) ;
--   'valeur'  : la valeur est conservée telle quelle, nil compris.
-- Une clé absente de cette table est inconnue : on l'ignore (elle n'est pas
-- sous la responsabilité de ce garde-fou).
GardeEtat.CLES = {
    gf_protected = 'booleen',
    gf_team = 'valeur',
    gf_mode = 'valeur',
}

--- Normalise une valeur selon le type déclaré pour la clé.
--- @param cle string Clé de state bag
--- @param valeur any Valeur à normaliser
--- @return any|nil Valeur normalisée, ou nil si la clé est inconnue
function GardeEtat.normaliser(cle, valeur)
    local typeCle = GardeEtat.CLES[cle]
    if typeCle == nil then return nil end

    if typeCle == 'booleen' then
        -- En Lua, seuls nil et false sont faux ; toute autre valeur est vraie.
        return valeur ~= nil and valeur ~= false
    end

    -- typeCle == 'valeur' : on renvoie la valeur telle quelle, nil compris.
    return valeur
end

--- Décide de l'action à prendre face à une valeur reçue d'un state bag.
--- @param cle string Clé de state bag
--- @param valeurRecue any Valeur annoncée par le state bag (non fiable)
--- @param valeurServeur any Valeur tenue par le serveur (vérité)
--- @return string 'ignorer' (clé inconnue), 'ok' (concorde) ou 'retablir'
function GardeEtat.decider(cle, valeurRecue, valeurServeur)
    if GardeEtat.CLES[cle] == nil then return 'ignorer' end

    local recue = GardeEtat.normaliser(cle, valeurRecue)
    local serveur = GardeEtat.normaliser(cle, valeurServeur)
    if recue == serveur then return 'ok' end
    return 'retablir'
end

--- Extrait l'identifiant numérique d'un joueur à partir d'un nom de state bag.
--- Accepte uniquement 'player:<entier>' (ex. 'player:12') ; refuse toute autre
--- forme, y compris 'player:12x', 'player:', 'entity:5', nil et les nombres.
--- Le motif est ancré (^…$) pour refuser les suffixes.
--- @param bagName any Nom du state bag
--- @return integer|nil Identifiant joueur, ou nil si le nom est invalide
function GardeEtat.joueurDuSac(bagName)
    if type(bagName) ~= 'string' then return nil end

    local chiffres = bagName:match('^player:(%d+)$')
    if not chiffres then return nil end

    local nombre = tonumber(chiffres)
    if not nombre then return nil end
    return math.tointeger(nombre)
end

local function estNombreFini(valeur)
    return type(valeur) == 'number' and valeur == valeur
        and valeur ~= math.huge and valeur ~= -math.huge
end

--- Décide si une anomalie doit être signalée pour le couple (src, cle).
--- L'état est une table fournie par l'appelant, structurée ainsi :
---   etat[src][cle] = { dernier = instant du dernier signalement, ignores = N }
--- `maintenant` vient de l'appelant (GetGameTimer() côté serveur), ce qui rend
--- la fonction testable sans attendre. Un couple est signalé au plus une fois
--- par intervalle de `intervalleMs` millisecondes ; à intervalle exactement
--- écoulé (maintenant - dernier >= intervalleMs), le signalement est autorisé.
--- Les rétablissements non signalés sont comptés et rendus au prochain
--- signalement, sans jamais retarder le rétablissement lui-même.
--- Retourne true, ignores (0 au premier signalement) ou false.
--- @param etat table État mutable fourni par l'appelant
--- @param src number Identifiant joueur
--- @param cle string Clé de state bag
--- @param maintenant number Instant courant (millisecondes)
--- @param intervalleMs number Intervalle minimal entre deux signalements
--- @return boolean Autorisation du signalement (false si entrée invalide)
--- @return number|nil Nombre de rétablissements non signalés (si autorisé)
function GardeEtat.signalable(etat, src, cle, maintenant, intervalleMs)
    -- Validation défensive : aucune entrée invalide ne modifie l'état.
    if type(etat) ~= 'table' then return false end
    if not estNombreFini(src) then return false end
    if type(cle) ~= 'string' then return false end
    if not estNombreFini(maintenant) then return false end
    if not estNombreFini(intervalleMs) or intervalleMs < 0 then return false end

    local joueur = etat[src]
    if type(joueur) ~= 'table' then
        joueur = {}
        etat[src] = joueur
    end

    local entree = joueur[cle]
    if type(entree) ~= 'table' then
        entree = {}
        joueur[cle] = entree
    end

    local dernier = entree.dernier
    local ignores = entree.ignores
    if type(ignores) ~= 'number' then ignores = 0 end

    if estNombreFini(dernier) and (maintenant - dernier) < intervalleMs then
        -- Signalement refusé : l'horodatage ne bouge pas, on compte l'écriture.
        entree.ignores = ignores + 1
        return false
    end

    -- Signalement autorisé : on mémorise l'instant et on restitue le cumul.
    entree.dernier = maintenant
    entree.ignores = 0
    return true, ignores
end

--- Oublie toutes les entrées d'un joueur (toutes ses clés et ses compteurs),
--- typiquement à la déconnexion. Ne touche pas aux autres joueurs.
--- @param etat table État mutable fourni par l'appelant
--- @param src number|nil Identifiant joueur
function GardeEtat.oublier(etat, src)
    if type(etat) ~= 'table' or src == nil then return end
    etat[src] = nil
end
