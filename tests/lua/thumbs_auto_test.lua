-- Vérifie qu'un départ rapide du lobby ne désactive pas les prochaines photos.
local root = os.getenv('GF_ROOT') or '.'
local resource = root .. '/server-data/resources/[gunfight]/gf_thumbs/'
local events, threads, sent, timers = {}, {}, {}, {}
local mode = { gf_mode = 'lobby' }
local stub = function() end
local env = setmetatable({
    Config = { AutoCapture = true, AutoCaptureDelay = 8000 },
    LocalPlayer = { state = mode },
    exports = setmetatable({}, { __call = stub }),
    RegisterNetEvent = function(name, fn) events[name] = fn end,
    RegisterNUICallback = stub,
    CreateThread = function(fn) threads[#threads + 1] = fn end,
    SetTimeout = function(_, fn) timers[#timers + 1] = fn end,
    GetResourceKvpString = stub,
    GetCurrentResourceName = function() return 'gf_thumbs' end,
    GetGameTimer = function() return 0 end,
    vector3 = function(x, y, z) return { x = x, y = y, z = z } end,
    NetworkIsPlayerActive = function() return true end,
    PlayerId = function() return 1 end,
    TriggerServerEvent = function(name) sent[#sent + 1] = name end,
    Wait = stub,
}, { __index = _G })
assert(loadfile(root .. '/server-data/resources/[gunfight]/gf_core/crash_marker.lua', 't', env))()
assert(loadfile(resource .. 'client.lua', 't', env))()
local changed = assert(events['gf_core:modeChanged'])

changed('lobby')
local first = timers[#timers]
mode.gf_mode = 'redzone'
changed('redzone')
first()
assert(#sent == 0, 'départ avant le délai : aucune capture')

mode.gf_mode = 'lobby'
changed('lobby')
timers[#timers]()
assert(#sent == 1 and sent[1] == 'gf_thumbs:lobbyReady', 'retour : nouvelle demande')
timers[#timers]()
assert(#sent == 2, 'nouvelle tentative automatique pendant le séjour au lobby')

changed('lobby')
local stale = timers[#timers]
changed('lobby')
stale()
timers[#timers]()
assert(#sent == 3, 'une seule demande pour les événements rapprochés')
print('Capture automatique : retour, nouvelle tentative et annulation vérifiés')
