-- =============================================================================
--  gf_menu client : callbacks NUI et événements enregistrés.
--  Exécuter depuis la racine du dépôt : lua5.4 tests/lua/menu_nui_callbacks.lua
--
--  client.lua est chargé tel quel dans un bac à sable : CreateThread ne lance
--  PAS sa boucle, SetTimeout enregistre sans déclencher, RegisterNetEvent et
--  RegisterNUICallback capturent les handlers sous leur nom.
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

local printed = {}
local callbacks, events, messages, serverEvents, threads, timeouts = {}, {}, {}, {}, {}, {}

-- Le corps du thread atteint Wait(0) : lever cette sentinelle interrompt la
-- boucle sans la laisser tourner à l'infini, et pcall la récupère en dehors.
local WAIT_SENTINEL = {}
local gameTimer = 0
local pausePressed = false

local function loadClient()
    local stub = function() return nil end
    local env = setmetatable({
        Config = TEST_CONFIG,
        print = function(...)
            local parts = {}
            for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
            printed[#printed + 1] = table.concat(parts, ' ')
        end,
        CreateThread = function(fn) threads[#threads + 1] = fn end,
        SetTimeout = function(ms, fn) timeouts[#timeouts + 1] = { ms = ms, fn = fn } end,
        RegisterNetEvent = function(name, fn) events[name] = fn end,
        RegisterNUICallback = function(name, fn) callbacks[name] = fn end,
        AddEventHandler = function(name, fn) events['@' .. name] = fn end,
        SendNUIMessage = function(payload) messages[#messages + 1] = payload end,
        TriggerServerEvent = function(name) serverEvents[#serverEvents + 1] = name end,
        GetGameTimer = function() return gameTimer end,
        GetCurrentResourceName = function() return 'gf_menu' end,
        SetNuiFocus = stub,
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
    -- config.lua defini une table locale dans son propre environnement : on
    -- recopie ses valeurs pour que le test lise les memes seuils que client.lua.
    for key, value in pairs(env.Config) do TEST_CONFIG[key] = value end
end

-- FiveM transmet un cb fonction : on collecte chaque réponse sans en perdre.
local function invoke(name, body)
    local handler = assert(callbacks[name], 'NUI callback not registered: ' .. name)
    local answers = {}
    handler(body, function(payload) answers[#answers + 1] = payload end)
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
        error(('%s : attendu %s, obtenu %s'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

loadClient()

check('callbacks ready, close et quit enregistrés', function()
    for _, name in ipairs({ 'ready', 'close', 'quit' }) do
        equal('function', type(callbacks[name]), 'callback ' .. name)
    end
end)

check('événements client enregistrés', function()
    for _, name in ipairs({
        'gf_menu:state', 'gf_lobby:state', 'gf_core:modeChanged', 'gf_core:spawned',
    }) do
        equal('function', type(events[name]), 'événement ' .. name)
    end
end)

check('CreateThread capturé sans exécuter la boucle', function()
    equal(1, #threads, 'threads enregistrés')
    equal('function', type(threads[1]), 'corps du thread')
end)

check('SetTimeout enregistré sans déclencher le garde-fou', function()
    equal(0, #timeouts, 'timeouts avant ouverture')

    -- Assez tard pour passer l'anti double appui ; une seule itération du
    -- thread suffit : le Wait lève la sentinelle juste après ouverture.
    gameTimer = TEST_CONFIG.ReopenDelayMs
    pausePressed = true
    local ok, err = pcall(threads[1])
    pausePressed = false
    equal(WAIT_SENTINEL, err, 'sentinelle de Wait (pcall)')

    equal(1, #timeouts, 'timeouts enregistrés')
    equal(TEST_CONFIG.PageReadyTimeoutMs, timeouts[1].ms, 'délai du garde-fou')
    equal('function', type(timeouts[1].fn), 'fonction du garde-fou')
    equal(0, #printed, 'garde-fou non déclenché')
end)

check('ready répond une fois ok après initialisation', function()
    local answers = invoke('ready', {})
    equal(1, #answers, 'réponses de ready')
    equal(true, answers[1].ok, 'ok')
end)

check('close répond une fois ok quand la page est prête', function()
    local answers = invoke('close', {})
    equal(1, #answers, 'réponses de close')
    equal(true, answers[1].ok, 'ok')
end)

check('quit répond une fois ok et prévient le serveur', function()
    local before = #serverEvents
    local answers = invoke('quit', {})
    equal(1, #answers, 'réponses de quit')
    equal(true, answers[1].ok, 'ok')
    equal(before + 1, #serverEvents, 'server events')
    equal('gf_menu:quit', serverEvents[#serverEvents], 'event serveur')
end)

check('close et quit avec un cb non fonction ne lèvent pas d erreur', function()
    for _, entree in ipairs({ { cb = {} }, { cb = false }, { cb = 'cb' }, { cb = nil } }) do
        local cb = entree.cb
        local before = #printed
        local okClose = pcall(callbacks.close, {}, cb)
        local okQuit = pcall(callbacks.quit, {}, cb)
        equal(true, okClose, 'close avec cb ' .. type(cb))
        equal(true, okQuit, 'quit avec cb ' .. type(cb))
        for i = before + 1, #printed do
            error('sortie inattendue : ' .. printed[i], 0)
        end
    end
end)

-- FiveM passe une funcref : une table dont __call exécute la fonction cible.
local function funcref(fn)
    return setmetatable({}, { __call = function(_, payload) fn(payload) end })
end

local function invokeFuncref(name, body)
    local handler = assert(callbacks[name], 'NUI callback not registered: ' .. name)
    local answers = {}
    local cb = funcref(function(payload) answers[#answers + 1] = payload end)
    handler(body, cb)
    return answers
end

check('un cb funcref responds exactement une fois', function()
    for _, name in ipairs({ 'ready', 'close', 'quit' }) do
        local answers = invokeFuncref(name, {})
        equal(1, #answers, 'réponses de ' .. name)
        equal(true, answers[1].ok, 'ok')
    end
end)

check('un cb valide répond encore une seule fois après un cb invalide', function()
    local answers = invoke('close', {})
    equal(1, #answers, 'réponses de close')
    equal(true, answers[1].ok, 'ok')
end)

check('gf_menu:state accepte une table quand le menu est fermé', function()
    local before = #messages
    local ok, err = pcall(events['gf_menu:state'], { build = 'dev', me = { name = 'Alice' } })
    equal(true, ok, 'handler sans erreur' .. (ok and '' or (' : ' .. tostring(err))))
    equal(before, #messages, 'aucun message NUI quand le menu est fermé')
end)

check('gf_menu:state ignore une charge utile non table', function()
    local before = #messages
    local ok = pcall(events['gf_menu:state'], 'invalide')
    equal(true, ok, 'handler sans erreur')
    equal(before, #messages, 'aucun message NUI')
end)

check('gf_lobby:state, modeChanged et spawned sans effet de bord', function()
    local before = #messages
    local okLobby = pcall(events['gf_lobby:state'], { me = { inLobby = true } })
    local okMode = pcall(events['gf_core:modeChanged'])
    local okSpawn = pcall(events['gf_core:spawned'])
    equal(true, okLobby, 'gf_lobby:state')
    equal(true, okMode, 'gf_core:modeChanged')
    equal(true, okSpawn, 'gf_core:spawned')
    equal(before, #messages, 'aucun message NUI')
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
