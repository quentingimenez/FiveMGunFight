-- =============================================================================
--  Bac à sable FiveM partagé par les tests Lua (chantier C18).
--  Ajouter tests/lua/lib à package.path puis require('fivem'). F.sandbox(options)
--  crée un environnement pour loadfile : le harnais y pose ses stubs FiveM,
--  options.globals les complète/écrase et options.overrides s'applique en
--  dernier ; les globales inconnues ne sont pas inventées (__index = _G).
--  F.root() donne la racine (GF_ROOT ou '.') et sb:load(chemin relatif) charge
--  un VRAI fichier de ressource. Le temps est pilotable (sb.now, sb:advance),
--  les threads ne démarrent pas seuls (sb:runThread, Wait lève F.STOP) et le
--  NUI se pilote avec sb:nuiCall / sb:nuiMessages / sb.focusCalls. Exemple :
--    local F = require('fivem')
--    local sb = F.sandbox({ resource = 'gf_menu' })
--    for _, f in ipairs({ 'config.lua', 'client.lua' }) do
--        sb:load('server-data/resources/[gunfight]/gf_menu/' .. f)
--    end
--    sb:runThread(1) ; sb:advance(5000) ; sb:nuiCall('ready', {})
-- =============================================================================

local F = {}

F.STOP = {}

function F.root()
    local override = os.getenv('GF_ROOT')
    if override and override ~= '' then return override end
    return '.'
end

local function listOf(t, name)
    if t == nil then return {} end
    if type(t) ~= 'table' then
        error(('fivem: %s doit être une table'):format(name), 2)
    end
    return t
end

function F.sandbox(options)
    options = options or {}
    local sb = {}

    sb.events = {}
    sb.sent = {}
    sb.provided = {}
    sb.timeouts = {}
    sb.threads = {}
    sb.nui = {}
    sb.nuiMessages = {}
    sb.focusCalls = {}
    sb.focus = nil
    sb.now = 0
    sb.files = listOf(options.files, 'options.files')

    local externalExports = listOf(options.exports, 'options.exports')
    local playerStates = {}

    local env = { source = options.source or 1 }
    setmetatable(env, { __index = _G })
    sb.env = env

    -- --------------------------------------------------------------- événements
    local function register(name, fn)
        local handlers = sb.events[name]
        if not handlers then
            handlers = {}
            sb.events[name] = handlers
        end
        handlers[#handlers + 1] = fn
    end

    env.RegisterNetEvent = register
    env.AddEventHandler = register

    function sb:emit(name, ...)
        env.source = options.source or 1
        local handlers = sb.events[name]
        if not handlers then return end
        for i = 1, #handlers do handlers[i](...) end
    end

    env.TriggerEvent = function(name, ...)
        local handlers = sb.events[name]
        if not handlers then return end
        for i = 1, #handlers do handlers[i](...) end
    end

    local function send(name, target, ...)
        sb.sent[#sb.sent + 1] = { nom = name, cible = target, args = { ... } }
    end

    env.TriggerClientEvent = function(name, target, ...) send(name, target, ...) end
    env.TriggerServerEvent = function(name, ...) send(name, nil, ...) end
    env.TriggerLatentClientEvent = function(name, target, ...) send(name, target, ...) end

    -- ------------------------------------------------------------------ exports
    local exportsTable = {}
    setmetatable(exportsTable, {
        __call = function(_, name, fn)
            sb.provided[name] = fn
        end,
        __index = function(_, name)
            return externalExports[name]
        end,
    })
    env.exports = exportsTable

    -- --------------------------------------------------------------------- temps
    env.GetGameTimer = function() return sb.now end

    local nextTimeoutId = 0
    env.SetTimeout = function(ms, fn)
        nextTimeoutId = nextTimeoutId + 1
        sb.timeouts[#sb.timeouts + 1] = {
            id = nextTimeoutId,
            due = sb.now + (ms or 0),
            fn = fn,
            order = nextTimeoutId,
            done = false,
        }
    end

    function sb:advance(ms)
        sb.now = sb.now + (ms or 0)
        while true do
            -- Échéance la plus proche, puis ordre d'enregistrement.
            local chosen, chosenIndex
            for i, timeout in ipairs(sb.timeouts) do
                if not timeout.done and timeout.due <= sb.now then
                    if not chosen or timeout.due < chosen.due
                        or (timeout.due == chosen.due and timeout.order < chosen.order) then
                        chosen, chosenIndex = timeout, i
                    end
                end
            end
            if not chosen then break end
            chosen.done = true
            table.remove(sb.timeouts, chosenIndex)
            chosen.fn()
        end
    end

    -- -------------------------------------------------------------------- threads
    local function storeThread(fn)
        sb.threads[#sb.threads + 1] = fn
    end
    env.CreateThread = storeThread
    env.Citizen = { CreateThread = storeThread }

    local function stopWait()
        error(F.STOP, 0)
    end
    env.Wait = stopWait
    env.Citizen.Wait = stopWait

    function sb:runThread(i)
        local fn = sb.threads[i]
        if not fn then error(('fivem: thread %s inexistant'):format(tostring(i)), 2) end
        local ok, err = pcall(fn)
        if ok then return end
        if err ~= F.STOP then error(err, 0) end
    end

    -- ----------------------------------------------------------------------- NUI
    env.RegisterNUICallback = function(name, fn)
        sb.nui[name] = fn
    end

    function sb:nuiCall(name, data)
        local callback = sb.nui[name]
        if not callback then
            error(('fivem: callback NUI non enregistré : %s'):format(tostring(name)), 2)
        end
        local answer
        local replied = false
        callback(data, function(payload)
            replied = true
            answer = payload
        end)
        if replied then return answer end
        return nil
    end

    env.SendNUIMessage = function(payload)
        sb.nuiMessages[#sb.nuiMessages + 1] = payload
    end

    env.SetNuiFocus = function(a, b)
        sb.focus = { a, b }
        sb.focusCalls[#sb.focusCalls + 1] = { a, b }
    end

    -- --------------------------------------------------------------- state bags
    env.Player = function(id)
        local player = playerStates[id]
        if not player then
            player = {}
            player.state = {}
            local state = player.state
            function state:set(key, value)
                state[key] = value
            end
            playerStates[id] = player
        end
        return player
    end

    env.GlobalState = {}
    function env.GlobalState:set(key, value)
        env.GlobalState[key] = value
    end

    -- -------------------------------------------------------------------- fichiers
    env.LoadResourceFile = function(resource, path)
        return sb.files[path]
    end
    env.SaveResourceFile = function(resource, path, content, length)
        sb.files[path] = content
        return true
    end

    env.GetCurrentResourceName = function()
        return options.resource
    end

    -- -------------------------------------------------------------- surcharges
    for key, value in pairs(listOf(options.globals, 'options.globals')) do
        env[key] = value
    end
    for key, value in pairs(listOf(options.overrides, 'options.overrides')) do
        env[key] = value
    end

    function sb:load(relativePath)
        local chunk = assert(loadfile(F.root() .. '/' .. relativePath, 't', env))
        chunk()
    end

    return sb
end

return F
