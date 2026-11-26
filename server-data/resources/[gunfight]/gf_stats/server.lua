-- =============================================================================
--  gf_stats - SERVEUR
--  Écrit les statistiques à vie des joueurs dans MariaDB (via oxmysql).
--
--  Alimenté par deux événements émis par les modes :
--    gf:modeKill   { mode, victim, killer }  killer vaut false si le kill
--                  n'est pas crédité (suicide, coéquipier, hors zone)
--    gf:matchEnded { mode, map, participants = { { src, won }, ... } }
--
--  Table : gf_stats_players (voir docker/db/init/01-schema.sql)
-- =============================================================================

local function execute(query, params)
    local ok, err = pcall(function()
        exports.oxmysql:execute(query, params, function() end)
    end)
    if not ok then
        print(('[gf_stats] requête impossible : %s'):format(tostring(err)))
    end
end

-- Identifiant stable : license en priorité, sinon fivem/steam/discord.
-- L'adresse IP n'est jamais enregistrée.
local function identifierOf(src)
    local fallback
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find('^license:') then return id end
        if not fallback then
            if id:find('^fivem:') or id:find('^steam:') or id:find('^discord:') then
                fallback = id
            end
        end
    end
    return fallback
end

local function nameOf(src)
    return (GetPlayerName(src) or '?'):sub(1, 60)
end

local SQL_DEATH = [[
INSERT INTO gf_stats_players (identifier, display_name, deaths)
VALUES (?, ?, 1)
ON DUPLICATE KEY UPDATE display_name = VALUES(display_name), deaths = deaths + 1
]]

local SQL_KILL = [[
INSERT INTO gf_stats_players (identifier, display_name, kills)
VALUES (?, ?, 1)
ON DUPLICATE KEY UPDATE display_name = VALUES(display_name), kills = kills + 1
]]

local SQL_MATCH = [[
INSERT INTO gf_stats_players (identifier, display_name, matches, wins)
VALUES (?, ?, 1, ?)
ON DUPLICATE KEY UPDATE display_name = VALUES(display_name), matches = matches + 1, wins = wins + VALUES(wins)
]]

AddEventHandler('gf:modeKill', function(data)
    if type(data) ~= 'table' or not data.victim then return end

    local victim = identifierOf(data.victim)
    if victim then execute(SQL_DEATH, { victim, nameOf(data.victim) }) end

    if data.killer then
        local killer = identifierOf(data.killer)
        if killer then execute(SQL_KILL, { killer, nameOf(data.killer) }) end
    end
end)

AddEventHandler('gf:matchEnded', function(data)
    if type(data) ~= 'table' or type(data.participants) ~= 'table' then return end

    for _, p in ipairs(data.participants) do
        if p.src then
            local id = identifierOf(p.src)
            if id then
                execute(SQL_MATCH, { id, nameOf(p.src), p.won and 1 or 0 })
            end
        end
    end
    print(('[gf_stats] partie terminée (%s) : %d joueur(s) enregistré(s)'):format(
        tostring(data.mode), #data.participants))
end)

-- Vérifie la connexion une fois au démarrage (visible dans les logs).
CreateThread(function()
    Wait(2000)
    local ok, err = pcall(function()
        exports.oxmysql:execute('SELECT 1 AS ok', {}, function(result)
            if result then print('[gf_stats] MariaDB connectée, statistiques persistantes actives')
            else print('[gf_stats] MariaDB sans réponse : vérifie mysql_connection_string') end
        end)
    end)
    if not ok then print('[gf_stats] oxmysql indisponible : ' .. tostring(err)) end
end)
