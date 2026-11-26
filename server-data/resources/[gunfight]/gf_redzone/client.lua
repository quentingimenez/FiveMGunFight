-- =============================================================================
--  gf_redzone - CLIENT : zone sur la carte, points véhicule (touche E), sortie (touche F),
--  tir bloqué en dehors de la zone, soin au kill.
-- =============================================================================

local map = nil       -- { name, center{x,y,z}, radius, spawns{} }
local blips = {}
local myVehicle = nil -- véhicule donné au départ

local function removeBlips()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
end

local function createBlips()
    removeBlips()
    if not map then return end
    local c = map.center

    local area = AddBlipForRadius(c.x, c.y, c.z, map.radius)
    SetBlipColour(area, 1)
    SetBlipAlpha(area, 130)
    blips[#blips + 1] = area

    local pin = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(pin, 310)
    SetBlipColour(pin, 1)
    SetBlipRoute(pin, true)
    SetBlipRouteColour(pin, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Redzone : ' .. map.name)
    EndTextCommandSetBlipName(pin)
    blips[#blips + 1] = pin

    for _, g in ipairs(map.garages or {}) do
        local b = AddBlipForCoord(g.x, g.y, g.z)
        SetBlipSprite(b, 225)  -- voiture
        SetBlipColour(b, 3)
        SetBlipScale(b, 0.7)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Point véhicule')
        EndTextCommandSetBlipName(b)
        blips[#blips + 1] = b
    end
end

local GARAGE_RADIUS = 2.5      -- distance pour pouvoir prendre la voiture
local lastVehicleRequest = 0

-- Point véhicule : prend la voiture (touche E)
local function takeVehicle(g)
    if GetGameTimer() - lastVehicleRequest < 2000 then return end
    lastVehicleRequest = GetGameTimer()
    CreateThread(function()
        local veh = exports.gf_core:GiveModeVehicle(map.vehicle or Config.Vehicle, g.x, g.y, g.z + 0.5, g.h or 0.0)
        if veh and veh ~= 0 then myVehicle = veh end
    end)
end

local function clear()
    map = nil
    myVehicle = nil
    removeBlips()
end

local function distToZone(pos)
    local c = map.center
    return #(vector2(pos.x, pos.y) - vector2(c.x, c.y)) - map.radius
end

local function drawText(text, y, r, g, b)
    SetTextFont(4)
    SetTextScale(0.55, 0.55)
    SetTextColour(r, g, b, 255)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, y)
end

RegisterNetEvent('gf_redzone:map', function(m)
    map = m
    createBlips()
end)

RegisterNetEvent('gf_redzone:clear', clear)

RegisterNetEvent('gf_core:modeChanged', function(mode)
    if mode ~= 'redzone' then clear() end
end)

RegisterNetEvent('gf_redzone:heal', function()
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
end)

-- À chaque réapparition (à pied), l'ancien véhicule a été supprimé
AddEventHandler('gf_core:spawned', function()
    myVehicle = nil
end)

-- ---------------------------------------------------------------- Boucle
CreateThread(function()
    while true do
        if not map then
            Wait(500)
        else
            local ped = PlayerPedId()
            local pid = PlayerId()
            local pos = GetEntityCoords(ped)
            local outside = distToZone(pos) > 0.0

            -- Cercle rouge au sol
            local c = map.center
            DrawMarker(1, c.x, c.y, c.z - 25.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                map.radius * 2.0, map.radius * 2.0, 70.0, 255, 40, 40, 50,
                false, false, 2, false, nil, nil, false)

            -- Points véhicule (marqueur bleu au sol + icône voiture)
            if not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
                for _, g in ipairs(map.garages or {}) do
                    local d = #(vector3(pos.x, pos.y, pos.z) - vector3(g.x, g.y, g.z))
                    if d < 60.0 then
                        DrawMarker(1, g.x, g.y, g.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            GARAGE_RADIUS * 2.0, GARAGE_RADIUS * 2.0, 0.8, 70, 150, 255, 120,
                            false, false, 2, false, nil, nil, false)
                        DrawMarker(36, g.x, g.y, g.z + 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            1.2, 1.2, 1.2, 70, 150, 255, 220, true, true, 2, false, nil, nil, false)
                        if d <= GARAGE_RADIUS + 0.5 then
                            drawText('Appuie sur ~b~E~w~ pour prendre ton véhicule', 0.9, 255, 255, 255)
                            if IsControlJustPressed(0, 38) then takeVehicle(g) end
                        end
                    end
                end
            end

            -- Véhicule : F = sortir, la voiture disparaît
            if myVehicle then
                if not DoesEntityExist(myVehicle) then
                    myVehicle = nil
                elseif IsPedInVehicle(ped, myVehicle, false) then
                    DisableControlAction(0, 75, true)   -- sortie normale du véhicule
                    if IsDisabledControlJustPressed(0, 75) then
                        local vpos = GetEntityCoords(myVehicle)
                        local speed = GetEntitySpeed(myVehicle)
                        local vel = GetEntityVelocity(myVehicle)
                        myVehicle = nil
                        SetEntityCoords(ped, vpos.x, vpos.y, vpos.z + 0.3, false, false, false, false)
                        exports.gf_core:DeleteModeVehicle()
                        -- on garde un peu d'élan pour que ce soit fluide
                        if speed > 3.0 then SetEntityVelocity(ped, vel.x * 0.3, vel.y * 0.3, 0.0) end
                    elseif outside then
                        drawText('Appuie sur ~r~F~w~ pour sortir du véhicule', 0.9, 255, 255, 255)
                    end
                elseif not IsEntityDead(ped) then
                    -- le joueur est sorti autrement (accident...) : on retire la voiture
                    myVehicle = nil
                    exports.gf_core:DeleteModeVehicle()
                end
            end

            -- Pas de tir depuis un véhicule, ni en dehors de la zone
            if IsPedInAnyVehicle(ped, false) then
                DisableControlAction(0, 69, true)  -- tir en véhicule
                DisableControlAction(0, 70, true)
                DisableControlAction(0, 92, true)
                DisableControlAction(0, 114, true)
                DisableControlAction(0, 68, true)  -- viser en véhicule
            end
            if outside then
                DisablePlayerFiring(pid, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)  -- viser
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 257, true)
                if not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) then
                    drawText('Rejoins la ~r~REDZONE~w~ pour combattre', 0.84, 255, 255, 255)
                end
            end
            Wait(0)
        end
    end
end)
