-- =============================================================================
--  gf_lobby - APPEARANCE SCHEMA (partagé client/serveur)
--  Source de vérité de l'apparence d'un personnage : génération déterministe
--  depuis (seed, genre, carnation) et validation des données enregistrées.
--  Aucune native ici : le fichier est chargé aussi bien par le client que par
--  le serveur. Les index de drawables/textures sont bornés une seconde fois
--  côté client contre les variations réellement installées.
-- =============================================================================

GFLobbyAppearanceSchema = GFLobbyAppearanceSchema or {}

local S = GFLobbyAppearanceSchema

-- Même générateur que la v1 : un personnage existant garde sa tenue et sa tête.
local LCG_MOD = 2147483648
local LCG_A = 1103515245
local LCG_C = 12345

local SKIN_PARENT = {
    { first = 0, second = 1, mix = 0.0 },
    { first = 1, second = 2, mix = 0.3 },
    { first = 2, second = 3, mix = 0.5 },
    { first = 3, second = 4, mix = 0.7 },
    { first = 4, second = 4, mix = 1.0 },
}

local ZONE_SET = {
    ZONE_HEAD = true,
    ZONE_TORSO = true,
    ZONE_LEFT_ARM = true,
    ZONE_RIGHT_ARM = true,
    ZONE_LEFT_LEG = true,
    ZONE_RIGHT_LEG = true,
}

local MAX_TATTOOS = 24
local MAX_TATTOOS_PER_ZONE = 4

if type(Config) == 'table' and type(Config.Character) == 'table' then
    local configured = tonumber(Config.Character.maxTattoos)
    if configured and configured >= 1 and configured <= 64 then
        MAX_TATTOOS = math.floor(configured)
    end
    local perZone = tonumber(Config.Character.maxTattoosPerZone)
    if perZone and perZone >= 1 and perZone <= 12 then
        MAX_TATTOOS_PER_ZONE = math.floor(perZone)
    end
end

S.MAX_TATTOOS = MAX_TATTOOS
S.MAX_TATTOOS_PER_ZONE = MAX_TATTOOS_PER_ZONE
S.OVERLAY_IDS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
S.COMPONENT_IDS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
S.PROP_IDS = { 0, 1, 2, 6, 7 }
S.FACE_FEATURE_COUNT = 20

local function clampNumber(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number or number ~= number then return fallback end
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

local function clampInt(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number or number ~= number then return fallback end
    number = math.floor(number)
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

local function cleanIdentifier(value)
    if type(value) ~= 'string' then return nil end
    if #value < 1 or #value > 64 then return nil end
    if not value:match('^[%w_]+$') then return nil end
    return value
end

-- Les clés numériques deviennent des chaînes après json.decode. On accepte les
-- deux formes pour que le même schéma serve au Lua, à la NUI et au fichier.
local function keyed(source, id)
    if type(source) ~= 'table' then return nil end
    local value = source[id]
    if value == nil then value = source[tostring(id)] end
    return value
end

local function hashInputs(seed, female, skin)
    local h = seed % LCG_MOD
    h = (h * 2654435761) % LCG_MOD
    h = (h + (female and 1229 or 314159)) % LCG_MOD
    h = (h * 40503 + (skin * 7919)) % LCG_MOD
    return math.floor(h) % LCG_MOD
end

local function newRandom(seed, female, skin)
    local state = hashInputs(seed, female, skin)
    local r = {}
    function r.next()
        state = (state * LCG_A + LCG_C) % LCG_MOD
        return state / LCG_MOD
    end
    function r.int(maxValue)
        if maxValue <= 1 then return 0 end
        return math.floor(r.next() * maxValue) % maxValue
    end
    return r
end

local function newOverlay(index, color, highlight, opacity, colorType)
    if index <= 0 then return nil end
    return {
        index = index,
        color = color,
        highlight = highlight,
        opacity = opacity,
        colorType = colorType,
    }
end

-- Apparence par défaut d'un personnage neuf. Les tirages de la v1 sont
-- conservés dans le même ordre : les personnages sans apparence gardent leur
-- tenue et leur tête actuelles.
function S.compute(seed, female, skin)
    seed = clampInt(seed, 1, 2147483647, 1337)
    skin = clampInt(skin, 0, 4, 0)
    female = female == true

    local r = newRandom(seed, female, skin)
    local torso = r.int(6)
    local legs = r.int(8)
    local shoes = r.int(7)
    local undershirt = r.int(5)
    local top = r.int(12)
    local hair = r.int(18)
    local hairColor = r.int(12)
    local eyeColor = r.int(6)
    local eyebrow = r.int(11)
    local eyebrowColor = r.int(12)
    local facialHair = r.int(5)
    local shapeFirst = r.int(20)
    local shapeSecond = r.int(20)
    local shapeMix = r.next()
    local parent = SKIN_PARENT[skin + 1]

    local appearance = {
        head = {
            shapeFirst = shapeFirst,
            shapeSecond = shapeSecond,
            shapeMix = shapeMix,
            skinFirst = parent.first,
            skinSecond = parent.second,
            skinMix = parent.mix,
            thirdMix = 0,
        },
        features = {},
        hair = {
            drawable = hair,
            texture = 0,
            color = hairColor,
            highlight = 0,
        },
        eyeColor = eyeColor,
        overlays = {},
        components = {},
        props = {},
        tattoos = {},
    }

    -- Les traits et overlays ajoutés par l'éditeur restent neutres par défaut :
    -- un personnage v1 sans `appearance` garde exactement son ancien rendu.
    for i = 1, S.FACE_FEATURE_COUNT do
        appearance.features[i] = 0.0
    end

    appearance.overlays[2] = newOverlay(eyebrow, eyebrowColor, 0, 1.0, 1)
    if female then
        appearance.overlays[1] = nil
    else
        appearance.overlays[1] = newOverlay(facialHair, hairColor, 0, 0.6, 1)
    end

    for _, component in ipairs(S.COMPONENT_IDS) do
        appearance.components[component] = { drawable = 0, texture = 0 }
    end
    appearance.components[3] = { drawable = torso, texture = 0 }
    appearance.components[4] = { drawable = legs, texture = 0 }
    appearance.components[6] = { drawable = shoes, texture = 0 }
    appearance.components[8] = { drawable = undershirt, texture = 0 }
    appearance.components[11] = { drawable = top, texture = 0 }

    return appearance
end

local function normalizeHead(raw, fallback)
    local source = type(raw) == 'table' and raw or {}
    local base = type(fallback) == 'table' and fallback or {}
    return {
        shapeFirst = clampInt(source.shapeFirst, 0, 45, clampInt(base.shapeFirst, 0, 45, 0)),
        shapeSecond = clampInt(source.shapeSecond, 0, 45, clampInt(base.shapeSecond, 0, 45, 0)),
        shapeMix = clampNumber(source.shapeMix, 0, 1, clampNumber(base.shapeMix, 0, 1, 0)),
        skinFirst = clampInt(source.skinFirst, 0, 4, clampInt(base.skinFirst, 0, 4, 0)),
        skinSecond = clampInt(source.skinSecond, 0, 4, clampInt(base.skinSecond, 0, 4, 0)),
        skinMix = clampNumber(source.skinMix, 0, 1, clampNumber(base.skinMix, 0, 1, 0)),
        thirdMix = 0,
    }
end

local function normalizeHair(raw, fallback)
    local source = type(raw) == 'table' and raw or {}
    local base = type(fallback) == 'table' and fallback or {}
    return {
        drawable = clampInt(source.drawable, 0, 255, clampInt(base.drawable, 0, 255, 0)),
        texture = clampInt(source.texture, 0, 99, clampInt(base.texture, 0, 99, 0)),
        color = clampInt(source.color, 0, 63, clampInt(base.color, 0, 63, 0)),
        highlight = clampInt(source.highlight, 0, 63, clampInt(base.highlight, 0, 63, 0)),
    }
end

local function normalizeOverlays(raw, fallback)
    local source = type(raw) == 'table' and raw or {}
    local base = type(fallback) == 'table' and fallback or {}
    local overlays = {}
    for _, id in ipairs(S.OVERLAY_IDS) do
        local entry = type(keyed(source, id)) == 'table' and keyed(source, id) or keyed(base, id)
        if type(entry) == 'table' then
            local index = clampInt(entry.index, 0, 99, 0)
            if index > 0 then
                overlays[id] = {
                    index = index,
                    color = clampInt(entry.color, 0, 63, 0),
                    highlight = clampInt(entry.highlight, 0, 63, 0),
                    opacity = clampNumber(entry.opacity, 0, 1, 1),
                    colorType = clampInt(entry.colorType, 0, 2, 0),
                }
            end
        end
    end
    return overlays
end

local function normalizeComponents(raw, fallback)
    local source = type(raw) == 'table' and raw or {}
    local base = type(fallback) == 'table' and fallback or {}
    local components = {}
    for _, id in ipairs(S.COMPONENT_IDS) do
        local entry = type(keyed(source, id)) == 'table' and keyed(source, id) or keyed(base, id)
        if type(entry) == 'table' then
            components[id] = {
                drawable = clampInt(entry.drawable, 0, 999, 0),
                texture = clampInt(entry.texture, 0, 99, 0),
            }
        else
            components[id] = { drawable = 0, texture = 0 }
        end
    end
    return components
end

local function normalizeProps(raw)
    local source = type(raw) == 'table' and raw or {}
    local props = {}
    for id = 0, 13 do
        local entry = type(keyed(source, id)) == 'table' and keyed(source, id) or nil
        if type(entry) == 'table' then
            local drawable = clampInt(entry.drawable, -1, 999, -1)
            props[id] = {
                drawable = drawable,
                texture = drawable >= 0 and clampInt(entry.texture, 0, 99, 0) or 0,
            }
        else
            props[id] = { drawable = -1, texture = 0 }
        end
    end
    return props
end

local function normalizeTattoos(raw)
    local tattoos = {}
    local seen = {}
    local perZone = {}
    if type(raw) ~= 'table' then return tattoos end
    for i = 1, #raw do
        local entry = raw[i]
        if type(entry) == 'table' then
            local collection = cleanIdentifier(entry.collection)
            local overlay = cleanIdentifier(entry.overlay)
            local zone = type(entry.zone) == 'string' and entry.zone or nil
            if collection and overlay and zone and ZONE_SET[zone] then
                local key = collection .. '|' .. overlay
                local count = perZone[zone] or 0
                if not seen[key] and #tattoos < MAX_TATTOOS
                    and count < MAX_TATTOOS_PER_ZONE then
                    seen[key] = true
                    perZone[zone] = count + 1
                    tattoos[#tattoos + 1] = {
                        collection = collection,
                        overlay = overlay,
                        zone = zone,
                    }
                end
            end
        end
    end
    return tattoos
end

-- Normalise une apparence complète. `raw` peut être nil (personnage v1) : les
-- valeurs par défaut sont alors calculées depuis seed/genre/carnation. Toutes
-- les valeurs absentes ou invalides retombent sur ces défauts.
function S.normalize(raw, gender, seed, skin)
    local female = gender == 'female'
    seed = clampInt(seed, 1, 2147483647, 1337)
    skin = clampInt(skin, 0, 4, 0)
    local defaults = S.compute(seed, female, skin)
    if type(raw) ~= 'table' then return defaults end

    local appearance = {
        head = normalizeHead(raw.head, defaults.head),
        features = {},
        hair = normalizeHair(raw.hair, defaults.hair),
        eyeColor = clampInt(raw.eyeColor, 0, 5, defaults.eyeColor),
        overlays = normalizeOverlays(raw.overlays, defaults.overlays),
        components = normalizeComponents(raw.components, defaults.components),
        props = normalizeProps(raw.props),
        tattoos = normalizeTattoos(raw.tattoos),
    }

    local features = type(raw.features) == 'table' and raw.features or {}
    for i = 1, S.FACE_FEATURE_COUNT do
        local value = clampNumber(keyed(features, i), -1, 1, keyed(defaults.features, i) or 0)
        appearance.features[i] = math.floor(value * 1000 + 0.5) / 1000
    end

    return appearance
end

-- Retourne l'apparence exploitable d'un personnage, ou nil si le personnage
-- lui-même est invalide.
function S.build(character)
    if type(character) ~= 'table' then return nil end
    local gender = character.gender == 'female' and 'female' or 'male'
    local seed = clampInt(character.seed, 1, 2147483647, 1337)
    local skin = clampInt(character.skin, 0, 4, 0)
    return S.normalize(character.appearance, gender, seed, skin)
end

-- Empreinte courte et déterministe : sert de clé de cache côté client pour
-- réappliquer l'apparence quand un vêtement ou un tatouage change.
function S.key(appearance)
    if type(appearance) ~= 'table' then return 'none' end
    local parts = {}
    local head = appearance.head or {}
    parts[#parts + 1] = table.concat({
        clampInt(head.shapeFirst, 0, 45, 0),
        clampInt(head.shapeSecond, 0, 45, 0),
        math.floor(clampNumber(head.shapeMix, 0, 1, 0) * 1000),
        clampInt(head.skinFirst, 0, 4, 0),
        clampInt(head.skinSecond, 0, 4, 0),
        math.floor(clampNumber(head.skinMix, 0, 1, 0) * 1000),
    }, ',')
    local hair = appearance.hair or {}
    parts[#parts + 1] = table.concat({
        clampInt(hair.drawable, 0, 255, 0),
        clampInt(hair.texture, 0, 99, 0),
        clampInt(hair.color, 0, 63, 0),
        clampInt(hair.highlight, 0, 63, 0),
        clampInt(appearance.eyeColor, 0, 5, 0),
    }, ',')
    local features = appearance.features or {}
    for i = 1, S.FACE_FEATURE_COUNT do
        parts[#parts + 1] = string.format('%.3f', clampNumber(keyed(features, i), -1, 1, 0))
    end
    local overlays = appearance.overlays or {}
    for _, id in ipairs(S.OVERLAY_IDS) do
        local entry = keyed(overlays, id)
        if type(entry) == 'table' and clampInt(entry.index, 0, 99, 0) > 0 then
            parts[#parts + 1] = table.concat({
                id,
                clampInt(entry.index, 0, 99, 0),
                clampInt(entry.color, 0, 63, 0),
                clampInt(entry.highlight, 0, 63, 0),
                math.floor(clampNumber(entry.opacity, 0, 1, 1) * 100),
            }, ',')
        end
    end
    local components = appearance.components or {}
    for _, id in ipairs(S.COMPONENT_IDS) do
        local entry = keyed(components, id)
        if type(entry) == 'table' then
            parts[#parts + 1] = table.concat({
                id,
                clampInt(entry.drawable, 0, 999, 0),
                clampInt(entry.texture, 0, 99, 0),
            }, ',')
        end
    end
    local props = appearance.props or {}
    for id = 0, 13 do
        local entry = keyed(props, id)
        if type(entry) == 'table' then
            parts[#parts + 1] = table.concat({
                'p' .. id,
                clampInt(entry.drawable, -1, 999, -1),
                clampInt(entry.texture, 0, 99, 0),
            }, ',')
        end
    end
    local tattoos = appearance.tattoos or {}
    for i = 1, #tattoos do
        local entry = tattoos[i]
        if type(entry) == 'table' then
            parts[#parts + 1] = tostring(entry.collection) .. '|' .. tostring(entry.overlay)
        end
    end
    return table.concat(parts, ';')
end
