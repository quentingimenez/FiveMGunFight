-- =============================================================================
--  gf_menu - SERVEUR
--  Autorité de l'état affiché dans le menu pause : lecture du mode gf_core et
--  des statistiques gf_stats, puis envoi au client. Aucune donnée ne vient du
--  client : tout part de `source`. Aucun SQL ici : gf_stats seule lit la base.
-- =============================================================================

local RESOURCE = 'gf_menu'

local sessions = {}      -- [src] = { joinedAt } durée de session
local demandesEtat = {}  -- [src] = { lastAt } cadence des demandes d'état
local demandesQuit = {}  -- [src] = { lastAt } cadence des déconnexions
local statsCache = {}    -- [src] = { at, stats } lecture gf_stats mise en cache

local function journaliserRefus(src, evenement, raison)
    print(('[%s] %s refusé pour %s (id %d) : %s'):format(
        RESOURCE, evenement, GetPlayerName(src) or '?', src, raison
    ))
end

local function assurerSession(src)
    local session = sessions[src]
    if not session then
        session = { joinedAt = GetGameTimer() }
        sessions[src] = session
    end
    return session
end

--- Cooldown par joueur. La table d'état est créée ici pour que `lastAt`
--- survive d'une demande à l'autre.
local function autoriser(etat, src, intervalleMs)
    local session = etat[src]
    if not session then
        session = {}
        etat[src] = session
    end
    return GFMenuState.cooldown(session, GetGameTimer(), intervalleMs)
end

-- Version du build déployé : même filtrage que gf_lobby, cette valeur finit
-- dans l'interface. Sans convar, on affiche le libellé de configuration.
local function buildSha()
    local sha = tostring(GetConvar('gf_build_sha', '') or ''):gsub('%s+', '')
    if not sha:match('^[%w._-]+$') then return Config.BuildFallback end
    return sha
end

--- Lit les statistiques au plus une fois par fenêtre de cache. Le garde-fou
--- garantit un seul retour même si gf_stats ne répond jamais (ou deux fois).
local function lireStats(src, callback)
    local maintenant = GetGameTimer()
    local cached = statsCache[src]
    if cached and maintenant - cached.at < Config.StatsCacheMs then
        callback(cached.stats)
        return
    end

    local repondu = false
    local function livrer(stats)
        if repondu then return end
        repondu = true
        statsCache[src] = { at = GetGameTimer(), stats = stats }
        callback(stats)
    end

    local ok, err = pcall(function()
        exports.gf_stats:GetPlayerStats(src, livrer)
    end)
    if not ok then
        print(('[gf_menu] gf_stats:GetPlayerStats: %s'):format(tostring(err)))
        livrer(nil)
        return
    end
    if not repondu then
        SetTimeout(Config.StatsTimeoutMs, function() livrer(nil) end)
    end
end

--- Construit et envoie l'état. Le mode est lu sous pcall : gf_core peut être
--- arrêté indépendamment de gf_menu.
local function envoyerEtat(src)
    local nom = GetPlayerName(src)
    if not nom then return end

    local session = assurerSession(src)
    local okMode, mode = pcall(function()
        return exports.gf_core:GetMode(src)
    end)
    if not okMode then
        print(('[gf_menu] gf_core:GetMode: %s'):format(tostring(mode)))
        mode = nil
    end

    lireStats(src, function(stats)
        -- Le joueur peut partir pendant l'attente de gf_stats : ne rien envoyer
        -- à une session déconnectée.
        if not GetPlayerName(src) then return end
        local ctx = {
            id = src,
            name = nom,
            mode = mode,
            build = buildSha(),
            online = #GetPlayers(),
            maxPlayers = GetConvarInt('sv_maxclients', Config.MaxPlayersFallback),
            stats = stats,
            now = GetGameTimer(),
            joinedAt = session.joinedAt,
        }
        TriggerClientEvent('gf_menu:state', src, GFMenuState.buildState(ctx))
    end)
end

-- ---------------------------------------------------------------- Événements
-- Tout handler vérifie d'abord `source`, puis l'absence d'argument, puis le
-- rate-limit. Chaque refus est journalisé, sans identifiant de licence.

RegisterNetEvent('gf_menu:requestState', function(...)
    local src = source
    if select('#', ...) > 0 then
        journaliserRefus(src, 'gf_menu:requestState', 'arguments inattendus')
        return
    end
    if not GetPlayerName(src) then
        journaliserRefus(src, 'gf_menu:requestState', 'joueur invalide')
        return
    end
    if not autoriser(demandesEtat, src, Config.StateCooldownMs) then
        journaliserRefus(src, 'gf_menu:requestState', 'trop de requêtes')
        return
    end

    envoyerEtat(src)
end)

RegisterNetEvent('gf_menu:quit', function(...)
    local src = source
    if select('#', ...) > 0 then
        journaliserRefus(src, 'gf_menu:quit', 'arguments inattendus')
        return
    end
    if not GetPlayerName(src) then
        journaliserRefus(src, 'gf_menu:quit', 'joueur invalide')
        return
    end
    if not autoriser(demandesQuit, src, Config.QuitCooldownMs) then
        journaliserRefus(src, 'gf_menu:quit', 'trop de requêtes')
        return
    end

    DropPlayer(src, Config.QuitReason)
end)

-- ---------------------------------------------------------------- Cycle de vie

AddEventHandler('playerJoining', function()
    local src = source
    assurerSession(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    sessions[src] = nil
    demandesEtat[src] = nil
    demandesQuit[src] = nil
    statsCache[src] = nil
end)
