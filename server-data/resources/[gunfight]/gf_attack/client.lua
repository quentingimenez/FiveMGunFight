-- =============================================================================
--  gf_attack - CLIENT
--   - zone toujours en ROUGE : murs en jeu + forme exacte sur la carte
--   - zone fermée aux attaquants pendant le choix des armes et le placement
--   - dégâts pour les défenseurs qui sortent de la zone pendant le combat
--   - spectateur sur ses alliés après la mort (clic gauche / clic droit)
-- =============================================================================

local zone = nil
local blips = {}

local RED = { 255, 40, 40 }   -- couleur de la zone (en jeu)
local BLIP_RED = 1            -- couleur de la zone (carte)

-- Le point (x, y) est-il à l'intérieur du contour ?
local function insideZone(x, y)
    local poly = zone and zone.points
    if not poly or #poly < 3 then return true end
    local inside = false
    local j = #poly
    for i = 1, #poly do
        local a, b = poly[i], poly[j]
        if ((a.y > y) ~= (b.y > y)) and (x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- ---------------------------------------------------------------- Carte
local function removeBlips()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
end

-- Distance entre le point (px, py) et le segment [a, b]
local function segDist(px, py, a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    local l = dx * dx + dy * dy
    local t = l > 0 and ((px - a.x) * dx + (py - a.y) * dy) / l or 0
    t = math.max(0, math.min(1, t))
    local x, y = a.x + dx * t - px, a.y + dy * t - py
    return math.sqrt(x * x + y * y)
end

local function edgeDist(pts, x, y)
    local m = math.huge
    for i = 1, #pts do m = math.min(m, segDist(x, y, pts[i], pts[i % #pts + 1])) end
    return m
end

-- GTA ne sait pas afficher un polygone sur la carte. Les rectangles (blips de
-- zone) restent alignés avec l'écran quand la minicarte tourne : la forme se
-- déforme et laisse des trous. Les CERCLES, eux, ne changent pas en tournant :
-- on remplit donc la zone avec des cercles qui ne débordent jamais du contour
-- (grille en nid d'abeille + cercles plus petits le long des bords), puis on
-- trace le contour avec de petits cercles opaques.
local function createBlips()
    removeBlips()
    if not zone then return end
    local c = zone.center
    local pts = zone.points

    local function circle(x, y, r, alpha)
        local b = AddBlipForRadius(x, y, c.z, r)
        SetBlipColour(b, BLIP_RED)
        SetBlipAlpha(b, alpha)
        blips[#blips + 1] = b
    end

    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(pts) do
        minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
        minY, maxY = math.min(minY, p.y), math.max(maxY, p.y)
    end
    local d = math.max(8.0, math.max(maxX - minX, maxY - minY) / 14.0)
    local r = d * 0.62
    local fill = {}

    local function covered(x, y)
        for _, f in ipairs(fill) do
            if (f[1] - x) ^ 2 + (f[2] - y) ^ 2 <= f[3] * f[3] then return true end
        end
        return false
    end

    -- 1) Grille en nid d'abeille (cercles entièrement dans la zone)
    local j, y = 0, minY
    while y <= maxY do
        local x = minX + (j % 2) * d / 2
        while x <= maxX do
            if insideZone(x, y) and edgeDist(pts, x, y) >= r then fill[#fill + 1] = { x, y, r } end
            x = x + d
        end
        j, y = j + 1, y + d * 0.866
    end

    -- 2) Le long des bords : cercles de plus en plus petits pour boucher les trous
    local area2 = 0.0
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        area2 = area2 + a.x * b.y - b.x * a.y
    end
    local sgn = area2 > 0 and 1 or -1   -- sens du contour -> côté intérieur
    for _, rr in ipairs({ r, r / 2, r / 4 }) do
        for i = 1, #pts do
            local a, b = pts[i], pts[i % #pts + 1]
            local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
            if len > 0.01 then
                local nx, ny = -(b.y - a.y) / len * sgn, (b.x - a.x) / len * sgn
                local n = math.ceil(len / (rr * 0.8))
                for k = 0, n do
                    local t = k / n
                    local px, py = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
                    local cx, cy = px + nx * rr, py + ny * rr
                    if insideZone(cx, cy) and edgeDist(pts, cx, cy) >= rr * 0.97
                        and not covered(px + nx * rr * 0.25, py + ny * rr * 0.25) then
                        fill[#fill + 1] = { cx, cy, rr }
                    end
                end
            end
        end
    end
    for _, f in ipairs(fill) do circle(f[1], f[2], f[3], Config.MapFillAlpha) end

    -- 3) Contour : petits cercles opaques
    local ro = math.max(2.0, d / 5.0)
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        local n = math.max(1, math.ceil(len / (ro * 1.4)))
        for k = 0, n - 1 do
            local t = k / n
            circle(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, ro, 255)
        end
    end

    -- 3) Icône au centre (+ GPS pour les attaquants)
    local defending = LocalPlayer.state.gf_team == zone.defenders
    local pin = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(pin, 84)
    SetBlipColour(pin, BLIP_RED)
    SetBlipRoute(pin, not defending)
    SetBlipRouteColour(pin, BLIP_RED)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName((defending and 'À défendre : ' or 'À attaquer : ') .. zone.name)
    EndTextCommandSetBlipName(pin)
    blips[#blips + 1] = pin
end

-- ---------------------------------------------------------------- Affichage en jeu
local function drawText(text, y, r, g, b)
    SetTextFont(4)
    SetTextScale(0.55, 0.55)
    SetTextColour(r or 255, g or 80, b or 80, 255)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, y or 0.78)
end

-- Mur vertical translucide entre deux points du contour (visible des deux côtés)
local function drawWall(a, b, alpha)
    local r, g, bl = RED[1], RED[2], RED[3]
    local z1 = math.min(a.z, b.z) - 5.0
    local z2 = math.max(a.z, b.z) + 25.0
    DrawPoly(a.x, a.y, z1, b.x, b.y, z1, b.x, b.y, z2, r, g, bl, alpha)
    DrawPoly(b.x, b.y, z2, a.x, a.y, z2, a.x, a.y, z1, r, g, bl, alpha)
    DrawPoly(b.x, b.y, z2, b.x, b.y, z1, a.x, a.y, z1, r, g, bl, alpha)
    DrawPoly(a.x, a.y, z1, a.x, a.y, z2, b.x, b.y, z2, r, g, bl, alpha)
end

-- ---------------------------------------------------------------- Spectateur (alliés)
local spec = { enabled = false, watching = false, target = nil }

local function aliveAllies()
    local list = {}
    local myTeam = LocalPlayer.state.gf_team
    if not myTeam then return list end
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local sid = GetPlayerServerId(pid)
            local st = Player(sid).state
            if st.gf_team == myTeam and st.gf_alive then list[#list + 1] = sid end
        end
    end
    table.sort(list)
    return list
end

local function stopSpectate()
    if spec.watching then NetworkSetInSpectatorMode(false, PlayerPedId()) end
    spec.enabled, spec.watching, spec.target = false, false, nil
end

RegisterNetEvent('gf_attack:spectate', function(on)
    if on then spec.enabled = true else stopSpectate() end
end)

-- Toute réapparition normale (nouvelle manche...) arrête le mode spectateur
AddEventHandler('gf_core:spawned', function(info)
    if not (info and info.spectator) then stopSpectate() end
end)

local function spectateFrame()
    local list = aliveAllies()
    if #list == 0 then
        if spec.watching then
            NetworkSetInSpectatorMode(false, PlayerPedId())
            spec.watching, spec.target = false, nil
        end
        drawText('Aucun allié en vie', 0.88, 255, 255, 255)
        return
    end

    local idx = 1
    for i, sid in ipairs(list) do if sid == spec.target then idx = i end end

    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    if IsDisabledControlJustPressed(0, 24) then idx = idx - 1 end   -- clic gauche : précédent
    if IsDisabledControlJustPressed(0, 25) then idx = idx + 1 end   -- clic droit : suivant
    if idx < 1 then idx = #list elseif idx > #list then idx = 1 end

    local target = list[idx]
    local pid = GetPlayerFromServerId(target)
    if pid == -1 then return end
    if target ~= spec.target or not spec.watching then
        NetworkSetInSpectatorMode(true, GetPlayerPed(pid))
        spec.target, spec.watching = target, true
    end
    drawText(('Spectateur : %s  (%d/%d)'):format(GetPlayerName(pid), idx, #list), 0.86, 255, 255, 255)
    drawText('Clic gauche / clic droit : changer de joueur', 0.89, 200, 200, 200)
end

-- ---------------------------------------------------------------- Événements
local function clear()
    zone = nil
    removeBlips()
    stopSpectate()
end

RegisterNetEvent('gf_attack:zone', function(z)
    local changed = not zone or zone.name ~= z.name or zone.defenders ~= z.defenders
    zone = z
    if changed then createBlips() end
end)

RegisterNetEvent('gf_attack:clear', clear)

RegisterNetEvent('gf_core:modeChanged', function(mode)
    if mode ~= 'attack' then clear() end
end)

-- L'équipe peut changer (/setteam, équilibrage) : on rafraîchit la carte
AddStateBagChangeHandler('gf_team', ('player:%d'):format(GetPlayerServerId(PlayerId())), function()
    SetTimeout(100, createBlips)
end)

-- Dégâts hors zone (défenseurs uniquement, pendant le combat)
CreateThread(function()
    while true do
        Wait(1000)
        if zone and zone.phase == 'live' and LocalPlayer.state.gf_team == zone.defenders
            and not LocalPlayer.state.gf_protected then
            local ped = PlayerPedId()
            if not IsEntityDead(ped) then
                local p = GetEntityCoords(ped)
                if not insideZone(p.x, p.y) then
                    ApplyDamageToPed(ped, zone.damage or 8, false)
                end
            end
        end
    end
end)

-- Boucle d'affichage (chaque image)
local lastOutside = nil   -- dernière position hors zone (attaquants, placement)

CreateThread(function()
    while true do
        if not zone then
            Wait(500)
        else
            local myTeam = LocalPlayer.state.gf_team
            local ped = PlayerPedId()
            local me = GetEntityCoords(ped)
            local attacking = myTeam and myTeam ~= zone.defenders

            -- Murs rouges (segments proches seulement, pour les performances)
            local pts = zone.points
            for i = 1, #pts do
                local a, c = pts[i], pts[i % #pts + 1]
                local mx, my = (a.x + c.x) / 2, (a.y + c.y) / 2
                if (me.x - mx) ^ 2 + (me.y - my) ^ 2 < 350.0 ^ 2 then
                    drawWall(a, c, 70)
                end
            end

            -- Zone fermée aux attaquants avant le combat
            if attacking and (zone.phase == 'select' or zone.phase == 'place') and not spec.enabled then
                local veh = GetVehiclePedIsIn(ped, false)
                local ent = veh ~= 0 and veh or ped
                local pos = GetEntityCoords(ent)
                if insideZone(pos.x, pos.y) then
                    if lastOutside then
                        SetEntityCoordsNoOffset(ent, lastOutside.x, lastOutside.y, lastOutside.z, false, false, false)
                        SetEntityVelocity(ent, 0.0, 0.0, 0.0)
                    end
                    drawText('ZONE FERMÉE : attends la fin du placement !')
                else
                    lastOutside = pos
                    if zone.phase == 'place' then
                        drawText('Placement : la zone ouvre bientôt', 0.84, 255, 255, 255)
                    end
                end
            else
                lastOutside = nil
            end

            -- Avertissement pour les défenseurs hors zone (combat)
            if zone.phase == 'live' and myTeam == zone.defenders and not spec.enabled
                and not insideZone(me.x, me.y) then
                drawText('RETOURNE DANS LA ZONE !')
            end

            -- Flèche au-dessus des coéquipiers
            if myTeam and not spec.enabled then
                for _, pid in ipairs(GetActivePlayers()) do
                    if pid ~= PlayerId() then
                        local st = Player(GetPlayerServerId(pid)).state
                        if st.gf_team == myTeam then
                            local p2 = GetPlayerPed(pid)
                            if IsEntityVisible(p2) and not IsEntityDead(p2) then
                                local pos = GetEntityCoords(p2)
                                DrawMarker(2, pos.x, pos.y, pos.z + 1.25, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                                    0.25, 0.25, 0.25, 80, 200, 255, 200, false, true, 2, false, nil, nil, false)
                            end
                        end
                    end
                end
            end

            if spec.enabled then spectateFrame() end
            Wait(0)
        end
    end
end)

-- =============================================================================
--  Soins : bandage (touche 3) et kevlar (touche 4)
--  Le serveur tient le nombre d'objets ; le client joue l'animation (on peut
--  marcher, pas tirer) puis applique le soin à la fin.
-- =============================================================================
local items = nil          -- { bandage = n, kevlar = n } ou nil hors du mode
local using = nil          -- { item, endsAt, total } pendant une utilisation
local gainedUntil = 0      -- affichage « +1 kevlar »
local message = nil        -- { text, untilT } petit message d'information

local function info(text)
    message = { text = text, untilT = GetGameTimer() + 1800 }
end

RegisterNetEvent('gf_attack:items', function(inv)
    if inv and items and (inv.kevlar or 0) > (items.kevlar or 0) and not using then
        gainedUntil = GetGameTimer() + 2000
    end
    items = inv
end)

local function tryUse(item)
    if not items or LocalPlayer.state.gf_mode ~= 'attack' or using then return end
    local def = Config.Items[item]
    local ped = PlayerPedId()
    if IsEntityDead(ped) or not LocalPlayer.state.gf_alive then return end
    if zone and zone.phase == 'select' then return end
    if IsPedInAnyVehicle(ped, false) then return info('Descends du véhicule pour te soigner') end
    if (items[item] or 0) <= 0 then return info(('Plus de %s'):format(def.label:lower())) end
    if def.stat == 'health' and GetEntityHealth(ped) >= GetEntityMaxHealth(ped) then
        return info('Vie déjà au maximum')
    end
    if def.stat == 'armour' and GetPedArmour(ped) >= 100 then
        return info('Kevlar déjà au maximum')
    end
    TriggerServerEvent('gf_attack:useItem', item)
end

for item, def in pairs(Config.Items) do
    RegisterCommand('+gf_' .. item, function() tryUse(item) end, false)
    RegisterCommand('-gf_' .. item, function() end, false)
    RegisterKeyMapping('+gf_' .. item, ('Gunfight : %s'):format(def.label:lower()), 'keyboard', def.key)
end

-- Le serveur a validé : animation puis soin
RegisterNetEvent('gf_attack:applyItem', function(item)
    local def = Config.Items[item]
    if not def or using then return end
    CreateThread(function()
        local ped = PlayerPedId()
        using = { item = item, endsAt = GetGameTimer() + def.duration * 1000, total = def.duration * 1000 }

        RequestAnimDict(def.anim.dict)
        local t = GetGameTimer() + 2000
        while not HasAnimDictLoaded(def.anim.dict) and GetGameTimer() < t do Wait(0) end
        -- 49 = haut du corps seulement + en boucle + on peut se déplacer
        TaskPlayAnim(ped, def.anim.dict, def.anim.name, 8.0, -8.0, -1, 49, 0, false, false, false)

        local ok = true
        while using and GetGameTimer() < using.endsAt do
            ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then ok = false break end
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 24, true)   -- tirer
            DisableControlAction(0, 25, true)   -- viser
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            Wait(0)
        end

        StopAnimTask(ped, def.anim.dict, def.anim.name, 2.0)
        RemoveAnimDict(def.anim.dict)
        if ok and using and not IsEntityDead(ped) then
            if def.stat == 'health' then
                SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + def.amount))
            else
                SetPedArmour(ped, math.min(100, GetPedArmour(ped) + def.amount))
            end
        end
        using = nil
    end)
end)

AddEventHandler('gf_core:spawned', function() using = nil end)

local function text(str, x, y, scale, r, g, b, align)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, 255)
    SetTextOutline()
    if align == 'right' then
        SetTextRightJustify(true)
        SetTextWrap(0.0, x)
    else
        SetTextCentre(true)
    end
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(str)
    EndTextCommandDisplayText(x, y)
end

-- Affichage : objets restants (bas droite), barre de progression, messages
CreateThread(function()
    while true do
        if not items or LocalPlayer.state.gf_mode ~= 'attack' or not LocalPlayer.state.gf_alive then
            Wait(300)
        else
            if not IsEntityDead(PlayerPedId()) then
                local b, k = items.bandage or 0, items.kevlar or 0
                text(('[%s] Bandage x%d'):format(Config.Items.bandage.key, b), 0.985, 0.86, 0.45,
                    b > 0 and 255 or 130, b > 0 and 255 or 130, b > 0 and 255 or 130, 'right')
                text(('[%s] Kevlar x%d'):format(Config.Items.kevlar.key, k), 0.985, 0.89, 0.45,
                    k > 0 and 120 or 130, k > 0 and 190 or 130, 255, 'right')
                if GetGameTimer() < gainedUntil then
                    text('+1 kevlar', 0.985, 0.83, 0.45, 120, 220, 120, 'right')
                end
            end

            if using then
                local left = math.max(0, using.endsAt - GetGameTimer())
                local p = 1.0 - left / using.total
                DrawRect(0.5, 0.80, 0.16, 0.012, 0, 0, 0, 160)
                DrawRect(0.5 - 0.08 + 0.08 * p, 0.80, 0.16 * p, 0.012, 120, 220, 120, 230)
                text(('%s… %.1f s'):format(Config.Items[using.item].label, left / 1000), 0.5, 0.765, 0.42, 255, 255, 255)
            end

            if message and GetGameTimer() < message.untilT then
                text(message.text, 0.5, 0.74, 0.45, 255, 200, 80)
            end
            Wait(0)
        end
    end
end)
