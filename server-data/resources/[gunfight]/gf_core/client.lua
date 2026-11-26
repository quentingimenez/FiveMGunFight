-- =============================================================================
--  gf_core - CLIENT
--  Exécute ce que le serveur demande : apparition, armes, gel, protection,
--  mode spectateur. Le client ne décide jamais du score ni des victoires.
-- =============================================================================

local protected = false
local spectator = false
local spawning = false
local hasSpawned = false
local spawnSeq = 0       -- incrémenté à chaque ordre de spawn (ignorer les anciens)
local modeVehicle = nil  -- véhicule donné par le mode (redzone)

-- Supprime le véhicule de mode (touche F en redzone, changement de mode...)
local function deleteModeVehicle()
    local veh = modeVehicle
    modeVehicle = nil
    if veh and DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end
    TriggerServerEvent('gf_core:vehicleGone')
end
exports('DeleteModeVehicle', deleteModeVehicle)
exports('GetModeVehicle', function() return modeVehicle end)

local function giveVehicle(model, x, y, z, heading)
    -- Véhicule de base choisi par un admin (/customveh, ressource gf_vehicles)
    if GetResourceState('gf_vehicles') == 'started' and type(GlobalState.gf_vehicle_base) == 'string' then
        model = GlobalState.gf_vehicle_base
    end
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        print(('[gf_core] Modèle de véhicule inconnu : %s'):format(model))
        return
    end
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) then return end

    local ped = PlayerPedId()
    local veh = CreateVehicle(hash, x, y, z, heading, true, false)
    SetModelAsNoLongerNeeded(hash)
    if veh == 0 then return end

    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, 'GUNFIGHT')
    SetVehicleDirtLevel(veh, 0.0)
    SetVehRadioStation(veh, 'OFF')
    -- Custom du véhicule de base réglée par un admin (/customveh, ressource gf_vehicles)
    if GetResourceState('gf_vehicles') == 'started' then
        exports.gf_vehicles:ApplyCustom(veh)
    end
    SetVehicleEngineOn(veh, true, true, false)
    SetPedIntoVehicle(ped, veh, -1)
    modeVehicle = veh

    local t = GetGameTimer() + 2000
    while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < t do Wait(0) end
    TriggerServerEvent('gf_core:vehicle', NetworkGetNetworkIdFromEntity(veh))
    return veh
end

-- Donne un véhicule de mode au joueur (l'ancien est supprimé) et l'installe dedans.
-- Utilisé par gf_redzone (points véhicule). Retourne le véhicule créé.
exports('GiveModeVehicle', function(model, x, y, z, heading)
    if modeVehicle and DoesEntityExist(modeVehicle) then
        SetEntityAsMissionEntity(modeVehicle, true, true)
        DeleteVehicle(modeVehicle)
    end
    modeVehicle = nil
    return giveVehicle(model, x + 0.0, y + 0.0, z + 0.0, (heading or 0.0) + 0.0)
end)

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

-- Emplacements d'armes : slots[1] = arme sur la touche 1, slots[2] = touche 2...
-- Remplis dans l'ordre où les armes ont été choisies (ou listées dans la config).
local slots = {}

local function applyLoadout(ped, name)
    RemoveAllPedWeapons(ped, true)
    SetPedArmour(ped, 0)
    slots = {}
    local lo = name and Config.Loadouts[name]
    if not lo then return end
    for _, w in ipairs(lo.weapons) do
        GiveWeaponToPed(ped, joaat(w[1]), w[2], false, false)
        SetPedInfiniteAmmo(ped, true, joaat(w[1]))
        slots[#slots + 1] = joaat(w[1])
    end
    if slots[1] then SetCurrentPedWeapon(ped, slots[1], true) end
    SetPedArmour(ped, lo.armour or 0)
end

-- Armes au choix : list = { { name, ammo, components = {}, tint }, ... }
local function applyWeapons(ped, list, armour)
    RemoveAllPedWeapons(ped, true)
    slots = {}
    for _, w in ipairs(list or {}) do
        local hash = joaat(w.name)
        GiveWeaponToPed(ped, hash, w.ammo or 250, false, false)
        SetPedInfiniteAmmo(ped, true, hash) -- réserve illimitée, il faut quand même recharger
        for _, comp in ipairs(w.components or {}) do
            GiveWeaponComponentToPed(ped, hash, joaat(comp))
        end
        if w.tint then SetPedWeaponTintIndex(ped, hash, w.tint) end
        slots[#slots + 1] = hash
    end
    if slots[1] then SetCurrentPedWeapon(ped, slots[1], true) end
    SetPedArmour(ped, armour or 0)
end

-- Touches 1, 2... : sortir l'arme de l'emplacement correspondant
local function selectSlot(i)
    local ped = PlayerPedId()
    local hash = slots[i]
    if not hash or IsEntityDead(ped) or not HasPedGotWeapon(ped, hash, false) then return end
    SetCurrentPedWeapon(ped, hash, true)
end

for i = 1, Config.WeaponSlots do
    RegisterCommand('+gf_slot' .. i, function() selectSlot(i) end, false)
    RegisterCommand('-gf_slot' .. i, function() end, false)
    RegisterKeyMapping('+gf_slot' .. i, ('Gunfight : arme %d'):format(i), 'keyboard', tostring(i))
end

-- ---------------------------------------------------------------- HUD des armes
-- Envoie à gf_ui les armes des emplacements (touche, nom, chargeur) et celle en main.
-- Nom affiché : label du catalogue, sinon le nom GTA sans « WEAPON_ ».
local WEAPON_INFO = {}
for _, w in pairs(Config.Weapons) do
    WEAPON_INFO[joaat(w.name)] = { name = w.name, label = w.label }
end
for _, lo in pairs(Config.Loadouts or {}) do
    for _, w in ipairs(lo.weapons or {}) do
        local hash = joaat(w[1])
        WEAPON_INFO[hash] = WEAPON_INFO[hash] or { name = w[1], label = w[1]:gsub('^WEAPON_', '') }
    end
end

CreateThread(function()
    local last = nil
    while true do
        local ped = PlayerPedId()
        local mode = LocalPlayer.state.gf_mode
        local data = nil
        if #slots > 0 and mode and mode ~= 'lobby' and not IsEntityDead(ped) and IsEntityVisible(ped) then
            local current = GetSelectedPedWeapon(ped)
            local list = {}
            for i, hash in ipairs(slots) do
                if HasPedGotWeapon(ped, hash, false) then
                    local info = WEAPON_INFO[hash] or { name = tostring(hash), label = '?' }
                    local _, clip = GetAmmoInClip(ped, hash)
                    list[#list + 1] = {
                        key = tostring(i),
                        name = info.name,
                        label = info.label,
                        clip = clip,
                        clipMax = GetMaxAmmoInClip(ped, hash, true),
                        active = hash == current,
                    }
                end
            end
            if #list > 0 then data = list end
        end
        local encoded = data and json.encode(data) or 'null'
        if encoded ~= last then
            TriggerEvent('gf_ui:weapons', data)
            last = encoded
        end
        Wait(100)
    end
end)

-- Contrôles GTA désactivés : roue des armes (TAB), molette, touches de
-- catégories d'armes (1 à 9 de GTA) et changement d'arme en véhicule.
local WEAPON_SWITCH_CONTROLS = {
    37,                                     -- roue des armes (TAB)
    12, 13, 14, 15, 16, 17,                 -- navigation / molette dans la roue
    99, 100, 115, 116,                      -- arme suivante / précédente (véhicule)
    157, 158, 159, 160, 161, 162, 163, 164, 165, -- touches 1 à 9 de GTA
    261, 262,                               -- molette : arme suivante / précédente
}

-- Gèle / dégèle le joueur ET son véhicule s'il est dedans
local function setFrozen(on)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, on)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        FreezeEntityPosition(veh, on)
        SetVehicleEngineOn(veh, true, true, false)
    end
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
    spawnSeq = spawnSeq + 1
    local seq = spawnSeq
    CreateThread(function()
        while spawning do Wait(50) end
        -- Un spawn plus récent a été reçu pendant l'attente : le plus ancien
        -- ne doit plus déplacer le joueur ni rejouer le fondu.
        if seq ~= spawnSeq then return end
        spawning = true

        local ok, err = pcall(function()
            DoScreenFadeOut(250)
            local t = GetGameTimer() + 1000
            while not IsScreenFadedOut() and GetGameTimer() < t do Wait(0) end

            local model = joaat(Config.PlayerModel)
            if GetEntityModel(PlayerPedId()) ~= model and loadModel(model) then
                SetPlayerModel(PlayerId(), model)
                SetPedDefaultComponentVariation(PlayerPedId())
                SetModelAsNoLongerNeeded(model)
            end

            -- L'ancien véhicule est supprimé par le serveur ; on oublie la référence
            -- (sauf keepVehicle : il reste dans la manche)
            if not o.keepVehicle then
                if modeVehicle and DoesEntityExist(modeVehicle) then
                    SetEntityAsMissionEntity(modeVehicle, true, true)
                    DeleteVehicle(modeVehicle)
                end
                modeVehicle = nil
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
            if not o.spectator then
                if o.weapons then
                    applyWeapons(ped, o.weapons, o.armour) -- armes au choix
                else
                    applyLoadout(ped, o.loadout)           -- équipement fixe
                end
            end
            setProtected((o.protected or o.spectator) and true or false)
            FreezeEntityPosition(ped, (o.freeze or o.spectator) and true or false)

            if o.vehicle and not o.spectator then
                local p = GetEntityCoords(ped)
                FreezeEntityPosition(ped, false) -- un personnage gelé ne monte pas en voiture
                giveVehicle(o.vehicle, p.x, p.y, p.z, (o.heading or 0.0) + 0.0)
                if o.freeze then setFrozen(true) end
            end

            -- Événement local pour les modes (ex. gf_redzone suit le véhicule)
            TriggerEvent('gf_core:spawned', { vehicle = modeVehicle, spectator = o.spectator and true or false })
        end)

        if not ok then
            print(('[gf_core] erreur de spawn : %s'):format(tostring(err)))
        end

        -- Même si le spawn échoue, ne jamais laisser l'écran de chargement
        -- bloqué : le joueur doit au moins voir le jeu et pouvoir utiliser /lobbyui.
        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()
        DoScreenFadeIn(400)
        spawning = false
        hasSpawned = true
    end)
end)

RegisterNetEvent('gf_core:setProtected', function(on)
    setProtected(on)
end)

RegisterNetEvent('gf_core:modeChanged', function()
    if modeVehicle and DoesEntityExist(modeVehicle) then
        SetEntityAsMissionEntity(modeVehicle, true, true)
        DeleteVehicle(modeVehicle)
    end
    modeVehicle = nil
end)

RegisterNetEvent('gf_core:freeze', function(on)
    setFrozen(on)
end)

RegisterNetEvent('gf_core:giveWeapons', function(list, armour)
    applyWeapons(PlayerPedId(), list, armour)
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

        -- Pas de roue des armes : seulement les touches 1, 2... (voir selectSlot)
        for _, control in ipairs(WEAPON_SWITCH_CONTROLS) do
            DisableControlAction(0, control, true)
        end
        HudWeaponWheelIgnoreSelection()

        -- Pas de collision entre véhicules (évite les « pits » entre joueurs).
        -- Les joueurs à pied restent percutables.
        if Config.DisableVehicleCollisions then
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                local pos = GetEntityCoords(veh)
                for _, other in ipairs(GetGamePool('CVehicle')) do
                    if other ~= veh and #(GetEntityCoords(other) - pos) < 80.0 then
                        SetEntityNoCollisionEntity(veh, other, true)
                        SetEntityNoCollisionEntity(other, veh, true)
                    end
                end
            end
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

    -- Filet de sécurité : si le serveur n'a pas envoyé (ou si le client a raté)
    -- gf_core:spawn, l'écran de chargement resterait sinon indéfiniment.
    SetTimeout(10000, function()
        if not hasSpawned then
            print('[gf_core] aucun spawn reçu après 10 s, libération de l’écran de chargement')
            ShutdownLoadingScreen()
            ShutdownLoadingScreenNui()
            -- Pas de fondu ici si un spawn est en cours : son propre thread
            -- gère DoScreenFadeIn et un double fondu laisserait l'écran noir.
            if not spawning then DoScreenFadeIn(400) end
            -- Demander au serveur de rejouer le spawn : libérer l'écran seul
            -- laisserait le joueur sans personnage. Pas de demande si un
            -- spawn est déjà en cours (il finira et posera hasSpawned).
            if not spawning then TriggerServerEvent('gf_core:ready') end
        end
    end)

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

-- Arrêt de la ressource pendant un spawn : libérer l'écran, sinon le joueur
-- reste sur le fond noir/chargement alors que gf_core ne répond plus.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    DoScreenFadeIn(400)
end)
