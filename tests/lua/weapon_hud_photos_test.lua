-- La réception des photos ne bloque pas les munitions et ne répète pas la requête.
local handlers, messages, calls, timers = {}, {}, {}, {}
local available, loading = true, true
local env = setmetatable({
    joaat = function() return 1 end,
    RegisterNetEvent = function(name, fn) handlers[name] = fn end,
    AddEventHandler = function(name, fn) handlers[name] = fn end,
    RegisterNUICallback = function() end,
    RegisterCommand = function() end,
    RegisterKeyMapping = function() end,
    SendNUIMessage = function(message) messages[#messages + 1] = message end,
    GetResourceState = function() return available and 'started' or 'stopped' end,
    CreateThread = function(fn) if not loading then fn() end end,
    SetTimeout = function(_, fn) timers[#timers + 1] = fn end,
    exports = { gf_thumbs = { Get = function(_, kind, names)
        calls[#calls + 1] = { kind = kind, names = names }
        return { WEAPON_GHOSTFAIR = 'data:image/png;base64,photo' }
    end } },
}, { __index = _G })

local root = os.getenv('GF_ROOT') or '.'
local chunk, err = loadfile(root .. '/server-data/resources/[gunfight]/gf_ui/client.lua', 't', env)
assert(chunk, err)
chunk()
loading = false
local weapons = {
    { key = '1', name = 'WEAPON_GHOSTFAIR', active = true, clip = 30 },
    { key = '2', name = 'WEAPON_PISTOL', active = false },
}
handlers['gf_ui:weapons'](weapons)
assert(#calls == 1 and #calls[1].names == 2)
assert(messages[1].type == 'weapons' and messages[2].type == 'weapon_photos')
weapons[1].clip = 29
handlers['gf_ui:weapons'](weapons)
assert(#calls == 1 and messages[#messages].data[1].clip == 29)
handlers['gf_thumbs:updated']('weapons', 'WEAPON_GHOSTFAIR')
timers[#timers]()
assert(#calls == 2 and calls[2].names[1] == 'WEAPON_GHOSTFAIR')
handlers['gf_ui:weapons'](nil)
available = false
handlers['gf_ui:weapons']({ { name = 'WEAPON_SMG' } })
assert(#calls == 2)
print('Photos du HUD : chargement, cache, actualisation et munitions vérifiés')
