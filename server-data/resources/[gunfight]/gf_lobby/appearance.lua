-- =============================================================================
--  gf_lobby - APPEARANCE (client)
--  Génération déterministe et application de l'apparence d'un personnage.
--  Un même seed + genre + carnation donne toujours le même rendu sur tous
--  les clients. Aucune dépendance, aucun événement, aucun état global aléatoire.
-- =============================================================================

GFLobbyAppearance = GFLobbyAppearance or {}

-- Ce fichier est chargé avant client.lua : même garde de déploiement, sinon
-- une config partagée absente empêche tout le script client de s'initialiser.
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

-- Hashes calculés au chargement depuis la config partagée : pas de hash figé.
local FREEMODE_MALE = joaat(Config.PedModels.male)     -- mp_m_freemode_01
local FREEMODE_FEMALE = joaat(Config.PedModels.female) -- mp_f_freemode_01

-- Modulo 2^31 : garde l'état LCG positif et dans les bornes 32 bits signées.
local LCG_MOD = 2147483648
local LCG_A = 1103515245
local LCG_C = 12345

-- Palettes de carnation : indices parents freemode (0..4), bornés avant usage.
local SKIN_PARENT = {
    { first = 0, second = 1, mix = 0.0 }, -- claire
    { first = 1, second = 2, mix = 0.3 }, -- hâlée
    { first = 2, second = 3, mix = 0.5 }, -- dorée
    { first = 3, second = 4, mix = 0.7 }, -- brune
    { first = 4, second = 4, mix = 1.0 }, -- sombre
}

-- ---------------------------------------------------------------- Utilitaires

local function clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

-- Entier à partir d'une valeur Lua (nombre ou chaîne numérique). Retourne nil
-- si la valeur n'est pas un entier exploitable.
local function toInteger(value)
    local t = type(value)
    if t == 'number' then
        if value ~= value or value < -math.huge or value > math.huge then return nil end
        if value % 1 ~= 0 then return nil end
        return math.tointeger(value) or math.floor(value)
    elseif t == 'string' then
        if not value:match('^%-?%d+$') then return nil end
        return tonumber(value)
    end
    return nil
end

-- Mélange déterministe des entrées dans un état 32 bits.
local function hashInputs(seed, female, skin)
    local h = seed % LCG_MOD
    h = (h * 2654435761) % LCG_MOD           -- Knuth multiplicative hash
    h = (h + (female and 1229 or 314159)) % LCG_MOD
    h = (h * 40503 + (skin * 7919)) % LCG_MOD
    return math.floor(h) % LCG_MOD
end

-- Générateur local : ne touche jamais à math.random (état global partagé).
local function newRandom(seed, female, skin)
    local state = hashInputs(seed, female, skin)
    local r = {}
    function r.next()
        state = (state * LCG_A + LCG_C) % LCG_MOD
        return state / LCG_MOD               -- flottant dans [0, 1)
    end
    function r.int(maxValue)
        if maxValue <= 1 then return 0 end
        return math.floor(r.next() * maxValue) % maxValue
    end
    return r
end

-- Vérifie le personnage : table + seed entier 1..2147483647 + genre + carnation.
-- Retourne female (booléen), seed, skin ; nil si invalide.
local function validateCharacter(character)
    if type(character) ~= 'table' then return nil end
    local seed = toInteger(character.seed)
    if not seed or seed < 1 or seed > 2147483647 then return nil end
    local gender = character.gender
    if gender ~= 'male' and gender ~= 'female' then return nil end
    local skin = toInteger(character.skin)
    if not skin or skin < 0 or skin > 4 then return nil end
    return gender == 'female', seed, skin
end

-- Vérifie le ped : existant, modèle freemode. Retourne false sinon.
-- HasModelLoaded n'est pas exigé ici : après SetPlayerModel le modèle peut être
-- marqué « plus nécessaire » alors que le ped est déjà au bon modèle ; exiger
-- le chargement ferait échouer l'apparence (personnage sans style).
local function validPed(ped)
    if not ped or ped == 0 or ped == nil then return false end
    if not DoesEntityExist(ped) then return false end
    local model = GetEntityModel(ped)
    if model ~= FREEMODE_MALE and model ~= FREEMODE_FEMALE then return false end
    return true
end

-- Compte les variations d'un composant ; 0 si le natif échoue.
local function drawableCount(ped, component)
    local count = GetNumberOfPedDrawableVariations(ped, component)
    if type(count) ~= 'number' or count < 0 then return 0 end
    return math.floor(count)
end

-- Compte les textures d'un drawable ; 0 si le natif échoue.
local function textureCount(ped, component, drawable)
    local count = GetNumberOfPedTextureVariations(ped, component, drawable)
    if type(count) ~= 'number' or count < 0 then return 0 end
    return math.floor(count)
end

-- ------------------------------------------------------------ Calcul (sans ped)

-- Construit la description déterministe de l'apparence, sans toucher au ped.
-- Utilisé par build() et repris tel quel par apply() pour garantir l'identité
-- entre aperçu et rendu final.
local function computeAppearance(seed, female, skin)
    local r = newRandom(seed, female, skin)

    -- Variantes de style : chaque seed de la NUI (1000, 1997, 2994, 3991)
    -- tire des indices différents grace au LCG, sans table figee de drawables.
    local outfit = {
        torso = r.int(6),
        legs = r.int(8),
        shoes = r.int(7),
        undershirt = r.int(5),
        top = r.int(12),
        hair = r.int(18),
        hairColor = r.int(12),
        eyeColor = r.int(6),
        eyebrow = r.int(11),
        eyebrowColor = r.int(12),
        facialHair = r.int(5),
    }

    local skinData = SKIN_PARENT[skin + 1]
    local blend = {
        shapeFirst = r.int(20),
        shapeSecond = r.int(20),
        shapeMix = r.next(),
        skinFirst = skinData.first,
        skinSecond = skinData.second,
        skinMix = skinData.mix,
        thirdMix = 0.0,
    }

    return {
        seed = seed,
        gender = female and 'female' or 'male',
        skin = skin,
        outfit = outfit,
        blend = blend,
    }
end

-- ------------------------------------------------------------------- Interface

-- Retourne la description déterministe calculée, ou nil si le personnage est
-- invalide. Ne touche jamais au ped : sert aux aperçus et aux tests.
function GFLobbyAppearance.build(character)
    local female, seed, skin = validateCharacter(character)
    -- Echec : validateCharacter ne retourne rien (seed nil). female=false est
    -- un succes valide (personnage masculin).
    if not seed then return nil end
    return computeAppearance(seed, female, skin)
end

-- Applique l'apparence sur un ped déjà au bon modèle freemode.
-- Retourne false sans exception si le ped, le modèle ou le personnage est
-- invalide. Ne change jamais le modèle du ped.
function GFLobbyAppearance.apply(ped, character)
    if not validPed(ped) then return false end

    local female, seed, skin = validateCharacter(character)
    if not seed then return false end

    local appearance = computeAppearance(seed, female, skin)
    local outfit = appearance.outfit
    local blend = appearance.blend

    -- Reset cosmétique : variations par défaut puis nettoyage des props.
    SetPedDefaultComponentVariation(ped)
    ClearPedDecorations(ped)
    ClearPedDecorationsLeaveScars(ped)
    RemoveAllPedWeapons(ped, true)

    -- Props (chapeau, masque, sac, gilet, décalques...).
    for _, slot in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }) do
        if IsPedComponentVariationValid(ped, slot, 0, 0) then
            SetPedComponentVariation(ped, slot, 0, 0, 0)
        end
    end
    for _, prop in ipairs({ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 }) do
        local count = GetNumberOfPedPropDrawableVariations(ped, prop)
        if count and count > 0 then
            ClearPedProp(ped, prop)
        end
    end
    ClearPedBloodDamage(ped)

    -- Tête cohérente : parents et mélanges bornés dans les plages natives.
    SetPedHeadBlendData(
        ped,
        clamp(blend.shapeFirst, 0, 45),
        clamp(blend.shapeSecond, 0, 45),
        0,
        clamp(blend.skinFirst, 0, 4),
        clamp(blend.skinSecond, 0, 4),
        0,
        clamp(blend.shapeMix, 0.0, 1.0),
        clamp(blend.skinMix, 0.0, 1.0),
        clamp(blend.thirdMix, 0.0, 1.0),
        false
    )
    SetPedEyeColor(ped, clamp(outfit.eyeColor, 0, 5))

    -- Tenue : chaque drawable/texture est borné sur les variations réelles du
    -- modèle avant l'appel natif, pour ne jamais transmettre un index invalide.
    local function setComponent(component, preferred)
        local count = drawableCount(ped, component)
        if count <= 0 then return end
        local drawable = clamp(preferred, 0, count - 1)
        local textures = textureCount(ped, component, drawable)
        if textures <= 0 then textures = 1 end
        local texture = clamp(preferred % textures, 0, textures - 1)
        SetPedComponentVariation(ped, component, drawable, texture, 0)
    end

    -- Cheveux : composant 2, couleur via SetPedHairColor.
    setComponent(2, outfit.hair)
    SetPedHairColor(ped, clamp(outfit.hairColor, 0, 63), clamp(outfit.hairColor, 0, 63))

    -- Sourcils et barbe légers (femme : pas de barbe visible).
    SetPedHeadOverlay(ped, 2, clamp(outfit.eyebrow, 0, 10), 1.0)
    SetPedHeadOverlayColor(ped, 2, 1, clamp(outfit.eyebrowColor, 0, 63), 0)
    if not female then
        local beard = clamp(outfit.facialHair, 0, 4)
        SetPedHeadOverlay(ped, 1, beard, beard > 0 and 0.6 or 0.0)
        if beard > 0 then
            SetPedHeadOverlayColor(ped, 1, 1, clamp(outfit.hairColor, 0, 63), 0)
        end
    else
        SetPedHeadOverlay(ped, 1, 0, 0.0)
    end

    setComponent(3, outfit.torso)       -- torse / armures
    setComponent(4, outfit.legs)        -- jambes
    setComponent(6, outfit.shoes)       -- chaussures
    setComponent(8, outfit.undershirt)  -- sous-vêtement
    setComponent(11, outfit.top)        -- haut

    return true
end

-- Export via le mécanisme FiveM : disponible aussi pour les autres ressources.
exports('GetLobbyAppearance', function()
    return GFLobbyAppearance
end)
