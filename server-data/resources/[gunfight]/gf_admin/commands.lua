-- =============================================================================
--  gf_admin - COMMANDES (shared_script, Lua pur)
--  Liste blanche des commandes du panneau. `build` renvoie la ligne exacte à
--  exécuter ou nil si la commande est refusée. Aucune native FiveM ici, aucune
--  dépendance à Config : ce module est partagé par le client et le serveur.
-- =============================================================================

GFAdminCommands = {}

-- Nombre d'arguments positionnels attendus par commande.
local ARGS = {
    setmode = 2,
    setteam = 2,
    resetchar = 1,
    give = 2,
    startround = 0,
    endmatch = 0,
    nextzone = 0,
    endgame = 0,
    nextmap = 0,
    editor = 0,
    maps = 0,
    customveh = 0,
    -- kick accepte une raison optionnelle (1 ou 2 arguments), traitée à part.
    kick = -1,
    -- spectate accepte 0 ou 1 argument (id), traité à part.
    spectate = -1,
    ['goto'] = 1,  -- mot réservé Lua : toujours comme clé de chaîne
    bring = 1,
    heal = 1,
    freeze = 1,
    announce = 1,
}

local MODES = { lobby = true, attack = true, redzone = true }
local TEAMS = { A = true, B = true }
local UI_COMMANDES = { editor = true, maps = true, customveh = true, spectate = true }

--- Identifiant joueur : chaîne correspondant à ^[1-9][0-9]*$
--- (entier positif, sans signe, sans zéro initial, sans espace).
local function idValide(valeur)
    return type(valeur) == 'string' and valeur:match('^[1-9][0-9]*$') ~= nil
end

--- Arme : mise en minuscules AVANT le contrôle, puis ^[a-z0-9_]+$ sur 1 à 48
--- caractères. Renvoie l'arme normalisée, ou nil si elle est invalide.
local function armeValide(valeur)
    if type(valeur) ~= 'string' then return nil end
    local arme = valeur:lower()
    if #arme < 1 or #arme > 48 then return nil end
    if not arme:match('^[a-z0-9_]+$') then return nil end
    return arme
end

--- Nettoyage local du texte libre (identique à celui du serveur, sans dépendance).
local function nettoyerTexte(texte, max)
    if type(texte) ~= 'string' then return '' end
    local propre = texte:gsub('%c', ' '):gsub('[;|\\`"]', '')
    propre = propre:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if max and #propre > max then propre = propre:sub(1, max) end
    return propre
end

--- Garde finale : aucune ligne ne doit contenir de contrôle, ';' ou saut de ligne.
local function lignePropre(ligne)
    if type(ligne) ~= 'string' then return false end
    return ligne:find('[%c;]') == nil
end

--- Toutes les lignes passent par ici, y compris celles des commandes historiques.
local function finir(ligne)
    if not lignePropre(ligne) then return nil end
    return ligne
end

--- Construit la ligne exacte (ex. 'setmode 3 attack', 'give 3 carbine'), ou nil.
function GFAdminCommands.build(command, args)
    local attendu = type(command) == 'string' and ARGS[command] or nil
    if not attendu then return nil end
    if type(args) ~= 'table' then return nil end

    -- kick : 1 ou 2 arguments, le second étant une raison optionnelle.
    if command == 'kick' then
        if #args < 1 or #args > 2 or args[3] ~= nil then return nil end
        if type(args[1]) ~= 'string' or not idValide(args[1]) then return nil end
        if args[2] ~= nil and type(args[2]) ~= 'string' then return nil end
        local ligne = 'kick ' .. args[1]
        if args[2] ~= nil then
            local raison = nettoyerTexte(args[2], 80)
            if raison ~= '' then ligne = ligne .. ' ' .. raison end
        end
        return finir(ligne)
    end

    -- spectate : aucun argument (arrêt) ou exactement un id positionnel [1].
    -- Comptage des clés via pairs : fiable même sur une table trouée.
    if command == 'spectate' then
        local nb = 0
        for cle in pairs(args) do
            nb = nb + 1
            if cle ~= 1 then return nil end
        end
        if nb == 0 then return finir('spectate') end
        if nb ~= 1 or not idValide(args[1]) then return nil end
        return finir('spectate ' .. args[1])
    end

    if #args ~= attendu or args[attendu + 1] ~= nil then return nil end

    -- Tout argument positionnel attendu doit être une chaîne.
    for i = 1, attendu do
        if type(args[i]) ~= 'string' then return nil end
    end

    -- Actions d'administration sur un joueur.
    if command == 'goto' or command == 'bring'
        or command == 'heal' or command == 'freeze' then
        if not idValide(args[1]) then return nil end
        return finir(command .. ' ' .. args[1])
    elseif command == 'announce' then
        local texte = nettoyerTexte(args[1])
        if #texte < 1 or #texte > 120 then return nil end
        return finir('announce ' .. texte)
    end

    if command == 'setmode' then
        if not idValide(args[1]) or not MODES[args[2]] then return nil end
        return finir(command .. ' ' .. args[1] .. ' ' .. args[2])
    elseif command == 'setteam' then
        if not idValide(args[1]) or not TEAMS[args[2]] then return nil end
        return finir(command .. ' ' .. args[1] .. ' ' .. args[2])
    elseif command == 'resetchar' then
        if not idValide(args[1]) then return nil end
        return finir(command .. ' ' .. args[1])
    elseif command == 'give' then
        local arme = armeValide(args[2])
        if not idValide(args[1]) or not arme then return nil end
        return finir(command .. ' ' .. args[1] .. ' ' .. arme)
    end

    -- Commandes sans argument (startround, endmatch, nextzone, endgame,
    -- nextmap, editor, maps, customveh) : la ligne est le nom seul.
    return finir(command)
end

--- Vrai uniquement pour les commandes qui ouvrent une autre interface.
function GFAdminCommands.opensUi(command)
    return UI_COMMANDES[command] == true
end
