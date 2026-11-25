-- =============================================================================
--  gf_attack - CLIENT : affichage de la zone (contour dessiné dans l'éditeur),
--  repères coéquipiers, dégâts pour les défenseurs qui sortent de la zone.
-- =============================================================================

local zone = nil
local blips = {}

local function hexToRgb(hex)
    hex = (hex or '#ffffff'):gsub('#', '')
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

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

local function removeBlips()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
end

local function createBlips()
    removeBlips()
    if not zone then return end
    local c = zone.center
    local myTeam = LocalPlayer.state.gf_team
    local defending = myTeam == zone.defenders
    local color = defending and 3 or 1 -- 3 = bleu, 1 = rouge

    -- GTA ne sait pas afficher un polygone sur la carte : on le dessine avec
    -- des rectangles (blips de zone) qui suivent exactement la forme.
    local pts = zone.points
    local function area(x, y, w, h, alpha)
        local b = AddBlipForArea(x, y, c.z, w, h)
        SetBlipColour(b, color)
        SetBlipAlpha(b, alpha)
        blips[#blips + 1] = b
    end

    -- 1) Remplissage : bandes horizontales entre les bords du polygone
    local minY, maxY = math.huge, -math.huge
    for _, p in ipairs(pts) do
        if p.y < minY then minY = p.y end
        if p.y > maxY then maxY = p.y end
    end
    local step = math.max(3.0, (maxY - minY) / 80.0)
    for y = minY + step / 2, maxY, step do
        local xs = {}
        local j = #pts
        for i = 1, #pts do
            local a, b = pts[j], pts[i]
            if (a.y > y) ~= (b.y > y) then
                xs[#xs + 1] = a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y)
            end
            j = i
        end
        table.sort(xs)
        for k = 1, #xs - 1, 2 do
            area((xs[k] + xs[k + 1]) / 2, y, xs[k + 1] - xs[k], step + 0.4, 70)
        end
    end

    -- 2) Contour : petits carrés le long de chaque bord
    local perimeter = 0.0
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        perimeter = perimeter + math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    end
    local dot = math.max(2.5, perimeter / 250.0)
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        local n = math.max(1, math.ceil(len / dot))
        for k = 0, n - 1 do
            local t = k / n
            area(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, dot * 1.4, dot * 1.4, 200)
        end
    end

    local pin = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(pin, 84)
    SetBlipColour(pin, color)
    SetBlipRoute(pin, not defending)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName((defending and 'À défendre : ' or 'À attaquer : ') .. zone.name)
    EndTextCommandSetBlipName(pin)
    blips[#blips + 1] = pin
end

local function drawText(text)
    SetTextFont(4)
    SetTextScale(0.6, 0.6)
    SetTextColour(255, 80, 80, 255)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.78)
end

-- Mur vertical translucide entre deux points du contour
local function drawWall(a, b, r, g, bl, al)
    local z1 = math.min(a.z, b.z) - 5.0
    local z2 = math.max(a.z, b.z) + 25.0
    DrawPoly(a.x, a.y, z1, b.x, b.y, z1, b.x, b.y, z2, r, g, bl, al)
    DrawPoly(b.x, b.y, z2, a.x, a.y, z2, a.x, a.y, z1, r, g, bl, al)
    DrawPoly(b.x, b.y, z2, b.x, b.y, z1, a.x, a.y, z1, r, g, bl, al)
    DrawPoly(a.x, a.y, z1, a.x, a.y, z2, b.x, b.y, z2, r, g, bl, al)
end

RegisterNetEvent('gf_attack:zone', function(z)
    zone = z
    createBlips()
end)

RegisterNetEvent('gf_attack:clear', function()
    zone = nil
    removeBlips()
end)

RegisterNetEvent('gf_core:modeChanged', function(mode)
    if mode ~= 'attack' then
        zone = nil
        removeBlips()
    end
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

-- Affichage (chaque image)
CreateThread(function()
    while true do
        if not zone then
            Wait(500)
        else
            local myTeam = LocalPlayer.state.gf_team
            local r, g, b = hexToRgb(zone.colors and zone.colors[zone.defenders])
            local me = GetEntityCoords(PlayerPedId())

            -- Murs de la zone (seulement les segments proches, pour les performances)
            local pts = zone.points
            for i = 1, #pts do
                local a, c = pts[i], pts[i % #pts + 1]
                local mx, my = (a.x + c.x) / 2, (a.y + c.y) / 2
                if (me.x - mx) ^ 2 + (me.y - my) ^ 2 < 300.0 ^ 2 then
                    drawWall(a, c, r, g, b, 45)
                end
            end

            -- Avertissement pour les défenseurs hors zone
            if zone.phase == 'live' and myTeam == zone.defenders and not insideZone(me.x, me.y) then
                drawText('RETOURNE DANS LA ZONE !')
            end

            -- Flèche au-dessus des coéquipiers
            if myTeam then
                local tr, tg, tb = hexToRgb(zone.colors and zone.colors[myTeam])
                for _, pid in ipairs(GetActivePlayers()) do
                    if pid ~= PlayerId() then
                        local st = Player(GetPlayerServerId(pid)).state
                        if st.gf_team == myTeam then
                            local ped = GetPlayerPed(pid)
                            if IsEntityVisible(ped) and not IsEntityDead(ped) then
                                local pos = GetEntityCoords(ped)
                                DrawMarker(2, pos.x, pos.y, pos.z + 1.25, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0,
                                    0.25, 0.25, 0.25, tr, tg, tb, 200, false, true, 2, false, nil, nil, false)
                            end
                        end
                    end
                end
            end
            Wait(0)
        end
    end
end)
