-- =============================================================================
--  gf_lobby - CLIENT
--  Présentation du lobby : état local, placement des peds, caméra scriptée,
--  protocole NUI et chien de garde. Le serveur reste l'autorité : ce fichier ne
--  sauvegarde rien et ne téléporte jamais un autre joueur.
-- =============================================================================

local RESOURCE = 'gf_lobby'
local WATCHDOG_MS = 15000
local RETRY_INTERVAL_MS = 2000
local RETRY_MAX = 8   -- ~15 s (8 × 2 s)

-- Garde de déploiement : si `shared_script 'config.lua'` manque sur une
-- installation, le client doit quand même charger ses callbacks. Sans ça,
-- une erreur ici empêche `RegisterNUICallback` et toute la NUI reste morte.
local configLoaded = type(Config) == 'table' and type(Config.Stage) == 'table'
if type(Config) ~= 'table' then Config = {} end
if type(Config.PedModels) ~= 'table' then
    Config.PedModels = { male = 'mp_m_freemode_01', female = 'mp_f_freemode_01' }
end
if type(Config.Character) ~= 'table' then
    Config.Character = { nameMin = 3, nameMax = 20, skins = 5 }
end
if type(Config.Stage) ~= 'table' then Config.Stage = {} end
Config.Stage.x = Config.Stage.x or 0.0
Config.Stage.y = Config.Stage.y or 0.0
Config.Stage.z = Config.Stage.z or 1000.0
Config.Stage.heading = Config.Stage.heading or 0.0
Config.Stage.spacing = Config.Stage.spacing or 1.45
if type(Config.Stage.camera) ~= 'table' then Config.Stage.camera = {} end
local cameraDefaults = {
    baseDistance = 4.4, distancePerMember = 0.95, height = 1.52, fov = 42.0,
    creatorDistance = 4.2, creatorOffset = 0.0, creatorFov = 40.0,
    creatorHeight = 1.45, creatorLookOffset = 0.0,
}
for key, value in pairs(cameraDefaults) do
    Config.Stage.camera[key] = Config.Stage.camera[key] or value
end

print(('[gf_lobby] client chargé (config %s)'):format(configLoaded and 'partagée' or 'locale de secours'))

-- ---------------------------------------------------------------- État local
local inLobby = false
local state = nil            -- dernier gf_lobby:state reçu
local nuiReady = false       -- callback `ready` reçu
local lastNuiSeen = 0        -- dernier ready/heartbeat (GetGameTimer)
local uiSuspended = false    -- interface relâchée par le chien de garde

local cam = nil
local camPos = nil           -- vector3, position interpolée
local camLook = nil          -- vector3, point de visée interpolé
local camFov = Config.Stage.camera.fov
local camTargetPos = nil
local camTargetLook = nil
local camTargetFov = Config.Stage.camera.fov

local lastAppearanceSeed = nil  -- seed du ped local pour éviter les reapplications
local remoteAppearance = {}     -- [ped] = clé d'apparence déjà appliquée
local previewCharacter = nil    -- aperçu local, jamais sauvegardé
local stateRetryActive = false  -- boucle de récupération de gf_lobby:state
local editing = false           -- éditeur ouvert depuis l'onglet Personnage
local creatorMode = 'create'    -- 'create' ou 'edit'
local catalogCache = {}         -- [gender] = variations réellement installées
local lastCatalogGender = nil   -- évite de renvoyer le catalogue à chaque aperçu
local previewAngleOffset = 0    -- rotation demandée par la NUI (face/profil/dos)

-- Fond de scène : une image fixe derrière le ped. La NUI est dessinée devant le
-- jeu, une image CSS cacherait donc le personnage : l'image est une texture
-- runtime dessinée chaque frame sur un plan 3D face à la caméra, juste derrière
-- la scène (géométrie dans backdrop.lua).
local BACKDROP_TXD = 'gf_lobby_backdrop'
local BACKDROP_TEXTURE = 'image'
local BACKDROP_IMAGE = 'img/backdrop.jpg' -- déclarée dans `files` (fxmanifest)
local BACKDROP_DEPTH = 1.0                -- mètres derrière la scène, le long de l'axe caméra
local BACKDROP_MARGIN = 1.1               -- le plan déborde de 10 % du champ de la caméra
-- Ligne de sol de l'image : rangée 1116 sur 1440 (ligne claire mesurée dans
-- img/backdrop.jpg). Les caméras posent les pieds dessus.
local BACKDROP_FLOOR_V = 1116 / 1440
-- DRAW_TEXTURED_POLY, appelée par son hash : c'est la forme vérifiée en jeu.
local DRAW_TEXTURED_POLY = 0x29280002282F1928
-- Hauteur de la racine du ped au-dessus de ses semelles, debout : 1,031 m
-- mesuré en jeu (GetEntityHeightAboveGround, mp_m_freemode_01, scène du lobby).
local PED_ROOT_ABOVE_FEET = 1.03
local backdropReady = nil   -- nil : texture pas encore créée ; sinon succès de la création
local backdropActive = false
local backdropGeneration = 0

-- ---------------------------------------------------------------- Utilitaires
local function now()
    return GetGameTimer()
end

local function touchNui()
    lastNuiSeen = now()
    uiSuspended = false
end

local function notify(message, level)
    TriggerEvent('gf_ui:notify', { text = message, level = level })
end

-- Enveloppe unique Lua → NUI (§5.2).
local function sendUi(kind, data)
    SendNUIMessage({ type = kind, data = data or {} })
end

local function validGender(gender)
    return gender == 'male' or gender == 'female'
end

local function clamp(value, lo, hi, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    if value < lo then return lo end
    if value > hi then return hi end
    return math.floor(value)
end

-- Validation locale d'un personnage : types et bornes avant tout envoi serveur.
-- L'apparence complète est normalisée par le schéma partagé, qui retombe sur
-- les valeurs par défaut du seed quand elle manque (personnages v1).
local function normalizeCharacter(data)
    if type(data) ~= 'table' then return nil end
    if not validGender(data.gender) then return nil end
    local skins = (Config.Character and Config.Character.skins) or 5
    local seed = clamp(data.seed, 1, 2147483647, nil)
    local skin = clamp(data.skin, 0, skins - 1, nil)
    if not seed or not skin then return nil end
    local character = { gender = data.gender, seed = seed, skin = skin }
    if type(GFLobbyAppearanceSchema) == 'table'
        and type(GFLobbyAppearanceSchema.normalize) == 'function' then
        character.appearance = GFLobbyAppearanceSchema.normalize(
            data.appearance, data.gender, seed, skin
        )
    end
    return character
end

-- Nom : longueur, caractères de contrôle, espaces consécutifs (§7, §5.1).
local function normalizeName(value)
    if type(value) ~= 'string' then return nil end
    local name = value:gsub('[%z\1-\31\127]', '')
    name = name:gsub('%s+', ' ')
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    local lo = (Config.Character and Config.Character.nameMin) or 3
    local hi = (Config.Character and Config.Character.nameMax) or 20
    local length = utf8.len(name)
    if not length or length < lo or length > hi then return nil end
    return name
end

-- ---------------------------------------------------------------- Modèle ped
local function loadModel(hash)
    if not hash then return false end
    RequestModel(hash)
    local timeout = now() + 5000
    while not HasModelLoaded(hash) and now() < timeout do
        Wait(0)
    end
    if not HasModelLoaded(hash) then return false end
    return true
end

local function modelFor(gender)
    local name = Config.PedModels and Config.PedModels[gender]
    if not name then return nil end
    return joaat(name)
end

-- Change uniquement le modèle du ped local (jamais celui d'un autre joueur).
local function applyLocalModel(gender)
    local hash = modelFor(gender)
    if not hash then return false end
    local ped = PlayerPedId()
    if GetEntityModel(ped) == hash then
        SetEntityVisible(ped, true, false)
        return true
    end
    if not loadModel(hash) then return false end
    SetPlayerModel(PlayerId(), hash)
    -- Laisser un tick au moteur pour installer le nouveau ped avant de toucher
    -- ses variations ; sinon SetPedDefaultComponentVariation vise l'ancien ped.
    Wait(0)
    ped = PlayerPedId()
    SetPedDefaultComponentVariation(ped)
    SetEntityVisible(ped, true, false)
    SetModelAsNoLongerNeeded(hash)
    lastAppearanceSeed = nil -- le ped a changé : applique l'apparence à nouveau
    return true
end

local function applyAppearance(ped, character)
    if not GFLobbyAppearance or type(GFLobbyAppearance.apply) ~= 'function' then
        return false
    end
    local ok, result = pcall(GFLobbyAppearance.apply, ped, character)
    if not ok then
        print(('[gf_lobby] GFLobbyAppearance.apply: %s'):format(tostring(result)))
        return false
    end
    return result ~= false
end

-- Clé de cache de l'apparence : seed/genre/carnation pour les personnages v1,
-- plus une empreinte complète pour propager vêtements et tatouages.
local function appearanceKey(character)
    if type(character) ~= 'table' then return 'none' end
    local key = ('%s:%s:%s'):format(
        tostring(character.gender), tostring(character.seed), tostring(character.skin)
    )
    if type(GFLobbyAppearanceSchema) == 'table'
        and type(GFLobbyAppearanceSchema.key) == 'function' then
        key = key .. ':' .. GFLobbyAppearanceSchema.key(character.appearance)
    end
    return key
end

-- Catalogue des variations réellement installées sur le modèle courant. La NUI
-- ne devine jamais les maxima : elle reçoit les comptes de drawables, de
-- textures et d'overlays, sinon elle proposerait des choix invisibles ou
-- invalides selon les DLC présents sur le serveur.
local function collectCatalog(gender)
    if catalogCache[gender] then return catalogCache[gender] end
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end

    local catalog = {
        components = {},
        props = {},
        overlays = {},
        hairColors = 64,
        makeupColors = 64,
        features = 20,
    }
    for component = 1, 11 do
        local count = GetNumberOfPedDrawableVariations(ped, component) or 0
        local textures = {}
        for drawable = 0, count - 1 do
            textures[#textures + 1] = GetNumberOfPedTextureVariations(ped, component, drawable) or 0
        end
        catalog.components[tostring(component)] = { count = count, textures = textures }
    end
    for _, prop in ipairs({ 0, 1, 2, 6, 7 }) do
        local count = GetNumberOfPedPropDrawableVariations(ped, prop) or 0
        local textures = {}
        for drawable = 0, count - 1 do
            textures[#textures + 1] = GetNumberOfPedPropTextureVariations(ped, prop, drawable) or 0
        end
        catalog.props[tostring(prop)] = { count = count, textures = textures }
    end
    for overlay = 0, 12 do
        catalog.overlays[tostring(overlay)] = GetNumHeadOverlayValues(overlay) or 0
    end
    catalogCache[gender] = catalog
    return catalog
end

local function sendCatalog(gender)
    local catalog = collectCatalog(gender)
    if catalog then sendUi('creatorCatalog', catalog) end
end

-- ---------------------------------------------------------------- Scène (§6.3)
local function stageBasis()
    local s = Config.Stage
    local rad = math.rad(s.heading or 0.0)
    local forward = vector3(-math.sin(rad), math.cos(rad), 0.0)
    local right = vector3(math.cos(rad), math.sin(rad), 0.0)
    local origin = vector3(s.x + 0.0, s.y + 0.0, s.z + 0.0)
    return origin, forward, right
end

local function slotOffset(slot, count)
    if not count or count < 1 then return 0.0 end
    local i = clamp(slot, 1, count, 1)
    return (i - (count + 1) / 2) * (Config.Stage.spacing or 1.45)
end

-- Dernière place donnée au ped, rejouée sans attendre après un spawn de gf_core.
local placedSlot, placedCount = nil, nil

local function placeSelfOnSlot(slot, count)
    -- Un état gf_lobby:state retardé peut arriver pendant le spawn d'un autre
    -- mode : ne pas forcer visibilité/collision/gel du ped dans ce cas.
    -- Au boot gf_mode est nil : on laisse passer pour initialiser le lobby.
    local mode = LocalPlayer.state and LocalPlayer.state.gf_mode
    if mode and mode ~= 'lobby' then return end
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local origin, _, right = stageBasis()
    local offset = slotOffset(slot, count)
    local x = origin.x + right.x * offset
    local y = origin.y + right.y * offset
    local z = origin.z

    -- La scène est dans le vide : aucun sol ne porte le ped, seul le gel le
    -- maintient à Config.Stage.z (altitude de sa racine).
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    ClearPedTasksImmediately(ped)
    SetEntityHeading(ped, (Config.Stage.heading or 0.0) + 0.0)
    -- gf_core peut laisser le ped invisible (spectateur) : le lobby doit toujours
    -- montrer le personnage, sinon le joueur ne voit rien ni dans le menu ni en 3D.
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    placedSlot, placedCount = slot, count
end

-- Applique l'apparence encapsulée des autres membres à leur ped local quand il
-- existe dans notre bucket. Aucun déplacement, aucun changement de modèle.
-- On associe les peds proches par distance au slot attendu : le bucket isolant
-- l'escouade, seuls ses membres sont en scène et la même seed donne le même
-- rendu sur tous les clients.
local function applyRemoteAppearances(currentState)
    if not currentState or type(currentState.party) ~= 'table' then return end
    local members = currentState.party.members
    if type(members) ~= 'table' then return end
    for knownPed in pairs(remoteAppearance) do
        if not DoesEntityExist(knownPed) then remoteAppearance[knownPed] = nil end
    end
    local myId = currentState.me and currentState.me.id
    local origin, _, right = stageBasis()

    local nearby = {}
    local used = {}
    local handle, ped = FindFirstPed()
    local ok = handle and handle ~= 0
    while ok do
        if ped and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped)
            and IsPedAPlayer(ped) and ped ~= PlayerPedId() then
            local coords = GetEntityCoords(ped)
            if #(coords - origin) < 12.0 then
                nearby[#nearby + 1] = ped
            end
        end
        local success, nextPed = FindNextPed(handle)
        ok = success and nextPed ~= nil and nextPed ~= 0
        ped = nextPed
    end
    if handle and handle ~= 0 then EndFindPed(handle) end

    for _, member in pairs(members) do
        if type(member) == 'table' and member.id ~= myId then
            local character = member.character
            if type(character) == 'table' and validGender(character.gender) then
                local slotPos = origin + right * slotOffset(member.slot, #members)
                local best, bestDist = nil, 2.0
                for _, pedHandle in ipairs(nearby) do
                    if not used[pedHandle] and DoesEntityExist(pedHandle) then
                        local dist = #(GetEntityCoords(pedHandle) - slotPos)
                        if dist < bestDist then best, bestDist = pedHandle, dist end
                    end
                end
                if best then
                    -- Ped distant : le modèle peut encore se charger. Sans cette
                    -- garde on appliquerait une apparence incomplète et on
                    -- cacheerait la clé, empêchant le retry 3 s de corriger.
                    -- Le ped local n'est pas concerné (déjà au bon modèle après
                    -- SetPlayerModel, où HasModelLoaded peut être faux).
                    if HasModelLoaded(GetEntityModel(best)) then
                        used[best] = true
                        local key = appearanceKey(character)
                        if remoteAppearance[best] ~= key then
                            if applyAppearance(best, character) then
                                remoteAppearance[best] = key
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Les peds distants peuvent arriver après le premier state : on retente
-- périodiquement, le cache évitant de réappliquer une apparence identique.
CreateThread(function()
    while true do
        Wait(3000)
        if inLobby and not uiSuspended and state and state.me and state.me.character
            and state.party and type(state.party.members) == 'table'
            and #state.party.members > 1 then
            applyRemoteAppearances(state)
        end
    end
end)

-- ---------------------------------------------------------------- Caméra (§8)
local function setCameraTargets(pos, look, fov)
    camTargetPos = pos
    camTargetLook = look
    camTargetFov = fov
    if not camPos then camPos = vector3(pos.x, pos.y, pos.z) end
    if not camLook then camLook = vector3(look.x, look.y, look.z) end
    -- Placement immédiat : sans ça la première frame montre l'origine du monde
    -- (fond noir) avant que le thread d'interpolation n'ait tourné.
    if cam and DoesCamExist(cam) then
        SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
        PointCamAtCoord(cam, camLook.x, camLook.y, camLook.z)
        SetCamFov(cam, camFov)
    end
end

-- Origine de la scène à l'altitude des pieds du ped. SetEntityCoordsNoOffset
-- place la racine du ped (au bassin) à Config.Stage.z : la caméra et le fond
-- se calent sur les pieds, sinon le cadre monte d'autant et coupe le bas du
-- corps. Le bas de GetModelDimensions ne convient pas : il descend 0,27 m sous
-- les semelles.
local function groundOrigin()
    local origin, forward, right = stageBasis()
    return vector3(origin.x, origin.y, origin.z - PED_ROOT_ABOVE_FEET), forward, right
end

-- Hauteur de regard qui pose les pieds sur la ligne de sol de l'image de fond,
-- pour une caméra `height` au-dessus des pieds et `distance` devant eux.
local function floorLookHeight(height, distance, fov)
    local screenY = GFLobbyBackdrop.floorScreenY(BACKDROP_FLOOR_V, BACKDROP_MARGIN)
    return GFLobbyBackdrop.lookHeight(height, distance, fov, screenY) or 0.0
end

-- ---------------------------------------------------------------- Fond de scène
-- Crée la texture une seule fois. Le premier argument de
-- CreateRuntimeTextureFromImage est le handle renvoyé par CreateRuntimeTxd :
-- lui passer le nom du dictionnaire provoque « invalid handle ».
local function ensureBackdropTexture()
    if backdropReady ~= nil then return backdropReady end
    local ok, texture = pcall(function()
        local txd = CreateRuntimeTxd(BACKDROP_TXD)
        return CreateRuntimeTextureFromImage(txd, BACKDROP_TEXTURE, BACKDROP_IMAGE)
    end)
    backdropReady = ok and texture ~= nil and texture ~= 0
    if not backdropReady then
        print(('[gf_lobby] fond : texture %s indisponible (%s)'):format(BACKDROP_IMAGE, tostring(texture)))
    end
    return backdropReady
end

local function drawBackdrop()
    if not camPos or not camLook then return end
    local quad = GFLobbyBackdrop.quad(camPos, camLook, camFov, GetAspectRatio(false),
        groundOrigin(), BACKDROP_DEPTH, BACKDROP_MARGIN)
    if not quad then return end
    for _, t in ipairs(GFLobbyBackdrop.triangles(quad)) do
        local a, b, c = t[1], t[2], t[3]
        Citizen.InvokeNative(DRAW_TEXTURED_POLY,
            a.p.x, a.p.y, a.p.z, b.p.x, b.p.y, b.p.z, c.p.x, c.p.y, c.p.z,
            255, 255, 255, 255, BACKDROP_TXD, BACKDROP_TEXTURE,
            a.u, a.v, 1.0, b.u, b.v, 1.0, c.u, c.v, 1.0)
    end
end

-- Dessine le fond chaque frame tant que la scène est présentée. Le numéro de
-- génération empêche deux boucles de coexister après un arrêt suivi d'une
-- reprise dans la même frame.
local function startBackdrop()
    if backdropActive or not ensureBackdropTexture() then return end
    backdropActive = true
    backdropGeneration = backdropGeneration + 1
    local generation = backdropGeneration
    CreateThread(function()
        while backdropActive and generation == backdropGeneration do
            drawBackdrop()
            Wait(0)
        end
    end)
end

local function stopBackdrop()
    backdropActive = false
end

local function groupCameraTargets(count)
    local s = Config.Stage
    local c = s.camera or {}
    local origin, forward = groundOrigin()
    local n = math.max(1, count or 1)
    local distance = (c.baseDistance or 4.4) + (n - 1) * (c.distancePerMember or 0.95)
    local height = c.height or 1.52
    local fov = c.fov or 42.0
    local pos = origin + forward * distance + vector3(0.0, 0.0, height)
    local look = origin + vector3(0.0, 0.0, floorLookHeight(height, distance, fov))
    return pos, look, fov
end

local function creatorCameraTargets()
    local c = Config.Stage.camera or {}
    local origin, forward, right = groundOrigin()
    local distance = c.creatorDistance or 4.2
    local height = c.creatorHeight or c.height or 1.45
    local fov = c.creatorFov or 40.0
    local pos = origin + forward * distance
        + right * (c.creatorOffset or 0.0)
        + vector3(0.0, 0.0, height)
    -- Vue de face, centrée sur la colonne de scène de la NUI.
    local look = origin - right * (c.creatorLookOffset or 0.0)
        + vector3(0.0, 0.0, floorLookHeight(height, distance, fov))
    return pos, look, fov
end

local function ensureCamera()
    if cam and DoesCamExist(cam) then return true end
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not cam then return false end
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    return true
end

local function destroyCamera()
    if cam and DoesCamExist(cam) then
        SetCamActive(cam, false)
        DestroyCam(cam, false)
    end
    cam = nil
    camPos, camLook = nil, nil
    camTargetPos, camTargetLook = nil, nil
    RenderScriptCams(false, false, 0, true, true)
end

-- Seul thread de caméra : tourne en continu mais ne travaille que si une
-- caméra existe. Wait(0) uniquement quand il y a quelque chose à interpoler.
CreateThread(function()
    while true do
        if cam and DoesCamExist(cam) and camTargetPos and camTargetLook then
            local frame = GetFrameTime() or 0.0
            local alpha = 1.0 - 0.88 ^ (math.max(frame, 0.0) * 60.0)
            if alpha < 0.02 then alpha = 0.02 end
            if alpha > 1.0 then alpha = 1.0 end

            camPos = camPos + (camTargetPos - camPos) * alpha
            camLook = camLook + (camTargetLook - camLook) * alpha
            camFov = camFov + (camTargetFov - camFov) * alpha

            SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
            PointCamAtCoord(cam, camLook.x, camLook.y, camLook.z)
            SetCamFov(cam, camFov)
        else
            Wait(100)
        end
        Wait(0)
    end
end)

-- ---------------------------------------------------------------- Entrée/sortie
local function enterLobbyUi()
    nuiReady = false
    touchNui()
    -- gf_core peut encore être en train de fondre l'écran : sans ça le joueur
    -- reste sur un écran noir alors que la NUI est déjà chargée.
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    -- Toujours forcer le fondu : si gf_core n'a pas exécuté le sien (spawn
    -- perdu, erreur silencieuse ou arrivée après l'état lobby), l'écran reste
    -- noir alors que la NUI est déjà visible. Un second fondu entrant est
    -- inoffensif.
    DoScreenFadeIn(400)
    local ped = PlayerPedId()
    -- Un mode précédent (ex. redzone) peut avoir laissé le joueur en
    -- spectateur : le ped reste masqué malgré IsEntityVisible=1.
    NetworkSetInSpectatorMode(false, PlayerPedId())
    if ped and ped ~= 0 then SetEntityVisible(ped, true, false) end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    DisplayHud(false)
    DisplayRadar(false)
    TriggerEvent('gf_ui:hud', nil)
    SetPlayerControl(PlayerId(), false, 0)
    if ped and ped ~= 0 then
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
    end
    inLobby = true
    uiSuspended = false
end

-- Sortie : restaure le jeu sans écraser le bucket ni le mode côté serveur.
local function leaveLobbyUi()
    inLobby = false
    nuiReady = false
    uiSuspended = false
    placedSlot, placedCount = nil, nil
    destroyCamera()
    stopBackdrop()
    local ped = PlayerPedId()
    SetPlayerControl(PlayerId(), true, 0)
    -- Le ped reste gelé : la scène est dans le vide et il tomberait. Chaque mode
    -- place le joueur par gf_core:Spawn, qui fixe lui-même le gel à la fin du spawn.
    if ped and ped ~= 0 then SetEntityInvincible(ped, false) end
    DisplayHud(true)
    DisplayRadar(true)
    SetNuiFocus(false, false)
    state = nil
    sendUi('close', {})
end

-- ---------------------------------------------------------------- Présentation
local function presentLobby(currentState)
    local me = currentState.me or {}
    local character = me.character or {}
    if not validGender(character.gender) then character.gender = 'male' end
    if not applyLocalModel(character.gender) then
        notify('Modèle de personnage indisponible.')
    end
    local ped = PlayerPedId()
    local appearance = appearanceKey(character)
    if lastAppearanceSeed ~= appearance then
        local ok, applied = pcall(applyAppearance, ped, character)
        if ok and applied then lastAppearanceSeed = appearance end
    end

    local members = (currentState.party and currentState.party.members) or {}
    local count = math.max(1, #members)
    local slot = me and me.slot
    if not slot then
        for _, member in pairs(members) do
            if type(member) == 'table' and member.isSelf then slot = member.slot break end
        end
    end
    placeSelfOnSlot(slot or 1, count)
    startBackdrop()
    local dbgPed = PlayerPedId()
    if dbgPed and dbgPed ~= 0 then
        local c = GetEntityCoords(dbgPed)
        print(('[gf_lobby] presentLobby ped=%s model=%s visible=%s coords=%.2f,%.2f,%.2f'):format(
            tostring(dbgPed), tostring(GetEntityModel(dbgPed)), tostring(IsEntityVisible(dbgPed)),
            c.x, c.y, c.z
        ))
    end

    -- La caméra et le ped local d'abord : une erreur d'apparence distante ne
    -- doit jamais laisser le joueur sur un écran noir ou sans caméra.
    if not ensureCamera() then return end
    local pos, look, fov = groupCameraTargets(count)
    setCameraTargets(pos, look, fov)
    DoScreenFadeIn(400)

    local ok, err = pcall(applyRemoteAppearances, currentState)
    if not ok then
        print(('[gf_lobby] apparences distantes: %s'):format(tostring(err)))
    end
end

local function presentCreator(sendCreator)
    local mode = creatorMode or 'create'
    local preview
    if mode == 'edit' then
        preview = previewCharacter or (state and state.me and state.me.character)
    else
        preview = previewCharacter
    end
    preview = preview or { gender = 'male', seed = 1337, skin = 0 }
    if not validGender(preview.gender) then
        preview.gender = 'male'
    end
    -- Même si le modèle échoue, on place le ped et on crée la caméra : le joueur
    -- doit toujours voir quelque chose et garder une interface utilisable.
    if not applyLocalModel(preview.gender) then
        notify('Modèle de personnage indisponible.')
    end
    local character = {
        name = preview.name or '',
        gender = preview.gender,
        seed = preview.seed,
        skin = preview.skin,
        appearance = preview.appearance,
    }
    if type(GFLobbyAppearanceSchema) == 'table'
        and type(GFLobbyAppearanceSchema.normalize) == 'function' then
        character.appearance = GFLobbyAppearanceSchema.normalize(
            preview.appearance, character.gender, character.seed, character.skin
        )
    end
    local ok, applied = pcall(applyAppearance, PlayerPedId(), character)
    if ok and applied then
        lastAppearanceSeed = appearanceKey(character)
    end
    placeSelfOnSlot(1, 1)
    if previewAngleOffset ~= 0 then
        local ped = PlayerPedId()
        if ped and ped ~= 0 then
            SetEntityHeading(ped, (Config.Stage.heading + previewAngleOffset) % 360)
        end
    end
    startBackdrop()
    if not ensureCamera() then return end
    local pos, look, fov = creatorCameraTargets()
    setCameraTargets(pos, look, fov)

    if lastCatalogGender ~= character.gender or sendCreator then
        sendCatalog(character.gender)
        lastCatalogGender = character.gender
    end
    if sendCreator then
        sendUi('creator', { mode = mode, character = character })
    end
    DoScreenFadeIn(400)
end

local function applyState(currentState)
    if type(currentState) ~= 'table' or type(currentState.me) ~= 'table' then return end
    state = currentState
    local me = state.me
    print(('[gf_lobby] applyState (inLobby=%s, camera=%s)'):format(
        tostring(me.inLobby), tostring(cam ~= nil and DoesCamExist(cam))
    ))

    if not me.inLobby then
        if inLobby then leaveLobbyUi() end
        return
    end

    if not inLobby then enterLobbyUi() end
    touchNui()

    -- Un state peut arriver pendant que l'éditeur est ouvert (mise à jour de
    -- l'escouade, arrivée d'un membre). On rafraîchit les données NUI sans
    -- remplacer la caméra ni le ped en cours d'édition.
    if editing and me.character ~= nil then
        sendUi('state', state)
        return
    end

    if me.character == nil then
        creatorMode = 'create'
        local ok, err = pcall(presentCreator, true)
        if not ok then print(('[gf_lobby] presentCreator: %s'):format(tostring(err))) end
    else
        local ok, err = pcall(presentLobby, state)
        if not ok then print(('[gf_lobby] presentLobby: %s'):format(tostring(err))) end
    end
    sendUi('state', state)
end

-- ---------------------------------------------------------------- Watchdog
local function suspendUi(reason)
    if uiSuspended then return end
    uiSuspended = true
    -- Joueur laissé en mode lobby côté serveur : on ne change que la présentation.
    destroyCamera()
    stopBackdrop()
    local ped = PlayerPedId()
    SetPlayerControl(PlayerId(), true, 0)
    -- Le ped reste gelé : la scène est dans le vide, le dégeler le ferait tomber.
    -- Le joueur garde la console F8 (lobbyui, attack, redzone).
    if ped and ped ~= 0 then SetEntityInvincible(ped, false) end
    DisplayHud(true)
    DisplayRadar(true)
    SetNuiFocus(false, false)
    notify(('Interface lobby suspendue (%s). Ouvre la console (F8) et tape lobbyui pour la rouvrir.'):format(reason))
end

CreateThread(function()
    while true do
        Wait(1000)
        if inLobby and not uiSuspended then
            local silentFor = lastNuiSeen > 0 and (now() - lastNuiSeen) or 0
            if not nuiReady then
                -- Laisse le temps au CEF de se charger sur un serveur déployé :
                -- 8 s produisait des suspensions alors que la page allait finir
                -- par envoyer `ready`, rendant la NUI inaccessible.
                if silentFor > WATCHDOG_MS then suspendUi('page non prête') end
            elseif silentFor > WATCHDOG_MS then
                suspendUi('heartbeat absent')
            end
        end
    end
end)

RegisterCommand('lobbyui', function()
    local mode = LocalPlayer.state and LocalPlayer.state.gf_mode
    local locallyInLobby = state and state.me and state.me.inLobby
    if mode ~= 'lobby' and not locallyInLobby then return end
    lastNuiSeen = now()
    nuiReady = true
    uiSuspended = false
    if state then
        applyState(state)
    else
        TriggerServerEvent('gf_lobby:requestState')
    end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
end, false)

-- ---------------------------------------------------------------- Récupération d'état
-- Une course au chargement peut faire arriver gf_lobby:state avant que le
-- handler ne soit en place, ou voir le serveur répondre avant que la page NUI
-- n'écoute. On retente tant qu'aucun état n'est reçu, puis on s'arrête.
local function stopStateRetry()
    stateRetryActive = false
end

local function startStateRetry()
    if stateRetryActive then return end
    stateRetryActive = true
    CreateThread(function()
        for attempt = 1, RETRY_MAX do
            Wait(RETRY_INTERVAL_MS)
            if not stateRetryActive or (state and state.me and state.me.inLobby == true) then return end
            print(('[gf_lobby] requestState retry %d'):format(attempt))
            TriggerServerEvent('gf_lobby:requestState')
        end
        stateRetryActive = false
    end)
end

-- ---------------------------------------------------------------- Serveur → NUI
-- Enregistré avant les callbacks NUI : le `ready` de la page déclenche un
-- requestState, le handler doit déjà exister quand la réponse revient.
RegisterNetEvent('gf_lobby:state', function(data)
    if type(data) ~= 'table' then return end
    -- La state replication peut être en retard au premier spawn : on ignore
    -- seulement un état arrivé après un changement de mode explicite.
    local mode = LocalPlayer.state and LocalPlayer.state.gf_mode
    if mode and mode ~= 'lobby' then return end
    touchNui()
    local me = data.me or {}
    -- Un état `inLobby=false` est transitoire (gf_core n'a pas encore attribué
    -- le mode lobby) : il ne doit pas couper la boucle de récupération.
    if me.inLobby == true then stopStateRetry() end
    print(('[gf_lobby] gf_lobby:state reçu (id=%s, inLobby=%s, character=%s)'):format(
        tostring(me.id), tostring(me.inLobby), tostring(me.character ~= nil)
    ))
    local ok, err = pcall(applyState, data)
    if not ok then
        print(('[gf_lobby] gf_lobby:state: %s'):format(tostring(err)))
    end
end)

-- ---------------------------------------------------------------- NUI → Lua
-- Chaque callback répond via sa fonction cb, y compris en erreur.
-- FiveM passes the NUI result callback as a function reference: a table with a
-- __call metamethod, not a Lua function (funcref_mt in citizen's scheduler.lua).
-- Calling only real functions left every fetch unanswered until the reference
-- was garbage collected, which made the page see `callback_unreachable`.
local function isCallable(value)
    if type(value) == 'function' then return true end
    local meta = getmetatable(value)
    return type(meta) == 'table' and rawget(meta, '__call') ~= nil
end

local function respond(cb, payload)
    if isCallable(cb) then cb(payload) end
end

local function fail(cb, message)
    respond(cb, { ok = false, error = message })
end

-- Valide la forme minimale puis relaie. Ne bloque jamais le fetch.
local function relay(cb, data, eventName, validator)
    if validator and not validator(data) then
        fail(cb, 'invalid_payload')
        return
    end
    TriggerServerEvent(eventName, data)
    respond(cb, { ok = true })
end

local CALLBACKS = {
    ready = function(cb)
        nuiReady = true
        touchNui()
        print(('[gf_lobby] NUI ready (state=%s)'):format(state and 'oui' or 'non'))
        -- Différer : la page peut appeler `ready` avant que le handler réseau
        -- gf_lobby:state soit enregistré par le moteur FiveM.
        SetTimeout(250, function()
            if state and state.me and state.me.inLobby then
                stopStateRetry()
                sendUi('state', state)
            else
                TriggerServerEvent('gf_lobby:requestState')
                startStateRetry()
            end
        end)
        respond(cb, { ok = true })
    end,
    heartbeat = function(cb)
        nuiReady = true
        touchNui()
        respond(cb, { ok = true })
    end,
    requestState = function(cb)
        print('[gf_lobby] NUI requestState')
        SetTimeout(250, function()
            TriggerServerEvent('gf_lobby:requestState')
            startStateRetry()
        end)
        respond(cb, { ok = true })
    end,
    previewCharacter = function(cb, data)
        local character = normalizeCharacter(data)
        if not character then fail(cb, 'invalid_character') return end
        previewCharacter = character
        if inLobby then
            local me = state and state.me
            local ok, err = pcall(function()
                if me and me.character ~= nil then
                    -- Personnage déjà créé (édition) : appliquer au ped existant
                    -- sans remplacer la caméra ni la scène.
                    if applyLocalModel(character.gender) then
                        applyAppearance(PlayerPedId(), character)
                        lastAppearanceSeed = appearanceKey(character)
                    end
                else
                    presentCreator(false)
                end
            end)
            if not ok then
                print(('[gf_lobby] previewCharacter: %s'):format(tostring(err)))
            end
        end
        respond(cb, {
            ok = true,
            gender = character.gender,
            seed = character.seed,
            skin = character.skin,
            appearance = character.appearance,
        })
    end,
    createCharacter = function(cb, data)
        if type(data) ~= 'table' then fail(cb, 'invalid_payload') return end
        local name = normalizeName(data.name)
        if not name then fail(cb, 'invalid_name') return end
        local character = normalizeCharacter(data)
        if not character then fail(cb, 'invalid_character') return end
        TriggerServerEvent('gf_lobby:createCharacter', {
            name = name,
            gender = character.gender,
            seed = character.seed,
            skin = character.skin,
            appearance = character.appearance,
        })
        respond(cb, { ok = true })
    end,
    -- Ouvre l'éditeur depuis l'onglet Personnage, en mode édition.
    editCharacter = function(cb)
        if not inLobby or not state or not state.me then
            fail(cb, 'not_in_lobby')
            return
        end
        local current = state.me.character
        if type(current) ~= 'table' then
            fail(cb, 'no_character')
            return
        end
        local appearance = nil
        if type(GFLobbyAppearanceSchema) == 'table'
            and type(GFLobbyAppearanceSchema.build) == 'function' then
            appearance = GFLobbyAppearanceSchema.build(current)
        end
        editing = true
        creatorMode = 'edit'
        previewAngleOffset = 0
        previewCharacter = {
            name = current.name or '',
            gender = current.gender,
            seed = current.seed,
            skin = current.skin,
            appearance = appearance,
        }
        local ok, err = pcall(presentCreator, true)
        if not ok then
            editing = false
            creatorMode = 'create'
            fail(cb, 'internal_error')
            print(('[gf_lobby] editCharacter: %s'):format(tostring(err)))
            return
        end
        respond(cb, { ok = true })
    end,
    -- Enregistre l'apparence éditée. Le serveur ne modifie que l'apparence et
    -- la carnation : le nom, le genre et la seed restent figés après création.
    saveAppearance = function(cb, data)
        if not editing then fail(cb, 'not_editing') return end
        if type(data) ~= 'table' then fail(cb, 'invalid_payload') return end
        local base = previewCharacter or (state and state.me and state.me.character)
        if type(base) ~= 'table' then fail(cb, 'no_character') return end
        local character = normalizeCharacter({
            gender = base.gender,
            seed = base.seed,
            skin = data.skin,
            appearance = data.appearance,
        })
        if not character then fail(cb, 'invalid_character') return end
        TriggerServerEvent('gf_lobby:updateAppearance', {
            appearance = character.appearance,
            skin = character.skin,
        })
        respond(cb, { ok = true })
    end,
    cancelEdit = function(cb)
        if editing then
            editing = false
            creatorMode = 'create'
            previewCharacter = nil
            previewAngleOffset = 0
            lastAppearanceSeed = nil
            if state then
                local ok, err = pcall(applyState, state)
                if not ok then print(('[gf_lobby] cancelEdit: %s'):format(tostring(err))) end
            end
        end
        respond(cb, { ok = true })
    end,
    -- Rotation locale du personnage pour voir le dos ou le profil.
    previewAngle = function(cb, data)
        local angle = type(data) == 'table' and clamp(data.angle, -180, 180, 0) or 0
        previewAngleOffset = angle
        local heading = (Config.Stage.heading + angle) % 360
        local ped = PlayerPedId()
        if ped and ped ~= 0 then SetEntityHeading(ped, heading + 0.0) end
        respond(cb, { ok = true })
    end,
    requestPlayers = function(cb)
        print('[gf_lobby] NUI requestPlayers')
        TriggerServerEvent('gf_lobby:requestPlayers')
        respond(cb, { ok = true })
        print('[gf_lobby] NUI requestPlayers -> ok')
    end,
    invite = function(cb, data)
        relay(cb, data, 'gf_lobby:invite', function(d)
            return type(d) == 'table' and type(d.id) == 'number'
                and d.id > 0 and d.id == math.floor(d.id)
        end)
    end,
    respondInvite = function(cb, data)
        relay(cb, data, 'gf_lobby:respondInvite', function(d)
            return type(d) == 'table' and type(d.partyId) == 'number' and d.partyId > 0
                and type(d.accept) == 'boolean'
        end)
    end,
    leaveParty = function(cb)
        TriggerServerEvent('gf_lobby:leaveParty')
        respond(cb, { ok = true })
    end,
    kickMember = function(cb, data)
        relay(cb, data, 'gf_lobby:kickMember', function(d)
            return type(d) == 'table' and type(d.id) == 'number'
                and d.id > 0 and d.id == math.floor(d.id)
        end)
    end,
    voteMap = function(cb, data)
        relay(cb, data, 'gf_lobby:voteMap', function(d)
            return type(d) == 'table' and (d.id == false or (type(d.id) == 'string' and #d.id >= 1 and #d.id <= 64))
        end)
    end,
    selectMode = function(cb, data)
        local mode = type(data) == 'table' and tostring(data.mode) or 'nil'
        print(('[gf_lobby] NUI selectMode entrée (mode=%s)'):format(mode))
        relay(cb, data, 'gf_lobby:selectMode', function(d)
            return type(d) == 'table' and type(d.mode) == 'string' and #d.mode > 0
        end)
        print(('[gf_lobby] NUI selectMode sortie (mode=%s)'):format(mode))
    end,
    play = function(cb, data)
        local mode = type(data) == 'table' and tostring(data.mode) or 'nil'
        print(('[gf_lobby] NUI play entrée (mode=%s)'):format(mode))
        relay(cb, data, 'gf_lobby:play', function(d)
            return type(d) == 'table' and type(d.mode) == 'string' and #d.mode > 0
        end)
        print(('[gf_lobby] NUI play sortie (mode=%s)'):format(mode))
    end,
}

for name, handler in pairs(CALLBACKS) do
    RegisterNUICallback(name, function(data, cb)
        local answered = false
        local safeCb = function(payload)
            if answered then return end
            answered = true
            respond(cb, payload)
        end
        local ok, err = pcall(handler, safeCb, data)
        if not ok then
            print(('[gf_lobby] callback %s: %s'):format(name, tostring(err)))
            -- Réponse de secours pour ne jamais laisser le fetch ouvert.
            fail(safeCb, 'internal_error')
        end
    end)
end

-- ---------------------------------------------------------------- Serveur → NUI
local RELAYED = {
    'invite', 'inviteResult', 'players', 'notice', 'launching', 'close'
}
for _, kind in ipairs(RELAYED) do
    RegisterNetEvent('gf_lobby:' .. kind, function(data)
        if kind == 'close' and inLobby then
            editing = false
            creatorMode = 'create'
            previewCharacter = nil
            leaveLobbyUi()
            return
        end
        sendUi(kind, data)
    end)
end

RegisterNetEvent('gf_lobby:createResult', function(result)
    sendUi('createResult', result)
end)

RegisterNetEvent('gf_lobby:appearanceResult', function(result)
    if editing and type(result) == 'table' and result.ok then
        local saved = previewCharacter
        editing = false
        creatorMode = 'create'
        previewCharacter = nil
        lastAppearanceSeed = nil
        -- Le state officiel arrive juste après ; on met à jour la copie locale
        -- pour que le retour au lobby n'affiche pas brièvement l'ancienne tenue.
        if state and state.me and state.me.character and type(saved) == 'table' then
            state.me.character.appearance = saved.appearance
            state.me.character.skin = saved.skin
        end
        if state then
            local ok, err = pcall(applyState, state)
            if not ok then print(('[gf_lobby] appearanceResult: %s'):format(tostring(err))) end
        end
    end
    sendUi('appearanceResult', result)
end)

-- ---------------------------------------------------------------- gf_core
RegisterNetEvent('gf_core:modeChanged', function(mode)
    if type(mode) == 'string' and mode ~= 'lobby' then
        if inLobby then leaveLobbyUi() end
        state = nil
    elseif mode == 'lobby' then
        TriggerServerEvent('gf_lobby:requestState')
    end
end)

RegisterNetEvent('gf_core:spawned', function()
    if not inLobby or not state then return end
    -- gf_core termine son spawn en dégelant le ped, puis émet cet événement
    -- (TriggerEvent, donc dans la même frame). Le replacer et le regeler tout
    -- de suite : dans le vide de la scène de création, les 200 ms d'attente
    -- ci-dessous suffisaient à le faire tomber (0,2 m mesuré, animation de chute).
    if placedSlot then placeSelfOnSlot(placedSlot, placedCount) end
    -- Le spawn de gf_core peut se terminer après l'état : on réapplique après
    -- un court délai, une seule fois.
    SetTimeout(200, function()
        if not inLobby or not state then return end
        pcall(applyState, state)
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    destroyCamera()
    SetNuiFocus(false, false)
    local ped = PlayerPedId()
    -- Le ped reste gelé : dans la scène du lobby, il tomberait du vide.
    if ped and ped ~= 0 then SetEntityInvincible(ped, false) end
    DisplayHud(true)
    DisplayRadar(true)
end)

-- Masque temporairement la NUI du lobby pendant l'interface d'administration.
AddEventHandler('gf_lobby:menuOverlay', function(ouvert)
    if not inLobby then return end
    SendNUIMessage({ type = 'menuOverlay', data = { open = ouvert == true } })
    if not ouvert then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
    end
end)
