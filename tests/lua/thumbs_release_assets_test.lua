-- Les assets d'armes demandés pour une photo doivent être libérés, et jamais
-- avant la suppression de l'objet qui les utilise.
local root = os.getenv('GF_ROOT') or '.'
local path = root .. '/server-data/resources/[gunfight]/gf_thumbs/client.lua'

-- Bouchons contrôlés : compteurs et séquence des appels natifs.
local calls = {
    RequestWeaponAsset = 0, HasWeaponAssetLoaded = 0, RemoveWeaponAsset = 0,
    IsWeaponValid = 0, CreateWeaponObject = 0, joaat = 0, GetGameTimer = 0,
    Wait = 0, DeleteEntity = 0,
}
local sequence = {}
local function note(name)
    calls[name] = calls[name] + 1
    sequence[#sequence + 1] = name
end

local weaponValid = true
local assetLoaded = true
local objectHash = 4242
local timer = 0
local requestedHash = nil
local removedHashes = {}
local events = {}
local nuiCallbacks = {}
local capturedData = { url = 'data:image/png;base64,AAAA' }

local function vec(x, y, z)
    local v = { x = x or 0.0, y = y or 0.0, z = z or 0.0 }
    local mt = {
        __add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __mul = function(a, s) return vec(a.x * s, a.y * s, a.z * s) end,
        __div = function(a, s) return vec(a.x / s, a.y / s, a.z / s) end,
    }
    return setmetatable(v, mt)
end

-- `exports` doit rester appelable (exports('Get', get)) tout en se laissant
-- indexer par ressource : client.lua fait exports[prov.resource][prov.export]().
local function exportsShim() end
local exportProviders = {
    gf_weapons = {
        List = function() return { { id = 'WEAPON_TEST' } } end,
    },
}
local exportsCallable = setmetatable(exportProviders, { __call = exportsShim })

local stub = function() end
local env = setmetatable({
    source = 1,
    print = print,
    math = math,
    type = type,
    tostring = tostring,
    pcall = pcall,
    ipairs = ipairs,
    pairs = pairs,
    table = table,
    string = string,
    os = os,
    io = io,
    next = next,
    select = select,
    error = error,
    assert = assert,
    rawget = rawget,
    rawequal = rawequal,
    rawset = rawset,
    tonumber = tonumber,
    unpack = unpack,
    Config = {
        KeyColor = { r = 0, g = 255, b = 0 },
        Fov = 60,
        Studio = { x = 0.0, y = 0.0, z = 0.0 },
        Kinds = {
            weapons = {
                subject = 'weapon',
                provider = { resource = 'gf_weapons', export = 'List' },
                width = 512,
                height = 512,
            },
        },
        AutoCapture = false,
    },
    RegisterNetEvent = function(name, fn) events[name] = fn end,
    RegisterNUICallback = function(name, fn) nuiCallbacks[name] = fn end,
    RegisterCommand = stub,
    AddEventHandler = stub,
    exports = exportsCallable,
    LocalPlayer = { state = { gf_mode = 'lobby' } },
    GetCurrentResourceName = function() return 'gf_thumbs' end,
    GetResourceState = function(name) if name == 'gf_weapons' then return 'started' end return 'missing' end,
    GetResourceKvpString = function() return '' end,
    SetResourceKvp = stub,
    DeleteResourceKvp = stub,
    TriggerServerEvent = stub,
    TriggerLatentServerEvent = stub,
    vector3 = vec,
    promise = {
        new = function()
            local p = {}
            function p:resolve(value) p.value = value end
            return p
        end,
    },
    Citizen = { Await = function(p) return p.value end },
    SetTimeout = stub,
    CreateThread = stub,
    Wait = function() note('Wait') end,
    GetGameTimer = function() note('GetGameTimer') timer = timer + 1000 return timer end,
    SendNUIMessage = function(message)
        if message.type == 'capture' then
            local cb = assert(nuiCallbacks.captured, 'callback NUI captured non enregistré')
            cb(capturedData, function() end)
        end
    end,
    joaat = function(id) note('joaat') if id == 'WEAPON_TEST' then return 123456 end return 999 end,
    IsWeaponValid = function() note('IsWeaponValid') return weaponValid end,
    RequestWeaponAsset = function(hash) note('RequestWeaponAsset') requestedHash = hash end,
    HasWeaponAssetLoaded = function() note('HasWeaponAssetLoaded') return assetLoaded end,
    RemoveWeaponAsset = function(hash) note('RemoveWeaponAsset') removedHashes[#removedHashes + 1] = hash end,
    CreateWeaponObject = function() note('CreateWeaponObject') return objectHash end,
    DeleteEntity = function() note('DeleteEntity') end,
    IsModelInCdimage = function() return true end,
    RequestModel = stub,
    HasModelLoaded = function() return true end,
    SetModelAsNoLongerNeeded = stub,
    CreateVehicle = function() return 0 end,
    SetVehicleDirtLevel = stub,
    SetVehicleLights = stub,
    FreezeEntityPosition = stub,
    SetEntityCollision = stub,
    SetEntityCoordsNoOffset = stub,
    SetEntityHeading = stub,
    CreateCam = function() return 1 end,
    SetCamFov = stub,
    SetCamCoord = stub,
    PointCamAtCoord = stub,
    RenderScriptCams = stub,
    DestroyCam = stub,
    GetRenderingCam = function() return -1 end,
    GetEntityModel = function() return 1 end,
    GetModelDimensions = function() return vec(-1.0, -1.0, -1.0), vec(1.0, 1.0, 1.0) end,
    GetOffsetFromEntityInWorldCoords = function() return vec(0.0, 0.0, 0.0) end,
    GetScreenCoordFromWorldCoord = function() return true, 0.5, 0.5 end,
    DrawPoly = stub,
    DrawLightWithRange = stub,
    HideHudAndRadarThisFrame = stub,
    HideHudComponentThisFrame = stub,
    DisableAllControlActions = stub,
    SetEntityAsMissionEntity = stub,
    SetFocusPosAndVel = stub,
    NetworkOverrideClockTime = stub,
    SetWeatherTypeNowPersist = stub,
    DisplayRadar = stub,
    ClearPrints = stub,
    ClearAllHelpMessages = stub,
    ClearFocus = stub,
    NetworkClearClockTimeOverride = stub,
    ClearOverrideWeather = stub,
    ClearWeatherTypePersist = stub,
    DoesCamExist = function() return false end,
    SetCamActive = stub,
    NetworkIsPlayerActive = function() return false end,
    PlayerId = function() return 1 end,
}, { __index = function(_, key)
    if _G[key] ~= nil then return _G[key] end
    return function() end
end })

assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_core/crash_marker.lua', 't', env))()
assert(loadfile(path, 't', env))()
local capture = assert(events['gf_thumbs:capture'], 'événement gf_thumbs:capture non enregistré')

local function reset(valid, loaded, obj)
    weaponValid, assetLoaded, objectHash = valid, loaded, obj
    calls.RequestWeaponAsset = 0
    calls.HasWeaponAssetLoaded = 0
    calls.RemoveWeaponAsset = 0
    calls.IsWeaponValid = 0
    calls.CreateWeaponObject = 0
    calls.joaat = 0
    calls.DeleteEntity = 0
    sequence = {}
    timer = 0
    requestedHash = nil
    removedHashes = {}
end

local function positionOf(name)
    for i, entry in ipairs(sequence) do
        if entry == name then return i end
    end
    return nil
end

-- 1. Succès : une seule demande, une seule libération, après la suppression.
reset(true, true, 4242)
capture('weapons', 'WEAPON_TEST')
assert(calls.IsWeaponValid == 1, 'IsWeaponValid doit être appelé une fois en succès')
assert(calls.RequestWeaponAsset == 1, 'une seule demande d asset en succès')
assert(calls.CreateWeaponObject == 1, 'objet créé une fois en succès')
assert(calls.DeleteEntity == 1, 'objet supprimé une fois en succès')
assert(calls.RemoveWeaponAsset == 1, 'asset libéré une fois en succès')
assert(requestedHash == 123456, 'hash demandé différent de joaat(id)')
assert(removedHashes[1] == requestedHash, 'asset libéré avec un hash différent de celui demandé')
local hashPosition = nil
for i, entry in ipairs(sequence) do
    if entry == 'RequestWeaponAsset' then hashPosition = i break end
end
assert(hashPosition, 'demande d asset absente de la séquence')
local removePos = assert(positionOf('RemoveWeaponAsset'), 'libération absente de la séquence')
local deletePos = assert(positionOf('DeleteEntity'), 'suppression absente de la séquence')
assert(removePos > deletePos, 'l asset doit être libéré après la suppression de l objet')

-- 2. Échec waitLoaded : l asset demandé est libéré, aucun objet créé.
reset(true, false, 4242)
capture('weapons', 'WEAPON_TEST')
assert(calls.RequestWeaponAsset == 1, 'asset demandé avant le timeout de chargement')
assert(calls.CreateWeaponObject == 0, 'aucun objet ne doit être créé si le chargement échoue')
assert(calls.RemoveWeaponAsset == 1, 'asset libéré après échec de chargement')
assert(removedHashes[1] == requestedHash, 'asset libéré avec un hash différent après échec de chargement')
assert(calls.DeleteEntity == 0, 'aucun objet à supprimer après échec de chargement')

-- 3. Échec CreateWeaponObject : l asset est libéré malgré l absence d objet.
reset(true, true, 0)
capture('weapons', 'WEAPON_TEST')
assert(calls.RequestWeaponAsset == 1, 'asset demandé avant la création')
assert(calls.CreateWeaponObject == 1, 'création d objet tentée une fois')
assert(calls.RemoveWeaponAsset == 1, 'asset libéré après échec de création')
assert(removedHashes[1] == requestedHash, 'asset libéré avec un hash différent après échec de création')
assert(calls.DeleteEntity == 0, 'aucun objet à supprimer après échec de création')

-- 4. Modèle invalide : aucune demande, donc aucune libération.
reset(false, true, 4242)
capture('weapons', 'WEAPON_TEST')
assert(calls.IsWeaponValid == 1, 'validité du modèle vérifiée')
assert(calls.RequestWeaponAsset == 0, 'aucun asset demandé pour un modèle invalide')
assert(calls.CreateWeaponObject == 0, 'aucun objet créé pour un modèle invalide')
assert(calls.RemoveWeaponAsset == 0, 'rien à libérer pour un modèle invalide')
assert(calls.DeleteEntity == 0, 'aucun objet supprimé pour un modèle invalide')

print('Photos : libération des assets d armes vérifiée')
