-- =============================================================================
--  gf_maps - SERVEUR
--  Stocke les maps créées en jeu dans data/maps.json (dans le dossier de la
--  ressource, donc conservé entre les redémarrages).
--
--  Format :
--   redzone : { id, name, enabled, center{x,y,z}, radius,
--               spawns{ {x,y,z,h} } (apparition à pied), garages{ {x,y,z,h} } (prise du véhicule) }
--   attack  : { id, name, enabled, points{ {x,y,z}, ... }, attackSpawn{x,y,z,h}, defenseSpawn{x,y,z,h} }
--   enabled = false : map décochée, elle n'est pas jouée (ni proposée au vote plus tard)
--
--  Pour les autres ressources :
--   exports.gf_maps:GetMaps('redzone' | 'attack')        -> toutes les maps
--   exports.gf_maps:GetActiveMaps('redzone' | 'attack')  -> seulement les maps cochées
--   événement serveur 'gf_maps:updated' (kind)     -> une map a été créée/modifiée/supprimée
-- =============================================================================

local RES = GetCurrentResourceName()
local FILE = 'data/maps.json'
local core = exports.gf_core

local Maps = { redzone = {}, attack = {} }

local function load()
    local raw = LoadResourceFile(RES, FILE)
    if not raw or raw == '' then return end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then
        Maps.redzone = type(data.redzone) == 'table' and data.redzone or {}
        Maps.attack = type(data.attack) == 'table' and data.attack or {}
    else
        print('^1[gf_maps] data/maps.json est illisible, il sera remplacé à la prochaine sauvegarde^0')
    end
end

local function save()
    SaveResourceFile(RES, FILE, json.encode(Maps), -1)
end

load()
print(('[gf_maps] %d redzone(s), %d zone(s) d\'attaque chargée(s)'):format(#Maps.redzone, #Maps.attack))

exports('GetMaps', function(kind)
    return Maps[kind] or {}
end)

-- Seulement les maps cochées "en jeu" dans l'éditeur (celles qui tournent / seront votables)
exports('GetActiveMaps', function(kind)
    local list = {}
    for _, m in ipairs(Maps[kind] or {}) do
        if m.enabled ~= false then list[#list + 1] = m end
    end
    return list
end)

-- ---------------------------------------------------------------- Validation
local function num(v, min, max)
    v = tonumber(v)
    if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
    if v < min then v = min end
    if v > max then v = max end
    return v + 0.0
end

local function point(p, withHeading)
    if type(p) ~= 'table' then return nil end
    local x, y, z = num(p.x, -10000, 10000), num(p.y, -10000, 10000), num(p.z, -200, 2500)
    if not (x and y and z) then return nil end
    local r = { x = x, y = y, z = z }
    if withHeading then r.h = num(p.h, 0, 360) or 0.0 end
    return r
end

local function cleanName(s)
    s = tostring(s or ''):gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #s > 40 then s = s:sub(1, 40) end
    return s ~= '' and s or nil
end

local function validate(kind, m)
    if type(m) ~= 'table' then return nil, 'Données invalides' end
    local name = cleanName(m.name)
    if not name then return nil, 'Donne un nom à la map' end

    if kind == 'redzone' then
        local center = point(m.center)
        if not center then return nil, 'Place le centre de la zone' end
        local radius = num(m.radius, 15, 500)
        if not radius then return nil, 'Rayon invalide' end
        local spawns, garages = {}, {}
        for _, s in ipairs(type(m.spawns) == 'table' and m.spawns or {}) do
            local p = point(s, true)
            if p and #spawns < 16 then spawns[#spawns + 1] = p end
        end
        for _, s in ipairs(type(m.garages) == 'table' and m.garages or {}) do
            local p = point(s, true)
            if p and #garages < 16 then garages[#garages + 1] = p end
        end
        if #spawns == 0 then return nil, 'Ajoute au moins un point d\'apparition' end
        if #garages == 0 then return nil, 'Ajoute au moins un point véhicule' end
        return { name = name, center = center, radius = radius, spawns = spawns, garages = garages }

    elseif kind == 'attack' then
        local points = {}
        for _, s in ipairs(type(m.points) == 'table' and m.points or {}) do
            local p = point(s)
            if p and #points < 64 then points[#points + 1] = p end
        end
        if #points < 3 then return nil, 'La zone doit avoir au moins 3 points' end
        local att, def = point(m.attackSpawn, true), point(m.defenseSpawn, true)
        if not att then return nil, 'Place le départ des attaquants' end
        if not def then return nil, 'Place le départ des défenseurs' end
        return { name = name, points = points, attackSpawn = att, defenseSpawn = def }
    end
    return nil, 'Type de map inconnu'
end

-- ---------------------------------------------------------------- Éditeur
local function openEditor(src)
    if src == 0 then return print('[gf_maps] La commande /editor s\'utilise en jeu.') end
    if not core:IsAdmin(src) then
        return core:Notify(src, 'Réservé aux administrateurs.')
    end
    core:SetMode(src, 'lobby')
    TriggerClientEvent('gf_maps:open', src, Maps)
end
RegisterCommand('editor', openEditor, false)
RegisterCommand('maps', openEditor, false)

RegisterNetEvent('gf_maps:save', function(kind, data)
    local src = source
    if not core:IsAdmin(src) then return end
    if not Maps[kind] then return end

    local clean, err = validate(kind, data)
    if not clean then
        return TriggerClientEvent('gf_maps:error', src, err)
    end

    local id = type(data.id) == 'string' and data.id:match('^[%w_]+$') and data.id or nil
    local replaced = false
    if id then
        for i, m in ipairs(Maps[kind]) do
            if m.id == id then
                clean.id = id
                clean.enabled = m.enabled ~= false
                Maps[kind][i] = clean
                replaced = true
                break
            end
        end
    end
    if not replaced then
        clean.id = ('%s_%d_%d'):format(kind, os.time(), math.random(1000, 9999))
        clean.enabled = true
        Maps[kind][#Maps[kind] + 1] = clean
    end

    save()
    print(('[gf_maps] %s a enregistré la map "%s" (%s)'):format(GetPlayerName(src), clean.name, kind))
    TriggerClientEvent('gf_maps:saved', src, Maps, clean.id)
    TriggerEvent('gf_maps:updated', kind)
end)

-- Cocher / décocher une map (en jeu ou non)
RegisterNetEvent('gf_maps:setEnabled', function(kind, id, enabled)
    local src = source
    if not core:IsAdmin(src) or not Maps[kind] then return end
    for _, m in ipairs(Maps[kind]) do
        if m.id == id then
            m.enabled = enabled and true or false
            save()
            print(('[gf_maps] %s a %s la map "%s" (%s)'):format(GetPlayerName(src),
                m.enabled and 'activé' or 'désactivé', m.name, kind))
            TriggerClientEvent('gf_maps:list', src, Maps)
            TriggerEvent('gf_maps:updated', kind)
            return
        end
    end
end)

RegisterNetEvent('gf_maps:delete', function(kind, id)
    local src = source
    if not core:IsAdmin(src) or not Maps[kind] then return end
    for i, m in ipairs(Maps[kind]) do
        if m.id == id then
            table.remove(Maps[kind], i)
            save()
            print(('[gf_maps] %s a supprimé la map "%s" (%s)'):format(GetPlayerName(src), m.name, kind))
            TriggerClientEvent('gf_maps:saved', src, Maps, nil)
            TriggerEvent('gf_maps:updated', kind)
            return
        end
    end
end)
