-- =============================================================================
--  gf_menu : le garde-fou du lobby ne doit pas bloquer Échap après un spawn.
--  Exécuter depuis la racine du dépôt : lua5.4 tests/lua/menu_lobby_gate_test.lua
--
--  client.lua est chargé tel quel dans le bac à sable partagé : CreateThread ne
--  lance PAS sa boucle, Wait lève F.STOP après un passage, RegisterNetEvent
--  capture les handlers (listes), SetNuiFocus et SendNUIMessage enregistrent
--  les appels. Le temps est piloté par sb.now.
-- =============================================================================

package.path = (os.getenv('GF_ROOT') or '.') .. '/tests/lua/lib/?.lua;' .. package.path
local T = require('assert')
local F = require('fivem')

local pausePressed = false

local sb = F.sandbox({
    resource = 'gf_menu',
    exports = {
        gf_ui = {
            PushLayer = function() return true end,
            PopLayer = function() return true end,
        },
    },
    globals = {
        DisableFrontendThisFrame = function() end,
        DisableControlAction = function() end,
        SetNuiFocusKeepInput = function() end,
    },
    overrides = { IsDisabledControlJustPressed = function() return pausePressed end },
})

sb:load('server-data/resources/[gunfight]/gf_menu/config.lua')
sb:load('server-data/resources/[gunfight]/gf_menu/client.lua')

local CONFIG = sb.env.Config

-- Une seule itération : sb.now assez loin pour passer ReopenDelayMs,
-- Wait lève la sentinelle juste après la gestion de l'appui.
local function pressEchap()
    sb.now = CONFIG.ReopenDelayMs
    pausePressed = true
    local ok, err = pcall(sb.threads[1])
    pausePressed = false
    T.equal(ok, false, 'thread interrompu par Wait')
    T.equal(err, F.STOP, 'sentinelle de Wait')
end

local function hasOpenMessage(from)
    for i = (from or 1), #sb.nuiMessages do
        local payload = sb.nuiMessages[i]
        if type(payload) == 'table' and payload.type == 'open' then return true end
    end
    return false
end

-- Le harnais enregistre cible = nil pour TriggerServerEvent.
local function serverEventCount()
    local count = 0
    for _, entry in ipairs(sb.sent) do
        if entry.cible == nil then count = count + 1 end
    end
    return count
end

T.equal(type(sb.events['gf_lobby:state'] and sb.events['gf_lobby:state'][1]), 'function', 'gf_lobby:state')
T.equal(type(sb.events['gf_core:modeChanged'] and sb.events['gf_core:modeChanged'][1]), 'function', 'gf_core:modeChanged')
T.equal(#sb.threads, 1, 'threads')

sb:emit('gf_lobby:state', { me = { inLobby = true } })
pressEchap()
T.equal(#sb.focusCalls, 0, 'aucun SetNuiFocus')
T.equal(hasOpenMessage(), false, 'aucun message open')
T.equal(serverEventCount(), 0, 'aucune demande d état')

sb:emit('gf_core:modeChanged', 'redzone')
pressEchap()
T.equal(#sb.focusCalls, 1, 'un SetNuiFocus')
T.equal(sb.focusCalls[1] and sb.focusCalls[1][1], true, 'SetNuiFocus(true')
T.equal(sb.focusCalls[1] and sb.focusCalls[1][2], true, 'SetNuiFocus(..., true)')
T.equal(hasOpenMessage(), true, 'message open émis')

sb:emit('gf_lobby:state', { me = { inLobby = true } })
sb:emit('gf_core:modeChanged', 'lobby')
local beforeFocus, beforeMessages = #sb.focusCalls, #sb.nuiMessages
pressEchap()
T.equal(#sb.focusCalls, beforeFocus, 'aucun SetNuiFocus supplémentaire')
T.equal(hasOpenMessage(beforeMessages + 1), false, 'aucun message open')

T.finish('menu_lobby_gate')
