-- Les délais réseau ne doivent jamais faire passer une photo existante pour absente.
local root = os.getenv('GF_ROOT') or '.'
local path = root .. '/server-data/resources/[gunfight]/gf_thumbs/'
local handlers, exported, batches = {}, {}, {}
local timeout, fail = nil, false
local stub = function() end
local env = setmetatable({
    Config = { AutoCapture = false },
    LocalPlayer = { state = {} },
    exports = setmetatable({}, { __call = function(_, name, fn) exported[name] = fn end }),
    RegisterNetEvent = function(name, fn) handlers[name] = fn end,
    RegisterNUICallback = stub, CreateThread = stub,
    GetResourceKvpString = stub,
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    Wait = stub,
    promise = { new = function()
        return { resolve = function(self, value) self.value = value end }
    end },
    SetTimeout = function(_, fn) timeout = fn end,
    Citizen = { Await = function(p)
        if not p.value then timeout() end
        return p.value
    end },
    TriggerServerEvent = function(name, req, kind, ids)
        if name ~= 'gf_thumbs:request' then return end
        batches[#batches + 1] = #ids
        if fail then return end
        local result = {}
        for _, id in ipairs(ids) do result[id] = 'photo-' .. id end
        handlers['gf_thumbs:data'](req, kind, result)
    end,
}, { __index = _G })
-- FiveM utilise p:resolve(...), la fonction stockée reçoit implicitement p.
assert(loadfile(path .. 'client.lua', 't', env))()
local ids = {}
for i = 1, 20 do ids[i] = tostring(i) end
local photos, complete = exported.Get('weapons', ids)
assert(complete and photos['20'] == 'photo-20', 'toutes les photos')
assert(#batches == 3 and batches[1] == 8 and batches[2] == 8 and batches[3] == 4, 'lots limités')
fail = true
local missing, ok = exported.Get('weapons', { 'late' })
assert(not ok and not missing.late, 'délai signalé')
fail = false
local retried, success = exported.Get('weapons', { 'late' })
assert(success and retried.late == 'photo-late', 'nouvel essai après délai')
print('Photos : lots et reprise après délai vérifiés')
