-- =============================================================================
--  gf_core - CLIENT
--  Exécute ce que le serveur demande : apparition, armes, gel, protection,
--  mode spectateur. Le client ne décide jamais du score ni des victoires.
-- =============================================================================

local protected = false
local spectator = false
local spawning = false

-- ---------------------------------------------------------------- Utilitaires
local function loadModel(hash)
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash)
end

-- Place le joueur au sol, même si la hauteur (z) de la config est approximative
local function placeOnGround(ped, x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    FreezeEntityPosition(ped, true)

    local timeout = GetGameTimer() + 4000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(x, y, z)
        Wait(0)
    end

    for _, h in ipairs({ z + 30.0, z + 100.0, 400.0, 900.0 }) do
        local found, groundZ = GetGroundZFor_3dCoord(x, y, h, false)
        if found then
            z = groundZ + 0.5
            break
        end
    end

    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    FreezeEntityPosition(ped, false)
end

local function applyLoadout(ped, name)
    RemoveAllPedWeapons(ped, true)
    SetPedArmour(ped, 0)
    local lo = name and Config.Loadouts[name]
    if not lo then return end
    for _, w in ipairs(lo.weapons) do
        GiveWeaponToPed(ped, joaat(w[1]), w[2], false, false)
    end
    if lo.weapons[1] then
        SetCurrentPedWeapon(ped, joaat(lo.weapons[1][1]), true)
    end
    SetPedArmour(ped, lo.armour or 0)
end

local function setProtected(on)
    protected = on
    SetEntityInvincible(PlayerPedId(), on)
end

local function setSpectator(on)
    spectator = on
    local ped = PlayerPedId()
    SetEntityVisible(ped, not on, false)
    SetEntityCollision(ped, not on, not on)
    FreezeEntityPosition(ped, on)
    if on then RemoveAllPedWeapons(ped, true) end
end

-- ---------------------------------------------------------------- Événements serveur
RegisterNetEvent('gf_core:spawn', function(o)
    CreateThread(function()
        while spawning do Wait(50) end
        spawning = true

        DoScreenFadeOut(250)
        local t = GetGameTimer() + 1000
        while not IsScreenFadedOut() and GetGameTimer() < t do Wait(0) end

        local model = joaat(Config.PlayerModel)
        if GetEntityModel(PlayerPedId()) ~= model and loadModel(model) then
            SetPlayerModel(PlayerId(), model)
            SetPedDefaultComponentVariation(PlayerPedId())
            SetModelAsNoLongerNeeded(model)
        end

        local x, y, z = o.x + 0.0, o.y + 0.0, o.z + 0.0
        RequestCollisionAtCoord(x, y, z)
        NetworkResurrectLocalPlayer(x, y, z, (o.heading or 0.0) + 0.0, true, true, false)

        local ped = PlayerPedId()
        ClearPedTasksImmediately(ped)
        ClearPlayerWantedLevel(PlayerId())
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        SetCanAttackFriendly(ped, true, false)

        if o.spectator then
            SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
        else
            placeOnGround(ped, x, y, z)
        end
        SetEntityHeading(ped, (o.heading or 0.0) + 0.0)

        setSpectator(o.spectator and true or false)
        if not o.spectator then applyLoadout(ped, o.loadout) end
        setProtected((o.protected or o.spectator) and true or false)
        FreezeEntityPosition(ped, (o.freeze or o.spectator) and true or false)

        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()
        DoScreenFadeIn(400)
        spawning = false
    end)
end)

RegisterNetEvent('gf_core:setProtected', function(on)
    setProtected(on)
end)

RegisterNetEvent('gf_core:freeze', function(on)
    FreezeEntityPosition(PlayerPedId(), on)
end)

-- ---------------------------------------------------------------- Boucle permanente
CreateThread(function()
    SetMaxWantedLevel(0)
    for i = 1, 15 do EnableDispatchService(i, false) end
    NetworkSetFriendlyFireOption(true)

    while true do
        local pid = PlayerId()
        local ped = PlayerPedId()

        if not Config.HealthRegen then
            SetPlayerHealthRechargeMultiplier(pid, 0.0)
        end

        -- Pas de tir ni de coups de poing quand on est protégé (lobby, préparation, spectateur)
        if protected or spectator or LocalPlayer.state.gf_mode == 'lobby' then
            DisablePlayerFiring(pid, true)
            DisableControlAction(0, 140, true) -- coup léger
            DisableControlAction(0, 141, true) -- coup fort
            DisableControlAction(0, 142, true) -- coup alternatif
            DisableControlAction(0, 24, true)  -- tirer
            DisableControlAction(0, 257, true) -- tirer (alternatif)
        end

        -- Le personnage peut changer (réapparition) : on réapplique l'invincibilité
        SetEntityInvincible(ped, protected or spectator)

        Wait(0)
    end
end)

-- ---------------------------------------------------------------- Connexion
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(250) end
    exports.spawnmanager:setAutoSpawn(false)
    TriggerServerEvent('gf_core:ready')

    TriggerEvent('chat:addSuggestion', '/lobby', 'Retourner au lobby')
    TriggerEvent('chat:addSuggestion', '/attack', 'Rejoindre le mode Attaque de zone')
    TriggerEvent('chat:addSuggestion', '/redzone', 'Rejoindre la Redzone')
    TriggerEvent('chat:addSuggestion', '/pos', 'Afficher ta position (pour créer des zones)')
end)

-- /pos : affiche tes coordonnées pour les copier dans un config.lua
RegisterCommand('pos', function()
    local p = GetEntityCoords(PlayerPedId())
    local text = ('vector3(%.1f, %.1f, %.1f)  heading %.0f'):format(p.x, p.y, p.z, GetEntityHeading(PlayerPedId()))
    TriggerEvent('chat:addMessage', { color = { 120, 200, 255 }, args = { 'Position', text } })
    print(text)
end, false)
