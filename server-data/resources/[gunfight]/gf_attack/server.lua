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
-- Dernier choix d'armes de chaque joueur (gardé d'une manche à l'autre)
S.choice = {}

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

-- Cap (heading GTA) pour regarder du point (x,y) vers (tx,ty)
local function headingTo(x, y, tx, ty)
    return (math.deg(math.atan(-(tx - x), ty - y)) + 360.0) % 360.0
end

-- ---------------------------------------------------------------- Maps
-- Une map = { name, points{ {x,y,z} }, attackSpawn{x,y,z,h}, defenseSpawn{x,y,z,h} }
-- On y ajoute center (centre) et radius (rayon englobant) pour l'affichage.
local function finalizeMap(m)
    local x, y, z = 0.0, 0.0, 0.0
    for _, p in ipairs(m.points) do x, y, z = x + p.x, y + p.y, z + p.z end
    local n = #m.points
    local c = { x = x / n, y = y / n, z = z / n }
    local r = 0.0
    for _, p in ipairs(m.points) do
        local d = math.sqrt((p.x - c.x) ^ 2 + (p.y - c.y) ^ 2)
        if d > r then r = d end
    end
    m.center, m.radius = c, r
    return m
end

-- Zone de secours (config.lua, cercle) -> polygone à 16 côtés
local function fallbackMap(z)
    local c = z.center
    local points = {}
    for i = 0, 15 do
        local a = i / 16 * 2 * math.pi
        points[#points + 1] = { x = c.x + math.cos(a) * z.radius, y = c.y + math.sin(a) * z.radius, z = c.z }
    end
    local rad = math.rad(z.attackFrom or 0)
    local d = z.radius + Config.AttackSpawnDistance
    local ax, ay = c.x + math.sin(rad) * d, c.y + math.cos(rad) * d
    return {
        name = z.name,
        points = points,
        attackSpawn = { x = ax, y = ay, z = c.z, h = headingTo(ax, ay, c.x, c.y) },
        defenseSpawn = { x = c.x, y = c.y, z = c.z, h = 0.0 },
    }
end

local function mapList()
    local ok, maps = pcall(function() return exports.gf_maps:GetActiveMaps('attack') end)
    if ok and type(maps) == 'table' and #maps > 0 then return maps end
    local list = {}
    for _, z in ipairs(Config.Zones) do list[#list + 1] = fallbackMap(z) end
    return list
end

local currentMap = nil
local function loadMap(index)
    local list = mapList()
    S.zoneIndex = ((index - 1) % #list) + 1
    currentMap = finalizeMap(list[S.zoneIndex])
end

loadMap(S.zoneIndex)

local function zone() return currentMap end
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

-- En vie / mort : partagé avec les clients (state bag) pour le mode spectateur
local function setAlive(src, alive)
    S.alive[src] = alive
    if GetPlayerName(src) then Player(src).state:set('gf_alive', alive and true or false, true) end
end

-- Rang du joueur dans son équipe (1, 2, 3...) pour ranger les voitures
local function slotOf(src)
    local t, list = S.team[src], {}
    for s, tm in pairs(S.team) do if tm == t then list[#list + 1] = s end end
    table.sort(list)
    for i, s in ipairs(list) do if s == src then return i end end
    return 1
end

-- Position d'apparition : les voitures sont rangées en rangées de 4 derrière
-- le point de départ de l'équipe, toutes tournées vers la zone.
local function spawnPos(src)
    local z = zone()
    local sp = roleOf(S.team[src]) == 'defense' and z.defenseSpawn or z.attackSpawn
    local h = math.rad(headingTo(sp.x, sp.y, z.center.x, z.center.y))
    local fx, fy = -math.sin(h), math.cos(h)   -- vers l'avant (la zone)
    local rx, ry = math.cos(h), math.sin(h)    -- vers le côté

    local i = slotOf(src) - 1
    local col, row = i % 4, math.floor(i / 4)
    local side = (col - 1.5) * Config.VehicleSpacing
    local back = row * Config.VehicleSpacing * 1.6
    local x = sp.x + rx * side - fx * back
    local y = sp.y + ry * side - fy * back
    return x, y, sp.z, math.deg(h) % 360.0
end

-- opts : vehicle (bool), freeze, protected, weapons (bool : armes choisies)
local function spawnRole(src, opts)
    local x, y, z, h = spawnPos(src)
    local weapons = nil
    if opts.weapons then
        weapons = core:BuildWeaponList(core:ResolveSelection(src, S.choice[src]))
    end
    core:Spawn(src, {
        x = x, y = y, z = z, heading = h,
        vehicle = opts.vehicle and Config.Vehicle or nil,
        weapons = weapons, armour = weapons and core:GetSelectionSettings().armour or nil,
        freeze = opts.freeze, protected = opts.protected,
    })
end

local function toSpectator(src)
    if not S.team[src] then return end
    local c = zone().center
    -- keepVehicle : la voiture du joueur mort reste dans la manche
    core:Spawn(src, { x = c.x, y = c.y, z = c.z + 45.0, heading = 0.0, spectator = true, keepVehicle = true })
    TriggerClientEvent('gf_attack:spectate', src, true)
end

-- Menu de choix des 2 armes (pendant la phase de choix)
local function openLoadout(src)
    local remaining = math.max(S.endsAt - now(), 1)
    local settings = core:GetSelectionSettings()
    TriggerClientEvent('gf_ui:loadout_open', src, {
        title = 'Choisis tes 2 armes',
        weapons = core:GetOwnedWeapons(src),
        selected = core:ResolveSelection(src, S.choice[src]),
        count = settings.count,
        seconds = remaining,
    })
end

local function sendZone(src)
    local z = zone()
    TriggerClientEvent('gf_attack:zone', src, {
        name = z.name,
        points = z.points,
        center = z.center,
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
    if S.phase == 'select' then
        setAlive(src, true)
        spawnRole(src, { vehicle = true, freeze = true, protected = true })
        openLoadout(src)
    elseif S.phase == 'place' then
        setAlive(src, true)
        spawnRole(src, { vehicle = true, weapons = true, protected = true })
    elseif S.phase == 'live' then
        setAlive(src, false)
        toSpectator(src)
        announce(src, 'Manche en cours', 'Tu joueras dès la prochaine manche', 4000)
    else
        setAlive(src, false)
        spawnRole(src, { protected = true })
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
-- 1) Choix des armes : tout le monde dans sa voiture, gelé, menu ouvert
local function startSelect()
    -- Début de match : on recharge la map (prend en compte les modifications de /editor)
    if S.round == 0 then loadMap(S.zoneIndex) end
    autobalance()
    S.round = S.round + 1
    S.phase = 'select'
    S.endsAt = now() + Config.SelectTime
    S.solo = count('A') == 0 or count('B') == 0

    eachPlayer(function(src)
        setAlive(src, true)
        spawnRole(src, { vehicle = true, freeze = true, protected = true })
        openLoadout(src)
        local role = roleOf(S.team[src])
        announce(src, ('Manche %d'):format(S.round),
            role == 'attack' and ('Tu ATTAQUES : ' .. zone().name) or ('Tu DÉFENDS : ' .. zone().name), 4000)
    end)
    if S.solo then
        announceAll(('Manche %d (test)'):format(S.round), 'Une équipe est vide : la manche se termine au chrono', 5000)
    end
    sendZoneAll()
    S.scoreboardDirty = true
end

-- 2) Placement : on peut rouler, les défenseurs s'installent,
--    les attaquants ne peuvent pas encore entrer dans la zone
local function startPlacement()
    S.phase = 'place'
    S.endsAt = now() + Config.PlacementTime
    eachPlayer(function(src)
        TriggerClientEvent('gf_ui:loadout_close', src)
        if S.alive[src] then
            core:GiveWeapons(src, core:ResolveSelection(src, S.choice[src]))
            core:Freeze(src, false)
            local attack = roleOf(S.team[src]) == 'attack'
            announce(src, 'Placement',
                attack and ('Zone fermée pendant %d s : prépare ton attaque'):format(Config.PlacementTime)
                    or ('%d s pour te placer dans la zone'):format(Config.PlacementTime), 3000)
        end
    end)
    sendZoneAll()
end

-- 3) Combat : les attaquants peuvent entrer, pas de réapparition
local function startLive()
    S.phase = 'live'
    S.endsAt = now() + Config.RoundTime
    eachPlayer(function(src)
        if S.alive[src] then core:SetProtected(src, false) end
    end)
    announceAll('GO !', 'La zone est ouverte : à l\'attaque !', 2500)
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
        setAlive(src, false)
        spawnRole(src, { protected = true })
    end)
    sendZoneAll()
end

local function nextRound()
    if S.matchOver then
        S.score = { A = 0, B = 0 }
        S.round = 0
        S.attackers = 'A'
        S.matchOver = false
        loadMap(S.zoneIndex + 1)
        for src in pairs(S.stats) do S.stats[src] = { kills = 0, deaths = 0 } end
    elseif Config.SwapSidesEveryRound then
        S.attackers = other(S.attackers)
    end

    if canStart() then startSelect() else goWaiting() end
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
    return ({ waiting = 'En attente de joueurs', select = 'Choix des armes', place = 'Placement', live = 'Combat', ended = 'Fin de manche' })[S.phase]
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
            if canStart() then startSelect() end
        elseif S.phase == 'select' then
            if t >= S.endsAt then startPlacement() end
        elseif S.phase == 'place' then
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
-- Le menu d'armes (gf_ui) envoie le choix ; gf_core le valide (armes possédées)
RegisterNetEvent('gf:loadoutChosen', function(ids)
    local src = source
    if not S.team[src] or S.phase ~= 'select' then return end
    S.choice[src] = core:ResolveSelection(src, ids)
end)

AddEventHandler('playerDropped', function()
    S.choice[source] = nil
end)

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
        Player(src).state:set('gf_alive', nil, true)
        TriggerClientEvent('gf_ui:loadout_close', src)
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
        setAlive(victim, false)
        announce(victim, 'Éliminé', 'Tu regardes tes alliés (clic gauche / droit pour changer)', 3000)
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
        startSelect()
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
    loadMap(S.zoneIndex + 1)
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

-- Une map a été créée / modifiée / supprimée avec /editor
AddEventHandler('gf_maps:updated', function(kind)
    if kind ~= 'attack' then return end
    if S.phase == 'waiting' then
        loadMap(S.zoneIndex)
        goWaiting()
    end
end)
