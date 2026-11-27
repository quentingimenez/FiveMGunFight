-- =============================================================================
--  gf_menu : menu_state.lua (module pur) — cas nominaux et limites.
--  Exécuter depuis la racine du dépôt : lua5.4 tests/lua/menu_state_test.lua
--
--  config.lua puis menu_state.lua sont chargés comme dans la ressource : le
--  module lit Config, aucune native n'est nécessaire.
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

dofile(RESOURCE .. 'config.lua')
dofile(RESOURCE .. 'menu_state.lua')

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

local TIRET = '—'
local NAN = 0 / 0

-- ------------------------------------------------------------------- formatKd

check('formatKd : ratio nominal à deux décimales', function()
    equal('0.17', GFMenuState.formatKd(4, 23), 'formatKd(4, 23)')
    equal('1.50', GFMenuState.formatKd(3, 2), 'formatKd(3, 2)')
    equal('0.00', GFMenuState.formatKd(0, 12), 'formatKd(0, 12)')
end)

check('formatKd : zéro mort ne divise pas', function()
    equal('5.00', GFMenuState.formatKd(5, 0), 'formatKd(5, 0)')
    equal('0.00', GFMenuState.formatKd(0, 0), 'formatKd(0, 0)')
end)

check('formatKd : morts négatifs traités comme zéro', function()
    equal('2.00', GFMenuState.formatKd(2, -3), 'formatKd(2, -3)')
end)

check('formatKd : entrées nil ou non numériques', function()
    equal(TIRET, GFMenuState.formatKd(nil, 3), 'kills nil')
    equal(TIRET, GFMenuState.formatKd(4, nil), 'deaths nil')
    equal(TIRET, GFMenuState.formatKd('4', 23), 'kills chaîne')
    equal(TIRET, GFMenuState.formatKd(4, {}), 'deaths table')
end)

check('formatKd : NaN et infinis', function()
    equal(TIRET, GFMenuState.formatKd(NAN, 23), 'kills NaN')
    equal(TIRET, GFMenuState.formatKd(4, NAN), 'deaths NaN')
    equal(TIRET, GFMenuState.formatKd(math.huge, 23), 'kills infini')
    equal(TIRET, GFMenuState.formatKd(4, -math.huge), 'deaths infini négatif')
end)

-- --------------------------------------------------------------- formatDuration

check('formatDuration : minutes', function()
    equal('1 min', GFMenuState.formatDuration(63), 'formatDuration(63)')
    equal('14 min', GFMenuState.formatDuration(896), 'formatDuration(896)')
    equal('0 min', GFMenuState.formatDuration(0), 'formatDuration(0)')
    equal('59 min', GFMenuState.formatDuration(3599), 'formatDuration(3599)')
end)

check('formatDuration : heures et minutes', function()
    -- 896 minutes = 14 h 56 ; l'entrée est en secondes (896 * 60).
    equal('14 h 56', GFMenuState.formatDuration(896 * 60), 'formatDuration(896 * 60)')
    equal('1 h 00', GFMenuState.formatDuration(3600), 'formatDuration(3600)')
    equal('1 h 01', GFMenuState.formatDuration(3661), 'formatDuration(3661)')
end)

check('formatDuration : jours et heures', function()
    equal('1 j 0 h', GFMenuState.formatDuration(24 * 3600), 'formatDuration(86400)')
    equal('2 j 3 h', GFMenuState.formatDuration((2 * 24 + 3) * 3600), 'formatDuration(183600)')
end)

check('formatDuration : valeurs invalides', function()
    equal(TIRET, GFMenuState.formatDuration(-1), 'négatif')
    equal(TIRET, GFMenuState.formatDuration(NAN), 'NaN')
    equal(TIRET, GFMenuState.formatDuration(math.huge), 'infini')
    equal(TIRET, GFMenuState.formatDuration(nil), 'nil')
    equal(TIRET, GFMenuState.formatDuration('63'), 'chaîne')
end)

-- ------------------------------------------------------------------- modeLabel

check('modeLabel : modes répertoriés', function()
    equal('DANS LE LOBBY', GFMenuState.modeLabel('lobby'), 'lobby')
    equal('ATTAQUE DE ZONE', GFMenuState.modeLabel('attack'), 'attack')
    equal('REDZONE', GFMenuState.modeLabel('redzone'), 'redzone')
end)

check('modeLabel : absence de mode', function()
    equal(Config.ModeLabelIdle, GFMenuState.modeLabel(nil), 'nil')
    equal(Config.ModeLabelIdle, GFMenuState.modeLabel(''), 'chaîne vide')
    equal('HORS PARTIE', GFMenuState.modeLabel(nil), 'libellé inactif')
end)

check('modeLabel : mode inconnu', function()
    equal(Config.ModeLabelFallback, GFMenuState.modeLabel('inconnu'), 'mode inconnu')
    equal(Config.ModeLabelFallback, GFMenuState.modeLabel(42), 'nombre')
end)

-- --------------------------------------------------------------------- cooldown

check('cooldown : première autorisation, refus puis nouvelle autorisation', function()
    local session = {}
    equal(true, GFMenuState.cooldown(session, 1000, 500), 'premier appel')
    equal(1000, session.lastAt, 'lastAt écrit')
    equal(false, GFMenuState.cooldown(session, 1200, 500), 'dans la fenêtre')
    equal(1000, session.lastAt, 'lastAt inchangé après refus')
    equal(true, GFMenuState.cooldown(session, 1500, 500), 'après la fenêtre')
    equal(1500, session.lastAt, 'lastAt mis à jour')
end)

check('cooldown : horloge qui recule', function()
    local session = { lastAt = 5000 }
    equal(false, GFMenuState.cooldown(session, 1000, 500), 'horloge arrière')
    equal(5000, session.lastAt, 'lastAt inchangé')
end)

check('cooldown : session invalide', function()
    equal(false, GFMenuState.cooldown(nil, 1000, 500), 'session nil')
    equal(false, GFMenuState.cooldown('session', 1000, 500), 'session chaîne')
    equal(false, GFMenuState.cooldown(false, 1000, 500), 'session booléen')
end)

check('cooldown : horloge et intervalle invalides', function()
    equal(false, GFMenuState.cooldown({}, nil, 500), 'horloge nil')
    equal(false, GFMenuState.cooldown({}, NAN, 500), 'horloge NaN')
    equal(false, GFMenuState.cooldown({}, math.huge, 500), 'horloge infinie')
    equal(false, GFMenuState.cooldown({}, 1000, nil), 'intervalle nil')
    equal(false, GFMenuState.cooldown({}, 1000, NAN), 'intervalle NaN')
    equal(false, GFMenuState.cooldown({}, 1000, -1), 'intervalle négatif')
end)

check('cooldown : interruption invalide dans la session', function()
    equal(false, GFMenuState.cooldown({ lastAt = 'hier' }, 1000, 500), 'lastAt chaîne')
    equal(false, GFMenuState.cooldown({ lastAt = NAN }, 1000, 500), 'lastAt NaN')
    equal(false, GFMenuState.cooldown({ lastAt = math.huge }, 1000, 500), 'lastAt infini')
    local session = { lastAt = nil }
    equal(true, GFMenuState.cooldown(session, 1000, 0), 'intervalle zéro')
end)

-- -------------------------------------------------------------------- buildState

check('buildState : état complet', function()
    local ctx = {
        build = '1.2.3',
        name = 'Alice',
        id = 42,
        mode = 'attack',
        now = 1000000,
        joinedAt = 1000000 - 63 * 1000,
        online = 17,
        maxPlayers = 48,
        stats = { kills = 4, deaths = 23, matches = 30, wins = 12, memberSince = '2024-01-02' },
    }
    local state = GFMenuState.buildState(ctx)
    equal('1.2.3', state.build, 'build')
    equal(Config.ServerName, state.server.name, 'server.name')
    equal(17, state.online, 'online')
    equal(48, state.maxPlayers, 'maxPlayers')
    equal(42, state.me.id, 'me.id')
    equal('Alice', state.me.name, 'me.name')
    equal('attack', state.me.mode, 'me.mode')
    equal('ATTAQUE DE ZONE', state.me.modeLabel, 'me.modeLabel')
    equal('2024-01-02', state.me.memberSince, 'me.memberSince')
    equal(true, state.statsAvailable, 'statsAvailable')
    equal(4, state.stats.kills, 'stats.kills')
    equal(23, state.stats.deaths, 'stats.deaths')
    equal(30, state.stats.matches, 'stats.matches')
    equal(12, state.stats.wins, 'stats.wins')
    equal('0.17', state.stats.kd, 'stats.kd')
    equal('1 min', state.stats.session, 'stats.session')
    equal(Config.Rules, state.rules, 'rules')
    equal(Config.DiscordUrl, state.discord.url, 'discord.url')
    equal(Config.Features, state.features, 'features')
    equal(false, state.isAdmin, 'isAdmin absent du contexte complet')
end)

check('buildState : droits admin strictement booléens', function()
    equal(true, GFMenuState.buildState({ isAdmin = true }).isAdmin, 'isAdmin true')
    equal(false, GFMenuState.buildState({ isAdmin = false }).isAdmin, 'isAdmin false')
    equal(false, GFMenuState.buildState({}).isAdmin, 'isAdmin absent')
    for _, valeur in ipairs({ 1, 'true', {} }) do
        equal(false, GFMenuState.buildState({ isAdmin = valeur }).isAdmin,
            'isAdmin truthy non booléen : ' .. type(valeur))
    end
end)

check('buildState : sans statistiques', function()
    local state = GFMenuState.buildState({ name = 'Bob', id = 7, mode = 'lobby' })
    equal(false, state.statsAvailable, 'statsAvailable')
    equal(TIRET, state.stats.kd, 'stats.kd')
    equal(TIRET, state.me.memberSince, 'me.memberSince')
    equal(TIRET, state.stats.session, 'stats.session')
    equal(0, state.stats.kills, 'stats.kills')
    equal(0, state.stats.deaths, 'stats.deaths')
    equal(0, state.stats.matches, 'stats.matches')
    equal(0, state.stats.wins, 'stats.wins')
    equal('DANS LE LOBBY', state.me.modeLabel, 'me.modeLabel')
    equal(Config.BuildFallback, state.build, 'build par défaut')
end)

check('buildState : session calculée même sans statistiques', function()
    local state = GFMenuState.buildState({ now = 1000, joinedAt = 0 })
    equal(false, state.statsAvailable, 'statsAvailable')
    equal('0 min', state.stats.session, 'stats.session')
end)

check('buildState : statistiques invalides', function()
    local state = GFMenuState.buildState({ stats = 'pas une table' })
    equal(false, state.statsAvailable, 'statsAvailable')
    equal(TIRET, state.stats.kd, 'stats.kd')
end)

check('buildState : champs manquants', function()
    for _, entree in ipairs({ { ctx = nil }, { ctx = 'x' }, { ctx = 42 }, { ctx = {} } }) do
        local ctx = entree.ctx
        local ok, state = pcall(GFMenuState.buildState, ctx)
        equal(true, ok, 'buildState ne lève pas pour ' .. type(ctx))
        equal(TIRET, state.me.name, 'me.name par défaut')
        equal(false, state.statsAvailable, 'statsAvailable par défaut')
        equal(TIRET, state.stats.session, 'stats.session par défaut')
        equal(Config.ModeLabelIdle, state.me.modeLabel, 'me.modeLabel par défaut')
    end
end)

check('buildState : statistiques partielles', function()
    local state = GFMenuState.buildState({
        stats = { kills = 3, deaths = 'invalide', wins = 2, memberSince = '2020' },
        now = 2000,
        joinedAt = nil,
    })
    equal(true, state.statsAvailable, 'statsAvailable')
    equal(3, state.stats.kills, 'stats.kills')
    equal(0, state.stats.deaths, 'stats.deaths invalide')
    equal(2, state.stats.wins, 'stats.wins')
    equal('3.00', state.stats.kd, 'stats.kd sans mort valide')
    equal(TIRET, state.stats.session, 'stats.session sans horloge')
    equal('2020', state.me.memberSince, 'me.memberSince')
end)

print(('%d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
