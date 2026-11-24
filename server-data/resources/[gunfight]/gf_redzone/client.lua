-- =============================================================================
--  gf_redzone - CLIENT : zones sur la carte, mur rouge, dégâts hors zone, soin
-- =============================================================================

local data = nil   -- { zones = {...}, active = index, damage = n }
local blips = {}

local function removeBlips()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
end

local function createBlips()
    removeBlips()
    if not data then return end
    for i, z in ipairs(data.zones) do
        local active = i == data.active
        local area = AddBlipForRadius(z.x, z.y, z.z, z.radius)
        SetBlipColour(area, active and 1 or 40) -- 1 = rouge, 40 = gris
        SetBlipAlpha(area, active and 130 or 60)
        blips[#blips + 1] = area

        local pin = AddBlipForCoord(z.x, z.y, z.z)
        SetBlipSprite(pin, 310)
        SetBlipColour(pin, active and 1 or 40)
        SetBlipScale(pin, active and 1.0 or 0.7)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName((active and 'Redzone : ' or 'Zone inactive : ') .. z.name)
        EndTextCommandSetBlipName(pin)
        blips[#blips + 1] = pin
    end
end

local function activeZone()
    return data and data.zones[data.active]
end

local function outside()
    local z = activeZone()
    if not z then return false end
    local p = GetEntityCoords(PlayerPedId())
    return #(vector2(p.x, p.y) - vector2(z.x, z.y)) > z.radius
end

RegisterNetEvent('gf_redzone:zones', function(d)
    data = d
    createBlips()
end)

RegisterNetEvent('gf_redzone:clear', function()
    data = nil
    removeBlips()
end)

RegisterNetEvent('gf_core:modeChanged', function(mode)
    if mode ~= 'redzone' then
        data = nil
        removeBlips()
    end
end)

RegisterNetEvent('gf_redzone:heal', function()
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
end)

-- Dégâts hors zone
CreateThread(function()
    while true do
        Wait(1000)
        if data and not LocalPlayer.state.gf_protected then
            local ped = PlayerPedId()
            if not IsEntityDead(ped) and outside() then
                ApplyDamageToPed(ped, data.damage or 10, false)
            end
        end
    end
end)

-- Affichage
CreateThread(function()
    while true do
        local z = activeZone()
        if not z then
            Wait(500)
        else
            DrawMarker(1, z.x, z.y, z.z - 25.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                z.radius * 2.0, z.radius * 2.0, 70.0, 255, 40, 40, 50,
                false, false, 2, false, nil, nil, false)

            if outside() then
                SetTextFont(4)
                SetTextScale(0.6, 0.6)
                SetTextColour(255, 80, 80, 255)
                SetTextOutline()
                SetTextCentre(true)
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName('HORS ZONE : RETOURNE DANS LA REDZONE !')
                EndTextCommandDisplayText(0.5, 0.78)
            end
            Wait(0)
        end
    end
end)
