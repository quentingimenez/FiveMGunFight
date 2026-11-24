-- =============================================================================
--  gf_attack - SERVEUR
--  Toute la logique de la partie est ici (le client ne fait qu'afficher).
--
--  Phases :  waiting  → en attente de joueurs
--            prep     → préparation, joueurs gelés et protégés
--            live     → combat, pas de réapparition
--            ended    → pause entre deux manches
-- =============================================================================

local core = exports.gf_core

local S = {}

local function resetState()
    S.phase = 'waiting'
    S.team = {}           -- [src] = 'A' | 'B'
    S.alive = {}          -- [src] = true | false
    S.stats = {}          -- [src] = { kills, deaths }
    S.score = { A = 0, B = 0 }
    S.attackers = 'A'
    S.round = 0
    S.zoneIndex = S.zoneIndex or 1
    S.endsAt = 0
    S.solo = false        -- manche de test : une équipe vide, seul le chrono termine la manche
    S.matchOver = false
    S.scoreboardDirty = true
end
resetState()

-- ---------------------------------------------------------------- Utilitaires
local function now() return os.time() end
local function other(t) return t == 'A' and 'B' or 'A' end
local function zone() return Config.Zones[S.zoneIndex] end
local function defenders() return other(S.attackers) end
local function roleOf(t) return t == S.attackers and 'attack' or 'defense' end

local function count(t)
    local n = 0
    for _, tm in pairs(S.team) do if tm == t then n = n + 1 end end
    return n
end

local function aliveCount(t)
    local n = 0
    for src, tm in pairs(S.team) do if tm == t and S.alive[src] then n = n + 1 end end
    return n
end

local function eachPlayer(fn)
    for src in pairs(S.team) do fn(src) end
end

local function setTeam(src, t)
    S.team[src] = t
    Player(src).state:set('gf_team', t, true)
    S.scoreboardDirty = true
end

local function announce(src, title, sub, ms)
    TriggerClientEvent('gf_ui:announce', src, { title = title, subtitle = sub, duration = ms or 4000 })
end

local function announceAll(title, sub, ms)
    eachPlayer(function(src) announce(src, title, sub, ms) end)
end

-- Cap (heading GTA) pour regarder du point (x,y) vers (tx,ty)
local function headingTo(x, y, tx, ty)
    return (math.deg(math.atan(-(tx - x), ty - y)) + 360.0) % 360.0
end

local function spawnPos(src)
    local z = zone()
    local c = z.center
    if roleOf(S.team[src]) == 'defense' then
        local a = math.random() * 2 * math.pi
        local d = math.random() * z.radius * 0.4
        local x, y = c.x + math.cos(a) * d, c.y + math.sin(a) * d
        return x, y, c.z, math.random(0, 359) + 0.0
    end
    local rad = math.rad(z.attackFrom or 0)
    local dist = z.radius + Config.AttackSpawnDistance
    local spread = Config.SpawnSpread
    local x = c.x + math.sin(rad) * dist + (math.random() * 2 - 1) * spread
    local y = c.y + math.cos(rad) * dist + (math.random() * 2 - 1) * spread
    return x, y, c.z, headingTo(x, y, c.x, c.y)
end

local function spawnRole(src, opts)
    local x, y, z, h = spawnPos(src)
    core:Spawn(src, {
        x = x, y = y, z = z, heading = h,
        loadout = opts.loadout and 'attack' or nil,
        freeze = opts.freeze, protected = opts.protected,
    })
end

local function toSpectator(src)
    if not S.team[src] then return end
    local c = zone().center
    core:Spawn(src, { x = c.x, y = c.y, z = c.z + 45.0, heading = 0.0, spectator = true })
end

local function sendZone(src)
    local z = zone()
    TriggerClientEvent('gf_attack:zone', src, {
        name = z.name,
        center = { x = z.center.x, y = z.center.y, z = z.center.z },
        radius = z.radius,
        defenders = defenders(),
        phase = S.phase,
        damage = Config.OutOfZoneDamage,
        colors = { A = Config.Teams.A.color, B = Config.Teams.B.color },
    })
end

local function sendZoneAll() eachPlayer(sendZone) end

-- Place un joueur selon la phase actuelle (arrivée en cours de partie, etc.)
local function placeForPhase(src)
    if S.phase == 'prep' then
        S.alive[src] = true
        spawnRole(src, { loadout = true, freeze = true, protected = true })
    elseif S.phase == 'live' then
        S.alive[src] = false
        toSpectator(src)
        announce(src, 'Manche en cours', 'Tu joueras dès la prochaine manche', 4000)
    else
        S.alive[src] = false
        spawnRole(src, { loadout = false, protected = true })
    end
    sendZone(src)
end

-- Équilibre les équipes (différence max de 1 joueur)
local function autobalance()
    for _ = 1, 64 do
        local a, b = count('A'), count('B')
        if math.abs(a - b) <= 1 then return end
        local from = a > b and 'A' or 'B'
        local pool = {}
        for src, t in pairs(S.team) do if t == from then pool[#pool + 1] = src end end
        local moved = pool[math.random(#pool)]
        setTeam(moved, other(from))
        core:Notify(moved, ('Équilibrage : tu passes dans l\'%s'):format(Config.Teams[other(from)].label))
    end
end

local function canStart()
    local a, b = count('A'), count('B')
    return a >= 1 and b >= 1 and a + b >= Config.MinPlayers
end

-- ---------------------------------------------------------------- Déroulement
local function startPrep()
    autobalance()
    S.round = S.round + 1
    S.phase = 'prep'
    S.endsAt = now() + Config.PrepTime
    S.solo = count('A') == 0 or count('B') == 0

    eachPlayer(function(src)
        S.alive[src] = true
        spawnRole(src, { loadout = true, freeze = true, protected = true })
        local role = roleOf(S.team[src])
        announce(src, ('Manche %d'):format(S.round),
            role == 'attack' and ('Tu ATTAQUES : ' .. zone().name) or ('Tu DÉFENDS : ' .. zone().name), 5000)
    end)
    if S.solo then
        announceAll(('Manche %d (test)'):format(S.round), 'Une équipe est vide : la manche se termine au chrono', 5000)
    end
    sendZoneAll()
    S.scoreboardDirty = true
end

local function startLive()
    S.phase = 'live'
    S.endsAt = now() + Config.RoundTime
    eachPlayer(function(src)
        if S.alive[src] then
            core:Freeze(src, false)
            core:SetProtected(src, false)
        end
    end)
    announceAll('GO !', nil, 2000)
    sendZoneAll()
end

local function endRound(winner, reason)
    if S.phase ~= 'live' then return end
    S.phase = 'ended'
    S.score[winner] = S.score[winner] + 1
    S.endsAt = now() + Config.EndDelay

    eachPlayer(function(src) core:SetProtected(src, true) end)

    local label = Config.Teams[winner].label
    if S.score[winner] >= Config.WinRounds then
        S.matchOver = true
        S.endsAt = now() + Config.MatchEndDelay
        announceAll(('%s remporte le match !'):format(label),
            ('Score final %d - %d'):format(S.score.A, S.score.B), 8000)
    else
        announceAll(('%s gagne la manche'):format(label), reason, 5000)
    end
    sendZoneAll()
    S.scoreboardDirty = true
end

local function goWaiting()
    S.phase = 'waiting'
    S.endsAt = 0
    eachPlayer(function(src)
        S.alive[src] = false
        spawnRole(src, { loadout = false, protected = true })
    end)
    sendZoneAll()
end

local function nextRound()
    if S.matchOver then
        S.score = { A = 0, B = 0 }
        S.round = 0
        S.attackers = 'A'
        S.matchOver = false
        S.zoneIndex = S.zoneIndex % #Config.Zones + 1
        for src in pairs(S.stats) do S.stats[src] = { kills = 0, deaths = 0 } end
    elseif Config.SwapSidesEveryRound then
        S.attackers = other(S.attackers)
    end

    if canStart() then startPrep() else goWaiting() end
end

local function checkWin()
    if S.phase ~= 'live' or S.solo then return end
    local att, def = S.attackers, defenders()
    local a, d = aliveCount(att), aliveCount(def)
    if a == 0 then
        endRound(def, 'Tous les attaquants ont été éliminés')
    elseif d == 0 then
        endRound(att, 'Tous les défenseurs ont été éliminés')
    end
end

-- ---------------------------------------------------------------- HUD & classement
local function phaseLabel()
    return ({ waiting = 'En attente de joueurs', prep = 'Préparation', live = 'Combat', ended = 'Fin de manche' })[S.phase]
end

local function sendHud()
    local remaining = S.endsAt > 0 and math.max(S.endsAt - now(), 0) or nil
    local function side(t)
        local role = roleOf(t) == 'attack' and 'Attaque' or 'Défense'
        return {
            label = ('%s · %s'):format(Config.Teams[t].label, role),
            value = S.score[t],
            sub = ('%d / %d en vie'):format(aliveCount(t), count(t)),
            color = Config.Teams[t].color,
        }
    end
    local left, right = side('A'), side('B')
    local subtitle = ('%s  •  %s  •  Premier à %d'):format(zone().name, phaseLabel(), Config.WinRounds)
    if S.phase == 'waiting' then
        subtitle = ('%s  •  En attente : %d / %d joueurs'):format(zone().name, count('A') + count('B'), Config.MinPlayers)
    end

    eachPlayer(function(src)
        local t = S.team[src]
        local attack = roleOf(t) == 'attack'
        TriggerClientEvent('gf_ui:hud', src, {
            title = S.round > 0 and ('Attaque de zone · Manche %d'):format(S.round) or 'Attaque de zone',
            subtitle = subtitle,
            timer = remaining,
            badge = {
                text = (attack and 'TU ATTAQUES' or 'TU DÉFENDS') .. (S.alive[src] == false and S.phase == 'live' and ' · ÉLIMINÉ' or ''),
                color = Config.Teams[t].color,
            },
            left = left, right = right,
        })
    end)
end

local function sendScoreboard()
    local rows = {}
    for src, t in pairs(S.team) do
        local st = S.stats[src] or { kills = 0, deaths = 0 }
        rows[#rows + 1] = {
            cells = { GetPlayerName(src) or '?', Config.Teams[t].label, st.kills, st.deaths,
                S.alive[src] and 'En vie' or '—' },
            color = Config.Teams[t].color,
        }
    end
    table.sort(rows, function(a, b) return a.cells[3] > b.cells[3] end)
    local data = {
        title = ('Attaque de zone · %d - %d'):format(S.score.A, S.score.B),
        columns = { 'Joueur', 'Équipe', 'Kills', 'Morts', 'État' },
        rows = rows,
    }
    eachPlayer(function(src) TriggerClientEvent('gf_ui:scoreboard', src, data) end)
end

-- Boucle principale (1 fois par seconde)
CreateThread(function()
    while true do
        Wait(1000)
        local t = now()
        if S.phase == 'waiting' then
            if canStart() then startPrep() end
        elseif S.phase == 'prep' then
            if t >= S.endsAt then startLive() end
        elseif S.phase == 'live' then
            if t >= S.endsAt then endRound(defenders(), 'Temps écoulé : la défense a tenu la zone') end
        elseif S.phase == 'ended' then
            if t >= S.endsAt then nextRound() end
        end

        sendHud()
        if S.scoreboardDirty then
            S.scoreboardDirty = false
            sendScoreboard()
        end
    end
end)

-- ---------------------------------------------------------------- Événements gf_core
AddEventHandler('gf:modeJoined', function(src, mode)
    if mode ~= 'attack' then return end
    local a, b = count('A'), count('B')
    local t = a < b and 'A' or (b < a and 'B' or (math.random(2) == 1 and 'A' or 'B'))
    setTeam(src, t)
    S.stats[src] = { kills = 0, deaths = 0 }
    core:Notify(src, ('Tu rejoins l\'%s. Tape /lobby pour quitter.'):format(Config.Teams[t].label))
    placeForPhase(src)
end)

AddEventHandler('gf:modeLeft', function(src, mode)
    if mode ~= 'attack' or not S.team[src] then return end
    S.team[src], S.alive[src], S.stats[src] = nil, nil, nil
    if GetPlayerName(src) then
        Player(src).state:set('gf_team', nil, true)
        TriggerClientEvent('gf_attack:clear', src)
    end
    S.scoreboardDirty = true

    if next(S.team) == nil and S.phase ~= 'waiting' then
        local zi = S.zoneIndex
        resetState()
        S.zoneIndex = zi
        return
    end
    checkWin()
end)

AddEventHandler('gf:playerKilled', function(victim, killer, weapon, mode)
    if mode ~= 'attack' or not S.team[victim] then return end

    local vs = S.stats[victim]
    if vs then vs.deaths = vs.deaths + 1 end
    if killer and S.team[killer] and S.team[killer] ~= S.team[victim] and S.stats[killer] then
        S.stats[killer].kills = S.stats[killer].kills + 1
    end
    S.scoreboardDirty = true

    if S.phase == 'live' and S.alive[victim] then
        S.alive[victim] = false
        announce(victim, 'Éliminé', 'Tu regardes la fin de la manche', 3000)
        SetTimeout(3000, function()
            if S.team[victim] and not S.alive[victim] then toSpectator(victim) end
        end)
        checkWin()
    else
        -- Mort hors combat (chute, etc.) : on le replace
        SetTimeout(2000, function()
            if S.team[victim] then placeForPhase(victim) end
        end)
    end
end)

-- Si gf_core redémarre, ses joueurs repartent au lobby : on repart de zéro
AddEventHandler('onResourceStop', function(res)
    if res == 'gf_core' then
        local zi = S.zoneIndex
        resetState()
        S.zoneIndex = zi
    end
end)

-- Si gf_attack (re)démarre alors que des joueurs étaient dans le mode, on les renvoie au lobby
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if Player(src).state.gf_mode == 'attack' then core:SetMode(src, 'lobby') end
    end
end)

-- ---------------------------------------------------------------- Commandes admin
local function reply(src, msg)
    if src == 0 then print('[gf_attack] ' .. msg) else core:Notify(src, msg) end
end

-- /startround : force le lancement (fonctionne même seul, pour tester)
RegisterCommand('startround', function(src)
    if not core:IsAdmin(src) then return end
    if next(S.team) == nil then return reply(src, 'Aucun joueur dans le mode Attaque.') end
    if S.phase == 'waiting' or S.phase == 'ended' then
        if S.phase == 'ended' and S.matchOver then nextRound() return end
        startPrep()
    else
        reply(src, 'Une manche est déjà en cours.')
    end
end, false)

-- /endmatch : arrête le match et remet les scores à zéro
RegisterCommand('endmatch', function(src)
    if not core:IsAdmin(src) then return end
    S.score = { A = 0, B = 0 }
    S.round = 0
    S.matchOver = false
    S.attackers = 'A'
    goWaiting()
    announceAll('Match arrêté', 'Par un administrateur', 4000)
end, false)

-- /nextzone : passe à la zone suivante (en attente uniquement)
RegisterCommand('nextzone', function(src)
    if not core:IsAdmin(src) then return end
    if S.phase ~= 'waiting' then return reply(src, 'Utilise /endmatch avant de changer de zone.') end
    S.zoneIndex = S.zoneIndex % #Config.Zones + 1
    goWaiting()
    reply(src, 'Zone : ' .. zone().name)
end, false)

-- /setteam [id] [A|B]
RegisterCommand('setteam', function(src, args)
    if not core:IsAdmin(src) then return end
    local target, t = tonumber(args[1]), (args[2] or ''):upper()
    if not target or not S.team[target] or (t ~= 'A' and t ~= 'B') then
        return reply(src, 'Utilisation : /setteam [id] [A|B] (le joueur doit être dans le mode Attaque)')
    end
    setTeam(target, t)
    placeForPhase(target)
    checkWin()
end, false)
