-- =============================================================================
--  gf_menu - CLIENT
--  Remplace le menu pause GTA V (INPUT_FRONTEND_PAUSE) par une page NUI.
--  Toute fermeture passe par fermerMenu() : un seul endroit remet le focus.
-- =============================================================================

local menuOuvert = false
local lobbyUiOpen = false
-- La page NUI reste chargée entre deux ouvertures : `ready` n'arrive qu'une
-- fois, donc pagePret n'est jamais remis à false après l'initialisation.
local pagePret = false
local derniereFermeture = 0
local etatEnAttente = nil
local generationOuverture = 0
local armesCasier = {}
local apercu = { generation = 0 }

local function fermerApercu()
    apercu.generation = apercu.generation + 1
    if apercu.camera then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(apercu.camera, false)
        ClearFocus()
    end
    if apercu.ped and DoesEntityExist(apercu.ped) then DeleteEntity(apercu.ped) end
    apercu.camera, apercu.ped, apercu.weapon = nil, nil, nil
end

local function appliquerApercu(choices)
    local weapon = apercu.weapon
    if not weapon or not apercu.ped or not DoesEntityExist(apercu.ped) then return end
    local ajouter = {}
    local objet = GetCurrentPedWeaponEntityIndex(apercu.ped, 0)
    if not objet or objet == 0 or not DoesEntityExist(objet) then objet = nil end
    for kind, group in pairs(weapon.accessories or {}) do
        local selected = type(choices) == 'table' and choices[kind] or nil
        if selected == nil then selected = (weapon.selections or {})[kind] or group.default or '' end
        for _, component in ipairs(group.options or {}) do
            if type(component) == 'string' and component:match('^[%w_]+$') then
                local hash = joaat(component)
                RemoveWeaponComponentFromPed(apercu.ped, apercu.hash, hash)
                if objet then RemoveWeaponComponentFromWeaponObject(objet, hash) end
                if selected == component then ajouter[#ajouter + 1] = hash end
            end
        end
    end
    for _, component in ipairs(ajouter) do
        GiveWeaponComponentToPed(apercu.ped, apercu.hash, component)
        if objet then GiveWeaponComponentToWeaponObject(objet, component) end
    end
end

-- Les pièces sont appliquées à nouveau après le chargement du modèle en jeu.
-- Une génération empêche qu'un ancien choix remplace une sélection plus récente.
local function actualiserApercu(choices)
    apercu.choices = choices
    apercu.revision = (apercu.revision or 0) + 1
    local revision, generation = apercu.revision, apercu.generation
    appliquerApercu(choices)
    CreateThread(function()
        Wait(150)
        if apercu.generation == generation and apercu.revision == revision then
            appliquerApercu(apercu.choices)
        end
    end)
end

local function ouvrirApercu(id, choices)
    fermerApercu()
    local weapon = armesCasier[id]
    if not menuOuvert or not weapon or type(weapon.name) ~= 'string'
        or not weapon.name:match('^[%w_]+$') then return false end
    apercu.weapon, apercu.choices, apercu.clientRevision = weapon, choices, 0
    local generation = apercu.generation
    CreateThread(function()
        local hash = joaat(weapon.name)
        if not IsWeaponValid(hash) then return end
        RequestWeaponAsset(hash, 31, 0)
        local deadline = GetGameTimer() + 5000
        while not HasWeaponAssetLoaded(hash) and GetGameTimer() < deadline and apercu.generation == generation do Wait(50) end
        if apercu.generation ~= generation or not menuOuvert or not HasWeaponAssetLoaded(hash) then
            RemoveWeaponAsset(hash)
            return
        end
        local player = PlayerPedId()
        local heading = 180.0
        local pos = vector3(-75.0, -818.0, 326.2)
        SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)
        RequestCollisionAtCoord(pos.x, pos.y, pos.z)
        local ped = ClonePed(player, heading, false, false)
        if not ped or ped == 0 then ClearFocus() RemoveWeaponAsset(hash) return end
        apercu.ped, apercu.hash = ped, hash
        SetEntityCoordsNoOffset(ped, pos.x, pos.y, pos.z, false, false, false)
        SetEntityHeading(ped, heading)
        SetEntityCollision(ped, false, false)
        SetEntityVisible(ped, true, false)
        ResetEntityAlpha(ped)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        RemoveAllPedWeapons(ped, true)
        GiveWeaponToPed(ped, hash, 250, false, true)
        SetCurrentPedWeapon(ped, hash, true)
        actualiserApercu(apercu.choices)
        local cameraPos = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.8, 0.75)
        local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        apercu.camera = cam
        SetCamCoord(cam, cameraPos.x, cameraPos.y, cameraPos.z)
        PointCamAtCoord(cam, pos.x, pos.y, pos.z + 0.65)
        SetCamFov(cam, 45.0)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, false)
        RemoveWeaponAsset(hash)
        SendNUIMessage({ type = 'accessoryPreviewReady' })
    end)
    return true
end

-- FiveM transmet le callback NUI comme référence de fonction : une table avec
-- un métaméthode __call, pas une fonction Lua (funcref_mt du scheduler de
-- citizen). Tester seulement type(cb) laissait chaque fetch sans réponse.
local function estAppelable(valeur)
    if type(valeur) == 'function' then return true end
    local meta = getmetatable(valeur)
    return type(meta) == 'table' and rawget(meta, '__call') ~= nil
end

--- Un callback NUI vient du viewport : s'il n'est pas appelable, FiveM
--- l'ignore. Ne pas lever d'erreur, ne pas répondre deux fois.
local function repondre(cb, reponse)
    if not estAppelable(cb) then return end
    cb(reponse)
end

-- ------------------------------------------------------------------- Ouverture

local function fermerMenu()
    if not menuOuvert then return end
    menuOuvert = false
    fermerApercu()
    derniereFermeture = GetGameTimer()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'close' })
    if lobbyUiOpen then TriggerEvent('gf_lobby:menuOverlay', false) end
end

local function ouvrirMenu()
    if menuOuvert then return end
    menuOuvert = true
    generationOuverture = generationOuverture + 1
    local generation = generationOuverture

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'open', data = {} })
    TriggerServerEvent('gf_menu:requestState')
    if etatEnAttente then
        SendNUIMessage({ type = 'state', data = etatEnAttente })
    end

    -- Si la page ne signale jamais `ready`, rendre le focus au jeu : sans ce
    -- garde-fou, un joueur pourrait rester piégé dans un NUI vide.
    SetTimeout(Config.PageReadyTimeoutMs, function()
        if menuOuvert and not pagePret and generation == generationOuverture then
            print('[gf_menu] page NUI indisponible')
            fermerMenu()
        end
    end)
end

-- -------------------------------------------------------------- Boucle d'entrée

CreateThread(function()
    while true do
        -- Le menu pause natif se bloque à chaque frame : c'est le seul
        -- endroit où Wait(0) est nécessaire dans cette ressource.
        DisableFrontendThisFrame()

        -- Cette invisibilité est locale et ne dure qu'une image ; les autres
        -- joueurs ne sont pas modifiés et réapparaissent dès la fin de l'aperçu.
        if apercu.camera then
            for _, player in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(player)
                if ped ~= 0 then SetEntityLocallyInvisible(ped) end
            end
        end

        if not menuOuvert and not lobbyUiOpen then
            DisableControlAction(0, Config.ToggleControl, true)
            if IsDisabledControlJustPressed(0, Config.ToggleControl)
                and GetGameTimer() - derniereFermeture >= Config.ReopenDelayMs then
                ouvrirMenu()
            end
        end

        Wait(0)
    end
end)

-- --------------------------------------------------------------------- État

--- Le serveur est la seule source de vérité. L'état est mémorisé même si le
--- menu est fermé, puis poussé à la page dès son ouverture.
RegisterNetEvent('gf_menu:state', function(data)
    if type(data) ~= 'table' then return end
    etatEnAttente = data
    if menuOuvert then
        SendNUIMessage({ type = 'state', data = data })
    end
end)

--- Le lobby est prioritaire : son ouverture empêche celle du menu. Le lobby
--- gère lui-même son focus ; ne pas le lui reprendre dans le même événement.
RegisterNetEvent('gf_lobby:state', function(data)
    lobbyUiOpen = type(data) == 'table'
        and type(data.me) == 'table'
        and data.me.inLobby == true
end)

--- Un changement de mode ou un spawn rend la main au jeu. Le lobby ferme son
--- UI sur ce même événement sans renvoyer `gf_lobby:state` : sans ce nettoyage
--- le garde-fou resterait posé et Échap n'ouvrirait jamais le menu en partie.
RegisterNetEvent('gf_core:modeChanged', function(mode)
    if type(mode) == 'string' and mode ~= 'lobby' then
        lobbyUiOpen = false
    end
    if menuOuvert then fermerMenu() end
end)

RegisterNetEvent('gf_core:spawned', function()
    if menuOuvert then fermerMenu() end
end)

-- ------------------------------------------------------------------ NUI → client

RegisterNUICallback('ready', function(data, cb)
    pagePret = true
    repondre(cb, { ok = true })
    if menuOuvert and etatEnAttente then
        SendNUIMessage({ type = 'state', data = etatEnAttente })
    end
end)

RegisterNUICallback('close', function(data, cb)
    if not pagePret then
        repondre(cb, { ok = false, error = 'page non prête' })
        return
    end
    fermerMenu()
    repondre(cb, { ok = true })
end)

RegisterNUICallback('quit', function(data, cb)
    if not pagePret then
        repondre(cb, { ok = false, error = 'page non prête' })
        return
    end
    TriggerServerEvent('gf_menu:quit')
    fermerMenu()
    repondre(cb, { ok = true })
end)

-- Ouvre le panneau d'administration : simple événement client local, gf_admin
-- revérifie les droits côté serveur.
RegisterNUICallback('openAdmin', function(_, cb)
    if not pagePret then
        repondre(cb, { ok = false })
        return
    end
    fermerMenu()
    TriggerEvent('gf_admin:open')
    repondre(cb, { ok = true })
end)

-- Le Casier et le catalogue admin partagent le focus du menu Échap.
local function transmettreArmes(kind, data)
    if type(data) ~= 'table' then return end
    CreateThread(function()
        local weapons = kind == 'locker' and data.weapons or data
        local ids = {}
        for _, weapon in ipairs(weapons or {}) do ids[#ids + 1] = weapon.name end
        local photos = {}
        if GetResourceState('gf_thumbs') == 'started' then
            local ok, result = pcall(function() return exports.gf_thumbs:Get('weapons', ids) end)
            if ok and type(result) == 'table' then photos = result end
        end
        if menuOuvert then SendNUIMessage({ type = kind, data = data, photos = photos }) end
    end)
end

RegisterNetEvent('gf_inventory:locker', function(data)
    armesCasier = {}
    for _, weapon in ipairs(type(data) == 'table' and data.weapons or {}) do
        if weapon.id then armesCasier[weapon.id] = weapon end
    end
    transmettreArmes('locker', data)
end)
RegisterNetEvent('gf_inventory:accessoriesSaved', function(weaponId)
    if not menuOuvert or not apercu.weapon or apercu.weapon.id ~= weaponId then return end
    fermerApercu()
    SendNUIMessage({ type = 'accessorySaved' })
end)
RegisterNetEvent('gf_inventory:adminData', function(data) transmettreArmes('armory', data) end)
RegisterNetEvent('gf_inventory:openAdmin', function(data)
    if lobbyUiOpen then TriggerEvent('gf_lobby:menuOverlay', true) end
    ouvrirMenu()
    transmettreArmes('armory', data)
end)

RegisterNUICallback('locker', function(_, cb)
    TriggerServerEvent('gf_inventory:requestLocker')
    repondre(cb, { ok = true })
end)

RegisterNUICallback('equipWeapon', function(data, cb)
    if type(data) == 'table' then TriggerServerEvent('gf_inventory:equip', data.slot, data.id) end
    repondre(cb, { ok = true })
end)

RegisterNUICallback('setAccessories', function(data, cb)
    if type(data) == 'table' then TriggerServerEvent('gf_inventory:setAccessories', data.id, data.choices) end
    repondre(cb, { ok = true })
end)

RegisterNUICallback('previewAccessories', function(data, cb)
    local ok = type(data) == 'table' and ouvrirApercu(data.id, data.choices)
    repondre(cb, { ok = not not ok })
end)

RegisterNUICallback('updateAccessoryPreview', function(data, cb)
    if menuOuvert and apercu.weapon and type(data) == 'table' and data.id == apercu.weapon.id
        and type(data.revision) == 'number' and data.revision > apercu.clientRevision then
        apercu.clientRevision = data.revision
        actualiserApercu(data.choices)
    end
    repondre(cb, { ok = true })
end)

RegisterNUICallback('closeAccessoryPreview', function(_, cb)
    fermerApercu()
    repondre(cb, { ok = true })
end)

RegisterNUICallback('giveWeapon', function(data, cb)
    if type(data) == 'table' then TriggerServerEvent('gf_inventory:adminGive', data.id) end
    repondre(cb, { ok = true })
end)

-- -------------------------------------------------------------- Fin de ressource

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    fermerApercu()
    if menuOuvert then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        if lobbyUiOpen then TriggerEvent('gf_lobby:menuOverlay', false) end
    end
end)
