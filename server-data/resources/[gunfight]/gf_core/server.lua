-- =============================================================================
--  gf_core - SERVEUR
--  Rôle : savoir dans quel mode est chaque joueur, le faire apparaître,
--  valider les morts/kills et bloquer les tirs interdits (coéquipiers, lobby).
--
--  Événements émis (pour les modes de jeu, côté serveur) :
--    gf:modeJoined (src, mode)          un joueur entre dans un mode
--    gf:modeLeft   (src, mode)          un joueur quitte un mode (ou se déconnecte)
--    gf:playerKilled (victim, killer, weaponHash, mode)   killer peut être nil
-- =============================================================================

local Modes = {}      -- [src] = 'lobby' | 'attack' | 'redzone'
local lastDeath = {}  -- [src] = GetGameTimer() de la dernière mort (anti doublon)

-- ---------------------------------------------------------------- Utilitaires
local function getMode(src)
    return Modes[src]
end

local function playersInMode(mode)
    local list = {}
    for src, m in pairs(Modes) do
        if m == mode then list[#list + 1] = src end
    end
    return list
end

local function isAdmin(src)
    return src == 0 or IsPlayerAceAllowed(src, Config.AdminAce)
end

local function setProtected(src, on)
    on = on and true or false
    Player(src).state:set('gf_protected', on, true)
    TriggerClientEvent('gf_core:setProtected', src, on)
end

local function freeze(src, on)
    TriggerClientEvent('gf_core:freeze', src, on and true or false)
end

--- Fait apparaître un joueur.
--- opts = { x, y, z, heading, loadout = 'attack'|'redzone'|nil,
---          protected = bool, freeze = bool, spectator = bool }
local function spawn(src, opts)
    Player(src).state:set('gf_protected', (opts.protected or opts.spectator) and true or false, true)
    TriggerClientEvent('gf_core:spawn', src, opts)
end

local function notify(src, msg)
    TriggerClientEvent('chat:addMessage', src, { color = { 255, 200, 0 }, args = { 'Gunfight', msg } })
end

local function spawnLobby(src)
    local l = Config.Lobby
    spawn(src, {
        x = l.x + math.random(-6, 6), y = l.y + math.random(-6, 6), z = l.z,
        heading = l.heading, protected = true,
    })
    TriggerClientEvent('gf_ui:hud', src, {
        title = 'Lobby',
        subtitle = '/attack  →  Attaque de zone     •     /redzone  →  Redzone',
    })
end

--- Change le mode d'un joueur. Retourne true si le changement a eu lieu.
local function setMode(src, mode)
    local def = Config.Modes[mode]
    if not def then return false end
    if def.resource and GetResourceState(def.resource) ~= 'started' then
        notify(src, ('Le mode %s est indisponible pour le moment.'):format(def.label))
        return false
    end

    local old = Modes[src]
    if old == mode then return false end

    if old then TriggerEvent('gf:modeLeft', src, old) end

    Modes[src] = mode
    local state = Player(src).state
    state:set('gf_mode', mode, true)
    state:set('gf_team', nil, true)
    SetPlayerRoutingBucket(src, def.bucket)

    TriggerClientEvent('gf_ui:hud', src, nil)
    TriggerClientEvent('gf_ui:scoreboard', src, nil)
    TriggerClientEvent('gf_core:modeChanged', src, mode)

    if mode == 'lobby' then
        spawnLobby(src)
    end

    TriggerEvent('gf:modeJoined', src, mode)
    return true
end

-- ---------------------------------------------------------------- Exports
exports('SetMode', setMode)
exports('GetMode', getMode)
exports('GetPlayersInMode', playersInMode)
exports('Spawn', spawn)
exports('SetProtected', setProtected)
exports('Freeze', freeze)
exports('IsAdmin', isAdmin)
exports('Notify', notify)

-- ---------------------------------------------------------------- Démarrage
CreateThread(function()
    -- Pas de piétons ni de voitures de la circulation dans les mondes de jeu
    for _, def in pairs(Config.Modes) do
        SetRoutingBucketPopulationEnabled(def.bucket, false)
    end
end)

-- Le client prévient quand il est prêt (fin du chargement)
RegisterNetEvent('gf_core:ready', function()
    local src = source
    if Modes[src] then return end

    local ids = {}
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if not id:find('^ip:') then ids[#ids + 1] = id end
    end
    print(('[gf_core] %s connecté. Identifiants : %s'):format(GetPlayerName(src), table.concat(ids, ', ')))

    setMode(src, 'lobby')
end)

AddEventHandler('playerDropped', function()
    local src = source
    local old = Modes[src]
    Modes[src] = nil
    lastDeath[src] = nil
    if old then TriggerEvent('gf:modeLeft', src, old) end
end)

-- ---------------------------------------------------------------- Morts / kills
local function handleDeath(victim, killer, weapon)
    local now = GetGameTimer()
    if lastDeath[victim] and now - lastDeath[victim] < 1500 then return end
    lastDeath[victim] = now

    local mode = Modes[victim]
    if not mode then return end

    -- Validation du tueur
    if killer then
        if killer == victim or Modes[killer] ~= mode or not GetPlayerName(killer) then
            killer = nil
        else
            local kp, vp = GetPlayerPed(killer), GetPlayerPed(victim)
            if kp ~= 0 and vp ~= 0 and #(GetEntityCoords(kp) - GetEntityCoords(vp)) > Config.MaxKillDistance then
                print(('[gf_core] Kill refusé (distance) : %s -> %s'):format(GetPlayerName(killer), GetPlayerName(victim)))
                killer = nil
            end
        end
    end

    if mode == 'lobby' then
        SetTimeout(2000, function()
            if Modes[victim] == 'lobby' then spawnLobby(victim) end
        end)
        return
    end

    TriggerEvent('gf:playerKilled', victim, killer, weapon, mode)

    -- Kill feed pour tous les joueurs du même mode
    local entry = {
        victim = GetPlayerName(victim),
        victimTeam = Player(victim).state.gf_team,
        killer = killer and GetPlayerName(killer) or nil,
        killerTeam = killer and Player(killer).state.gf_team or nil,
        weapon = weapon,
    }
    for _, p in ipairs(playersInMode(mode)) do
        TriggerClientEvent('gf_ui:killfeed', p, entry)
    end
end

-- Ces événements sont envoyés par la ressource "baseevents" (côté client)
RegisterNetEvent('baseevents:onPlayerKilled')
AddEventHandler('baseevents:onPlayerKilled', function(killerId, data)
    handleDeath(source, tonumber(killerId), data and data.weaponhash or nil)
end)

RegisterNetEvent('baseevents:onPlayerDied')
AddEventHandler('baseevents:onPlayerDied', function()
    handleDeath(source, nil, nil)
end)

-- ---------------------------------------------------------------- Anti friendly-fire
-- Exécuté par le serveur pour CHAQUE tir qui touche : on annule les dégâts
-- interdits (coéquipier, joueur protégé, modes différents, lobby).
local function playerFromEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 1 then return nil end
    local owner = NetworkGetEntityOwner(entity)
    if owner and owner > 0 and GetPlayerPed(owner) == entity then return owner end
    return nil
end

AddEventHandler('weaponDamageEvent', function(sender, data)
    local netId = data.hitGlobalId
    if (not netId or netId == 0) and data.hitGlobalIds then netId = data.hitGlobalIds[1] end
    if not netId or netId == 0 then return end

    local victim = playerFromEntity(NetworkGetEntityFromNetworkId(netId))
    if not victim then return end

    local sMode, vMode = Modes[sender], Modes[victim]
    if sMode ~= vMode or sMode == 'lobby' or not sMode then
        CancelEvent() return
    end

    local vState, sState = Player(victim).state, Player(sender).state
    if vState.gf_protected or sState.gf_protected then
        CancelEvent() return
    end
    if sState.gf_team and sState.gf_team == vState.gf_team and sender ~= victim then
        CancelEvent() return
    end
end)

-- ---------------------------------------------------------------- Commandes
RegisterCommand('lobby', function(src)
    if src > 0 then setMode(src, 'lobby') end
end, false)

RegisterCommand('attack', function(src)
    if src > 0 then setMode(src, 'attack') end
end, false)

RegisterCommand('redzone', function(src)
    if src > 0 then setMode(src, 'redzone') end
end, false)

-- Admin : /setmode [id] [lobby|attack|redzone]
RegisterCommand('setmode', function(src, args)
    if not isAdmin(src) then return end
    local target, mode = tonumber(args[1]), args[2]
    if not target or not GetPlayerName(target) or not Config.Modes[mode or ''] then
        if src > 0 then notify(src, 'Utilisation : /setmode [id] [lobby|attack|redzone]') else print('setmode [id] [lobby|attack|redzone]') end
        return
    end
    setMode(target, mode)
end, false)
