-- =============================================================================
--  gf_redzone - SERVEUR
--  Phases :  idle    → personne dans le mode
--            live    → partie en cours (Config.GameDuration)
--            ended   → classement final, puis nouvelle partie sur la map suivante
-- =============================================================================

local core = exports.gf_core

local S = {
    phase = 'idle',
    players = {},    -- [src] = { kills, deaths, streak, best }
    map = nil,       -- map en cours { name, center{x,y,z}, radius, spawns{} }
    mapIndex = 0,
    endsAt = 0,
    spawnCursor = 0,
    dirty = true,
}

local function now() return os.time() end

local function eachPlayer(fn)
    for src in pairs(S.players) do fn(src) end
end

local function announce(src, title, sub, ms)
    TriggerClientEvent('gf_ui:announce', src, { title = title, subtitle = sub, duration = ms or 3000 })
end

local function headingTo(x, y, tx, ty)
    return (math.deg(math.atan(-(tx - x), ty - y)) + 360.0) % 360.0
end

-- ---------------------------------------------------------------- Maps
-- Zone de secours (config.lua) -> même format qu'une map de l'éditeur
local function fallbackMap(z)
    local c = { x = z.center.x, y = z.center.y, z = z.center.z }
    local spawns, garages = {}, {}
    for i = 0, 3 do
        local a = i * math.pi / 2
        local d = z.radius + 60.0
        local x, y = c.x + math.sin(a) * d, c.y + math.cos(a) * d
        local h = headingTo(x, y, c.x, c.y)
        spawns[#spawns + 1] = { x = x, y = y, z = c.z, h = h }
        -- point véhicule à 8 m à côté de l'apparition
        local hr = math.rad(h)
        garages[#garages + 1] = { x = x + math.cos(hr) * 8.0, y = y + math.sin(hr) * 8.0, z = c.z, h = h }
    end
    return { name = z.name, center = c, radius = z.radius, spawns = spawns, garages = garages }
end

local function mapList()
    -- Seulement les maps cochées "en jeu" dans /editor
    local ok, maps = pcall(function() return exports.gf_maps:GetActiveMaps('redzone') end)
    if ok and type(maps) == 'table' and #maps > 0 then
        for _, m in ipairs(maps) do
            -- maps créées avant l'ajout des points véhicule : on réutilise les apparitions
            if not m.garages or #m.garages == 0 then m.garages = m.spawns end
        end
        return maps
    end
    local list = {}
    for _, z in ipairs(Config.Zones) do list[#list + 1] = fallbackMap(z) end
    return list
end

local function nextMap()
    local list = mapList()
    S.mapIndex = S.mapIndex % #list + 1
    S.map = list[S.mapIndex]
end

local function sendMap(src)
    local m = S.map
    if not m then return end
    TriggerClientEvent('gf_redzone:map', src, {
        name = m.name,
        center = m.center,
        radius = m.radius,
        spawns = m.spawns,
        garages = m.garages,
        vehicle = Config.Vehicle,
    })
end

-- ---------------------------------------------------------------- Zone
local function distToZone(src)
    local ped = GetPlayerPed(src)
    if ped == 0 or not S.map then return math.huge end
    local p, c = GetEntityCoords(ped), S.map.center
    return #(vector2(p.x, p.y) - vector2(c.x, c.y)) - S.map.radius
end

local function insideZone(src, margin)
    return distToZone(src) <= (margin or 0.0)
end

-- Appelé par gf_core pour chaque tir : on ne peut toucher / être touché que dans la zone
exports('AllowDamage', function(sender, victim)
    if S.phase ~= 'live' then return false end
    -- Le véhicule ne sert qu'à rejoindre la zone : aucun dégât venant d'un
    -- joueur au volant (écrasement, percussion, tir depuis le véhicule).
    local ped = GetPlayerPed(sender)
    if ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= 0 then return false end
    return insideZone(sender, 3.0) and insideZone(victim, 3.0)
end)

-- ---------------------------------------------------------------- Apparition
local function spawnPlayer(src)
    if not S.players[src] or not S.map then return end
    local spawns = S.map.spawns
    S.spawnCursor = S.spawnCursor % #spawns + 1
    local sp = spawns[S.spawnCursor]

    -- Apparition à pied, légèrement dispersée pour ne pas s'empiler
    local x = sp.x + (math.random() * 2 - 1) * 2.5
    local y = sp.y + (math.random() * 2 - 1) * 2.5

    -- Sans choix enregistré, conserver l'équipement de départ de la Redzone.
    local equipped = core:GetEquippedWeapons(src)
    local options = {
        x = x, y = y, z = sp.z, heading = sp.h or 0.0,
        protected = S.phase ~= 'live',
    }
    if #equipped > 0 then
        options.weapons = core:BuildWeaponList(core:ResolveSelection(src, equipped))
        options.armour = core:GetSelectionSettings().armour
    else
        options.loadout = 'redzone'
    end
    core:Spawn(src, options)
end

local function kd(p)
    return p.deaths > 0 and (math.floor(p.kills / p.deaths * 100 + 0.5) / 100) or p.kills
end

local function ranking()
    local list = {}
    for src, p in pairs(S.players) do list[#list + 1] = { src = src, p = p } end
    table.sort(list, function(a, b)
        if a.p.kills ~= b.p.kills then return a.p.kills > b.p.kills end
        return a.p.deaths < b.p.deaths
    end)
    return list
end

-- ---------------------------------------------------------------- Déroulement
local function startGame()
    nextMap()
    S.phase = 'live'
    S.endsAt = now() + Config.GameDuration
    S.spawnCursor = 0
    -- Journal local : début de match et entrée en phase live (S.map est connue).
    -- Effectif présent au coup d'envoi, avant la remise à zéro des statistiques.
    local joueurs = {}
    for src in pairs(S.players) do
        joueurs[#joueurs + 1] = { src = src }
    end
    TriggerEvent('gf:matchStarted', {
        mode = 'redzone', map = S.map.name, joueurs = joueurs,
    })
    TriggerEvent('gf:phase', { mode = 'redzone', phase = 'live' })
    for src, p in pairs(S.players) do
        p.kills, p.deaths, p.streak, p.best = 0, 0, 0, 0
        sendMap(src)
        spawnPlayer(src)
        announce(src, 'Redzone', S.map.name .. ' · nouvelle partie', 4000)
    end
    S.dirty = true
end

local function endGame()
    S.phase = 'ended'
    S.endsAt = now() + Config.EndDelay
    TriggerEvent('gf:phase', { mode = 'redzone', phase = 'ended' }) -- journal local de la phase

    local r = ranking()
    local podium = {}
    for i = 1, math.min(3, #r) do
        podium[#podium + 1] = ('%d. %s (%d)'):format(i, GetPlayerName(r[i].src) or '?', r[i].p.kills)
    end
    local winner = r[1] and GetPlayerName(r[1].src) or '—'

    -- Statistiques persistantes (gf_stats) : vainqueur = premier du classement.
    local participants, topSrc = {}, r[1] and r[1].src
    for src in pairs(S.players) do
        participants[#participants + 1] = { src = src, won = src == topSrc }
    end
    TriggerEvent('gf:matchEnded', {
        mode = 'redzone',
        map = S.map and S.map.name or nil,
        participants = participants,
    })

    eachPlayer(function(src)
        core:SetProtected(src, true)
        announce(src, ('Victoire de %s !'):format(winner), table.concat(podium, '   '), 8000)
        TriggerClientEvent('gf_ui:scoreboard_show', src, Config.EndDelay * 1000)
    end)
    -- Journal local : après gf:matchEnded, dans l'ordre du classement calculé.
    local rows = {}
    for _, e in ipairs(r) do
        rows[#rows + 1] = { name = GetPlayerName(e.src) or '?', kills = e.p.kills, deaths = e.p.deaths }
    end
    TriggerEvent('gf:matchResults', { mode = 'redzone', rows = rows })
    S.dirty = true
end

local function goIdle()
    S.phase = 'idle'
    S.endsAt = 0
    S.map = nil
    TriggerEvent('gf:phase', { mode = 'redzone', phase = 'idle' }) -- journal local de la phase
end

-- ---------------------------------------------------------------- HUD & classement
local function sendHud()
    if S.phase == 'idle' then return end
    local remaining = math.max(S.endsAt - now(), 0)
    eachPlayer(function(src)
        local p = S.players[src]
        TriggerClientEvent('gf_ui:hud', src, {
            title = 'Redzone · ' .. (S.map and S.map.name or ''),
            subtitle = S.phase == 'live' and 'Fin de la partie dans' or 'Nouvelle partie dans',
            timer = remaining,
            badge = { text = 'CHACUN POUR SOI', color = '#ff3b3b' },
            left = { label = 'Kills', value = p.kills, sub = ('Série : %d'):format(p.streak), color = '#ff5a5f' },
            right = { label = 'Morts', value = p.deaths, sub = ('K/D : %s'):format(kd(p)), color = '#cfd6e4' },
        })
    end)
end

local function sendScoreboard()
    local rows = {}
    for i, e in ipairs(ranking()) do
        local p = e.p
        rows[#rows + 1] = { cells = { '#' .. i, GetPlayerName(e.src) or '?', p.kills, p.deaths, kd(p), p.best } }
    end
    local data = {
        title = 'Redzone · ' .. (S.map and S.map.name or 'Classement'),
        columns = { 'Rang', 'Joueur', 'Kills', 'Morts', 'K/D', 'Meilleure série' },
        rows = rows,
    }
    eachPlayer(function(src) TriggerClientEvent('gf_ui:scoreboard', src, data) end)
end

CreateThread(function()
    while true do
        Wait(1000)
        if S.phase == 'live' and now() >= S.endsAt then
            endGame()
        elseif S.phase == 'ended' and now() >= S.endsAt then
            if next(S.players) then startGame() else goIdle() end
        end
        sendHud()
        if S.dirty then
            S.dirty = false
            sendScoreboard()
        end
    end
end)

-- ---------------------------------------------------------------- Événements gf_core
AddEventHandler('gf:modeJoined', function(src, mode)
    if mode ~= 'redzone' then return end
    S.players[src] = { kills = 0, deaths = 0, streak = 0, best = 0 }
    S.dirty = true

    if S.phase == 'idle' then
        startGame()
        return
    end
    sendMap(src)
    spawnPlayer(src)
    announce(src, 'Redzone', (S.map and S.map.name or '') .. ' · rejoins la zone !', 3000)
    core:Notify(src, 'Prends ta voiture au point véhicule (E), roule jusqu\'à la zone rouge, F pour sortir. On ne peut tirer que DANS la zone. /lobby pour quitter.')
end)

AddEventHandler('gf:modeLeft', function(src, mode)
    if mode ~= 'redzone' or not S.players[src] then return end
    S.players[src] = nil
    S.dirty = true
    if GetPlayerName(src) then TriggerClientEvent('gf_redzone:clear', src) end
    if next(S.players) == nil then goIdle() end
end)

AddEventHandler('gf:playerKilled', function(victim, killer, weapon, mode)
    if mode ~= 'redzone' then return end
    local v = S.players[victim]
    if not v then return end

    v.deaths = v.deaths + 1
    v.streak = 0

    local k = killer and S.players[killer]
    local credited = false
    if k and S.phase == 'live' and insideZone(killer, Config.KillZoneMargin) then
        credited = true
        k.kills = k.kills + 1
        k.streak = k.streak + 1
        if k.streak > k.best then k.best = k.streak end
        if Config.HealOnKill then
            TriggerClientEvent('gf_redzone:heal', killer)
            TriggerEvent('gf:healGranted', killer)
        end
        for _, n in ipairs(Config.StreakAnnounces) do
            if k.streak == n then
                eachPlayer(function(src)
                    announce(src, ('%s : %d kills d\'affilée !'):format(GetPlayerName(killer), n), nil, 3000)
                end)
            end
        end
    end
    TriggerEvent('gf:modeKill', { mode = 'redzone', victim = victim, killer = credited and killer or false })
    S.dirty = true

    SetTimeout(Config.RespawnDelay * 1000, function()
        if S.players[victim] then spawnPlayer(victim) end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == 'gf_core' then
        S.players = {}
        goIdle()
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if core:GetMode(src) == 'redzone' then core:SetMode(src, 'lobby') end
    end
end)

-- ---------------------------------------------------------------- Commandes admin
-- /endgame : termine la partie en cours (classement puis map suivante)
RegisterCommand('endgame', function(src)
    if not core:IsAdmin(src) then return end
    if S.phase == 'live' then endGame() end
end, false)

-- /nextmap : passe directement à la map suivante
RegisterCommand('nextmap', function(src)
    if not core:IsAdmin(src) then return end
    if next(S.players) then startGame() end
end, false)
