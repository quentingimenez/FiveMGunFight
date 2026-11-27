-- =============================================================================
--  gf_admin - SERVEUR
--  Seule source de vérité du panneau : droits et liste des joueurs sont lus
--  côté serveur. Aucune donnée d'identifiant (license, IP, Discord, nom) ne
--  transite dans les messages, les événements ou les journaux.
-- =============================================================================

local core = exports.gf_core
local RESOURCE = 'gf_admin'
local DERNIERE_DEMANDE = {}  -- [src] = GetGameTimer() de la dernière demande admise
local DELAI_MS = 500

-- Un seul événement réseau, sans argument : tout vient de `source`.
RegisterNetEvent('gf_admin:requestData', function()
    local src = source

    -- Rate-limit 1 requête / 500 ms, AVANT le contrôle admin et pour tout le monde.
    -- Refus silencieux : un non-admin ne peut pas déclencher Notify/denied/print en boucle.
    local maintenant = GetGameTimer()
    if DERNIERE_DEMANDE[src] and maintenant - DERNIERE_DEMANDE[src] < DELAI_MS then
        return
    end
    DERNIERE_DEMANDE[src] = maintenant

    -- Les droits sont vérifiés avant toute lecture de données.
    local okAdmin, admin = pcall(function() return core:IsAdmin(src) end)
    if not okAdmin or admin ~= true then
        core:Notify(src, 'Réservé aux administrateurs.')
        TriggerClientEvent('gf_admin:denied', src)
        print(('[%s] demande refusée : non-administrateur'):format(RESOURCE))
        return
    end

    local players = {}
    for _, valeur in ipairs(GetPlayers()) do
        local id = tonumber(valeur)
        if id then
            local okMode, mode = pcall(function() return core:GetMode(id) end)
            if not okMode then mode = nil end
            local okTeam, team = pcall(function() return core:GetTeam(id) end)
            if not okTeam then team = nil end
            players[#players + 1] = {
                id = id,
                name = GetPlayerName(id),
                mode = mode,
                team = team,
                ping = GetPlayerPing(id),
            }
        end
    end
    table.sort(players, function(a, b) return a.id < b.id end)

    local okCatalogue, catalogue = pcall(function() return core:GetWeaponCatalog() end)
    local weapons = okCatalogue and type(catalogue) == 'table' and catalogue or {}

    TriggerClientEvent('gf_admin:data', src, { players = players, weapons = weapons })
end)

AddEventHandler('playerDropped', function()
    local src = source
    DERNIERE_DEMANDE[src] = nil
end)
