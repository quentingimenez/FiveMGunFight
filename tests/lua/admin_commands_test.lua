-- =============================================================================
--  Partie D - commandes admin : message explicite au lieu du refus silencieux.
--
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/admin_commands_test.lua
--  La racine est calculée comme dans tests/lua/lobby_queue_test.lua
--  (GF_ROOT ou debug.getinfo du script).
--
--  Les vrais fichiers serveur sont chargés avec loadfile(path, 't', env) dans
--  TROIS bacs à sable distincts (un par ressource : chaque config.lua définit
--  le global Config). Aucune règle métier n'est recopiée ici : seules les
--  natives FiveM et les exports sont remplacées par des fausses pilotées.
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

local RESOURCES = repoRoot() .. '/server-data/resources/[gunfight]/'

local ADMIN_REQUIS = 'Réservé aux administrateurs. Tape /whoami pour voir ton identifiant.'
local IDENTIFIANTS = 'Identifiants : license:abc, fivem:42, discord:99'
local AIDE_ADMIN = 'Pour devenir admin, ajoute un de ces identifiants à la variable ADMIN_IDENTIFIERS du serveur (.env ou gabarit Unraid), puis redémarre-le.'

local passed, failed = 0, 0

local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print(('ok      %s'):format(name))
    else
        failed = failed + 1
        print(('ECHEC   %s\n        %s'):format(name, tostring(err)))
    end
end

local function equal(expected, actual, message)
    if expected ~= actual then
        error(('%s : attendu %s, obtenu %s'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local eq = equal

local function expectList(obtenu, attendu, message)
    equal(#attendu, #obtenu, message .. ' (taille)')
    for i = 1, #attendu do
        equal(attendu[i], obtenu[i], ('%s (%d)'):format(message, i))
    end
end

-- ---------------------------------------------------------------------------
--  Faux partagés par les trois ressources.
-- ---------------------------------------------------------------------------

local function stub() return nil end

-- Vecteur minimal : les configs utilisent vector3(...) et redzone fait
-- #(vector2(a) - vector2(b)) ; on fournit donc l'arithmétique et la norme.
local function newVector(x, y, z)
    return setmetatable({ x = x, y = y, z = z or 0 }, {
        __add = function(a, b) return newVector(a.x + b.x, a.y + b.y, a.z + b.z) end,
        __sub = function(a, b) return newVector(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __mul = function(a, b)
            if type(b) == 'number' then return newVector(a.x * b, a.y * b, a.z * b) end
            if type(a) == 'number' then return newVector(b.x * a, b.y * a, b.z * a) end
            return newVector(a.x * b.x, a.y * b.y, a.z * b.z)
        end,
        __unm = function(a) return newVector(-a.x, -a.y, -a.z) end,
        __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end,
    })
end

local function newHarness(admin)
    local h = {
        admin = admin and true or false,
        commands = {},        -- [nom] = gestionnaire
        netHandlers = {},
        eventHandlers = {},
        notices = {},         -- liste de { src, msg } (exports.gf_core:Notify)
        clients = {},         -- liste de { name, target, data }
        events = {},          -- liste de { name, args }
        logs = {},            -- lignes print()
        exportsByName = {},   -- exports('Nom', fn)
        setTimeouts = {},     -- timers programmés : { ms, fn } (jamais exécutés)
        setModeCalls = {},    -- appels exports.gf_core:SetMode : { src, mode }
        forceLaunchQueueCalls = {}, -- arguments reçus par gf_lobby:ForceLaunchQueue
        forceLaunchQueue = nil,     -- pilote : fonction renvoyant le nombre de joueurs lancés
    }

    local envMetatable = {
        __index = function(_, name)
            local valeur = rawget(_G, name)
            if valeur ~= nil then return valeur end
            -- Toute native FiveM non nommément simulée ne fait rien.
            return stub
        end,
    }

    local function newEnv(resource)
        local env = {}
        -- gf_core/server.lua lit _G.Validation, _G.RateLimit, etc. : les modules
        -- chargés dans env doivent être visibles par ce biais, pas dans le _G du test.
        env._G = env
        env.print = function(...)
            local parts = {}
            for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
            h.logs[#h.logs + 1] = table.concat(parts, ' ')
        end
        env.GetCurrentResourceName = function() return resource end
        env.GetResourceState = function() return 'started' end
        env.GetConvar = function(_name, default) return default end
        env.LoadResourceFile = function() return nil end
        env.GetGameTimer = function() return 0 end
        env.GetPlayerName = function() return 'Joueur' end
        env.GetPlayerIdentifiers = function()
            return { 'license:abc', 'ip:1.2.3.4', 'fivem:42', 'discord:99' }
        end
        env.IsPlayerAceAllowed = function() return h.admin end
        env.GetPlayers = function() return {} end
        env.GetPlayerPed = function() return 0 end
        env.GetEntityCoords = function() return newVector(0, 0, 0) end
        env.GetVehiclePedIsIn = function() return 0 end
        env.SetPlayerRoutingBucket = stub
        env.GetPlayerRoutingBucket = function() return 0 end
        env.SetRoutingBucketPopulationEnabled = stub
        env.AddStateBagChangeHandler = stub
        env.Player = function()
            return { state = { set = stub } }
        end
        env.json = {
            encode = function() return '{}' end,
            decode = function() return nil end,
        }
        env.vector2 = function(x, y) return newVector(x, y, 0) end
        env.vec2 = env.vector2
        env.vector3 = function(x, y, z) return newVector(x, y, z) end
        env.vec3 = env.vector3

        env.RegisterCommand = function(name, handler)
            h.commands[name] = handler
        end
        env.RegisterNetEvent = function(name, handler)
            if type(name) == 'function' and handler == nil then return end
            h.netHandlers[name] = handler
        end
        env.AddEventHandler = function(name, handler)
            h.eventHandlers[name] = handler
        end
        -- Les threads et timers ne sont jamais lancés : on teste les commandes,
        -- pas la boucle de jeu.
        env.CreateThread = stub
        env.SetTimeout = function(ms, fn)
            h.setTimeouts[#h.setTimeouts + 1] = { ms = ms, fn = fn }
        end
        env.Wait = stub

        env.TriggerClientEvent = function(name, target, data)
            h.clients[#h.clients + 1] = { name = name, target = target, data = data }
        end
        env.TriggerEvent = function(name, ...)
            h.events[#h.events + 1] = { name = name, args = { ... } }
        end

        -- exports('Nom', fn) : table appelable. Les objets de ressources sont
        -- des tables à méthodes appelées avec ':' (self en premier argument).
        local genericExport = setmetatable({}, {
            __index = function() return stub end,
        })
        local coreExport = {
            IsAdmin = function(_self, _src) return h.admin end,
            Notify = function(_self, src, msg)
                h.notices[#h.notices + 1] = { src = src, msg = msg }
            end,
            SetMode = function(_self, src, mode)
                h.setModeCalls[#h.setModeCalls + 1] = { src = src, mode = mode }
                return true
            end,
            GetMode = function() return nil end,
            Spawn = stub,
            SetTeam = stub,
            SetProtected = stub,
            GetEquippedWeapons = function() return {} end,
            GetOwnedWeapons = function() return {} end,
            ResolveSelection = function(_self, _src, ids) return ids or {} end,
            BuildWeaponList = function() return {} end,
            GetSelectionSettings = function() return { count = 2, armour = 100 } end,
            CanJoin = function() return true end,
        }
        -- Toute méthode non listée (ex. Freeze, GiveWeapons) renvoie nil au
        -- lieu de lever une erreur ; les méthodes explicites restent prioritaires.
        setmetatable(coreExport, { __index = function() return stub end })
        local mapsExport = {
            GetActiveMaps = function() return {} end,
        }
        local lobbyExport = {
            ForceLaunchQueue = function(_self, maxPlayers)
                h.forceLaunchQueueCalls[#h.forceLaunchQueueCalls + 1] = maxPlayers
                if h.forceLaunchQueue then return h.forceLaunchQueue(maxPlayers) end
                return 0
            end,
        }
        local exportsTable = setmetatable({
            gf_core = coreExport,
            gf_maps = mapsExport,
            gf_attack = genericExport,
            gf_redzone = genericExport,
            gf_inventory = genericExport,
            gf_lobby = lobbyExport,
        }, {
            __call = function(_t, name, fn)
                h.exportsByName[name] = fn
            end,
        })
        env.exports = exportsTable

        setmetatable(env, envMetatable)
        return env
    end

    local function loadFiles(env, files)
        for _, file in ipairs(files) do
            local chunk = assert(loadfile(RESOURCES .. file, 't', env),
                'loadfile impossible : ' .. file)
            local ok, err = pcall(chunk)
            if not ok then error('chargement de ' .. file .. ' : ' .. tostring(err), 2) end
        end
    end

    -- Ordre des fxmanifest.lua : shared puis scripts serveur, modules gf_core
    -- chargés dans env (visibles via _G) avant server.lua.
    loadFiles(newEnv('gf_attack'), {
        'gf_attack/config.lua', 'gf_attack/rules.lua', 'gf_attack/server.lua',
    })
    loadFiles(newEnv('gf_redzone'), {
        'gf_redzone/config.lua', 'gf_redzone/server.lua',
    })
    loadFiles(newEnv('gf_core'), {
        'gf_core/config.lua', 'gf_core/validation.lua', 'gf_core/rate_limit.lua',
        'gf_core/shot_validation.lua', 'gf_core/state_guard.lua',
        'gf_core/server.lua',
    })

    function h.call(name, src)
        local handler = assert(h.commands[name], 'commande absente : ' .. name)
        -- args est TOUJOURS une table : setmode indexe args[1].
        handler(src, {})
    end

    function h.resetRecords()
        h.notices, h.clients, h.events, h.logs = {}, {}, {}, {}
        h.setTimeouts, h.forceLaunchQueueCalls = {}, {}
        -- h.forceLaunchQueue est volontairement conservé : chaque scénario le pose après reset.
    end

    function h.noticesMessages()
        local list = {}
        for _, n in ipairs(h.notices) do list[#list + 1] = n.msg end
        return list
    end

    function h.noticesFrom(src)
        for _, n in ipairs(h.notices) do
            if n.src ~= src then return false end
        end
        return true
    end

    function h.notifyMessages(src)
        local list = {}
        for _, c in ipairs(h.clients) do
            if c.name == 'gf_ui:notify' and c.target == src then
                list[#list + 1] = c.data and c.data.text
            end
        end
        return list
    end

    function h.clientNames()
        local list = {}
        for _, c in ipairs(h.clients) do list[#list + 1] = c.name end
        return list
    end

    function h.eventNames()
        local list = {}
        for _, e in ipairs(h.events) do list[#list + 1] = e.name end
        return list
    end

    return h
end

-- ---------------------------------------------------------------------------
--  Scénarios 1 : joueur 5 NON admin, message ADMIN_REQUIS et rien d'autre.
-- ---------------------------------------------------------------------------

local COMMANDES = {
    { name = 'startround', canal = 'notify' },
    { name = 'endmatch',   canal = 'notify' },
    { name = 'nextzone',   canal = 'notify' },
    { name = 'setteam',    canal = 'notify' },
    { name = 'endgame',    canal = 'notify' },
    { name = 'nextmap',    canal = 'notify' },
    { name = 'setmode',    canal = 'client' },
}

for _, commande in ipairs(COMMANDES) do
    local nom = commande.name
    check('1. ' .. nom .. ' refuse le non-admin avec le message exact', function()
        local h = newHarness(false)
        h.resetRecords()
        h.call(nom, 5)

        if commande.canal == 'notify' then
            eq(1, #h.notices, 'un seul Notify')
            eq(true, h.noticesFrom(5), 'Notify destiné au joueur 5')
            expectList(h.noticesMessages(), { ADMIN_REQUIS }, 'message ADMIN_REQUIS')
            expectList(h.clientNames(), {}, 'aucun TriggerClientEvent')
        elseif commande.canal == 'client' then
            expectList(h.noticesMessages(), {}, 'aucun Notify pour setmode')
            expectList(h.clientNames(), { 'gf_ui:notify' }, 'une seule notification')
            expectList(h.notifyMessages(5), { ADMIN_REQUIS }, 'message ADMIN_REQUIS exact')
        end
        expectList(h.eventNames(), {}, 'aucun TriggerEvent')
        expectList(h.logs, {}, 'aucun print')
    end)
end

-- ---------------------------------------------------------------------------
--  Scénarios 2 : les mêmes commandes par un admin ne délivrent PAS le message.
--  Les effets annexes sont tolérés (faux sans erreur).
-- ---------------------------------------------------------------------------

for _, commande in ipairs(COMMANDES) do
    local nom = commande.name
    check('2. ' .. nom .. ' admin ne renvoie pas le message de refus', function()
        local h = newHarness(true)
        h.resetRecords()
        h.call(nom, 5)

        for _, msg in ipairs(h.noticesMessages()) do
            if msg == ADMIN_REQUIS then
                error('message ADMIN_REQUIS envoyé à un admin', 2)
            end
        end
        for _, msg in ipairs(h.notifyMessages(5)) do
            if msg == ADMIN_REQUIS then
                error('notification ADMIN_REQUIS envoyée à un admin', 2)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
--  Scénarios 3 : /whoami.
-- ---------------------------------------------------------------------------

check('3a. /whoami non-admin : identifiants sans ip puis aide', function()
    local h = newHarness(false)
    h.resetRecords()
    h.call('whoami', 5)

    expectList(h.clientNames(), {
        'gf_ui:notify', 'gf_ui:notify', 'gf_ui:notify',
    }, 'trois messages')
    expectList(h.notifyMessages(5), {
        'Administrateur : non', IDENTIFIANTS, AIDE_ADMIN,
    }, 'contenu exact des messages')
    expectList(h.noticesMessages(), {}, 'aucun Notify')
    expectList(h.eventNames(), {}, 'aucun TriggerEvent')
    expectList(h.logs, {}, 'aucun print')
end)

check('3b. /whoami admin : pas de message d aide', function()
    local h = newHarness(true)
    h.resetRecords()
    h.call('whoami', 5)

    expectList(h.clientNames(), { 'gf_ui:notify', 'gf_ui:notify' }, 'deux messages')
    expectList(h.notifyMessages(5), {
        'Administrateur : oui', IDENTIFIANTS,
    }, 'contenu exact des messages')
    for _, msg in ipairs(h.notifyMessages(5)) do
        if msg == AIDE_ADMIN then error('aide envoyée à un admin', 2) end
    end
    expectList(h.noticesMessages(), {}, 'aucun Notify')
    expectList(h.eventNames(), {}, 'aucun TriggerEvent')
    expectList(h.logs, {}, 'aucun print')
end)

check('3c. /whoami depuis la console : print exact, aucun message réseau', function()
    local h = newHarness(false)
    h.resetRecords()
    h.call('whoami', 0)

    expectList(h.logs, { "[gf_core] La commande /whoami s'utilise en jeu." }, 'print exact')
    expectList(h.clientNames(), {}, 'aucun TriggerClientEvent')
    expectList(h.noticesMessages(), {}, 'aucun Notify')
    expectList(h.eventNames(), {}, 'aucun TriggerEvent')
end)

-- ---------------------------------------------------------------------------
--  Scénarios 4 : /startround et la file du lobby (ForceLaunchQueue).
--  Le faux SetMode n'ajoute aucun joueur : sans la file, le message reste
--  'Aucun joueur dans le mode Attaque.'
-- ---------------------------------------------------------------------------

local function timer2500(h)
    local count = 0
    for _, t in ipairs(h.setTimeouts) do
        if t.ms == 2500 then count = count + 1 end
    end
    return count
end

local function hasMessage(messages, needle)
    for _, msg in ipairs(messages) do
        if msg and msg:find(needle, 1, true) then return true end
    end
    return false
end

check('4a. startround : ForceLaunchQueue renvoie 3, message exact et timer 2500', function()
    local h = newHarness(true)
    h.resetRecords()
    h.forceLaunchQueue = function() return 3 end
    h.call('startround', 5)

    local messages = h.noticesMessages()
    local found = false
    for _, msg in ipairs(messages) do
        if msg == 'Lancement forcé : 3 joueur(s) de la file rejoignent la partie.' then found = true end
    end
    eq(true, found, 'message exact de lancement forcé reçu par l admin')

    local called = false
    for _, arg in ipairs(h.forceLaunchQueueCalls) do
        if type(arg) == 'number' and arg > 0 then called = true end
    end
    eq(true, called, 'ForceLaunchQueue appelé avec un nombre de places > 0')

    eq(true, timer2500(h) > 0, 'au moins un timer de 2500 ms programmé')
end)

check('4d. startround : la file part avant l admin, qui n entre qu au coup d envoi', function()
    local h = newHarness(true)
    h.resetRecords()
    h.setModeCalls = {}
    h.forceLaunchQueue = function() return 2 end
    h.call('startround', 5)

    -- L'admin ne doit pas quitter le lobby avant le lancement de la file :
    -- s'il y est avec son escouade, il part avec elle.
    eq(0, #h.setModeCalls, 'aucun SetMode avant le timer')
    local timer = nil
    for _, t in ipairs(h.setTimeouts) do
        if t.ms == 2500 then timer = t end
    end
    eq(true, timer ~= nil, 'timer de 2500 ms programmé')
    timer.fn()
    eq(1, #h.setModeCalls, 'un SetMode au coup d envoi')
    eq(5, h.setModeCalls[1].src, 'SetMode pour l admin')
    eq('attack', h.setModeCalls[1].mode, 'vers le mode attack')
end)

check('4b. startround : ForceLaunchQueue renvoie 0, comportement actuel conservé', function()
    local h = newHarness(true)
    h.resetRecords()
    h.forceLaunchQueue = function() return 0 end
    h.call('startround', 5)

    local messages = h.noticesMessages()
    eq(false, hasMessage(messages, 'Lancement forcé'), 'aucun message de lancement forcé')
    eq(false, hasMessage(h.logs, 'Lancement forcé'), 'aucun print de lancement forcé')
    eq(0, timer2500(h), 'aucun timer de 2500 ms')

    local found = false
    for _, msg in ipairs(messages) do
        if msg == 'Aucun joueur dans le mode Attaque.' then found = true end
    end
    eq(true, found, 'message actuel conservé')
end)

check('4c. startround : ForceLaunchQueue lève une erreur, rien ne propage', function()
    local h = newHarness(true)
    h.resetRecords()
    h.forceLaunchQueue = function() error('panne simulée') end

    local ok, err = pcall(h.call, 'startround', 5)
    eq(true, ok, 'aucune erreur propagée : ' .. tostring(err))

    local messages = h.noticesMessages()
    eq(false, hasMessage(messages, 'Lancement forcé'), 'aucun message de lancement forcé')
    eq(false, hasMessage(h.logs, 'Lancement forcé'), 'aucun print de lancement forcé')
    eq(0, timer2500(h), 'aucun timer de 2500 ms')

    local found = false
    for _, msg in ipairs(messages) do
        if msg == 'Aucun joueur dans le mode Attaque.' then found = true end
    end
    eq(true, found, 'message actuel conservé')
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
