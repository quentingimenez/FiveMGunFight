-- Une capture automatique ne doit pas écraser une photo présente sur le serveur.
local root = os.getenv('GF_ROOT') or '.'
local events, writes, updated = {}, 0, 0
local existing = true
local stub = function() end
local env = setmetatable({
    source = 1,
    Config = { Kinds = { weapons = {} }, Folder = 'thumbs', MaxImageBytes = 1024 },
    exports = { gf_core = { IsAdmin = function() return true end } },
    Base64 = { decode = function() return '\137PNG\r\n\26\nimage' end },
    GetCurrentResourceName = function() return 'gf_thumbs' end,
    RegisterCommand = stub,
    RegisterNetEvent = function(name, fn) events[name] = fn end,
    AddEventHandler = stub,
    LoadResourceFile = function() if existing then return 'photo' end end,
    SaveResourceFile = function() writes = writes + 1 return true end,
    TriggerClientEvent = function(name) if name == 'gf_thumbs:updated' then updated = updated + 1 end end,
}, { __index = _G })
assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_thumbs/server.lua', 't', env))()
local save = assert(events['gf_thumbs:save'])
save('weapons', 'WEAPON_TEST', 'data:image/png;base64,abc', true)
assert(writes == 0 and updated == 1, 'photo existante conservée')
existing = false
save('weapons', 'WEAPON_TEST', 'data:image/png;base64,abc', true)
assert(writes == 1, 'nouvelle photo automatique enregistrée')
existing = true
save('weapons', 'WEAPON_TEST', 'data:image/png;base64,abc', false)
assert(writes == 2, 'photo manuelle remplaçable')
print('Photos : protection des images existantes vérifiée')
