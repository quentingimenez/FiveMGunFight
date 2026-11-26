-- =============================================================================
--  gf_lobby client: every NUI callback must answer the page.
--  Run from the repository root: lua5.4 tests/lua/lobby_nui_callbacks.lua
--
--  client.lua is loaded as is, in a sandbox where FiveM natives are no-op
--  stubs. RegisterNUICallback records the handlers so the test can call them
--  the way FiveM does.
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

local RESOURCE = repoRoot() .. '/server-data/resources/[gunfight]/gf_lobby/'

-- FiveM hands NUI callbacks a function reference, not a Lua function: a table
-- whose metatable has __call (funcref_mt in citizen/scripting/lua/scheduler.lua).
-- Indexing it raises, like the real one.
local function fivemFuncRef(onCall)
    return setmetatable({}, {
        __call = function(_, ...) onCall(...) end,
        __index = function() error('Cannot index a funcref', 2) end,
        __newindex = function() error('Cannot set indexes on a funcref', 2) end,
    })
end

local printed = {}

local function loadClient()
    local callbacks = {}
    local stub = function() return nil end
    local env = setmetatable({
        print = function(...)
            local parts = {}
            for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
            printed[#printed + 1] = table.concat(parts, ' ')
        end,
        RegisterNUICallback = function(name, handler) callbacks[name] = handler end,
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
    return callbacks
end

-- Calls a registered NUI callback the way FiveM does and returns every
-- payload sent back to the page.
local function invoke(callbacks, name, body)
    local handler = assert(callbacks[name], 'NUI callback not registered: ' .. name)
    local answers = {}
    handler(body, fivemFuncRef(function(payload) answers[#answers + 1] = payload end))
    return answers
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
        error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local callbacks = loadClient()

check('heartbeat answers through a FiveM function reference', function()
    local answers = invoke(callbacks, 'heartbeat', {})
    equal(1, #answers, 'answers')
    equal(true, answers[1].ok, 'ok')
end)

check('previewCharacter answers ok for a valid character', function()
    local answers = invoke(callbacks, 'previewCharacter', { gender = 'female', seed = 1337, skin = 0 })
    equal(1, #answers, 'answers')
    equal(true, answers[1].ok, 'ok')
end)

check('previewCharacter answers the error for an invalid character', function()
    local answers = invoke(callbacks, 'previewCharacter', { gender = 'robot', seed = 1337, skin = 0 })
    equal(1, #answers, 'answers')
    equal(false, answers[1].ok, 'ok')
    equal('invalid_character', answers[1].error, 'error')
end)

check('every registered callback answers exactly once', function()
    local names = {}
    for name in pairs(callbacks) do names[#names + 1] = name end
    table.sort(names)
    equal(true, #names > 0, 'registered callbacks')
    for _, name in ipairs(names) do
        local answers = invoke(callbacks, name, {})
        equal(1, #answers, 'answers from ' .. name)
    end
end)

check('a callback without a usable cb is ignored without an error', function()
    for _, cb in ipairs({ {}, false, 'cb' }) do
        local before = #printed
        callbacks.heartbeat({}, cb)
        for i = before + 1, #printed do
            error('unexpected output: ' .. printed[i], 0)
        end
    end
end)

check('voteMap answers ok for a valid map id', function()
    local answers = invoke(callbacks, 'voteMap', { id = 'secours_1' })
    equal(1, #answers, 'answers')
    equal(true, answers[1].ok, 'ok')
    equal(nil, answers[1].error, 'error')
end)

check('voteMap answers ok for the false removal id', function()
    local answers = invoke(callbacks, 'voteMap', { id = false })
    equal(1, #answers, 'answers')
    equal(true, answers[1].ok, 'ok')
end)

check('voteMap answers invalid_payload for invalid ids', function()
    local invalidBodies = {
        { id = 42 },
        { id = '' },
        { id = string.rep('a', 65) },
        {},  -- id = nil
    }
    for _, body in ipairs(invalidBodies) do
        local answers = invoke(callbacks, 'voteMap', body)
        equal(1, #answers, 'answers')
        equal(false, answers[1].ok, 'ok')
        equal('invalid_payload', answers[1].error, 'error')
    end
    -- Non-table payloads must be rejected, never indexed.
    for _, body in ipairs({ 'x', false }) do
        local answers = invoke(callbacks, 'voteMap', body)
        equal(1, #answers, 'answers')
        equal(false, answers[1].ok, 'ok')
        equal('invalid_payload', answers[1].error, 'error')
    end
    local answers = invoke(callbacks, 'voteMap', nil)
    equal(1, #answers, 'answers')
    equal(false, answers[1].ok, 'ok')
    equal('invalid_payload', answers[1].error, 'error')
end)

check('voteMap accepts a 64-character id', function()
    local answers = invoke(callbacks, 'voteMap', { id = string.rep('a', 64) })
    equal(1, #answers, 'answers')
    equal(true, answers[1].ok, 'ok')
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
