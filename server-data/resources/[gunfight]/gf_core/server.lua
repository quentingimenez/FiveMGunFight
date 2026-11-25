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

local Validation = _G.Validation
local RateLimit = _G.RateLimit

local Modes = {}        -- [src] = 'lobby' | 'attack' | 'redzone'
local Spawning = {}     -- [src] = true tant qu'un spawn vient d'être envoyé (anti doublon)
local SpawnOpts = {}    -- [src] = dernier spawn envoyé (rejouable si le client l'a raté)
local lastDeath = {}    -- [src] = GetGameTimer() de la dernière mort (anti doublon)
local Multi = {}        -- [src] = { count, last } pour les multi-kills
local Vehicles = {}     -- [src] = netId du véhicule de mode (redzone)
local lastDamager = {}  -- [victime] = { src = tireur, at, weapon } (dégât serveur autorisé)

-- Rate-limits par joueur (voir rate_limit.lua et config.lua)
local rateVehicle = {}
local rateVehicleGone = {}
local rateReady = {}
local rateRefus = {}

-- Supprime le véhicule de mode d'un joueur (s'il en a un)
local function deleteVehicle(src)
    local netId = Vehicles[src]
    Vehicles[src] = nil
    if not netId then return end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh ~= 0 and DoesEntityExist(veh) and GetEntityType(veh) == 2 then
        DeleteEntity(veh)
    end
end

-- Journalise un refus sans spam : au plus un message par joueur et par minute.
local function journaliserRefus(src, evenement, raison)
    local reglage = Config.RefusLogRateLimit
    if not RateLimit.autoriser(rateRefus, src, reglage.max, reglage.window, GetGameTimer()) then
        return
    end
    print(('[gf_core] %s refusé pour %s (id %d) : %s'):format(
        evenement, GetPlayerName(src) or '?', src, raison
    ))
end

local function autoriserRate(etat, src, reglage)
    return RateLimit.autoriser(etat, src, reglage.max, reglage.window, GetGameTimer())
end

-- Dépendances natives injectées dans le module pur validation.lua.
local function verifierVehicule(src, netId)
    return Validation.verifierVehicule(netId, src, {
        entityFromNetId = NetworkGetEntityFromNetworkId,
        entityExists = DoesEntityExist,
        entityType = GetEntityType,
        entityOwner = NetworkGetEntityOwner,
        entityCoords = GetEntityCoords,
        playerCoords = function(joueur)
            local ped = GetPlayerPed(joueur)
            if not ped or ped == 0 then return nil end
            return GetEntityCoords(ped)
        end,
        maxDistance = Config.VehicleBindDistance,
    })
end

-- Le client signale le véhicule qu'il vient de recevoir. Il ne peut le faire
-- que pour une entité qui lui appartient (propriétaire réseau), du bon type,
-- proche de lui, et sans dépasser le rate-limit.
RegisterNetEvent('gf_core:vehicle', function(netId)
    local src = source
    if not autoriserRate(rateVehicle, src, Config.VehicleRateLimit) then
        journaliserRefus(src, 'gf_core:vehicle', 'trop de requêtes')
        return
    end

    local ok, raison, id = verifierVehicule(src, netId)
    if not ok then
        journaliserRefus(src, 'gf_core:vehicle', raison)
        return
    end

    if Vehicles[src] and Vehicles[src] ~= id then deleteVehicle(src) end
    Vehicles[src] = id
end)

RegisterNetEvent('gf_core:vehicleGone', function()
    local src = source
    if not autoriserRate(rateVehicleGone, src, Config.VehicleGoneRateLimit) then
        journaliserRefus(src, 'gf_core:vehicleGone', 'trop de requêtes')
        return
    end
    Vehicles[src] = nil
end)

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
---          protected = bool, freeze = bool, spectator = bool,
---          vehicle = 'modele' (le joueur apparaît dans ce véhicule) }
local function spawn(src, opts)
    deleteVehicle(src) -- l'ancien véhicule disparaît à chaque réapparition
    Player(src).state:set('gf_protected', (opts.protected or opts.spectator) and true or false, true)
    print(('[gf_core] spawn %s mode=%s'):format(src, tostring(Modes[src])))
    -- Fenêtre courte : un ready qui arrive juste après le spawn en cours ne
    -- doit pas renvoyer un second gf_core:spawn (le client n'a pas encore
    -- pu conserver le premier).
    Spawning[src] = true
    SpawnOpts[src] = opts
    SetTimeout(3000, function()
        if Spawning[src] then Spawning[src] = nil end
    end)
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
    deleteVehicle(src)
    Multi[src] = nil

    Modes[src] = mode
    local state = Player(src).state
    state:set('gf_mode', mode, true)
    state:set('gf_team', nil, true)
    SetPlayerRoutingBucket(src, def.bucket)

    TriggerClientEvent('gf_ui:hud', src, nil)
    TriggerClientEvent('gf_ui:scoreboard', src, nil)
    TriggerClientEvent('gf_ui:killfeed', src, nil) -- le kill feed est propre à chaque mode
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
exports('DeleteVehicle', deleteVehicle)

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
    if not autoriserRate(rateReady, src, Config.ReadyRateLimit) then
        journaliserRefus(src, 'gf_core:ready', 'trop de requêtes')
        return
    end

    local current = Modes[src]

    -- Le client peut avoir raté le premier gf_core:spawn (chargement NUI,
    -- reconnexion, redémarrage). On renvoie le lobby seulement si aucun
    -- spawn n'est déjà en cours : sinon on ajoute un doublon qui écrase le
    -- vrai spawn (souvent le fond du menu reste affiché).
    if current == 'lobby' then
        if Spawning[src] then
            print(('[gf_core] ready %s : spawn lobby déjà en cours'):format(src))
            return
        end
        print(('[gf_core] ready %s : nouveau spawn lobby'):format(src))
        spawnLobby(src)
        return
    elseif current then
        -- Reconnexion en plein mode : rejouer le dernier spawn reçu par le
        -- serveur, pour ne pas laisser le joueur sans personnage.
        if not Spawning[src] and SpawnOpts[src] then
            print(('[gf_core] ready %s : re-spawn mode %s'):format(src, current))
            spawn(src, SpawnOpts[src])
        end
        return
    end

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
    Spawning[src] = nil
    SpawnOpts[src] = nil
    lastDeath[src] = nil
    lastDamager[src] = nil
    for victime, entree in pairs(lastDamager) do
        if entree.src == src then lastDamager[victime] = nil end
    end
    Multi[src] = nil
    deleteVehicle(src)
    RateLimit.oublier(rateVehicle, src)
    RateLimit.oublier(rateVehicleGone, src)
    RateLimit.oublier(rateReady, src)
    RateLimit.oublier(rateRefus, src)
    if old then TriggerEvent('gf:modeLeft', src, old) end
end)

-- ---------------------------------------------------------------- Morts / kills
local function mortConfirmee(victime)
    return Validation.mortConfirmee(victime, {
        ped = GetPlayerPed,
        health = GetEntityHealth,
        -- Native serveur indisponible sur certaines versions : le pcall évite
        -- une erreur et Validation retombe alors sur la santé.
        dead = function(ped)
            local ok, mort = pcall(IsEntityDead, ped)
            return ok and mort == true
        end,
    })
end

local function handleDeath(victim, weapon)
    local now = GetGameTimer()
    if lastDeath[victim] and now - lastDeath[victim] < 1500 then return end

    -- La preuve de dégât est consommée dès qu'une mort est signalée : elle ne
    -- doit jamais servir deux fois, même si la validation suivante échoue.
    local entree = lastDamager[victim]
    lastDamager[victim] = nil

    local mode = Modes[victim]
    if not mode then return end

    -- La victime doit être réellement morte côté serveur (configurable pour
    -- les serveurs où GetEntityHealth ne reflète pas la mort au bon moment).
    if Config.ValidateDeathHealth then
        local morte, raison = mortConfirmee(victim)
        if not morte then
            journaliserRefus(victim, 'mort', raison)
            return
        end
    end

    lastDeath[victim] = now

    -- Le tueur ne vient jamais du client : seulement du dernier dégât autorisé
    -- vu par weaponDamageEvent, récent et dans le même mode.
    local memeMode = entree ~= nil and entree.src ~= nil and Modes[entree.src] == mode
    local killer, armeDegat = nil, nil
    if entree then
        killer, armeDegat = Validation.tueurCreditable(
            entree, now, Config.KillCreditWindow * 1000, memeMode, victim
        )
    end
    weapon = weapon or armeDegat

    -- Validation supplémentaire du tueur (sécurité en profondeur)
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

    -- Multi-kills (DOUBLÉ, TRIPLÉ, ...) : kills enchaînés sans mourir
    Multi[victim] = nil
    if killer then
        local m = Multi[killer]
        if m and now - m.last <= Config.MultiKillWindow * 1000 then
            m.count = m.count + 1
            m.last = now
        else
            m = { count = 1, last = now }
            Multi[killer] = m
        end
        TriggerClientEvent('gf_ui:kill', killer, { victim = GetPlayerName(victim), count = m.count })
    end

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

-- Ces événements sont envoyés par la ressource "baseevents" (côté client).
-- Le tueur fourni par le client est ignoré : il vient de weaponDamageEvent.
RegisterNetEvent('baseevents:onPlayerKilled')
AddEventHandler('baseevents:onPlayerKilled', function(_, data)
    local arme = type(data) == 'table' and data.weaponhash or nil
    handleDeath(source, arme)
end)

RegisterNetEvent('baseevents:onPlayerDied')
AddEventHandler('baseevents:onPlayerDied', function()
    handleDeath(source, nil)
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

    -- Règle propre au mode (ex. redzone : tirs uniquement dans la zone).
    -- La ressource du mode peut exporter AllowDamage(sender, victim) -> false pour bloquer.
    local res = Config.Modes[sMode] and Config.Modes[sMode].resource
    if res and GetResourceState(res) == 'started' then
        local ok, allowed = pcall(function() return exports[res]:AllowDamage(sender, victim) end)
        if ok and allowed == false then
            CancelEvent() return
        end
    end

    -- Dégât autorisé : c'est la seule preuve que le serveur gardera pour
    -- créditer un kill. `weaponType` est fourni par le serveur (data).
    if sender ~= victim then
        lastDamager[victim] = { src = sender, at = GetGameTimer(), weapon = data.weaponType }

        -- Marqueur de dégâts pour le tireur
        TriggerClientEvent('gf_ui:hit', sender, {
            damage = math.floor(tonumber(data.weaponDamage) or 0),
            fatal = data.willKill and true or false,
        })
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
