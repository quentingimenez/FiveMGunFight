-- =============================================================================
--  gf_maps - CLIENT : éditeur de maps vu du ciel
--
--  /editor (admin) ouvre la liste des maps. En création/modification :
--   - caméra vue de dessus, déplacement avec les touches de marche (ZQSD/WASD),
--     Maj = plus vite, molette = zoom
--   - molette maintenue + glisser = tourner et incliner la vue (camera.lua),
--     boutons du panneau pour les mêmes réglages et le retour à la vue du dessus
--   - clic gauche = placer, clic droit = retirer le dernier point
-- =============================================================================

local E = {
    open = false,      -- éditeur ouvert (liste ou édition)
    editing = false,   -- en cours de création / modification
    maps = { redzone = {}, attack = {} },
    kind = nil,        -- 'redzone' | 'attack'
    step = 1,
    map = nil,         -- map en cours d'édition
    cam = nil,
    pos = vector2(0.0, 0.0),
    refZ = 0.0,        -- hauteur du sol au point visé
    height = 180.0,    -- distance de la caméra au point visé (altitude en vue du dessus)
    view = nil,        -- angle de vue { pitch, yaw } (GFMapsCamera)
    camGround = nil,   -- hauteur du sol sous la caméra elle-même
    hover = nil,       -- point du sol sous la souris
    closed = false,    -- polygone fermé (attaque)
}

-- ---------------------------------------------------------------- Maths
local function cross(a, b)
    return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
end

local function normalize(v)
    local l = #v
    if l == 0 then return v end
    return v / l
end

local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function headingTo(from, to)
    return (math.deg(math.atan(-(to.x - from.x), to.y - from.y)) + 360.0) % 360.0
end

local function centroid(points)
    local x, y, z = 0.0, 0.0, 0.0
    for _, p in ipairs(points) do x, y, z = x + p.x, y + p.y, z + p.z end
    local n = math.max(#points, 1)
    return { x = x / n, y = y / n, z = z / n }
end

local function pointInPolygon(px, py, poly)
    local inside = false
    local j = #poly
    for i = 1, #poly do
        local a, b = poly[i], poly[j]
        if ((a.y > py) ~= (b.y > py)) and (px < (b.x - a.x) * (py - a.y) / (b.y - a.y) + a.x) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function deepCopy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deepCopy(v) end
    return r
end

-- ---------------------------------------------------------------- Caméra
local function groundAt(x, y)
    local found, z = GetGroundZFor_3dCoord(x, y, 1500.0, false)
    if found then return z end
    return nil
end

local function camView()
    if not E.view then E.view = GFMapsCamera.new(Config.EditorCamera) end
    return E.view
end

local function camPosition()
    local view = camView()
    local p = GFMapsCamera.position({ x = E.pos.x, y = E.pos.y, z = E.refZ }, E.height, view)
    p.z = GFMapsCamera.aboveGround(p.z, E.camGround, Config.EditorCamera.groundClearanceM)
    return p, view
end

local function updateCam()
    if not E.cam then return end
    local p, view = camPosition()
    SetCamCoord(E.cam, p.x, p.y, p.z)
    SetCamRot(E.cam, view.pitch, 0.0, view.yaw, 2)
    SetFocusPosAndVel(E.pos.x, E.pos.y, E.refZ, 0.0, 0.0, 0.0)
end

local function camStart(x, y, z)
    E.pos = vector2(x, y)
    E.refZ = z or 0.0
    E.view = GFMapsCamera.new(Config.EditorCamera)
    E.camGround = nil
    if not E.cam then
        E.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamFov(E.cam, 60.0)
        updateCam()
        RenderScriptCams(true, true, 400, true, true)
    else
        updateCam()
    end
end

local function camStop()
    if E.cam then
        RenderScriptCams(false, true, 400, true, true)
        DestroyCam(E.cam, false)
        E.cam = nil
    end
    ClearFocus()
end

-- Convertit une position de la souris (0..1) en point au sol
local function screenToWorld(sx, sy)
    if not E.cam then return nil end
    local camPos = GetCamCoord(E.cam)
    local rot = GetCamRot(E.cam, 2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)

    local forward = vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
    local right = vector3(math.cos(rz), math.sin(rz), 0.0)
    local up = cross(right, forward)

    local t = math.tan(math.rad(GetCamFov(E.cam)) / 2.0)
    local aspect = GetAspectRatio(false)
    local nx, ny = sx * 2.0 - 1.0, 1.0 - sy * 2.0
    local dir = normalize(forward + right * (nx * t * aspect) + up * (ny * t))

    local dest = camPos + dir * 4000.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(camPos.x, camPos.y, camPos.z,
        dest.x, dest.y, dest.z, 1, PlayerPedId(), 0)
    local _, hit, coords = GetShapeTestResult(ray)
    if hit == 1 then
        return { x = coords.x, y = coords.y, z = coords.z }
    end

    -- Rien touché (sol pas encore chargé) : intersection avec le plan du sol
    if dir.z >= -0.01 then return nil end
    local k = (E.refZ - camPos.z) / dir.z
    local p = camPos + dir * k
    return { x = p.x, y = p.y, z = E.refZ }
end

-- ---------------------------------------------------------------- État envoyé à l'interface
local function stateForUi()
    local m = E.map or {}
    local defenseInside = nil
    if E.kind == 'attack' and m.defenseSpawn and #(m.points or {}) >= 3 then
        defenseInside = pointInPolygon(m.defenseSpawn.x, m.defenseSpawn.y, m.points)
    end
    return {
        open = E.open,
        editing = E.editing,
        kind = E.kind,
        step = E.step,
        id = m.id,
        name = m.name or '',
        radius = m.radius,
        hasCenter = m.center ~= nil,
        spawnCount = #(m.spawns or {}),
        garageCount = #(m.garages or {}),
        pointCount = #(m.points or {}),
        closed = E.closed,
        hasAttackSpawn = m.attackSpawn ~= nil,
        hasDefenseSpawn = m.defenseSpawn ~= nil,
        defenseInside = defenseInside,
    }
end

local function sendState()
    SendNUIMessage({ type = 'state', state = stateForUi(), maps = E.maps })
end

local function toast(msg, isError)
    SendNUIMessage({ type = 'toast', text = msg, error = isError and true or false })
end

-- ---------------------------------------------------------------- Ouverture / fermeture
local function setPlayerFrozen(on)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, on)
    SetEntityInvincible(ped, on)
    SetEntityVisible(ped, not on, false)
end

local function openEditor(maps)
    local dejaOuvert = E.open
    E.maps = maps or E.maps
    E.open = true
    E.editing = false
    if not dejaOuvert then
        exports.gf_ui:PushLayer(GetCurrentResourceName())
    end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    setPlayerFrozen(true)
    sendState()
end

local function stopEditing()
    E.editing = false
    E.map = nil
    E.kind = nil
    E.hover = nil
    SetNuiFocusKeepInput(false)
end

local function closeEditor()
    stopEditing()
    camStop()
    E.open = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    setPlayerFrozen(false)
    DisplayRadar(true)
    sendState()
    -- En dernier : le lobby reprend le focus après nous.
    exports.gf_ui:PopLayer(GetCurrentResourceName())
end

local function startEdit(kind, id)
    E.kind = kind
    E.step = 1
    E.closed = false
    E.map = nil

    if id then
        for _, m in ipairs(E.maps[kind] or {}) do
            if m.id == id then E.map = deepCopy(m) break end
        end
    end

    local focus
    if E.map then
        if kind == 'redzone' then
            focus = E.map.center
            E.map.spawns = E.map.spawns or {}
            E.map.garages = E.map.garages or {}
        else
            E.closed = true
            focus = centroid(E.map.points)
        end
    else
        E.map = kind == 'redzone' and { radius = 80.0, spawns = {}, garages = {} } or { points = {} }
        local p = GetEntityCoords(PlayerPedId())
        focus = { x = p.x, y = p.y, z = p.z }
    end

    E.editing = true
    E.height = E.map.radius and math.max(150.0, E.map.radius * 3.0) or 180.0
    camStart(focus.x, focus.y, focus.z)
    SetNuiFocusKeepInput(true)
    sendState()
end

-- ---------------------------------------------------------------- Actions de souris
local function onClick(hit, button)
    local m = E.map
    if not m or not hit then return end

    if E.kind == 'redzone' then
        if E.step == 1 then
            if button == 0 then m.center = hit end
        elseif E.step == 2 or E.step == 3 then
            -- étape 2 : apparition à pied · étape 3 : points véhicule
            local list = E.step == 2 and m.spawns or m.garages
            if button == 0 then
                hit.h = m.center and headingTo(hit, m.center) or 0.0
                if #list >= 16 then return toast('16 points maximum', true) end
                list[#list + 1] = hit
            elseif button == 2 then
                list[#list] = nil
            end
        end
    else
        if E.step == 1 then
            if button == 0 then
                if E.closed then return toast('La zone est fermée. Clic droit pour la rouvrir.', true) end
                local snap = math.max(4.0, E.height / 25.0)
                if #m.points >= 3 and dist2d(hit, m.points[1]) <= snap then
                    E.closed = true
                    toast('Zone fermée !')
                elseif #m.points >= 64 then
                    toast('64 points maximum', true)
                else
                    m.points[#m.points + 1] = hit
                end
            elseif button == 2 then
                if E.closed then E.closed = false else m.points[#m.points] = nil end
            end
        elseif E.step == 2 or E.step == 3 then
            if button == 0 then
                local c = #m.points > 0 and centroid(m.points) or hit
                hit.h = headingTo(hit, c)
                if E.step == 2 then m.attackSpawn = hit else m.defenseSpawn = hit end
            elseif button == 2 then
                if E.step == 2 then m.attackSpawn = nil else m.defenseSpawn = nil end
            end
        end
    end
    sendState()
end

-- ---------------------------------------------------------------- Callbacks de l'interface
local function ok(cb) cb({ ok = true }) end

RegisterNUICallback('close', function(_, cb) closeEditor() ok(cb) end)

RegisterNUICallback('startEdit', function(d, cb)
    if d.kind == 'redzone' or d.kind == 'attack' then startEdit(d.kind, d.id) end
    ok(cb)
end)

RegisterNUICallback('cancelEdit', function(_, cb)
    stopEditing()
    camStop()
    sendState()
    ok(cb)
end)

RegisterNUICallback('step', function(d, cb)
    local maxStep = 4
    E.step = math.max(1, math.min(maxStep, tonumber(d.step) or 1))
    sendState()
    ok(cb)
end)

RegisterNUICallback('click', function(d, cb)
    onClick(screenToWorld(tonumber(d.x) or 0.5, tonumber(d.y) or 0.5), tonumber(d.button) or 0)
    ok(cb)
end)

RegisterNUICallback('hover', function(d, cb)
    E.hover = screenToWorld(tonumber(d.x) or 0.5, tonumber(d.y) or 0.5)
    ok(cb)
end)

RegisterNUICallback('wheel', function(d, cb)
    local delta = tonumber(d.delta) or 0
    if d.shift and E.kind == 'redzone' and E.map then
        E.map.radius = math.max(15.0, math.min(500.0, (E.map.radius or 80.0) - delta * 0.02))
        sendState()
    else
        E.height = math.max(30.0, math.min(900.0, E.height * (delta > 0 and 1.12 or 0.89)))
    end
    ok(cb)
end)

-- Angle de vue : { dx, dy } en pixels (molette maintenue + glisser) ou
-- { action = 'left' | 'right' | 'tilt' | 'flat' | 'top' } (boutons du panneau).
RegisterNUICallback('camera', function(d, cb)
    if E.editing and E.cam and type(d) == 'table' then
        if d.action ~= nil then
            GFMapsCamera.step(camView(), d.action, Config.EditorCamera)
        else
            GFMapsCamera.drag(camView(), tonumber(d.dx), tonumber(d.dy), Config.EditorCamera)
        end
        updateCam()
    end
    ok(cb)
end)

RegisterNUICallback('radius', function(d, cb)
    if E.map and E.kind == 'redzone' then
        E.map.radius = math.max(15.0, math.min(500.0, tonumber(d.value) or 80.0))
    end
    ok(cb)
end)

RegisterNUICallback('closePolygon', function(_, cb)
    if E.map and E.kind == 'attack' and #E.map.points >= 3 then
        E.closed = true
        sendState()
    else
        toast('Il faut au moins 3 points', true)
    end
    ok(cb)
end)

RegisterNUICallback('typing', function(d, cb)
    -- Pendant la saisie du nom, le clavier ne doit pas bouger la caméra
    SetNuiFocusKeepInput(not d.on and E.editing)
    ok(cb)
end)

RegisterNUICallback('save', function(d, cb)
    local m = E.map
    if m then
        m.name = d.name
        -- Les véhicules / joueurs regardent toujours vers la zone
        if E.kind == 'redzone' and m.center then
            for _, sp in ipairs(m.spawns) do sp.h = headingTo(sp, m.center) end
            for _, sp in ipairs(m.garages) do sp.h = headingTo(sp, m.center) end
        elseif E.kind == 'attack' and #m.points > 0 then
            local c = centroid(m.points)
            if m.attackSpawn then m.attackSpawn.h = headingTo(m.attackSpawn, c) end
            if m.defenseSpawn then m.defenseSpawn.h = headingTo(m.defenseSpawn, c) end
        end
        TriggerServerEvent('gf_maps:save', E.kind, m)
    end
    ok(cb)
end)

RegisterNUICallback('delete', function(d, cb)
    TriggerServerEvent('gf_maps:delete', d.kind, d.id)
    ok(cb)
end)

-- ---------------------------------------------------------------- Réponses du serveur
RegisterNetEvent('gf_maps:open', function(maps)
    openEditor(maps)
end)

RegisterNetEvent('gf_maps:saved', function(maps, id)
    E.maps = maps
    if E.editing and id then
        stopEditing()
        camStop()
        toast('Map enregistrée !')
    elseif not id then
        toast('Map supprimée')
    end
    sendState()
end)

-- Liste mise à jour (map cochée / décochée)
RegisterNetEvent('gf_maps:list', function(maps)
    E.maps = maps
    sendState()
end)

RegisterNUICallback('toggle', function(d, cb)
    TriggerServerEvent('gf_maps:setEnabled', d.kind, d.id, d.enabled and true or false)
    ok(cb)
end)

RegisterNetEvent('gf_maps:error', function(msg)
    toast(msg, true)
end)

-- ---------------------------------------------------------------- Dessin
local function marker(t, x, y, z, sx, sy, sz, r, g, b, a, faceCam)
    DrawMarker(t, x, y, z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, sx, sy, sz, r, g, b, a,
        false, faceCam or false, 2, false, nil, nil, false)
end

local function thickLine(a, b, w, r, g, bl, al)
    local dx, dy = b.x - a.x, b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    local px, py = -dy / len * w, dx / len * w
    local za, zb = a.z + 0.6, b.z + 0.6
    local x1, y1, x2, y2 = a.x + px, a.y + py, b.x + px, b.y + py
    local x3, y3, x4, y4 = b.x - px, b.y - py, a.x - px, a.y - py
    DrawPoly(x1, y1, za, x2, y2, zb, x3, y3, zb, r, g, bl, al)
    DrawPoly(x3, y3, zb, x4, y4, za, x1, y1, za, r, g, bl, al)
    DrawPoly(x3, y3, zb, x2, y2, zb, x1, y1, za, r, g, bl, al)
    DrawPoly(x1, y1, za, x4, y4, za, x3, y3, zb, r, g, bl, al)
end

local function drawEdit()
    local m = E.map
    if not m then return end
    local s = math.max(1.5, E.height / 45.0)

    if E.kind == 'redzone' then
        if m.center then
            local c = m.center
            marker(1, c.x, c.y, c.z - 3.0, m.radius * 2.0, m.radius * 2.0, 8.0, 255, 40, 40, 90)
            marker(1, c.x, c.y, c.z - 1.0, s, s, 4.0, 255, 255, 255, 200)
        end
        -- Apparition à pied (vert)
        for _, sp in ipairs(m.spawns) do
            marker(1, sp.x, sp.y, sp.z - 1.0, s * 2.0, s * 2.0, 3.0, 60, 220, 120, 200)
        end
        -- Points véhicule (bleu + icône voiture), orientés vers la zone
        for _, sp in ipairs(m.garages) do
            marker(1, sp.x, sp.y, sp.z - 1.0, s * 2.0, s * 2.0, 3.0, 70, 150, 255, 200)
            marker(36, sp.x, sp.y, sp.z + s, s, s, s, 70, 150, 255, 230, true)
            if m.center then
                local h = math.rad(headingTo(sp, m.center))
                local tip = { x = sp.x - math.sin(h) * s * 4.0, y = sp.y + math.cos(h) * s * 4.0, z = sp.z }
                thickLine(sp, tip, s * 0.25, 70, 150, 255, 220)
            end
        end
        if E.hover and E.step <= 3 then
            marker(1, E.hover.x, E.hover.y, E.hover.z - 1.0, s, s, 3.0, 255, 255, 255, 150)
        end
    else
        local pts = m.points
        for i = 1, #pts do
            local p = pts[i]
            local first = i == 1 and not E.closed
            local size = first and s * 1.8 or s
            marker(1, p.x, p.y, p.z - 1.0, size, size, 4.0, first and 255 or 255, first and 220 or 140, 0, 220)
            if i < #pts then thickLine(p, pts[i + 1], s * 0.3, 255, 140, 0, 220) end
        end
        if E.closed and #pts >= 3 then
            thickLine(pts[#pts], pts[1], s * 0.3, 255, 140, 0, 220)
        elseif E.step == 1 and E.hover and #pts > 0 then
            thickLine(pts[#pts], E.hover, s * 0.2, 255, 255, 255, 140)
        end
        if E.hover and E.step <= 3 then
            marker(1, E.hover.x, E.hover.y, E.hover.z - 1.0, s, s, 3.0, 255, 255, 255, 150)
        end
        if m.attackSpawn then
            local p = m.attackSpawn
            marker(1, p.x, p.y, p.z - 1.0, s * 2.5, s * 2.5, 4.0, 255, 70, 70, 220)
        end
        if m.defenseSpawn then
            local p = m.defenseSpawn
            marker(1, p.x, p.y, p.z - 1.0, s * 2.5, s * 2.5, 4.0, 70, 150, 255, 220)
        end
    end
end

-- ---------------------------------------------------------------- Boucle de l'éditeur
CreateThread(function()
    local nextGround = 0
    while true do
        if not E.open then
            Wait(300)
        else
            DisableAllControlActions(0)
            DisableAllControlActions(1)
            DisableAllControlActions(2)
            HideHudAndRadarThisFrame()

            if E.editing and E.cam then
                local dt = GetFrameTime()
                local lr = GetDisabledControlNormal(0, 30)  -- gauche / droite
                local ud = GetDisabledControlNormal(0, 31)  -- avant / arrière
                local speed = E.height * 1.1 * dt
                if IsDisabledControlPressed(0, 21) then speed = speed * 2.5 end
                local dx, dy = GFMapsCamera.move(lr, ud, speed, camView().yaw)
                E.pos = vector2(E.pos.x + dx, E.pos.y + dy)

                if GetGameTimer() > nextGround then
                    nextGround = GetGameTimer() + 500
                    local g = groundAt(E.pos.x, E.pos.y)
                    if g then E.refZ = E.refZ + (g - E.refZ) * 0.5 end
                    local p = camPosition()
                    E.camGround = groundAt(p.x, p.y)
                end

                updateCam()
                drawEdit()
            end
            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and E.open then closeEditor() end
end)
