-- =============================================================================
--  gf_thumbs - CLIENT
--
--  1) API pour les autres ressources :
--       exports.gf_thumbs:Get(kind, ids) -> { [id] = 'data:image/png;base64,...' }
--     (bloquant, à appeler dans un thread ; résultat mis en cache)
--
--  2) Studio photo (admin, /thumbs <famille> [id]) : pose l'objet au milieu
--     d'une boîte verte, cadre la caméra selon la taille du modèle, la page
--     NUI capture l'image du jeu, détoure le vert et recadre, puis la photo
--     est envoyée au serveur.
-- =============================================================================

-- ---------------------------------------------------------------- API (cache)
local cache = {}     -- [kind] = { [id] = dataURL | false }
local pending = {}   -- [reqId] = promise
local nextReq = 0

RegisterNetEvent('gf_thumbs:data', function(reqId, kind, result)
    local p = pending[reqId]
    pending[reqId] = nil
    if type(result) ~= 'table' then result = {} end
    if p then p:resolve({ kind = kind, result = result }) end
end)

RegisterNetEvent('gf_thumbs:updated', function(kind, id)
    if cache[kind] then cache[kind][id] = nil end
end)

local function get(kind, ids)
    if type(kind) ~= 'string' or type(ids) ~= 'table' then return {} end
    cache[kind] = cache[kind] or {}
    local missing, out = {}, {}
    for _, id in ipairs(ids) do
        local v = cache[kind][id]
        if v == nil then missing[#missing + 1] = id
        elseif v then out[id] = v end
    end
    if #missing > 0 then
        nextReq = nextReq + 1
        local p = promise.new()
        pending[nextReq] = p
        TriggerServerEvent('gf_thumbs:request', nextReq, kind, missing)
        -- Si le serveur ne répond pas (anti-spam), on n'attend pas indéfiniment
        local reqId = nextReq
        SetTimeout(8000, function()
            if pending[reqId] then pending[reqId] = nil p:resolve({ result = {} }) end
        end)
        local res = Citizen.Await(p).result or {}
        for _, id in ipairs(missing) do
            cache[kind][id] = res[id] or false
            if res[id] then out[id] = res[id] end
        end
    end
    return out
end
exports('Get', get)

-- ---------------------------------------------------------------- Studio
local capturing = false
local captureWaiter = nil -- promesse de la photo en cours

-- Réponse de la page NUI après capture (enregistré une seule fois)
RegisterNUICallback('captured', function(data, cb)
    cb({})
    local p = captureWaiter
    captureWaiter = nil
    if p then p:resolve(data) end
end)

local function waitLoaded(check, ms)
    local t = GetGameTimer() + (ms or 10000)
    while not check() and GetGameTimer() < t do Wait(0) end
    return check()
end

-- Comment poser chaque type d'objet. spawn(id, pos) -> entité ; view = côté de la caméra.
local Subjects = {
    vehicle = {
        spawn = function(id, pos)
            local hash = joaat(id)
            if not IsModelInCdimage(hash) then return nil end
            RequestModel(hash)
            if not waitLoaded(function() return HasModelLoaded(hash) end) then return nil end
            local veh = CreateVehicle(hash, pos.x, pos.y, pos.z, 0.0, false, false)
            SetModelAsNoLongerNeeded(hash)
            if veh == 0 then return nil end
            SetVehicleDirtLevel(veh, 0.0)
            SetVehicleLights(veh, 2)
            -- Custom du véhicule de base, si gf_vehicles en a une pour ce modèle
            if GetResourceState('gf_vehicles') == 'started' then exports.gf_vehicles:ApplyCustom(veh) end
            return veh
        end,
        -- trois quarts avant gauche, légèrement au-dessus
        view = vector3(-0.85, 1.0, 0.32),
    },
    weapon = {
        spawn = function(id, pos)
            local hash = joaat(id)
            if not IsWeaponValid(hash) then return nil end
            RequestWeaponAsset(hash, 31, 0)
            if not waitLoaded(function() return HasWeaponAssetLoaded(hash) end) then return nil end
            local obj = CreateWeaponObject(hash, 0, pos.x, pos.y, pos.z, true, 1.0, 0)
            if obj == 0 then return nil end
            return obj
        end,
        view = 'side', -- de profil, perpendiculaire à l'axe le plus long
    },
}

-- Boîte verte autour du studio (DrawPoly : couleur unie, non éclairée)
local function drawBox(c, s)
    local k = Config.KeyColor
    local p = {
        vector3(c.x - s, c.y - s, c.z - s), vector3(c.x + s, c.y - s, c.z - s),
        vector3(c.x + s, c.y + s, c.z - s), vector3(c.x - s, c.y + s, c.z - s),
        vector3(c.x - s, c.y - s, c.z + s), vector3(c.x + s, c.y - s, c.z + s),
        vector3(c.x + s, c.y + s, c.z + s), vector3(c.x - s, c.y + s, c.z + s),
    }
    local faces = { {1, 2, 3, 4}, {5, 6, 7, 8}, {1, 2, 6, 5}, {2, 3, 7, 6}, {3, 4, 8, 7}, {4, 1, 5, 8} }
    for _, f in ipairs(faces) do
        local a, b, cc, d = p[f[1]], p[f[2]], p[f[3]], p[f[4]]
        -- les deux sens pour être visible de l'intérieur quel que soit le tri des faces
        local function tri(u, v, w)
            DrawPoly(u.x, u.y, u.z, v.x, v.y, v.z, w.x, w.y, w.z, k.r, k.g, k.b, 255)
        end
        tri(a, b, cc) tri(a, cc, d) tri(cc, b, a) tri(d, cc, a)
    end
end

-- Place la caméra pour que tout l'objet tienne dans l'image
local function frame(cam, ent, view)
    local minV, maxV = GetModelDimensions(GetEntityModel(ent))
    local size = maxV - minV
    local centerLocal = (minV + maxV) / 2
    local center = GetOffsetFromEntityInWorldCoords(ent, centerLocal.x, centerLocal.y, centerLocal.z)
    local dir
    if view == 'side' then
        -- regarder le long de l'axe horizontal le plus fin
        dir = size.x >= size.y and vector3(0.0, -1.0, 0.04) or vector3(-1.0, 0.0, 0.04)
    else
        dir = view
    end
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
    dir = dir / len
    local radius = math.sqrt(size.x * size.x + size.y * size.y + size.z * size.z) / 2
    local dist = radius / math.sin(math.rad(Config.Fov / 2)) * 0.92
    local camPos = center + dir * dist
    SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
    PointCamAtCoord(cam, center.x, center.y, center.z)
    return center, radius, camPos
end

local function shoot(kind, id)
    local def = Config.Kinds[kind]
    local subject = Subjects[def.subject]
    local s = Config.Studio
    local pos = vector3(s.x, s.y, s.z)
    local ent = subject.spawn(id, pos)
    if not ent then
        print(('[gf_thumbs] %s/%s : modèle introuvable, ignoré'):format(kind, id))
        return false
    end
    FreezeEntityPosition(ent, true)
    SetEntityCollision(ent, false, false)
    SetEntityCoordsNoOffset(ent, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(ent, 0.0)

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(cam, Config.Fov)
    local center, radius, camPos = frame(cam, ent, subject.view)
    RenderScriptCams(true, false, 0, true, true)

    -- quelques images pour laisser le modèle et les textures (HD) se charger
    local boxSize = math.max(8.0, radius * 6.0)
    local untilT = GetGameTimer() + 900
    while GetGameTimer() < untilT do
        drawBox(center, boxSize)
        DrawLightWithRange(camPos.x, camPos.y, camPos.z + 1.0, 255, 255, 255, radius * 6.0, 1.2)
        HideHudAndRadarThisFrame()
        Wait(0)
    end

    local p = promise.new()
    local active = true
    CreateThread(function()
        while active do
            drawBox(center, boxSize)
            DrawLightWithRange(camPos.x, camPos.y, camPos.z + 1.0, 255, 255, 255, radius * 6.0, 1.2)
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
    captureWaiter = p
    SendNUIMessage({ type = 'capture', kind = kind, id = id, width = def.width, height = def.height, key = Config.KeyColor })
    SetTimeout(10000, function()
        if captureWaiter == p then captureWaiter = nil p:resolve({ error = 'délai dépassé' }) end
    end)
    local data = Citizen.Await(p)
    active = false

    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    SetEntityAsMissionEntity(ent, true, true)
    DeleteEntity(ent)

    if type(data) == 'table' and type(data.url) == 'string' then
        TriggerLatentServerEvent('gf_thumbs:save', 200000, kind, id, data.url)
        return true
    end
    print(('[gf_thumbs] %s/%s : capture échouée%s'):format(kind, id, data and data.error and (' (' .. data.error .. ')') or ''))
    return false
end

-- Liste des identifiants d'une famille, fournie par la ressource concernée
local function listOf(kind)
    local prov = Config.Kinds[kind].provider
    if GetResourceState(prov.resource) ~= 'started' then return {} end
    local ok, list = pcall(function() return exports[prov.resource][prov.export]() end)
    return ok and type(list) == 'table' and list or {}
end

RegisterNetEvent('gf_thumbs:capture', function(kind, onlyId)
    if capturing or not Config.Kinds[kind] then return end
    capturing = true
    local ids = {}
    for _, item in ipairs(listOf(kind)) do
        if not onlyId or item.id == onlyId then ids[#ids + 1] = item.id end
    end
    if #ids == 0 then
        capturing = false
        return print(('[gf_thumbs] Rien à photographier pour %s%s'):format(kind, onlyId and ('/' .. onlyId) or ''))
    end

    -- Studio : midi, grand soleil, chargement du décor autour du studio
    local ped = PlayerPedId()
    local s = Config.Studio
    FreezeEntityPosition(ped, true)
    SetFocusPosAndVel(s.x, s.y, s.z, 0.0, 0.0, 0.0)
    NetworkOverrideClockTime(12, 0, 0)
    SetWeatherTypeNowPersist('EXTRASUNNY')
    DisplayRadar(false)

    local ok = 0
    for i, id in ipairs(ids) do
        BeginTextCommandPrint('STRING')
        AddTextComponentSubstringPlayerName(('Photo %d/%d : %s'):format(i, #ids, id))
        EndTextCommandPrint(1500, true)
        if shoot(kind, id) then ok = ok + 1 end
        Wait(300)
    end

    ClearFocus()
    NetworkClearClockTimeOverride()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    DisplayRadar(true)
    FreezeEntityPosition(ped, false)
    capturing = false
    print(('[gf_thumbs] %d/%d photo(s) %s envoyée(s) au serveur'):format(ok, #ids, kind))
end)
