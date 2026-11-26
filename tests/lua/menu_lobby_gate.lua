-- =============================================================================
--  gf_menu : le garde-fou du lobby ne doit pas bloquer Échap après un spawn.
--  Exécuter depuis la racine du dépôt : lua5.4 tests/lua/menu_lobby_gate.lua
--
--  client.lua est chargé tel quel dans un bac à sable : CreateThread ne lance
--  PAS sa boucle, Wait lève une sentinelle après un passage, RegisterNetEvent
--  capture les handlers, SetNuiFocus et SendNUIMessage enregistrent les appels.
-- =============================================================================

local function repoRoot()
    local override = os.getenv('GF_ROOT')
    if override and override ~= '' then return override end
    local info = debug.getinfo(1, 'S')
    local path = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    path = path:gsub('\\', '/')
    local prefix = path:match('^(.*)/tests/lua/[^/]+%.lua$')
    if prefix and prefix ~= '' then return prefix end
    return '.'
end

local RESOURCE = repoRoot() .. '/server-data/resources/[gunfight]/gf_menu/'
local TEST_CONFIG = {}

local events, threads, messages, focusCalls, serverEvents, timeouts = {}, {}, {}, {}, {}, {}
local WAIT_SENTINEL = {}
local gameTimer = 0
local pausePressed = false

local function loadClient()
    local stub = function() return nil end
    local env = setmetatable({
        Config = TEST_CONFIG,
        print = function() end,
        CreateThread = function(fn) threads[#threads + 1] = fn end,
        SetTimeout = function(ms, fn) timeouts[#timeouts + 1] = { ms = ms, fn = fn } end,
        RegisterNetEvent = function(name, fn) events[name] = fn end,
        RegisterNUICallback = function() end,
        AddEventHandler = function(name, fn) events['@' .. name] = fn end,
        SendNUIMessage = function(payload) messages[#messages + 1] = payload end,
        TriggerServerEvent = function(name) serverEvents[#serverEvents + 1] = name end,
        GetGameTimer = function() return gameTimer end,
        GetCurrentResourceName = function() return 'gf_menu' end,
        SetNuiFocus = function(on, cursor) focusCalls[#focusCalls + 1] = { on = on, cursor = cursor } end,
        SetNuiFocusKeepInput = stub,
        DisableFrontendThisFrame = stub,
        DisableControlAction = stub,
        IsDisabledControlJustPressed = function() return pausePressed end,
        Wait = function() error(WAIT_SENTINEL, 0) end,
    }, {
        __index = function(_, key)
            local value = _G[key]
            if value ~= nil then return value end
            return stub
        end,
    })
    for _, file in ipairs({ 'config.lua', 'client.lua' }) do
        local chunk = assert(loadfile(RESOURCE .. file, 't', env))
        chunk()
    end
    for key, value in pairs(env.Config) do TEST_CONFIG[key] = value end
end

local passed, failed = 0, 0

local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print(('ok      %s'):format(name))
    else
        failed = failed + 1
        print(('FAIL    %s\n        %s'):format(name, tostring(err)))
    end
end

local function equal(expected, actual, message)
    if expected ~= actual then
        error(('%s : attendu %s, obtenu %s'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

-- Une seule itération : GetGameTimer assez loin pour passer ReopenDelayMs,
-- Wait lève la sentinelle juste après la gestion de l'appui.
local function pressEchap()
    gameTimer = TEST_CONFIG.ReopenDelayMs
    pausePressed = true
    local ok, err = pcall(threads[1])
    pausePressed = false
    equal(false, ok, 'thread interrompu par Wait')
    equal(WAIT_SENTINEL, err, 'sentinelle de Wait')
end

local function hasOpenMessage(from)
    for i = (from or 1), #messages do
        local payload = messages[i]
        if type(payload) == 'table' and payload.type == 'open' then return true end
    end
    return false
end

loadClient()

check('handlers et thread enregistrés', function()
    equal('function', type(events['gf_lobby:state']), 'gf_lobby:state')
    equal('function', type(events['gf_core:modeChanged']), 'gf_core:modeChanged')
    equal(1, #threads, 'threads')
end)

check('inLobby seul bloque Échap (garde-fou actif)', function()
    events['gf_lobby:state']({ me = { inLobby = true } })
    pressEchap()
    equal(0, #focusCalls, 'aucun SetNuiFocus')
    equal(false, hasOpenMessage(), 'aucun message open')
    equal(0, #serverEvents, 'aucune demande d état')
end)

check('modeChanged redzone rend la main et ouvre le menu', function()
    events['gf_core:modeChanged']('redzone')
    pressEchap()
    equal(1, #focusCalls, 'un SetNuiFocus')
    equal(true, focusCalls[1].on, 'SetNuiFocus(true')
    equal(true, focusCalls[1].cursor, 'SetNuiFocus(..., true)')
    equal(true, hasOpenMessage(), 'message open émis')
end)

check('mode lobby ne lève pas le garde-fou', function()
    events['gf_lobby:state']({ me = { inLobby = true } })
    events['gf_core:modeChanged']('lobby')
    local beforeFocus, beforeMessages = #focusCalls, #messages
    pressEchap()
    equal(beforeFocus, #focusCalls, 'aucun SetNuiFocus supplémentaire')
    equal(false, hasOpenMessage(beforeMessages + 1), 'aucun message open')
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
