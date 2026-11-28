-- Le premier contrôle automatique doit concerner les armes, même si les
-- autres catalogues sont volumineux ou encore en cours de chargement.
local root = os.getenv('GF_ROOT') or '.'
local handlers, requests = {}, {}
local stub = function() end
local providers = {
    weaponsProvider = { List = function() return { { id = 'WEAPON_NEW' } } end },
    vehiclesProvider = { List = function() return { { id = 'CAR_NEW' } } end },
}
setmetatable(providers, { __call = stub })
local env = setmetatable({
    Config = { AutoCapture = false, Kinds = {
        vehicles = { auto = true, provider = { resource = 'vehiclesProvider', export = 'List' } },
        weapons = { auto = true, provider = { resource = 'weaponsProvider', export = 'List' } },
    } },
    LocalPlayer = { state = { gf_mode = 'lobby' } }, exports = providers,
    RegisterNetEvent = function(name, fn) handlers[name] = fn end,
    RegisterNUICallback = stub, CreateThread = stub, SetTimeout = stub,
    GetResourceKvpString = stub, GetResourceState = function() return 'started' end,
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    Wait = stub,
    promise = { new = function() return { resolve = function(self, value) self.value = value end } end },
    Citizen = { Await = function(p) return assert(p.value) end },
    TriggerServerEvent = function(name, req, kind, ids)
        if name ~= 'gf_thumbs:request' then return end
        requests[#requests + 1] = kind
        local result = {}
        for _, id in ipairs(ids) do result[id] = 'photo' end
        handlers['gf_thumbs:data'](req, kind, result)
    end,
}, { __index = _G })
assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_core/crash_marker.lua', 't', env))()
assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_thumbs/client.lua', 't', env))()
handlers['gf_thumbs:autoCapture']()
assert(requests[1] == 'weapons' and requests[2] == 'vehicles', 'armes vérifiées avant véhicules')
print('Photos : priorité aux armes vérifiée')
