-- =============================================================================
--  gf_vehicles - CLIENT
--  - ApplyCustom(veh, props?) : applique une custom (par défaut celle de
--    GlobalState.gf_vehicle_custom) ; appelé par gf_core sur chaque véhicule de mode.
--  - Menu /customveh (admin) : aperçu local du véhicule, caméra, réglages en direct.
-- =============================================================================

-- ---------------------------------------------------------------- Application
local function applyCustom(veh, p)
    p = p or GlobalState.gf_vehicle_custom
    if not veh or veh == 0 or not DoesEntityExist(veh) or type(p) ~= 'table' then return end
    SetVehicleModKit(veh, 0)

    if p.wheelType then SetVehicleWheelType(veh, p.wheelType) end
    for k, i in pairs(p.mods or {}) do
        local t = tonumber(k)
        if t then
            if i < 0 then RemoveVehicleMod(veh, t)
            elseif i < GetNumVehicleMods(veh, t) then SetVehicleMod(veh, t, i, false) end
        end
    end

    if p.paintType then
        SetVehicleModColor_1(veh, p.paintType, 0, 0)
        SetVehicleModColor_2(veh, p.paintType, 0)
    end
    if p.primary then SetVehicleCustomPrimaryColour(veh, p.primary.r, p.primary.g, p.primary.b) end
    if p.secondary then SetVehicleCustomSecondaryColour(veh, p.secondary.r, p.secondary.g, p.secondary.b) end
    if p.pearl or p.wheelColor then
        local pearl, wheel = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, p.pearl or pearl, p.wheelColor or wheel)
    end

    if p.windowTint then SetVehicleWindowTint(veh, p.windowTint) end
    ToggleVehicleMod(veh, 22, p.xenon == true)
    if p.xenon and p.xenonColor then SetVehicleXenonLightsColor(veh, p.xenonColor) end
    for side = 0, 3 do SetVehicleNeonLightEnabled(veh, side, p.neon == true) end
    if p.neonColor then SetVehicleNeonLightsColour(veh, p.neonColor.r, p.neonColor.g, p.neonColor.b) end
    if p.plateStyle then SetVehicleNumberPlateTextIndex(veh, p.plateStyle) end
    if p.plate then SetVehicleNumberPlateText(veh, p.plate) end
end
exports('ApplyCustom', applyCustom)

-- ---------------------------------------------------------------- Menu admin
local preview, cam, heading = nil, nil, 0.0
local previewHash, previewPos = nil, nil
local props = {}

local function label(text, fallback)
    if not text or text == '' or text == 'NULL' then return fallback end
    local s = GetLabelText(text)
    if s == 'NULL' then return fallback end
    return s
end

-- Liste des réglages possibles pour le véhicule d'aperçu (dépend du type de jantes)
local function buildOptions()
    local veh = preview
    local mods = {}
    for _, slot in ipairs(Config.ModSlots) do
        local n = GetNumVehicleMods(veh, slot.type)
        if n > 0 then
            local choices = { { id = -1, label = 'Origine' } }
            for i = 0, n - 1 do
                choices[#choices + 1] = { id = i, label = label(GetModTextLabel(veh, slot.type, i), ('%s %d'):format(slot.label, i + 1)) }
            end
            mods[#mods + 1] = { type = slot.type, label = slot.label, choices = choices }
        end
    end
    local wheels = { { id = -1, label = 'Origine' } }
    for i = 0, GetNumVehicleMods(veh, 23) - 1 do
        wheels[#wheels + 1] = { id = i, label = label(GetModTextLabel(veh, 23, i), ('Jante %d'):format(i + 1)) }
    end
    return {
        mods = mods,
        wheels = wheels,
        paintTypes = Config.PaintTypes,
        wheelTypes = Config.WheelTypes,
        windowTints = Config.WindowTints,
        plateStyles = Config.PlateStyles,
        xenonColors = Config.XenonColors,
        gameColors = Config.GameColors,
        plateMax = Config.PlateMaxLength,
    }
end

local function closeMenu()
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
    if cam then
        RenderScriptCams(false, true, 400, true, true)
        DestroyCam(cam, false)
        cam = nil
    end
    if preview and DoesEntityExist(preview) then
        SetEntityAsMissionEntity(preview, true, true)
        DeleteVehicle(preview)
    end
    preview = nil
    SetModelAsNoLongerNeeded(previewHash or 0)
    FreezeEntityPosition(PlayerPedId(), false)
end

-- Véhicule local (non réseau) : seul l'admin le voit
local function spawnPreview()
    preview = CreateVehicle(previewHash, previewPos.x, previewPos.y, previewPos.z, heading, false, false)
    if preview == 0 then preview = nil return false end
    SetVehicleOnGroundProperly(preview)
    FreezeEntityPosition(preview, true)
    SetEntityInvincible(preview, true)
    SetVehicleDirtLevel(preview, 0.0)
    SetVehicleLights(preview, 2)
    return true
end

RegisterNetEvent('gf_vehicles:openMenu', function(model, current)
    if preview then return end
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return print(('[gf_vehicles] Modèle inconnu : %s'):format(model)) end
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) then return end

    local ped = PlayerPedId()
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 7.0, 0.0)
    heading = GetEntityHeading(ped) + 140.0
    previewHash, previewPos = hash, pos
    if not spawnPreview() then return end
    FreezeEntityPosition(ped, true)

    props = type(current) == 'table' and current or {}
    applyCustom(preview, props)

    local vpos = GetEntityCoords(preview)
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local c = GetOffsetFromEntityInWorldCoords(preview, -4.5, 5.5, 1.6)
    SetCamCoord(cam, c.x, c.y, c.z)
    PointCamAtCoord(cam, vpos.x, vpos.y, vpos.z + 0.3)
    SetCamFov(cam, 50.0)
    RenderScriptCams(true, true, 500, true, true)

    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open', options = buildOptions(), props = props })
end)

-- Un réglage modifié dans le menu : on l'applique à l'aperçu
RegisterNUICallback('change', function(data, cb)
    if not preview or type(data) ~= 'table' then return cb({}) end
    if type(data.props) == 'table' then props = data.props end
    applyCustom(preview, props)
    -- Le type de jantes change la liste des jantes disponibles
    cb(data.rebuild and buildOptions() or {})
end)

-- Réinitialiser : nouvel aperçu d'origine, custom vide
RegisterNUICallback('reset', function(_, cb)
    if not preview then return cb({}) end
    SetEntityAsMissionEntity(preview, true, true)
    DeleteVehicle(preview)
    props = {}
    spawnPreview()
    cb({ options = preview and buildOptions() or nil })
end)

RegisterNUICallback('rotate', function(data, cb)
    if preview and type(data) == 'table' and type(data.delta) == 'number' then
        heading = (heading + data.delta) % 360.0
        SetEntityHeading(preview, heading)
    end
    cb({})
end)

RegisterNUICallback('save', function(_, cb)
    TriggerServerEvent('gf_vehicles:saveCustom', props)
    closeMenu()
    cb({})
end)

RegisterNUICallback('close', function(_, cb)
    closeMenu()
    cb({})
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and preview then closeMenu() end
end)
