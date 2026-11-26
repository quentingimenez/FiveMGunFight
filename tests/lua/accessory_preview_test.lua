-- L'aperçu ne touche qu'un clone et libère caméra et clone à la fermeture.
local root = os.getenv('GF_ROOT') or '.'
local callbacks, events, threads, calls = {}, {}, {}, {}
local function record(name)
    return function(...) calls[#calls + 1] = { name, ... } end
end
local env = setmetatable({
    Config = { PageReadyTimeoutMs = 1000 },
    RegisterNUICallback = function(name, fn) callbacks[name] = fn end,
    RegisterNetEvent = function(name, fn) events[name] = fn end,
    AddEventHandler = function(name, fn) events[name] = fn end,
    CreateThread = function(fn) threads[#threads + 1] = fn end,
    SetTimeout = function() end,
    GetResourceState = function() return 'missing' end,
    GetGameTimer = function() return 100 end,
    GetCurrentResourceName = function() return 'gf_menu' end,
    PlayerPedId = function() return 1 end,
    GetEntityHeading = function() return 0 end,
    GetOffsetFromEntityInWorldCoords = function() return { x = 1, y = 2, z = 3 } end,
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    ClonePed = function() return 2 end,
    DoesEntityExist = function() return true end,
    CreateCam = function() return 3 end,
    IsWeaponValid = function() return true end,
    HasWeaponAssetLoaded = function() return true end,
    joaat = function(value) return value end,
    GiveWeaponToPed = record('weapon'),
    GiveWeaponComponentToPed = record('component'),
    RemoveWeaponComponentFromPed = record('remove'),
    GetCurrentPedWeaponEntityIndex = function() return 9 end,
    GiveWeaponComponentToWeaponObject = record('objectComponent'),
    RemoveWeaponComponentFromWeaponObject = record('objectRemove'),
    DeleteEntity = record('delete'),
    DestroyCam = record('camera'),
    RenderScriptCams = record('render'),
    SetFocusPosAndVel = record('focus'),
    ClearFocus = record('clearfocus'),
    SetEntityCoordsNoOffset = record('coords'),
    GetActivePlayers = function() return { 1, 2 } end,
    GetPlayerPed = function(id) return id == 1 and 1 or 4 end,
    SetEntityLocallyInvisible = record('hidden'),
}, { __index = function(_, key) return _G[key] or function() end end })
assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_menu/client.lua', 't', env))()
events['gf_inventory:openAdmin']({})
events['gf_inventory:locker']({ weapons = { {
    id = 'carbine', name = 'WEAPON_CARBINERIFLE', selections = {},
    accessories = { sight = { options = { 'COMPONENT_AT_SCOPE_MEDIUM' } },
        clip = { options = { 'CLIP_1', 'CLIP_2' }, default = 'CLIP_1' } },
} } })
local function invoke(name, value)
    local result
    callbacks[name](value, function(response) result = response end)
    return result
end
assert(invoke('previewAccessories', { id = 'carbine', choices = {} }).ok)
threads[#threads]()
local rooftop
for _, call in ipairs(calls) do
    if call[1] == 'coords' and call[2] == 2 and call[3] == -75.0 and call[4] == -818.0 then rooftop = true end
    assert(not (call[1] == 'coords' and call[2] == 1), 'le joueur réel ne doit pas être téléporté')
end
assert(rooftop, 'le clone doit être placé sur la Maze Bank')
local stop = {}
env.Wait = function() error(stop) end
local _, reason = pcall(threads[1])
assert(reason == stop)
env.Wait = function() end
local hidden = {}
for _, call in ipairs(calls) do if call[1] == 'hidden' then hidden[call[2]] = true end end
assert(hidden[1] and hidden[4] and not hidden[2], 'seuls les personnages des joueurs doivent être masqués localement')
invoke('updateAccessoryPreview', { id = 'carbine', revision = 2,
    choices = { sight = 'COMPONENT_AT_SCOPE_MEDIUM', clip = 'CLIP_2' } })
local found, objectFound
for _, call in ipairs(calls) do
    if call[1] == 'component' and call[2] == 2 and call[4] == 'COMPONENT_AT_SCOPE_MEDIUM' then found = true end
    if call[1] == 'objectComponent' and call[2] == 9 and call[3] == 'COMPONENT_AT_SCOPE_MEDIUM' then objectFound = true end
end
assert(found, 'le viseur doit être appliqué au clone')
assert(objectFound, 'le viseur doit aussi être appliqué au modèle visible')
local count = #calls
invoke('updateAccessoryPreview', { id = 'carbine', revision = 1, choices = { sight = '' } })
assert(#calls == count, 'une ancienne sélection ne doit pas écraser la plus récente')
local lastRemove, firstAdd = 0, nil
for i = count, 1, -1 do
    local call = calls[i]
    if call[1] == 'component' then firstAdd = i end
    if call[1] == 'remove' then lastRemove = i break end
end
assert(firstAdd and lastRemove < firstAdd, 'les anciennes pièces doivent être retirées avant les nouvelles')
events['gf_inventory:accessoriesSaved']('carbine')
local deleted, camera, focus
for _, call in ipairs(calls) do
    if call[1] == 'delete' and call[2] == 2 then deleted = true end
    if call[1] == 'camera' and call[2] == 3 then camera = true end
    if call[1] == 'clearfocus' then focus = true end
end
assert(deleted and camera and focus, 'le clone, la caméra et le focus doivent être libérés')
assert(not invoke('previewAccessories', { id = 'unknown' }).ok, 'une arme inconnue est refusée')
print('Aperçu : clone, modification et nettoyage vérifiés')
