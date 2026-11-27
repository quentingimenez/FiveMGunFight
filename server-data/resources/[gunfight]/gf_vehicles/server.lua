-- =============================================================================
--  gf_vehicles - SERVEUR
--  Véhicule de base des modes et custom de chaque véhicule (réglés par un admin).
--  Partagés à tous via GlobalState.gf_vehicle_base et GlobalState.gf_vehicle_customs ;
--  gf_core crée le véhicule de base et lui applique sa custom.
-- =============================================================================

local RES = GetCurrentResourceName()
local core = exports.gf_core

local KNOWN = {}
for _, v in ipairs(Config.Vehicles) do KNOWN[v.model] = true end

local Data = { base = Config.DefaultModel, customs = {} }

-- ---------------------------------------------------------------- Validation
local function int(v, min, max)
    if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then return nil end
    v = math.floor(v)
    if v < min or v > max then return nil end
    return v
end

local function rgb(v)
    if type(v) ~= 'table' then return nil end
    local r, g, b = int(v.r, 0, 255), int(v.g, 0, 255), int(v.b, 0, 255)
    if not (r and g and b) then return nil end
    return { r = r, g = g, b = b }
end

local MOD_TYPES = {}
for _, slot in ipairs(Config.ModSlots) do MOD_TYPES[slot.type] = true end
MOD_TYPES[23] = true -- jantes

-- Ne garde que les propriétés connues, avec des valeurs dans les bornes.
local function sanitize(p)
    if type(p) ~= 'table' then return nil end
    local out = {}
    out.paintType = int(p.paintType, 0, #Config.PaintTypes - 1)
    out.primary = rgb(p.primary)
    out.secondary = rgb(p.secondary)
    out.pearl = int(p.pearl, 0, 160)
    out.wheelColor = int(p.wheelColor, 0, 160)
    out.wheelType = int(p.wheelType, 0, #Config.WheelTypes - 1)
    out.windowTint = int(p.windowTint, 0, #Config.WindowTints - 1)
    out.xenon = p.xenon == true
    out.xenonColor = int(p.xenonColor, 0, #Config.XenonColors - 1)
    out.neon = p.neon == true
    out.neonColor = rgb(p.neonColor)
    out.plateStyle = int(p.plateStyle, 0, #Config.PlateStyles - 1)
    if type(p.plate) == 'string' then
        local plate = p.plate:upper():gsub('[^%w ]', ''):sub(1, Config.PlateMaxLength)
        if plate ~= '' then out.plate = plate end
    end
    out.mods = {}
    if type(p.mods) == 'table' then
        for k, v in pairs(p.mods) do
            local t = int(tonumber(k), 0, 49)
            local i = int(v, -1, 255)
            if t and i and MOD_TYPES[t] then out.mods[tostring(t)] = i end
        end
    end
    return out
end

-- ---------------------------------------------------------------- Fichier
-- Version de chaque modèle (taille de son .yft) : si le fichier change (nouvelle
-- copie d'un pack), les clients qui l'avaient mis de côté après un plantage le
-- retentent tout seuls (voir gf_core et gf_thumbs).
local function modelVersions()
    local versions = {}
    for _, v in ipairs(Config.Vehicles) do
        local raw = LoadResourceFile(RES, ('stream/%s.yft'):format(v.model))
        versions[v.model] = raw and tostring(#raw) or '0'
    end
    return versions
end

local function publish()
    -- répliqués à tous les clients
    GlobalState:set('gf_vehicle_versions', modelVersions(), true)
    GlobalState:set('gf_vehicle_base', Data.base, true)
    GlobalState:set('gf_vehicle_customs', Data.customs, true)
end

local function load()
    local raw = LoadResourceFile(RES, Config.CustomFile)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            if type(data.base) == 'string' and KNOWN[data.base] then Data.base = data.base end
            if type(data.customs) == 'table' then
                for model, p in pairs(data.customs) do
                    if KNOWN[model] then Data.customs[model] = sanitize(p) end
                end
            end
            -- Ancien format { default = ... } : custom du véhicule par défaut
            if type(data.default) == 'table' and not Data.customs[Config.DefaultModel] then
                Data.customs[Config.DefaultModel] = sanitize(data.default)
            end
        else
            print(('^1[gf_vehicles] %s est illisible, custom par défaut utilisée^0'):format(Config.CustomFile))
        end
    end
    publish()
end

local function save()
    SaveResourceFile(RES, Config.CustomFile, json.encode(Data), -1)
end

load()

-- ---------------------------------------------------------------- Menu admin
RegisterCommand('customveh', function(src)
    if src == 0 then return print('[gf_vehicles] La commande /customveh s\'utilise en jeu.') end
    if not core:IsAdmin(src) then
        return core:Notify(src, 'Réservé aux administrateurs.')
    end
    TriggerClientEvent('gf_vehicles:openMenu', src, { base = Data.base, customs = Data.customs })
end, false)

-- Enregistrer : le véhicule affiché devient le véhicule de base, avec cette custom
RegisterNetEvent('gf_vehicles:saveCustom', function(model, props)
    local src = source
    if not core:IsAdmin(src) then return end
    if type(model) ~= 'string' or not KNOWN[model] then return end
    local clean = sanitize(props)
    if not clean then return end
    Data.base = model
    Data.customs[model] = clean
    save()
    publish()
    core:Notify(src, 'Véhicule de base enregistré : il s\'applique aux prochains véhicules.')
    print(('[gf_vehicles] Véhicule de base %s choisi (avec sa custom) par %s'):format(model, GetPlayerName(src) or src))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'vehicle_custom', nil, 'modele=' .. model) end)
    end
end)
