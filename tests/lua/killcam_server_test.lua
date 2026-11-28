-- Test du serveur gf_killcam : horodatage, tampon, clip et exports.
-- Lancement : lua5.4 tests/lua/killcam_server_test.lua  (ou GF_ROOT=<racine> du dépôt).
-- config.lua, track.lua et server.lua sont chargés avec loadfile(path, 't', env)
-- dans le MÊME environnement simulé, dans cet ordre. Aucune règle métier n'est
-- recopiée ici : les vrais fichiers de la ressource sont exécutés.

local root = os.getenv('GF_ROOT') or '.'
local base = root .. '/server-data/resources/[gunfight]/gf_killcam/'

local ok = 0

local function check(condition, message)
    if not condition then
        io.stderr:write(('ECHEC : %s\n'):format(tostring(message)))
        os.exit(1)
    end
    ok = ok + 1
end

-- ---------------------------------------------------------------------------
-- Faux du serveur FiveM.
-- ---------------------------------------------------------------------------
local clock = 100000
local modes = {}
local names = {
    [1] = 'Tueur', [2] = 'Victime', [3] = 'Proche', [4] = 'Loin',
    [5] = 'AutreMode', [6] = 'Spectateur', [7] = 'Huitieme', [8] = 'Neuvieme',
    [9] = 'Dixieme', [10] = 'Onzieme', [11] = 'Douzieme',
}
local players = {}

local handlers = {}         -- RegisterNetEvent(name, fn) et AddEventHandler(name, fn)
local clips = {}            -- { { event, target, bytes, clip }, ... }
local prints = {}           -- print capturé de l'environnement serveur
local exported = {}         -- exports('Nom', fn) / exports('Ressource', table)

local exportsProxy
exportsProxy = setmetatable({}, {
    __call = function(_, name, value)
        if type(name) == 'string' and type(value) == 'table' then
            -- Forme exports('gf_killcam', { RemainingMs = fn, ... }).
            exported[name] = value
            for key, fn in pairs(value) do exported[key] = fn end
        elseif type(name) == 'string' and type(value) == 'function' then
            -- Forme exports('RemainingMs', fn).
            exported[name] = value
        elseif type(name) == 'string' then
            -- Forme exports.gf_core.GetMode(_, src) : la table est fournie plus bas.
            return exported[name]
        end
    end,
    __index = function(_, key) return exported[key] end,
})

local env = setmetatable({
    source = 0,
    Config = nil,
    exports = exportsProxy,
    GetGameTimer = function() return clock end,
    GetPlayers = function()
        local result = {}
        for i = 1, #players do result[i] = players[i] end
        return result
    end,
    GetPlayerName = function(src) return names[src] end,
    RegisterNetEvent = function(name, fn) handlers[name] = fn end,
    AddEventHandler = function(name, fn)
        if type(fn) == 'function' then handlers[name] = fn end
    end,
    TriggerLatentClientEvent = function(event, target, bytes, clip)
        clips[#clips + 1] = { event = event, target = target, bytes = bytes, clip = clip }
    end,
    TriggerClientEvent = function() end,
    TriggerEvent = function() end,
    RegisterCommand = function() end,
    CreateThread = function() end,
    Wait = function() end,
    GetCurrentResourceName = function() return 'gf_killcam' end,
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
        prints[#prints + 1] = table.concat(parts, '\t')
    end,
}, { __index = _G })

-- exports.gf_core.GetMode(_, src) : lecture du mode courant du joueur.
exported.gf_core = { GetMode = function(a, b)
    -- Certains exports passent la source en premier, d'autres en second.
    local src = type(a) == 'number' and a or b
    return modes[src]
end }
exported.gf_killcam = setmetatable({}, { __index = exported })

assert(type(env.Config) == 'nil', 'préambule : Config absent avant le chargement')
assert(loadfile(base .. 'config.lua', 't', env))()
local Config = assert(env.Config, 'Config global absent de config.lua')
check(Config.Enabled == true, 'config : Enabled=true au chargement')
check(Config.BufferSeconds == 30, 'config : BufferSeconds=30 au chargement')
check(Config.ReplaySeconds == 8, 'config : ReplaySeconds=8 au chargement')
check(Config.SampleMs == 100, 'config : SampleMs=100 au chargement')
check(Config.BatchMs == 1000, 'config : BatchMs=1000 au chargement')
check(Config.MaxOthers == 6, 'config : MaxOthers=6 au chargement')
check(Config.OthersRadius == 120.0, 'config : OthersRadius=120.0 au chargement')
check(Config.Modes and Config.Modes.attack == true and Config.Modes.redzone == true,
    'config : Modes attack et redzone actifs')

assert(loadfile(base .. 'track.lua', 't', env))()
assert(env.GFKillcamTrack, 'GFKillcamTrack absent de track.lua')
assert(loadfile(base .. 'server.lua', 't', env))()

local samplesHandler = assert(handlers['gf_killcam:samples'],
    'handler gf_killcam:samples absent (RegisterNetEvent ou AddEventHandler)')
local killedHandler = assert(handlers['gf:playerKilled'], 'handler gf:playerKilled absent')
local droppedHandler = assert(handlers['playerDropped'], 'handler playerDropped absent')
local modeLeftHandler = assert(handlers['gf:modeLeft'], 'handler gf:modeLeft absent')

local RemainingMs = exported.RemainingMs
if type(RemainingMs) ~= 'function' and type(exported.gf_killcam) == 'table' then
    RemainingMs = exported.gf_killcam.RemainingMs
end
RemainingMs = assert(RemainingMs, 'export RemainingMs absent')

-- ---------------------------------------------------------------------------
-- Utilitaires du test : aucun comportement métier n'est réimplémenté.
-- ---------------------------------------------------------------------------
local function sample(t, x, y, z, w)
    return {
        t = t or 0, x = x or 0, y = y or 0, z = z or 0,
        h = 0, cx = 0, cy = 0, cz = 0, rx = 0, ry = 0, rz = 0,
        w = w or 0, a = false, s = false, v = 0,
    }
end

local function send(src, lot)
    env.source = src
    return samplesHandler(lot)
end

local function kill(victim, killer, weapon, mode)
    env.source = killer
    return killedHandler(victim, killer, weapon, mode)
end

local function lastClip()
    return clips[#clips]
end

local function reset()
    -- Horloge strictement croissante entre les scénarios (le rate-limit est interne).
    clock = clock + 10000
    clips = {}
    modes = {}
    players = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11' }
    for src in pairs(names) do modes[src] = 'attack' end
    -- Vidage de l'état interne (tampons, rate-limit, chronomètres) via le handler du serveur.
    for src = 1, 11 do
        env.source = src
        droppedHandler('reset')
    end
    env.source = 0
end

local function sortedSamples(list)
    local times = {}
    for i, s in ipairs(list or {}) do times[i] = s.t end
    for i = 1, #times do
        for j = i + 1, #times do
            if times[j] < times[i] then times[i], times[j] = times[j], times[i] end
        end
    end
    return times
end

local function isSorted(times)
    for i = 2, #times do
        if times[i] < times[i - 1] then return false end
    end
    return true
end

-- 1. Mode refusé : un lot en lobby est ignoré, même après passage en attack.
do
    reset()
    modes[1] = 'lobby'
    send(1, { sample(0, 0), sample(100, 1) })
    modes[1] = 'attack'
    kill(2, 1, 100, 'attack')
    check(#clips == 0, 'cas 1 : aucun clip quand le lot a été envoyé en mode lobby')
    -- Le tampon doit rester vide : le kill suivant, sans nouvel envoi, ne produit rien non plus.
    kill(2, 1, 100, 'attack')
    check(#clips == 0, 'cas 1 : tampon vide après refus du mode')
end

-- 2. Rate-limit : 1 lot / 700 ms.
do
    reset()
    send(1, { sample(0, 10) })
    clock = clock + 100
    send(1, { sample(0, 20) })
    clock = clock + 600                     -- t+700 depuis le premier lot
    send(1, { sample(0, 30) })
    kill(2, 1, 123, 'attack')
    local envoye = lastClip()
    check(envoye ~= nil, 'cas 2 : clip produit')
    local clip = envoye and envoye.clip
    check(clip and clip.killer and #clip.killer.samples == 2,
        'cas 2 : seulement 2 échantillons (1er et 3e lot)')
    if clip and clip.killer then
        local xs = {}
        for _, s in ipairs(clip.killer.samples) do xs[#xs + 1] = s.x end
        table.sort(xs)
        check(xs[1] == 10 and xs[2] == 30, 'cas 2 : échantillons du 1er et 3e lot, pas du 2e')
    end
end

-- 3. Horodatage : dernier échantillon à GetGameTimer(), précédents espacés de SampleMs.
do
    reset()
    local t0 = clock
    send(1, { sample(0, 1), sample(0, 2), sample(0, 3) })
    kill(2, 1, 456, 'attack')
    local envoye = lastClip()
    local clip = envoye and envoye.clip
    check(clip and clip.killer and #clip.killer.samples == 3, 'cas 3 : 3 échantillons dans le clip')
    if clip and clip.killer then
        local times = sortedSamples(clip.killer.samples)
        local windowStart = t0 - Config.ReplaySeconds * 1000
        check(isSorted(times), 'cas 3 : temps triés par ordre croissant')
        check(times[3] == Config.ReplaySeconds * 1000,
            'cas 3 : dernier t = fin de la fenêtre de ReplaySeconds')
        check(times[2] == Config.ReplaySeconds * 1000 - Config.SampleMs,
            'cas 3 : avant-dernier t espacé de SampleMs')
        check(times[1] == Config.ReplaySeconds * 1000 - 2 * Config.SampleMs,
            'cas 3 : premier t espacé de 2*SampleMs (horodatage serveur)')
        check(windowStart <= t0, 'cas 3 : fenêtre relative cohérente avec GetGameTimer()')
    end
end

-- 4. Tampon borné à BufferSeconds (configuration modifiée dynamiquement).
do
    reset()
    local saved = Config.BufferSeconds
    Config.BufferSeconds = 1
    for i = 0, 24 do
        send(1, { sample(0, i) })
        if i < 24 then clock = clock + 700 end  -- au-dessus du rate-limit de 700 ms
    end
    kill(2, 1, 789, 'attack')
    local envoye = lastClip()
    check(envoye ~= nil, 'cas 4 : clip produit avec BufferSeconds=1')
    local clip = envoye and envoye.clip
    if clip and clip.killer then
        local times = sortedSamples(clip.killer.samples)
        check(#times > 0, 'cas 4 : échantillons présents')
        local durationMs = (clip.duration or 0) * 1000
        local oldest = times[1]
        check(oldest >= durationMs - 1000 - 200,
            'cas 4 : aucun échantillon plus vieux que BufferSeconds (=1s)')
    end
    Config.BufferSeconds = saved
    check(Config.BufferSeconds == 30, 'cas 4 : BufferSeconds restauré à 30')
end

-- 5. Clip envoyé à la victime avec les champs du contrat.
do
    reset()
    send(1, { sample(0, 1) })
    send(2, { sample(0, 2) })
    kill(2, 1, 999, 'attack')
    local sent = lastClip()
    check(sent ~= nil, 'cas 5 : clip émis')
    check(sent and sent.event == 'gf_killcam:play', 'cas 5 : event gf_killcam:play')
    check(sent and sent.target == 2, 'cas 5 : destinataire = victime')
    check(sent and sent.bytes == 250000, 'cas 5 : 250000 octets')
    local clip = sent and sent.clip
    check(clip ~= nil, 'cas 5 : clip présent')
    if clip then
        check(clip.duration == 8, 'cas 5 : duration=8')
        check(clip.killer and clip.killer.id == 1 and clip.killer.name == 'Tueur',
            'cas 5 : identité du tueur')
        check(clip.victim and clip.victim.id == 2 and clip.victim.name == 'Victime',
            'cas 5 : identité de la victime')
        check(clip.weapon == 999, 'cas 5 : hash d’arme conservé')
        check(type(clip.others) == 'table', 'cas 5 : liste others présente')
        check(isSorted(sortedSamples(clip.killer.samples)), 'cas 5 : samples du tueur triés')
        check(isSorted(sortedSamples(clip.victim.samples)), 'cas 5 : samples de la victime triés')
    end
end

-- 6. others : même mode, rayon, maximum 6, ids triés.
do
    reset()
    -- 3 = à 50 m, 4 = à 200 m, 5 = autre mode, 6..11 = proches.
    send(1, { sample(0, 0, 0, 0) })
    send(2, { sample(0, 0, 0, 0) })
    send(3, { sample(0, 50, 0, 0) })
    send(4, { sample(0, 200, 0, 0) })
    modes[5] = 'lobby'
    send(5, { sample(0, 10, 0, 0) })
    for src = 6, 11 do send(src, { sample(0, 10 + src, 0, 0) }) end
    kill(2, 1, 111, 'attack')
    local clip = lastClip()
    check(clip ~= nil and clip.clip ~= nil, 'cas 6 : clip produit')
    if clip and clip.clip and clip.clip.others then
        local others = clip.clip.others
        check(#others <= Config.MaxOthers, 'cas 6 : au plus MaxOthers (6)')
        check(#others == Config.MaxOthers, 'cas 6 : MaxOthers proches inclus')
        local ids = {}
        for _, other in ipairs(others) do ids[#ids + 1] = other.id end
        check(isSorted(ids), 'cas 6 : ids triés')
        local seen = {}
        for _, id in ipairs(ids) do seen[id] = true end
        check(seen[3] == true, 'cas 6 : joueur proche inclus')
        local eligible = { [3] = true, [6] = true, [7] = true, [8] = true,
            [9] = true, [10] = true, [11] = true }
        local onlyEligible = true
        for id in pairs(seen) do
            if not eligible[id] then onlyEligible = false end
        end
        check(onlyEligible, 'cas 6 : seuls les joueurs proches du même mode sont conservés')
        check(seen[4] ~= true, 'cas 6 : joueur trop loin écarté')
        check(seen[5] ~= true, 'cas 6 : joueur d’un autre mode écarté')
        check(seen[1] ~= true and seen[2] ~= true,
            'cas 6 : tueur et victime absents de others')
    end
end

-- 7. Pas de clip sur suicide ou tueur inconnu.
do
    reset()
    send(1, { sample(0, 1) })
    send(2, { sample(0, 2) })
    local before = #clips
    kill(1, 1, 222, 'attack')
    check(#clips == before, 'cas 7 : aucun clip sur suicide')
    names[1] = nil
    kill(2, 1, 222, 'attack')
    check(#clips == before, 'cas 7 : aucun clip si GetPlayerName(tueur) est nil')
    names[1] = 'Tueur'
end

-- 8. Tampon du tueur non vide mais sans échantillon dans la fenêtre de rejeu :
--    aucun clip envoyé et aucun chronomètre mémorisé.
do
    reset()
    send(1, { sample(0, 1) })               -- seul échantillon, horodaté à T
    clock = clock + Config.ReplaySeconds * 1000 + 1000   -- T+9000 ms, hors fenêtre (8 s)
    local before = #clips
    kill(2, 1, 777, 'attack')
    check(#clips == before, 'cas 8 : aucun clip si le tampon du tueur est hors fenêtre')
    check(RemainingMs(2) == 0, 'cas 8 : RemainingMs=0 sans clip valide (pas de Restants)')
end

-- 9. RemainingMs : avant clip, après clip, progression, expiration, joueur inconnu.
do
    reset()
    check(RemainingMs(1) == 0, 'cas 9 : RemainingMs=0 avant tout clip')
    send(1, { sample(0, 1) })
    send(2, { sample(0, 2) })
    kill(2, 1, 333, 'attack')
    check(RemainingMs(2) == 8000, 'cas 9 : RemainingMs=8000 juste après le clip')
    clock = clock + 3000
    check(RemainingMs(2) == 5000, 'cas 9 : RemainingMs=5000 après 3000 ms')
    clock = clock + 6000
    check(RemainingMs(2) == 0, 'cas 9 : RemainingMs=0 après expiration')
    check(RemainingMs(999) == 0, 'cas 9 : RemainingMs=0 pour un joueur inconnu')
end

-- 10. playerDropped et gf:modeLeft vident le tampon / le chronomètre.
do
    reset()
    send(1, { sample(0, 1) })
    env.source = 1
    -- Le handler reçoit (src, mode) : c'est bien le joueur 1 qui quitte le mode.
    modeLeftHandler(1, 'attack')
    kill(2, 1, 444, 'attack')
    check(#clips == 0, 'cas 10 : aucun clip après gf:modeLeft du tueur')

    clock = clock + 800                     -- nouveau lot autorisé après le rate-limit
    send(1, { sample(0, 1) })
    send(2, { sample(0, 2) })
    kill(2, 1, 444, 'attack')
    check(RemainingMs(2) == 8000, 'cas 10 : clip actif avant playerDropped')
    env.source = 2
    droppedHandler('déconnexion')
    check(RemainingMs(2) == 0, 'cas 10 : RemainingMs=0 après playerDropped')
end

-- Confidentialité : aucun identifiant ni adresse IP dans les logs serveur.
for _, line in ipairs(prints) do
    check(not (line:find('license:', 1, true) or line:find('ip:', 1, true)),
        'fuite d’identifiant dans un print : ' .. line)
end

print(('%d test(s) réussi(s), 0 échec(s)'):format(ok))
