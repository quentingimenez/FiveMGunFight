-- =============================================================================
--  gf_lobby client: every NUI callback must answer the page.
--  Run from the repository root: lua5.4 tests/lua/lobby_nui_callbacks_test.lua
--
--  client.lua is loaded as is, in a sandbox where FiveM natives are no-op
--  stubs. RegisterNUICallback records the handlers so the test can call them
--  the way FiveM does.
-- =============================================================================

package.path = (os.getenv('GF_ROOT') or '.') .. '/tests/lua/lib/?.lua;' .. package.path
local T = require('assert')
local F = require('fivem')

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

local function capture(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, ' ')
end

local sb = F.sandbox({
    resource = 'gf_lobby',
    globals = {
        print = capture,
        RegisterCommand = function() end,
        PlayerPedId = function() return 0 end,
    },
})

sb:load('server-data/resources/[gunfight]/gf_lobby/config.lua')
sb:load('server-data/resources/[gunfight]/gf_lobby/client.lua')

-- Calls a registered NUI callback the way FiveM does and returns every
-- payload sent back to the page.
local function invoke(name, body)
    local handler = assert(sb.nui[name], 'NUI callback not registered: ' .. name)
    local answers = {}
    handler(body, fivemFuncRef(function(payload) answers[#answers + 1] = payload end))
    return answers
end

local answers = invoke('heartbeat', {})
T.equal(#answers, 1, 'heartbeat answers through a FiveM function reference: answers')
T.equal(answers[1] and answers[1].ok, true, 'heartbeat answers through a FiveM function reference: ok')

answers = invoke('previewCharacter', { gender = 'female', seed = 1337, skin = 0 })
T.equal(#answers, 1, 'previewCharacter answers ok for a valid character: answers')
T.equal(answers[1] and answers[1].ok, true, 'previewCharacter answers ok for a valid character: ok')

answers = invoke('previewCharacter', { gender = 'robot', seed = 1337, skin = 0 })
T.equal(#answers, 1, 'previewCharacter answers the error for an invalid character: answers')
T.equal(answers[1] and answers[1].ok, false, 'previewCharacter answers the error for an invalid character: ok')
T.equal(answers[1] and answers[1].error, 'invalid_character', 'previewCharacter answers the error for an invalid character: error')

do
    local names = {}
    for name in pairs(sb.nui) do names[#names + 1] = name end
    table.sort(names)
    T.check(#names > 0, 'every registered callback answers exactly once: registered callbacks')
    for _, name in ipairs(names) do
        local perCallback = invoke(name, {})
        T.equal(#perCallback, 1, 'every registered callback answers exactly once: answers from ' .. name)
    end
end

do
    local message = 'a callback without a usable cb is ignored without an error'
    for _, cb in ipairs({ {}, false, 'cb' }) do
        local before = #printed
        sb.nui.heartbeat({}, cb)
        T.equal(#printed, before, message .. ': unexpected output')
    end
end

answers = invoke('voteMap', { id = 'secours_1' })
T.equal(#answers, 1, 'voteMap answers ok for a valid map id: answers')
T.equal(answers[1] and answers[1].ok, true, 'voteMap answers ok for a valid map id: ok')
T.equal(answers[1] ~= nil and answers[1].error, nil, 'voteMap answers ok for a valid map id: error')

answers = invoke('voteMap', { id = false })
T.equal(#answers, 1, 'voteMap answers ok for the false removal id: answers')
T.equal(answers[1] and answers[1].ok, true, 'voteMap answers ok for the false removal id: ok')

do
    local message = 'voteMap answers invalid_payload for invalid ids'
    local invalidBodies = {
        { id = 42 },
        { id = '' },
        { id = string.rep('a', 65) },
        {},  -- id = nil
    }
    for _, body in ipairs(invalidBodies) do
        local invalidAnswers = invoke('voteMap', body)
        T.equal(#invalidAnswers, 1, message .. ': answers')
        T.equal(invalidAnswers[1] and invalidAnswers[1].ok, false, message .. ': ok')
        T.equal(invalidAnswers[1] and invalidAnswers[1].error, 'invalid_payload', message .. ': error')
    end
    -- Non-table payloads must be rejected, never indexed.
    for _, body in ipairs({ 'x', false }) do
        local invalidAnswers = invoke('voteMap', body)
        T.equal(#invalidAnswers, 1, message .. ': answers')
        T.equal(invalidAnswers[1] and invalidAnswers[1].ok, false, message .. ': ok')
        T.equal(invalidAnswers[1] and invalidAnswers[1].error, 'invalid_payload', message .. ': error')
    end
    local nilAnswers = invoke('voteMap', nil)
    T.equal(#nilAnswers, 1, message .. ': answers')
    T.equal(nilAnswers[1] and nilAnswers[1].ok, false, message .. ': ok')
    T.equal(nilAnswers[1] and nilAnswers[1].error, 'invalid_payload', message .. ': error')
end

answers = invoke('voteMap', { id = string.rep('a', 64) })
T.equal(#answers, 1, 'voteMap accepts a 64-character id: answers')
T.equal(answers[1] and answers[1].ok, true, 'voteMap accepts a 64-character id: ok')

T.finish('lobby_nui_callbacks')
