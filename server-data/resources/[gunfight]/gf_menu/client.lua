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

RegisterNetEvent('gf_inventory:locker', function(data) transmettreArmes('locker', data) end)
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

RegisterNUICallback('giveWeapon', function(data, cb)
    if type(data) == 'table' then TriggerServerEvent('gf_inventory:adminGive', data.id) end
    repondre(cb, { ok = true })
end)

-- -------------------------------------------------------------- Fin de ressource

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if menuOuvert then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        if lobbyUiOpen then TriggerEvent('gf_lobby:menuOverlay', false) end
    end
end)
