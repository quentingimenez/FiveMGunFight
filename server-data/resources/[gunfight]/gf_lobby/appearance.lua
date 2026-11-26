-- =============================================================================
--  gf_lobby - APPEARANCE (client)
--  Application de l'apparence complète d'un personnage : tête, traits du
--  visage, cheveux, overlays, vêtements, accessoires et tatouages.
--  Le schéma et la génération par défaut vivent dans appearance_schema.lua,
--  partagé avec le serveur pour que les deux côtés valident pareil.
-- =============================================================================

GFLobbyAppearance = GFLobbyAppearance or {}

local Schema = GFLobbyAppearanceSchema

-- Garde de déploiement : une config absente ne doit pas empêcher le client de
-- s'initialiser, mais le schéma est obligatoire pour appliquer une apparence.
if type(Config) ~= 'table' then Config = {} end
if type(Config.PedModels) ~= 'table' then
    Config.PedModels = { male = 'mp_m_freemode_01', female = 'mp_f_freemode_01' }
end
if type(Config.PedModels.male) ~= 'string' or Config.PedModels.male == '' then
    Config.PedModels.male = 'mp_m_freemode_01'
end
if type(Config.PedModels.female) ~= 'string' or Config.PedModels.female == '' then
    Config.PedModels.female = 'mp_f_freemode_01'
end

local FREEMODE_MALE = joaat(Config.PedModels.male)
local FREEMODE_FEMALE = joaat(Config.PedModels.female)

local function clampNumber(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number or number ~= number then return fallback end
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

local function validPed(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local model = GetEntityModel(ped)
    return model == FREEMODE_MALE or model == FREEMODE_FEMALE
end

local function drawableCount(ped, component)
    local ok, count = pcall(GetNumberOfPedDrawableVariations, ped, component)
    if not ok or type(count) ~= 'number' or count < 0 then return 0 end
    return count
end

local function textureCount(ped, component, drawable)
    local ok, count = pcall(GetNumberOfPedTextureVariations, ped, component, drawable)
    if not ok or type(count) ~= 'number' or count < 0 then return 0 end
    return count
end

local function propDrawableCount(ped, prop)
    local ok, count = pcall(GetNumberOfPedPropDrawableVariations, ped, prop)
    if not ok or type(count) ~= 'number' or count < 0 then return 0 end
    return count
end

local function propTextureCount(ped, prop, drawable)
    local ok, count = pcall(GetNumberOfPedPropTextureVariations, ped, prop, drawable)
    if not ok or type(count) ~= 'number' or count < 0 then return 0 end
    return count
end

-- Applique un composant en bornant le drawable et la texture aux variations
-- réellement présentes sur le ped. Ne touche pas au composant 2 (cheveux).
local function setComponent(ped, component, entry)
    if type(entry) ~= 'table' then return end
    local count = drawableCount(ped, component)
    if count <= 0 then return end
    local drawable = math.floor(clampNumber(entry.drawable, 0, count - 1, 0))
    local textures = textureCount(ped, component, drawable)
    local texture = 0
    if textures > 0 then
        texture = math.floor(clampNumber(entry.texture, 0, textures - 1, 0))
    end
    SetPedComponentVariation(ped, component, drawable, texture, 0)
end

local function setProp(ped, prop, entry)
    if type(entry) ~= 'table' then
        ClearPedProp(ped, prop)
        return
    end
    local preferred = math.floor(clampNumber(entry.drawable, -1, 999, -1))
    if preferred < 0 then
        ClearPedProp(ped, prop)
        return
    end
    local count = propDrawableCount(ped, prop)
    if count <= 0 then
        ClearPedProp(ped, prop)
        return
    end
    local drawable = math.min(preferred, count - 1)
    local textures = propTextureCount(ped, prop, drawable)
    local texture = 0
    if textures > 0 then
        texture = math.floor(clampNumber(entry.texture, 0, textures - 1, 0))
    end
    SetPedPropIndex(ped, prop, drawable, texture, true)
end

-- Applique une apparence sur un ped déjà au bon modèle freemode.
-- Retourne false sans exception si le ped, le modèle ou le personnage est
-- invalide. Ne change jamais le modèle du ped.
function GFLobbyAppearance.apply(ped, character)
    if not validPed(ped) then return false end
    if not Schema or type(Schema.build) ~= 'function' then return false end

    local appearance = Schema.build(character)
    if not appearance then return false end

    -- Reset cosmétique : variations par défaut puis nettoyage des props.
    SetPedDefaultComponentVariation(ped)
    ClearPedDecorations(ped)
    ClearPedDecorationsLeaveScars(ped)
    RemoveAllPedWeapons(ped, true)
    ClearPedBloodDamage(ped)

    for prop = 0, 13 do
        ClearPedProp(ped, prop)
    end

    local head = appearance.head or {}
    SetPedHeadBlendData(
        ped,
        math.floor(clampNumber(head.shapeFirst, 0, 45, 0)),
        math.floor(clampNumber(head.shapeSecond, 0, 45, 0)),
        0,
        math.floor(clampNumber(head.skinFirst, 0, 4, 0)),
        math.floor(clampNumber(head.skinSecond, 0, 4, 0)),
        0,
        clampNumber(head.shapeMix, 0.0, 1.0, 0.0),
        clampNumber(head.skinMix, 0.0, 1.0, 0.0),
        0.0,
        false
    )
    SetPedEyeColor(ped, math.floor(clampNumber(appearance.eyeColor, 0, 5, 0)))

    local features = appearance.features or {}
    for index = 0, 19 do
        SetPedFaceFeature(ped, index, clampNumber(features[index + 1], -1.0, 1.0, 0.0))
    end

    -- Cheveux : composant 2, texture et couleur.
    local hair = appearance.hair or {}
    local hairCount = drawableCount(ped, 2)
    if hairCount > 0 then
        local drawable = math.floor(clampNumber(hair.drawable, 0, hairCount - 1, 0))
        local hairTextures = textureCount(ped, 2, drawable)
        local texture = 0
        if hairTextures > 0 then
            texture = math.floor(clampNumber(hair.texture, 0, hairTextures - 1, 0))
        end
        SetPedComponentVariation(ped, 2, drawable, texture, 0)
    end
    local hairColor = math.floor(clampNumber(hair.color, 0, 63, 0))
    local hairHighlight = math.floor(clampNumber(hair.highlight, 0, 63, 0))
    SetPedHairColor(ped, hairColor, hairHighlight)

    -- Overlays du visage (barbe, sourcils, maquillage, rougeurs...).
    local overlays = appearance.overlays or {}
    for overlay = 0, 12 do
        local entry = overlays[overlay]
        if type(entry) == 'table' then
            local index = math.floor(clampNumber(entry.index, 0, 99, 0))
            if index > 0 then
                SetPedHeadOverlay(ped, overlay, index, clampNumber(entry.opacity, 0.0, 1.0, 1.0))
                SetPedHeadOverlayColor(
                    ped,
                    overlay,
                    math.floor(clampNumber(entry.colorType, 0, 2, 0)),
                    math.floor(clampNumber(entry.color, 0, 63, 0)),
                    math.floor(clampNumber(entry.highlight, 0, 63, 0))
                )
            else
                SetPedHeadOverlay(ped, overlay, 0, 0.0)
            end
        else
            SetPedHeadOverlay(ped, overlay, 0, 0.0)
        end
    end

    -- Vêtements et accessoires portés sur le corps.
    local components = appearance.components or {}
    for _, component in ipairs(Schema.COMPONENT_IDS) do
        setComponent(ped, component, components[component])
    end
    local props = appearance.props or {}
    for prop = 0, 13 do
        setProp(ped, prop, props[prop])
    end

    -- Tatouages : les décorations sont posées après les vêtements pour que
    -- les overlays de peau restent visibles sur les zones découvertes.
    ClearPedDecorations(ped)
    local tattoos = appearance.tattoos or {}
    for i = 1, #tattoos do
        local entry = tattoos[i]
        if type(entry) == 'table'
            and type(entry.collection) == 'string'
            and type(entry.overlay) == 'string' then
            AddPedDecorationFromHashes(ped, joaat(entry.collection), joaat(entry.overlay))
        end
    end

    return true
end

-- Compatibilité avec l'ancienne API : renvoie l'apparence complète calculée.
function GFLobbyAppearance.build(character)
    if not Schema or type(Schema.build) ~= 'function' then return nil end
    return Schema.build(character)
end

exports('GetLobbyAppearance', function()
    return GFLobbyAppearance
end)
