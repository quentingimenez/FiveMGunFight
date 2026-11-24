-- =============================================================================
--  gf_attack - CLIENT : affichage de la zone, repères coéquipiers,
--  dégâts pour les défenseurs qui sortent de la zone.
-- =============================================================================

local zone = nil
local blips = {}

local function hexToRgb(hex)
    hex = (hex or '#ffffff'):gsub('#', '')
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
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

    local area = AddBlipForRadius(c.x, c.y, c.z, zone.radius)
    SetBlipColour(area, defending and 3 or 1) -- 3 = bleu, 1 = rouge
    SetBlipAlpha(area, 110)

    local pin = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(pin, 84)
    SetBlipColour(pin, defending and 3 or 1)
    SetBlipRoute(pin, not defending)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName((defending and 'À défendre : ' or 'À attaquer : ') .. zone.name)
    EndTextCommandSetBlipName(pin)

    blips = { area, pin }
end

local function draw3dText(text)
    SetTextFont(4)
    SetTextScale(0.6, 0.6)
    SetTextColour(255, 80, 80, 255)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.78)
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
                local dist = #(vector2(p.x, p.y) - vector2(zone.center.x, zone.center.y))
                if dist > zone.radius then
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
            local c = zone.center
            local myTeam = LocalPlayer.state.gf_team
            local r, g, b = hexToRgb(zone.colors and zone.colors[zone.defenders])

            -- Mur de la zone
            DrawMarker(1, c.x, c.y, c.z - 25.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                zone.radius * 2.0, zone.radius * 2.0, 70.0, r, g, b, 45,
                false, false, 2, false, nil, nil, false)

            -- Avertissement pour les défenseurs hors zone
            if zone.phase == 'live' and myTeam == zone.defenders then
                local p = GetEntityCoords(PlayerPedId())
                if #(vector2(p.x, p.y) - vector2(c.x, c.y)) > zone.radius then
                    draw3dText('RETOURNE DANS LA ZONE !')
                end
            end

            -- Flèche au-dessus des coéquipiers
            if myTeam then
                local tr, tg, tb = hexToRgb(zone.colors and zone.colors[myTeam])
                for _, pid in ipairs(GetActivePlayers()) do
                    if pid ~= PlayerId() then
                        local sid = GetPlayerServerId(pid)
                        local st = Player(sid).state
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
