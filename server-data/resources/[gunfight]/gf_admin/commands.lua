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
}

local MODES = { lobby = true, attack = true, redzone = true }
local TEAMS = { A = true, B = true }
local UI_COMMANDES = { editor = true, maps = true, customveh = true }

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

--- Construit la ligne exacte (ex. 'setmode 3 attack', 'give 3 carbine'), ou nil.
function GFAdminCommands.build(command, args)
    local attendu = type(command) == 'string' and ARGS[command] or nil
    if not attendu then return nil end
    if type(args) ~= 'table' then return nil end
    if #args ~= attendu or args[attendu + 1] ~= nil then return nil end

    -- Tout argument positionnel attendu doit être une chaîne.
    for i = 1, attendu do
        if type(args[i]) ~= 'string' then return nil end
    end

    if command == 'setmode' then
        if not idValide(args[1]) or not MODES[args[2]] then return nil end
        return command .. ' ' .. args[1] .. ' ' .. args[2]
    elseif command == 'setteam' then
        if not idValide(args[1]) or not TEAMS[args[2]] then return nil end
        return command .. ' ' .. args[1] .. ' ' .. args[2]
    elseif command == 'resetchar' then
        if not idValide(args[1]) then return nil end
        return command .. ' ' .. args[1]
    elseif command == 'give' then
        local arme = armeValide(args[2])
        if not idValide(args[1]) or not arme then return nil end
        return command .. ' ' .. args[1] .. ' ' .. arme
    end

    -- Commandes sans argument (startround, endmatch, nextzone, endgame,
    -- nextmap, editor, maps, customveh) : la ligne est le nom seul.
    return command
end

--- Vrai uniquement pour les commandes qui ouvrent une autre interface.
function GFAdminCommands.opensUi(command)
    return UI_COMMANDES[command] == true
end
