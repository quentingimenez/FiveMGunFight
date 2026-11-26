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

--- Lit les statistiques d'un joueur (lecture seule, hors chemin chaud).
--- callback(stats) est TOUJOURS appelé exactement une fois.
--- stats = { kills, deaths, matches, wins, memberSince } ou nil si inconnu.
--- L'identifiant complet ne sort jamais de cette ressource ni des logs.
exports('GetPlayerStats', function(src, callback)
    if type(callback) ~= 'function' then return end

    local function livrer(stats)
        callback(stats)
    end

    if type(src) ~= 'number' or not GetPlayerName(src) then
        livrer(nil)
        return
    end

    local identifiant = identifierOf(src)
    if not identifiant then
        livrer(nil)
        return
    end

    local repondu = false
    local function repondre(stats)
        if repondu then return end
        repondu = true
        livrer(stats)
    end

    local requete = [[
        SELECT kills, deaths, matches, wins,
               DATE_FORMAT(first_seen, '%d/%m/%Y') AS member_since
        FROM gf_stats_players WHERE identifier = ?
    ]]

    local ok, err = pcall(function()
        exports.oxmysql:single(requete, { identifiant }, function(ligne)
            if type(ligne) ~= 'table' then
                repondre(nil)
                return
            end
            repondre({
                kills = tonumber(ligne.kills) or 0,
                deaths = tonumber(ligne.deaths) or 0,
                matches = tonumber(ligne.matches) or 0,
                wins = tonumber(ligne.wins) or 0,
                memberSince = ligne.member_since or nil,
            })
        end)
    end)
    if not ok then
        print(('[gf_stats] lecture des statistiques impossible : %s'):format(tostring(err)))
        repondre(nil)
    end
end)
