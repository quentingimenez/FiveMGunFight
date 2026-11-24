-- =============================================================================
--  gf_redzone - SERVEUR
-- =============================================================================

local core = exports.gf_core

local S = {
    players = {},   -- [src] = { kills, deaths, streak, best, spawnId }
    zoneIndex = 1,
    rotateAt = os.time() + Config.RotationMinutes * 60,
    dirty = true,
}

local function now() return os.time() end
local function zone() return Config.Zones[S.zoneIndex] end

local function eachPlayer(fn)
    for src in pairs(S.players) do fn(src) end
end

local function announce(src, title, sub, ms)
    TriggerClientEvent('gf_ui:announce', src, { title = title, subtitle = sub, duration = ms or 3000 })
end

local function headingTo(x, y, tx, ty)
    return (math.deg(math.atan(-(tx - x), ty - y)) + 360.0) % 360.0
end

local function sendZones(src)
    local list = {}
    for i, z in ipairs(Config.Zones) do
        list[i] = { name = z.name, x = z.center.x, y = z.center.y, z = z.center.z, radius = z.radius }
    end
    TriggerClientEvent('gf_redzone:zones', src, { zones = list, active = S.zoneIndex, damage = Config.OutOfZoneDamage })
end

local function spawnInZone(src)
    local p = S.players[src]
    if not p then return end
    local z = zone()
    local a = math.random() * 2 * math.pi
    local d = z.radius * (0.3 + math.random() * 0.6)
    local x, y = z.center.x + math.cos(a) * d, z.center.y + math.sin(a) * d

    p.spawnId = p.spawnId + 1
    local myId = p.spawnId
    core:Spawn(src, {
        x = x, y = y, z = z.center.z, heading = headingTo(x, y, z.center.x, z.center.y),
        loadout = 'redzone', protected = true,
    })
    SetTimeout(Config.SpawnProtection * 1000 + 1000, function()
        local cur = S.players[src]
        if cur and cur.spawnId == myId then core:SetProtected(src, false) end
    end)
end

local function insideZone(src, margin)
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    local p, c = GetEntityCoords(ped), zone().center
    return #(vector2(p.x, p.y) - vector2(c.x, c.y)) <= zone().radius + (margin or 0.0)
end

local function kd(p)
    return p.deaths > 0 and (math.floor(p.kills / p.deaths * 100 + 0.5) / 100) or p.kills
end

-- ---------------------------------------------------------------- HUD & classement
local function sendHud()
    local remaining = #Config.Zones > 1 and math.max(S.rotateAt - now(), 0) or nil
    eachPlayer(function(src)
        local p = S.players[src]
        TriggerClientEvent('gf_ui:hud', src, {
            title = 'Redzone · ' .. zone().name,
            subtitle = remaining and 'Prochaine zone dans' or 'Chacun pour soi',
            timer = remaining,
            badge = { text = 'CHACUN POUR SOI', color = '#ff3b3b' },
            left = { label = 'Kills', value = p.kills, sub = ('Série : %d'):format(p.streak), color = '#ff5a5f' },
            right = { label = 'Morts', value = p.deaths, sub = ('K/D : %s'):format(kd(p)), color = '#cfd6e4' },
        })
    end)
end

local function sendScoreboard()
    local rows = {}
    for src, p in pairs(S.players) do
        rows[#rows + 1] = { cells = { GetPlayerName(src) or '?', p.kills, p.deaths, kd(p), p.best } }
    end
    table.sort(rows, function(a, b) return a.cells[2] > b.cells[2] end)
    for i, r in ipairs(rows) do table.insert(r.cells, 1, '#' .. i) end
    local data = {
        title = 'Redzone · Classement',
        columns = { 'Rang', 'Joueur', 'Kills', 'Morts', 'K/D', 'Meilleure série' },
        rows = rows,
    }
    eachPlayer(function(src) TriggerClientEvent('gf_ui:scoreboard', src, data) end)
end

local function rotate()
    S.zoneIndex = S.zoneIndex % #Config.Zones + 1
    S.rotateAt = now() + Config.RotationMinutes * 60
    eachPlayer(function(src)
        sendZones(src)
        announce(src, 'Nouvelle zone', zone().name, 4000)
        spawnInZone(src)
    end)
end

CreateThread(function()
    while true do
        Wait(1000)
        if #Config.Zones > 1 and now() >= S.rotateAt then rotate() end
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
    S.players[src] = { kills = 0, deaths = 0, streak = 0, best = 0, spawnId = 0 }
    S.dirty = true
    sendZones(src)
    spawnInZone(src)
    announce(src, 'Redzone', zone().name .. ' · chacun pour soi', 3000)
    core:Notify(src, 'Bienvenue en Redzone ! Seuls les kills DANS la zone comptent. /lobby pour quitter.')
end)

AddEventHandler('gf:modeLeft', function(src, mode)
    if mode ~= 'redzone' or not S.players[src] then return end
    S.players[src] = nil
    S.dirty = true
    if GetPlayerName(src) then TriggerClientEvent('gf_redzone:clear', src) end
end)

AddEventHandler('gf:playerKilled', function(victim, killer, weapon, mode)
    if mode ~= 'redzone' then return end
    local v = S.players[victim]
    if not v then return end

    v.deaths = v.deaths + 1
    v.streak = 0

    local k = killer and S.players[killer]
    if k and insideZone(killer, Config.KillZoneMargin) then
        k.kills = k.kills + 1
        k.streak = k.streak + 1
        if k.streak > k.best then k.best = k.streak end
        if Config.HealOnKill then TriggerClientEvent('gf_redzone:heal', killer) end
        for _, n in ipairs(Config.StreakAnnounces) do
            if k.streak == n then
                eachPlayer(function(src)
                    announce(src, ('%s : %d kills d\'affilée !'):format(GetPlayerName(killer), n), nil, 3000)
                end)
            end
        end
    end
    S.dirty = true

    SetTimeout(Config.RespawnDelay * 1000, function()
        if S.players[victim] then spawnInZone(victim) end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == 'gf_core' then S.players = {} end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if Player(src).state.gf_mode == 'redzone' then core:SetMode(src, 'lobby') end
    end
end)

-- ---------------------------------------------------------------- Commandes admin
RegisterCommand('rotatezone', function(src)
    if not core:IsAdmin(src) then return end
    rotate()
end, false)

RegisterCommand('resetredzone', function(src)
    if not core:IsAdmin(src) then return end
    for _, p in pairs(S.players) do
        p.kills, p.deaths, p.streak, p.best = 0, 0, 0, 0
    end
    S.dirty = true
end, false)
