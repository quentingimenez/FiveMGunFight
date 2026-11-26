-- =============================================================================
--  gf_lobby - tests de la file d'attente (module pur + intégration serveur).
--
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/lobby_queue_test.lua
--  La racine est calculée comme dans tests/lua/lobby_nui_callbacks.lua
--  (GF_ROOT ou debug.getinfo du script).
--
--  Les deux premières parties testent queue.lua sans FiveM. La dernière charge
--  config.lua, queue.lua puis server.lua TELS QUELS dans un environnement bac à
--  sable : toutes les natives et exports sont des fausses pilotées par le test.
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

local function contains(text, fragment, message)
    if type(text) ~= 'string' or not text:find(fragment, 1, true) then
        error(('%s : "%s" absent de %s'):format(message, fragment, tostring(text)), 2)
    end
end

-- ---------------------------------------------------------------------------
--  Chargement du module pur dans son propre environnement.
-- ---------------------------------------------------------------------------

local function loadQueue()
    local env = setmetatable({}, { __index = _G })
    local chunk = assert(loadfile(RESOURCE .. 'queue.lua', 't', env))
    chunk()
    return assert(env.LobbyQueue, 'LobbyQueue non défini')
end

local Q = loadQueue()

local function partiesSimples()
    return {
        [1] = { id = 1, members = { 1, 2 } },
        [2] = { id = 2, members = { 3 } },
        [3] = { id = 3, members = { 4, 5, 6 }, launching = true },
    }
end

local function tousEligibles()
    return function() return true end
end

check('join, leave et has sur une file vide', function()
    local q = Q.new()
    equal(false, Q.has(q, 1), 'has avant join')
    equal(true, Q.join(q, 1, 'attack'), 'join')
    equal(true, Q.has(q, 1), 'has après join')
    equal('attack', q.entries[1].mode, 'mode enregistré')
    equal(true, Q.leave(q, 1), 'leave')
    equal(false, Q.leave(q, 1), 'leave répété')
    equal(false, Q.has(q, 1), 'has après leave')
    -- Une réinscription reprend un nouvel ordre : on inscrit l'escouade 2
    -- entre le départ et le retour de l'escouade 1.
    local q2 = Q.new()
    Q.join(q2, 1)
    Q.leave(q2, 1)
    Q.join(q2, 2)
    Q.join(q2, 1)
    assert(q2.entries[1].order > q2.entries[2].order, 'nouvel ordre après réinscription')
    local ready = Q.ready(q2, { [1] = { members = { 1 } }, [2] = { members = { 2 } } }, tousEligibles())
    equal(2, #ready, 'deux escouades prêtes')
    equal(2, ready[1].partyId, 'escouade 2 garde son rang')
    equal(1, ready[2].partyId, 'escouade 1 réinscrite en dernier')
end)

check('un join en double ne change pas l ordre', function()
    local q = Q.new()
    Q.join(q, 1)
    Q.join(q, 2)
    local before = q.entries[1].order
    equal(false, Q.join(q, 1), 'join en double refusé')
    equal(before, q.entries[1].order, 'ordre inchangé')
    Q.join(q, 1)
    equal(before, q.entries[1].order, 'ordre toujours inchangé')
end)

check('ready exige tous les membres éligibles', function()
    local q = Q.new()
    Q.join(q, 1)
    Q.join(q, 2)
    local parties = partiesSimples()
    local eligible = function(src) return src ~= 2 end
    local ready = Q.ready(q, parties, eligible)
    equal(1, #ready, 'ready taille')
    equal(2, ready[1].partyId, 'seule l escouade 2 est prête')
end)

check('ready exclut une escouade en lancement', function()
    local q = Q.new()
    Q.join(q, 1)
    Q.join(q, 2)
    Q.join(q, 3)
    local ready = Q.ready(q, partiesSimples(), tousEligibles())
    equal(2, #ready, 'ready exclut launching')
    equal(1, ready[1].partyId, 'première escouade')
    equal(2, ready[2].partyId, 'deuxième escouade')
end)

check('ready purge une escouade disparue', function()
    local q = Q.new()
    Q.join(q, 1)
    Q.join(q, 99)
    local ready = Q.ready(q, partiesSimples(), tousEligibles())
    equal(1, #ready, 'ready après purge')
    equal(false, Q.has(q, 99), 'entrée obsolète retirée')
end)

check('ready respecte l ordre FIFO', function()
    local q = Q.new()
    Q.join(q, 3)
    Q.join(q, 1)
    Q.join(q, 2)
    -- Trois escouades sans drapeau launching : toutes doivent être prêtes.
    local parties = {
        [1] = { id = 1, members = { 1, 2 } },
        [2] = { id = 2, members = { 3 } },
        [3] = { id = 3, members = { 4 } },
    }
    local ready = Q.ready(q, parties, tousEligibles())
    equal(3, #ready, 'trois escouades prêtes')
    equal(3, ready[1].partyId, 'première inscrite')
    equal(1, ready[2].partyId, 'deuxième inscrite')
    equal(2, ready[3].partyId, 'troisième inscrite')
end)

check('ready renvoie une copie des membres', function()
    local q = Q.new()
    Q.join(q, 1)
    local parties = partiesSimples()
    local ready = Q.ready(q, parties, tousEligibles())
    equal(1, #ready, 'une escouade')
    equal(1, ready[1].members[1], 'membre copié')
    ready[1].members[1] = 999
    ready[1].partyId = 999
    equal(1, parties[1].members[1], 'parties non modifiées')
    local again = Q.ready(q, parties, tousEligibles())
    equal(1, again[1].partyId, 'file non modifiée')
end)

check('count ignore les escouades lancées et inéligibles', function()
    local q = Q.new()
    Q.join(q, 1)
    Q.join(q, 2)
    Q.join(q, 3)
    equal(3, Q.count(q, partiesSimples(), tousEligibles()), 'toutes prêtes')
    equal(1, Q.count(q, partiesSimples(), function(src) return src ~= 2 end), 'membre 2 exclu')
end)

check('pick : trois exemples de la spécification', function()
    local function squad(id, count)
        local members = {}
        for i = 1, count do members[i] = id * 100 + i end
        return { partyId = id, members = members }
    end
    local list = { squad(1, 3), squad(2, 2), squad(3, 4) }
    -- Exemple 1 : tailles 2 puis 2, min 2 max 3 -> seule la première tient.
    local ex1 = Q.pick({ squad(1, 2), squad(2, 2) }, 2, 3)
    assert(ex1, 'exemple 1 : pick doit renvoyer une liste')
    equal(1, #ex1, 'exemple 1 : une seule escouade')
    equal(1, ex1[1].partyId, 'exemple 1 : première escouade retenue')
    -- Exemple 2 : tailles 3 puis 1, min 4 max 4 -> les deux.
    local ex2 = Q.pick({ squad(1, 3), squad(2, 1) }, 4, 4)
    assert(ex2, 'exemple 2 : pick doit renvoyer une liste')
    equal(2, #ex2, 'exemple 2 : deux escouades')
    equal(1, ex2[1].partyId, 'exemple 2 : première escouade')
    equal(2, ex2[2].partyId, 'exemple 2 : deuxième escouade')
    -- Exemple 3 : une escouade de 1, min 2 -> nil.
    equal(nil, Q.pick({ squad(1, 1) }, 2, 10), 'exemple 3 : pick sous le seuil')
    -- Cas supplémentaire : sous le seuil (total 3+2+4 = 9 < 10).
    equal(nil, Q.pick(list, 10, 10), 'pick sous le seuil')
    -- Plafond : on garde les escouades entières qui tiennent.
    local chosen = Q.pick(list, 4, 6)
    assert(chosen, 'pick doit renvoyer une liste')
    equal(2, #chosen, 'deux escouades choisies')
    equal(1, chosen[1].partyId, 'première escouade')
    equal(2, chosen[2].partyId, 'deuxième escouade')
    -- Une escouade trop grosse est sautée, pas coupée.
    local chosen2 = Q.pick({ squad(1, 4), squad(2, 2) }, 2, 3)
    assert(chosen2, 'pick doit renvoyer une liste')
    equal(1, #chosen2, 'grosse escouade sautée')
    equal(2, chosen2[1].partyId, 'deuxième escouade retenue')
end)

check('pick ne coupe jamais une escouade ni sa liste', function()
    local list = {
        { partyId = 1, members = { 10, 11 } },
        { partyId = 2, members = { 20, 21 } },
    }
    local copy = {
        { partyId = 1, members = { 10, 11 } },
        { partyId = 2, members = { 20, 21 } },
    }
    local chosen = Q.pick(list, 4, 5)
    assert(chosen, 'pick doit renvoyer une liste')
    equal(2, #chosen, 'deux escouades entières')
    equal(2, #chosen[1].members, 'première escouade entière')
    equal(2, #chosen[2].members, 'deuxième escouade entière')
    equal(2, #list, 'liste d entrée intacte')
    equal(10, list[1].members[1], 'membres d entrée intacts')
    equal(20, copy[2].members[1], 'référence d entrée inchangée')
    equal(nil, Q.pick(nil, 1, 2), 'pick sur liste nil')
end)

-- ---------------------------------------------------------------------------
--  Environnement bac à sable pour server.lua.
-- ---------------------------------------------------------------------------

local function newServer()
    local env = {}
    local online = {}          -- [src] = true
    local states = {}          -- [src] = dernier gf_lobby:state
    local notices = {}         -- [src] = liste de messages
    local launching = {}       -- liste de { target, data }
    local timers = {}          -- liste de fonctions SetTimeout
    local threads = {}         -- liste de coroutines CreateThread
    local setModeCalls = {}    -- liste de { src, mode }
    -- Journal commun : SetMode et RegisterSquads y sont consignés dans l'ordre
    -- d'appel, ce qui permet de vérifier que l'enregistrement précède le
    -- lancement des escouades.
    local journal = {}         -- liste de { kind, ... }
    local clock = 0            -- horloge GetGameTimer
    local canJoin = true
    local modes = {}           -- mode simulé par joueur dans gf_core
    local netHandlers = {}
    local eventHandlers = {}
    local logs = {}
    -- exports(name, fn) enregistre les exports dynamiques du serveur (par
    -- exemple ForceLaunchQueue), tout en gardant l'accès par champ pour les
    -- exports statiques gf_core / gf_attack.
    local registeredExports = {}
    -- Vote de carte : choix exposés par gf_attack et appels à SetNextMap.
    local mapChoices = {
        { id = 'a', name = 'Alpha' },
        { id = 'b', name = 'Bravo' },
    }
    local setNextMapCalls = {}
    local randomFn = nil

    env.print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        logs[#logs + 1] = table.concat(parts, ' ')
    end
    env.source = nil

    env.GetCurrentResourceName = function() return 'gf_lobby' end
    env.GetConvar = function(_name, default) return default end
    env.GetResourceState = function() return 'started' end
    env.LoadResourceFile = function() return nil end
    env.SaveResourceFile = function() return true end
    env.IsPlayerAceAllowed = function() return false end
    env.GetPlayerRoutingBucket = function() return 0 end
    env.SetPlayerRoutingBucket = function() return nil end
    env.GetGameTimer = function() return clock end
    -- math.random pilotable par les scénarios d'égalité ; les autres fonctions
    -- math restent accessibles via _G.math.
    env.math = setmetatable({
        random = function(n)
            if randomFn then return randomFn(n) end
            return 1
        end,
    }, { __index = _G.math })
    env.GetPlayers = function()
        local list = {}
        for src in pairs(online) do list[#list + 1] = tostring(src) end
        table.sort(list)
        return list
    end
    env.GetPlayerName = function(src)
        if online[tonumber(src)] then return ('Joueur%d'):format(tonumber(src)) end
        return nil
    end
    env.GetPlayerIdentifiers = function(src)
        return { 'license:test' .. tostring(src) }
    end
    env.json = {
        encode = function() return '{}' end,
        decode = function() return nil end,
    }

    env.RegisterNetEvent = function(name, handler)
        if type(name) == 'function' and handler == nil then
            -- RegisterNetEvent peut être appelé avec un seul argument.
            return
        end
        netHandlers[name] = handler
    end
    env.AddEventHandler = function(name, handler) eventHandlers[name] = handler end
    env.RegisterCommand = function() return nil end

    env.CreateThread = function(fn)
        threads[#threads + 1] = coroutine.create(fn)
    end
    env.Wait = function() return coroutine.yield() end
    env.SetTimeout = function(_ms, fn)
        timers[#timers + 1] = fn
    end

    env.exports = setmetatable({
        gf_core = {
            GetMode = function(_self, src) return modes[tonumber(src)] end,
            SetMode = function(self, src, mode)
                modes[tonumber(src)] = mode
                local call = { src = tonumber(src), mode = mode }
                setModeCalls[#setModeCalls + 1] = call
                journal[#journal + 1] = { kind = 'SetMode', call = call }
                return true
            end,
            GetPlayersInMode = function() return {} end,
        },
        gf_attack = {
            CanJoin = function() return canJoin end,
            RegisterSquads = function(self, escouades)
                local call = { escouades = escouades }
                journal[#journal + 1] = { kind = 'RegisterSquads', call = call }
                return true
            end,
            GetMapChoices = function() return mapChoices end,
            SetNextMap = function(_self, id)
                local call = { id = id }
                setNextMapCalls[#setNextMapCalls + 1] = call
                journal[#journal + 1] = { kind = 'SetNextMap', call = call }
                return true
            end,
        },
    }, {
        __call = function(_self, name, fn)
            registeredExports[name] = fn
        end,
    })

    env.TriggerClientEvent = function(name, target, data)
        if name == 'gf_lobby:state' then
            states[target] = data
        elseif name == 'gf_lobby:notice' then
            notices[target] = notices[target] or {}
            notices[target][#notices[target] + 1] = data and data.message or ''
        elseif name == 'gf_lobby:launching' then
            launching[#launching + 1] = { target = target, data = data }
        end
    end

    setmetatable(env, { __index = _G })

    for _, file in ipairs({ 'config.lua', 'queue.lua', 'server.lua' }) do
        local chunk = assert(loadfile(RESOURCE .. file, 't', env))
        chunk()
    end

    -- Fait avancer chaque coroutine d'un pas (jusqu'au premier Wait).
    local function tick()
        for i = 1, #threads do
            local co = threads[i]
            if coroutine.status(co) ~= 'dead' then
                local ok, err = coroutine.resume(co)
                if not ok then error('thread: ' .. tostring(err), 2) end
            end
        end
    end

    local function flushTimers()
        local pending = timers
        timers = {}
        for _, fn in ipairs(pending) do fn() end
    end

    local function callNet(name, src, payload)
        env.source = src
        local handler = assert(netHandlers[name], 'handler net absent: ' .. name)
        handler(payload)
        env.source = nil
    end

    local function callEvent(name, ...)
        local handler = assert(eventHandlers[name], 'handler event absent: ' .. name)
        handler(...)
    end

    local function makePlayer(src)
        online[src] = true
        -- Le joueur entre d'abord dans le lobby, puis crée son personnage.
        callEvent('gf:modeJoined', src, 'lobby')
        clock = clock + 3000  -- cooldown de création (2 s) et de mode (1 s)
        callNet('gf_lobby:createCharacter', src, {
            name = 'Alpha', gender = 'male', seed = 123, skin = 0,
        })
        clock = clock + 2000
    end

    local function stateOf(src)
        return assert(states[src], 'aucun state pour ' .. tostring(src))
    end

    local function queueOf(src)
        return assert(stateOf(src).queue, 'aucun état de file pour ' .. tostring(src))
    end

    local function partyOf(src)
        return assert(stateOf(src).party, 'aucune escouade pour ' .. tostring(src))
    end

    local function noticesOf(src)
        return notices[src] or {}
    end

    local function lastNotice(src)
        local list = noticesOf(src)
        return list[#list] or ''
    end

    local function setModeCount()
        return #setModeCalls
    end

    local function setModeFor(src, mode)
        for _, call in ipairs(setModeCalls) do
            if call.src == src and call.mode == mode then return true end
        end
        return false
    end

    local function launchingCount()
        return #launching
    end

    -- Amorçage : les deux threads créés au chargement avancent jusqu'à Wait(500).
    tick()

    return {
        env = env, tick = tick, flushTimers = flushTimers,
        callNet = callNet, callEvent = callEvent, makePlayer = makePlayer,
        stateOf = stateOf, queueOf = queueOf, partyOf = partyOf,
        noticesOf = noticesOf, lastNotice = lastNotice,
        setModeCount = setModeCount, setModeFor = setModeFor,
        journal = journal,
        registerCalls = function()
            local calls = {}
            for _, entry in ipairs(journal) do
                if entry.kind == 'RegisterSquads' then
                    calls[#calls + 1] = entry.call
                end
            end
            return calls
        end,
        firstSetModeIndex = function()
            for i, entry in ipairs(journal) do
                if entry.kind == 'SetMode' then return i end
            end
            return nil
        end,
        launchingCount = launchingCount, logs = logs,
        setNextMapCalls = setNextMapCalls,
        journalIndex = function(kind)
            for i, entry in ipairs(journal) do
                if entry.kind == kind then return i end
            end
            return nil
        end,
        setRandom = function(fn) randomFn = fn end,
        -- 600 ms pour passer l'anti-spam de 500 ms du vote.
        vote = function(src, id)
            clock = clock + 600
            callNet('gf_lobby:voteMap', src, { id = id })
        end,
        advance = function(ms) clock = clock + ms end,
        setCanJoin = function(value) canJoin = value end,
        clearModes = function()
            for src in pairs(modes) do modes[src] = nil end
        end,
        play = function(src, mode)
            clock = clock + 2000
            callNet('gf_lobby:play', src, { mode = mode })
        end,
        cancel = function(src)
            callNet('gf_lobby:selectMode', src, { mode = 'attack', cancel = true })
        end,
        threshold = function()
            tick()
            flushTimers()
        end,
        min = function(value) env.Config.Matchmaking.attackMin = value end,
        max = function(value) env.Config.Matchmaking.attackMax = value end,
        forceLaunch = function(maxPlayers)
            local fn = assert(registeredExports.ForceLaunchQueue, 'export ForceLaunchQueue absent')
            return fn(maxPlayers)
        end,
    }
end

-- ---------------------------------------------------------------------------
--  Scénarios d'intégration : a à h.
-- ---------------------------------------------------------------------------

check('a. joueur seul : play inscrit sans notice d erreur', function()
    local s = newServer()
    s.makePlayer(1)
    s.play(1, 'attack')
    equal(true, s.queueOf(1).joined, 'joined du joueur 1')
    equal(1, s.queueOf(1).size, 'taille de file')
    for _, message in ipairs(s.noticesOf(1)) do
        if message:find('Aucun joueur', 1, true) then
            error('notice inattendue: ' .. message, 2)
        end
    end
    -- Joueur 2 : lobby, personnage, non inscrit.
    s.makePlayer(2)
    equal(1, s.queueOf(2).size, 'taille vue par le joueur 2')
    equal(false, s.queueOf(2).joined, 'joueur 2 non inscrit')
end)

check('b. un second play ne retire pas l escouade', function()
    local s = newServer()
    s.makePlayer(1)
    s.play(1, 'attack')
    s.play(1, 'attack')
    equal(true, s.queueOf(1).joined, 'joined après second play')
    equal(1, s.queueOf(1).size, 'taille après second play')
    contains(s.lastNotice(1), 'déjà dans la file', 'notice de doublon')
end)

check('c1. le chef annule sa recherche', function()
    local s = newServer()
    s.makePlayer(1)
    s.play(1, 'attack')
    s.cancel(1)
    equal(false, s.queueOf(1).joined, 'joined après annulation')
    equal(0, s.queueOf(1).size, 'file vide après annulation')
    contains(s.lastNotice(1), 'retirée de la file', 'notice d annulation')
end)

check('c2. un non-chef ne peut pas annuler', function()
    local s = newServer()
    s.makePlayer(1)
    s.makePlayer(2)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    equal(2, s.partyOf(1).size, 'escouade 1+2')
    s.play(1, 'attack')
    -- Le joueur 2 est membre, pas chef.
    s.cancel(2)
    contains(s.lastNotice(2), 'Seul le chef', 'erreur de droits')
    equal(true, s.queueOf(1).joined, 'file du chef inchangée')
    equal(2, s.queueOf(1).size, 'taille inchangée')
    s.cancel(1)
    equal(false, s.queueOf(1).joined, 'annulation par le chef')
end)

check('d. escouade 1+2 inscrite ensemble', function()
    local s = newServer()
    s.makePlayer(1)
    s.makePlayer(2)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    equal(2, s.partyOf(1).size, 'escouade formée')
    equal(2, s.partyOf(2).size, 'escouade formée pour le membre')
    s.play(1, 'attack')
    equal(2, s.queueOf(1).size, 'deux joueurs comptés')
    equal(true, s.queueOf(1).joined, 'chef inscrit')
    equal(true, s.queueOf(2).joined, 'membre inscrit')
end)

check('e. seuil, départ, retour et relancement', function()
    local s = newServer()
    s.min(2)
    s.makePlayer(1)
    s.makePlayer(2)
    s.makePlayer(3)  -- observateur
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')

    s.threshold()
    equal(true, s.setModeFor(1, 'attack'), 'SetMode pour 1')
    equal(true, s.setModeFor(2, 'attack'), 'SetMode pour 2')
    equal(2, s.launchingCount(), 'deux événements launching')

    -- Départ des joueurs 1 et 2 vers attack : l'observateur lit la file à 0.
    s.callEvent('gf:modeJoined', 1, 'attack')
    s.callEvent('gf:modeJoined', 2, 'attack')
    equal(0, s.queueOf(3).size, 'file à 0 pour l observateur')

    -- Retour au lobby : escouade et inscription persistent.
    s.callEvent('gf:modeJoined', 1, 'lobby')
    s.callEvent('gf:modeJoined', 2, 'lobby')
    equal(2, s.partyOf(1).size, 'escouade toujours de 2')
    equal(2, s.partyOf(2).size, 'escouade toujours de 2 pour le membre')
    equal(true, s.queueOf(1).joined, 'inscription persistée')
    equal(true, s.queueOf(2).joined, 'inscription persistée pour le membre')
    equal(false, s.partyOf(1).launching, 'drapeau launching libéré pour le chef')
    equal(false, s.partyOf(2).launching, 'drapeau launching libéré pour le membre')

    -- Le mode des joueurs est censé avoir été quitté.
    s.clearModes()
    local beforeModes = s.setModeCount()
    local beforeLaunch = s.launchingCount()
    s.threshold()
    assert(s.setModeCount() > beforeModes, 'de nouveaux SetMode attendus')
    assert(s.launchingCount() > beforeLaunch, 'un nouvel événement launching attendu')
    equal(true, s.setModeFor(1, 'attack'), 'relancement pour 1')
    equal(true, s.setModeFor(2, 'attack'), 'relancement pour 2')
end)

check('f. CanJoin false bloque le seuil', function()
    local s = newServer()
    s.min(2)
    s.setCanJoin(false)
    s.makePlayer(1)
    s.makePlayer(2)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')
    local beforeModes = s.setModeCount()
    local beforeLaunch = s.launchingCount()
    s.threshold()
    equal(beforeModes, s.setModeCount(), 'aucun SetMode')
    equal(beforeLaunch, s.launchingCount(), 'aucun launching')
end)

check('g. un membre hors lobby n est pas compté ni lancé', function()
    local s = newServer()
    s.min(2)
    s.makePlayer(1)
    s.makePlayer(2)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')
    equal(2, s.queueOf(1).size, 'deux joueurs inscrits')

    -- Le joueur 2 quitte le lobby : l'escouade persiste mais n'est plus prête.
    s.callEvent('gf:modeJoined', 2, 'attack')
    equal(0, s.queueOf(1).size, 'file à 0 pour le joueur 1')
    local beforeModes = s.setModeCount()
    local beforeLaunch = s.launchingCount()
    s.threshold()
    equal(beforeModes, s.setModeCount(), 'aucun SetMode')
    equal(beforeLaunch, s.launchingCount(), 'aucun launching')
end)

check('h. pick ne coupe pas deux escouades de 2', function()
    local s = newServer()
    s.min(2)
    s.max(3)
    s.makePlayer(1)
    s.makePlayer(2)
    s.makePlayer(3)
    s.makePlayer(4)
    -- Première escouade : 1+2.
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local party1 = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = party1, accept = true })
    -- Deuxième escouade : 3+4.
    s.callNet('gf_lobby:invite', 3, { id = 4 })
    local party2 = s.stateOf(3).party.id
    s.callNet('gf_lobby:respondInvite', 4, { partyId = party2, accept = true })
    s.play(1, 'attack')
    s.play(3, 'attack')
    equal(4, s.queueOf(1).size, 'quatre joueurs dans la file')

    s.threshold()
    equal(true, s.setModeFor(1, 'attack'), 'SetMode pour 1')
    equal(true, s.setModeFor(2, 'attack'), 'SetMode pour 2')
    equal(false, s.setModeFor(3, 'attack'), 'pas de SetMode pour 3')
    equal(false, s.setModeFor(4, 'attack'), 'pas de SetMode pour 4')
    equal(true, s.queueOf(3).joined, 'escouade 2 toujours inscrite')
    equal(2, s.partyOf(3).size, 'escouade 2 intacte')
end)

-- ---------------------------------------------------------------------------
--  Scénarios d'intégration : enregistrement auprès de gf_attack.
-- ---------------------------------------------------------------------------

-- Compare deux listes de membres sans tenir compte de leur ordre.
local function memesMembres(attendu, obtenu)
    if type(obtenu) ~= 'table' or #obtenu ~= #attendu then return false end
    local restants = {}
    for i = 1, #obtenu do restants[i] = obtenu[i] end
    for _, src in ipairs(attendu) do
        local trouve = false
        for i, candidat in ipairs(restants) do
            if candidat == src then
                table.remove(restants, i)
                trouve = true
                break
            end
        end
        if not trouve then return false end
    end
    return #restants == 0
end

-- Compare deux listes d'escouades sans tenir compte de l'ordre des listes ni
-- de celui des membres (la spécification demande une égalité d'ensemble).
local function memesEscouades(attendu, obtenu)
    if type(obtenu) ~= 'table' or #obtenu ~= #attendu then return false end
    local restants = {}
    for i = 1, #obtenu do restants[i] = obtenu[i] end
    for _, squad in ipairs(attendu) do
        local trouve = false
        for i, candidat in ipairs(restants) do
            if memesMembres(squad, candidat) then
                table.remove(restants, i)
                trouve = true
                break
            end
        end
        if not trouve then return false end
    end
    return #restants == 0
end

check('i. RegisterSquads enregistre les deux escouades avant SetMode', function()
    local s = newServer()
    s.min(3)
    s.makePlayer(1)
    s.makePlayer(2)
    s.makePlayer(3)
    -- Escouade {1, 2}.
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    -- Joueur 3 seul dans sa propre escouade.
    s.play(1, 'attack')
    s.play(3, 'attack')
    equal(3, s.queueOf(1).size, 'trois joueurs dans la file')

    s.threshold()

    local registerCalls = s.registerCalls()
    equal(1, #registerCalls, 'un seul appel à RegisterSquads')
    local escouades = registerCalls[1].escouades
    assert(memesEscouades({ { 1, 2 }, { 3 } }, escouades),
        'RegisterSquads doit recevoir les escouades {1,2} et {3}')
    local premierSetMode = s.firstSetModeIndex()
    assert(premierSetMode, 'au moins un SetMode attendu')
    -- RegisterSquads est consigné avant le premier SetMode dans le journal.
    equal('RegisterSquads', s.journal[1].kind, 'RegisterSquads en tête du journal')
    assert(1 < premierSetMode, 'RegisterSquads appelé avant le premier SetMode')
    equal(true, s.setModeFor(1, 'attack'), 'SetMode pour 1')
    equal(true, s.setModeFor(2, 'attack'), 'SetMode pour 2')
    equal(true, s.setModeFor(3, 'attack'), 'SetMode pour 3')
end)

check('j. un RegisterSquads qui lève une erreur n empêche pas les SetMode', function()
    local s = newServer()
    s.min(2)
    -- Remplacement de la méthode du faux export avant le seuil.
    s.env.exports.gf_attack.RegisterSquads = function(_self, _escouades)
        error('panne simulée de gf_attack')
    end
    s.makePlayer(1)
    s.makePlayer(2)
    s.makePlayer(3)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')
    s.play(3, 'attack')

    s.threshold()

    equal(true, s.setModeFor(1, 'attack'), 'SetMode pour 1 malgré l erreur')
    equal(true, s.setModeFor(2, 'attack'), 'SetMode pour 2 malgré l erreur')
    equal(true, s.setModeFor(3, 'attack'), 'SetMode pour 3 malgré l erreur')
end)

-- ---------------------------------------------------------------------------
--  Scénarios d'intégration : export ForceLaunchQueue (lancement forcé).
-- ---------------------------------------------------------------------------

check('k. ForceLaunchQueue lance une escouade solo sous le seuil', function()
    local s = newServer()
    -- attackMin reste à 20 : le lancement forcé ne doit pas en tenir compte.
    equal(20, s.env.Config.Matchmaking.attackMin, 'seuil inchangé')
    s.makePlayer(1)
    s.play(1, 'attack')
    equal(true, s.queueOf(1).joined, 'joueur inscrit')
    equal(1, s.forceLaunch(30), 'ForceLaunchQueue renvoie 1 joueur')

    -- Avant flushTimers : le lancement est en attente.
    equal(-1, s.forceLaunch(30), 'second appel pendant le lancement')

    s.flushTimers()
    equal(true, s.setModeFor(1, 'attack'), 'SetMode pour le joueur 1')
    local registerCalls = s.registerCalls()
    equal(1, #registerCalls, 'un seul appel à RegisterSquads')
    assert(memesEscouades({ { 1 } }, registerCalls[1].escouades),
        'RegisterSquads doit recevoir l escouade {1}')
    local premierSetMode = s.firstSetModeIndex()
    assert(premierSetMode, 'au moins un SetMode attendu')
    assert(1 < premierSetMode, 'RegisterSquads appelé avant le premier SetMode')
end)

check('l. ForceLaunchQueue respecte la limite et l ordre FIFO', function()
    local s = newServer()
    s.makePlayer(1)
    s.makePlayer(2)
    s.makePlayer(3)
    s.makePlayer(4)
    -- Première escouade inscrite : 1+2.
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local party1 = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = party1, accept = true })
    -- Deuxième escouade inscrite : 3+4.
    s.callNet('gf_lobby:invite', 3, { id = 4 })
    local party2 = s.stateOf(3).party.id
    s.callNet('gf_lobby:respondInvite', 4, { partyId = party2, accept = true })
    s.play(1, 'attack')
    s.play(3, 'attack')
    equal(4, s.queueOf(1).size, 'quatre joueurs dans la file')

    -- Limite 3 : la première escouade de 2 tient, la seconde (2 joueurs) ne
    -- tient plus (2+2 > 3) et n'est pas coupée.
    equal(2, s.forceLaunch(3), 'ForceLaunchQueue renvoie 2 joueurs')
    s.flushTimers()

    equal(true, s.setModeFor(1, 'attack'), 'SetMode pour 1')
    equal(true, s.setModeFor(2, 'attack'), 'SetMode pour 2')
    equal(false, s.setModeFor(3, 'attack'), 'pas de SetMode pour 3')
    equal(false, s.setModeFor(4, 'attack'), 'pas de SetMode pour 4')
    local registerCalls = s.registerCalls()
    equal(1, #registerCalls, 'un seul appel à RegisterSquads')
    assert(memesEscouades({ { 1, 2 } }, registerCalls[1].escouades),
        'seule la première escouade est enregistrée')
    equal(true, s.queueOf(3).joined, 'escouade 2 toujours inscrite')
end)

check('m. ForceLaunchQueue sans cible ou limite invalide renvoie 0', function()
    local s = newServer()
    -- File vide : aucune escouade prête.
    equal(0, s.forceLaunch(30), 'file vide')

    s.makePlayer(1)
    s.play(1, 'attack')
    -- Limite absente / nil : pick ne peut pas retenir d'escouade (max = nil).
    equal(0, s.forceLaunch(nil), 'maxPlayers nil')
    -- Limite 0 : rejet explicite avant même la lecture de la file.
    equal(0, s.forceLaunch(0), 'maxPlayers 0')
    equal(0, s.forceLaunch(-1), 'maxPlayers négatif')
    equal(0, s.forceLaunch('abc'), 'maxPlayers non numérique')
    local beforeModes = s.setModeCount()
    s.flushTimers()
    equal(beforeModes, s.setModeCount(), 'aucun SetMode après un retour 0')
end)

check('n. l escouade reste inscrite après un lancement forcé et un retour lobby', function()
    local s = newServer()
    s.makePlayer(1)
    s.makePlayer(2)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')
    equal(2, s.forceLaunch(30), 'deux joueurs lancés')
    s.flushTimers()
    equal(true, s.setModeFor(1, 'attack'), 'SetMode pour 1')
    equal(true, s.setModeFor(2, 'attack'), 'SetMode pour 2')

    -- Départ vers attack puis retour au lobby, comme dans le scénario e.
    s.callEvent('gf:modeJoined', 1, 'attack')
    s.callEvent('gf:modeJoined', 2, 'attack')
    s.callEvent('gf:modeJoined', 1, 'lobby')
    s.callEvent('gf:modeJoined', 2, 'lobby')

    equal(true, s.queueOf(1).joined, 'inscription persistée pour le chef')
    equal(true, s.queueOf(2).joined, 'inscription persistée pour le membre')
    equal(2, s.queueOf(1).size, 'deux joueurs comptés au retour')
    equal(2, s.partyOf(1).size, 'escouade toujours de 2')
    equal(false, s.partyOf(1).launching, 'drapeau launching libéré')
    -- Un second lancement forcé est de nouveau possible.
    s.clearModes()
    equal(2, s.forceLaunch(30), 'relancement forcé possible après retour')
end)

-- ---------------------------------------------------------------------------
--  Partie F.1 : dépouillement pur (LobbyQueue.tally) et vote de carte.
-- ---------------------------------------------------------------------------

-- Nombre de voix d'une carte dans un état de file ; -1 si la carte est absente
-- de la liste envoyée au client.
local function mapVotes(queue, id)
    for _, map in ipairs(queue.maps or {}) do
        if map.id == id then return map.votes end
    end
    return -1
end

local choicesVote = {
    { id = 'a', name = 'Alpha' },
    { id = 'b', name = 'Bravo' },
}

check('o. tally : majorité simple', function()
    local winner, counts = Q.tally(
        { [1] = 'a', [2] = 'b', [3] = 'a' }, { 1, 2, 3 }, choicesVote,
        function(_n) return 1 end
    )
    equal('a', winner, 'gagnant')
    equal(2, counts.a, 'voix pour a')
    equal(1, counts.b, 'voix pour b')
end)

check('p. tally : égalité départagée par l ordre des choix', function()
    local winner, counts = Q.tally(
        { [1] = 'a', [2] = 'b' }, { 1, 2 }, choicesVote,
        function(_n) return 2 end
    )
    equal('b', winner, 'gagnant en égalité')
    equal(1, counts.a, 'voix pour a')
    equal(1, counts.b, 'voix pour b')
end)

check('q. tally : aucun vote donne un gagnant nil', function()
    local winner, counts = Q.tally({}, {}, choicesVote, function(_n) return 1 end)
    equal(nil, winner, 'gagnant sans vote')
    equal(nil, next(counts), 'comptes vides')
end)

check('r. tally : votes hors liste ou id inconnu ignorés', function()
    local votes = { [1] = 'a', [2] = 'b', [4] = 'a', [5] = 'z' }
    local voters = { 1, 2 }
    local winner1, counts1 = Q.tally(votes, voters, choicesVote, function(_n) return 1 end)
    equal('a', winner1, 'gagnant avec tirage 1')
    equal(1, counts1.a, 'voix pour a')
    equal(1, counts1.b, 'voix pour b')
    equal(nil, counts1.z, 'id inconnu non compté')
    local winner2 = Q.tally(votes, voters, choicesVote, function(_n) return 2 end)
    equal('b', winner2, 'gagnant avec tirage 2')
end)

check('s. tally : fonction pure (votes et voters inchangés)', function()
    local votes = { [1] = 'a', [2] = 'b', [4] = 'a', [5] = 'z' }
    local voters = { 1, 2 }
    Q.tally(votes, voters, choicesVote, function(_n) return 1 end)
    equal('a', votes[1], 'votes[1] inchangé')
    equal(2, #voters, 'voters inchangé')
end)

check('t. tally : sans fonction aléatoire, premier candidat gagne', function()
    local winner, counts = Q.tally({ [1] = 'a', [2] = 'b' }, { 1, 2 }, choicesVote)
    equal('a', winner, 'gagnant par défaut en égalité')
    equal(1, counts.a, 'voix pour a')
    equal(1, counts.b, 'voix pour b')
end)

check('u. vote : un joueur non inscrit reçoit une erreur', function()
    local s = newServer()
    s.makePlayer(1)
    s.vote(1, 'a')
    equal('Inscris ton escouade dans la file pour voter.', s.lastNotice(1), 'notice d erreur exacte')
    equal(false, s.queueOf(1).joined, 'joueur toujours non inscrit')
    equal(0, mapVotes(s.queueOf(1), 'a'), 'aucune voix pour a')
    equal(0, mapVotes(s.queueOf(1), 'b'), 'aucune voix pour b')
    equal(nil, s.queueOf(1).myVote, 'aucun vote personnel')
end)

check('v. vote : deux joueurs inscrits votent pour des cartes distinctes', function()
    local s = newServer()
    s.makePlayer(1)
    s.makePlayer(2)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')
    s.vote(1, 'a')
    s.vote(2, 'b')
    equal(1, mapVotes(s.queueOf(1), 'a'), 'voix pour a')
    equal(1, mapVotes(s.queueOf(1), 'b'), 'voix pour b')
    equal('a', s.queueOf(1).myVote, 'vote du joueur 1')
    equal('b', s.queueOf(2).myVote, 'vote du joueur 2')
end)

check('w. vote : revoter la même carte retire le vote, id inconnu refusé', function()
    local s = newServer()
    s.makePlayer(1)
    s.makePlayer(2)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')
    s.vote(1, 'a')
    s.vote(2, 'b')

    s.vote(1, 'a')
    equal(nil, s.queueOf(1).myVote, 'vote du joueur 1 retiré')
    equal(0, mapVotes(s.queueOf(1), 'a'), 'voix pour a après retrait')
    equal(1, mapVotes(s.queueOf(1), 'b'), 'voix pour b après retrait')

    s.vote(1, 'z')
    contains(s.lastNotice(1), 'Carte inconnue.', 'notice d id inconnu')
    equal(nil, s.queueOf(1).myVote, 'vote du joueur 1 toujours nil')
    equal(0, mapVotes(s.queueOf(1), 'a'), 'voix pour a inchangée')
    equal(1, mapVotes(s.queueOf(1), 'b'), 'voix pour b inchangée')
end)

check('x. lancement : SetNextMap avant l enregistrement et le premier SetMode', function()
    local s = newServer()
    s.min(2)
    s.makePlayer(1)
    s.makePlayer(2)
    s.makePlayer(3)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')
    s.play(3, 'attack')
    s.vote(1, 'a')
    s.vote(2, 'a')
    s.vote(3, 'b')
    equal(2, mapVotes(s.queueOf(1), 'a'), 'deux voix pour a avant seuil')
    equal(1, mapVotes(s.queueOf(1), 'b'), 'une voix pour b avant seuil')

    s.threshold()

    equal(1, #s.setNextMapCalls, 'un seul appel à SetNextMap')
    equal('a', s.setNextMapCalls[1].id, 'carte gagnante')
    local setNextMapIndex = s.journalIndex('SetNextMap')
    assert(setNextMapIndex, 'SetNextMap doit figurer au journal')
    local registerIndex = s.journalIndex('RegisterSquads')
    assert(registerIndex, 'RegisterSquads doit figurer au journal')
    local firstSetMode = s.firstSetModeIndex()
    assert(firstSetMode, 'au moins un SetMode attendu')
    assert(setNextMapIndex < registerIndex, 'SetNextMap avant RegisterSquads')
    assert(setNextMapIndex < firstSetMode, 'SetNextMap avant le premier SetMode')

    equal(true, s.setModeFor(1, 'attack'), 'SetMode pour 1')
    equal(true, s.setModeFor(2, 'attack'), 'SetMode pour 2')
    equal(true, s.setModeFor(3, 'attack'), 'SetMode pour 3')

    equal(nil, s.queueOf(1).myVote, 'votes vidés pour 1')
    equal(nil, s.queueOf(2).myVote, 'votes vidés pour 2')
    equal(nil, s.queueOf(3).myVote, 'votes vidés pour 3')
    equal(0, mapVotes(s.queueOf(1), 'a'), 'carte a à 0 après lancement')
    equal(0, mapVotes(s.queueOf(1), 'b'), 'carte b à 0 après lancement')
    for _, src in ipairs({ 1, 2, 3 }) do
        contains(s.lastNotice(src), 'Carte choisie : Alpha (2 vote(s)).',
            ('notice de carte envoyée à %d'):format(src))
    end
end)

check('y. égalité : le gagnant suit math.random', function()
    local function equalVote(randomValue)
        local s = newServer()
        s.min(2)
        s.makePlayer(1)
        s.makePlayer(2)
        s.callNet('gf_lobby:invite', 1, { id = 2 })
        local partyId = s.stateOf(1).party.id
        s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
        s.play(1, 'attack')
        s.vote(1, 'a')
        s.vote(2, 'b')
        s.setRandom(function(_n) return randomValue end)
        s.threshold()
        return s
    end

    local first = equalVote(1)
    equal(1, #first.setNextMapCalls, 'un seul appel sur le premier serveur')
    equal('a', first.setNextMapCalls[1].id, 'tirage 1 donne a')

    local second = equalVote(2)
    equal(1, #second.setNextMapCalls, 'un seul appel sur le second serveur')
    equal('b', second.setNextMapCalls[1].id, 'tirage 2 donne b')
end)

check('z. aucun vote : SetNextMap jamais appelé mais escouades enregistrées', function()
    local s = newServer()
    s.min(2)
    s.makePlayer(1)
    s.makePlayer(2)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')
    s.threshold()
    equal(0, #s.setNextMapCalls, 'aucun appel à SetNextMap')
    equal(nil, s.journalIndex('SetNextMap'), 'aucune trace de SetNextMap')
    equal(1, #s.registerCalls(), 'RegisterSquads toujours appelé')
end)

check('aa. annulation par le chef : votes de l escouade effacés', function()
    local s = newServer()
    s.min(20)
    s.makePlayer(1)
    s.makePlayer(2)
    s.callNet('gf_lobby:invite', 1, { id = 2 })
    local partyId = s.stateOf(1).party.id
    s.callNet('gf_lobby:respondInvite', 2, { partyId = partyId, accept = true })
    s.play(1, 'attack')
    s.vote(1, 'a')
    s.vote(2, 'b')
    equal(1, mapVotes(s.queueOf(1), 'a'), 'voix pour a avant annulation')
    equal(1, mapVotes(s.queueOf(1), 'b'), 'voix pour b avant annulation')

    s.cancel(1)
    equal(false, s.queueOf(1).joined, 'chef retiré de la file')
    equal(nil, s.queueOf(1).myVote, 'vote du chef effacé')
    equal(nil, s.queueOf(2).myVote, 'vote du membre effacé')
    equal(0, mapVotes(s.queueOf(1), 'a'), 'carte a à 0 après annulation')
    equal(0, mapVotes(s.queueOf(1), 'b'), 'carte b à 0 après annulation')
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
