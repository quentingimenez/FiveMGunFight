-- =============================================================================
--  gf_admin - CLIENT
--  Panneau d'administration NUI (touche F10). Les droits sont revérifiés côté
--  serveur : aucun état d'administrateur n'est conservé ici.
--  Toute fermeture passe par fermer() : un seul endroit remet le focus.
-- =============================================================================

local ouvert = false
local lobbyUiOpen = false

-- FiveM transmet le callback NUI comme référence de fonction : une table avec
-- un métaméthode __call, pas une fonction Lua. Tester seulement type(cb)
-- laissait chaque réponse sans effet.
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

local function ouvrir()
    if ouvert then return end
    ouvert = true
    if lobbyUiOpen then TriggerEvent('gf_lobby:menuOverlay', true) end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'open' })
end

local function fermer()
    if not ouvert then return end
    ouvert = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'close' })
    -- En dernier : le lobby reprend le focus après nous.
    if lobbyUiOpen then TriggerEvent('gf_lobby:menuOverlay', false) end
end

-- ---------------------------------------------------------------------- État

-- Le lobby garde la priorité sur son propre focus ; on mémorise son ouverture
-- exactement comme gf_menu le fait.
RegisterNetEvent('gf_lobby:state', function(data)
    lobbyUiOpen = type(data) == 'table'
        and type(data.me) == 'table'
        and data.me.inLobby == true
end)

RegisterNetEvent('gf_core:modeChanged', function(mode)
    if type(mode) == 'string' and mode ~= 'lobby' then
        lobbyUiOpen = false
    end
    if ouvert then fermer() end
end)

-- ------------------------------------------------------------------- Commande

RegisterCommand('admin', function()
    if ouvert then
        fermer()
    else
        TriggerServerEvent('gf_admin:requestData')
    end
end, false)

RegisterKeyMapping('admin', 'Gunfight : panneau admin', 'keyboard', 'F10')

AddEventHandler('gf_admin:open', function()
    TriggerServerEvent('gf_admin:requestData')
end)

-- Refus serveur : la page reste fermée, le serveur a déjà prévenu le joueur.
RegisterNetEvent('gf_admin:denied', function() end)

-- ------------------------------------------------------------------ Données

RegisterNetEvent('gf_admin:data', function(data)
    if type(data) ~= 'table' then return end
    if not ouvert then ouvrir() end

    local players = type(data.players) == 'table' and data.players or {}
    local weapons = type(data.weapons) == 'table' and data.weapons or {}

    local noms = {}
    for _, weapon in ipairs(weapons) do
        if type(weapon) == 'table' and type(weapon.name) == 'string' then
            noms[#noms + 1] = weapon.name
        end
    end

    CreateThread(function()
        local photos = {}
        if GetResourceState('gf_thumbs') == 'started' then
            local ok, result = pcall(function()
                return exports.gf_thumbs:Get('weapons', noms)
            end)
            if ok and type(result) == 'table' then photos = result end
        end
        -- Le panneau peut avoir été fermé pendant le chargement des photos.
        if ouvert then
            SendNUIMessage({
                type = 'data',
                data = { players = players, weapons = weapons },
                photos = photos,
            })
        end
    end)
end)

-- -------------------------------------------------------------- NUI → client

RegisterNUICallback('ready', function(_, cb)
    repondre(cb, { ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    fermer()
    repondre(cb, { ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    TriggerServerEvent('gf_admin:requestData')
    repondre(cb, { ok = true })
end)

RegisterNUICallback('run', function(data, cb)
    if type(data) ~= 'table' then
        repondre(cb, { ok = false })
        return
    end

    local command = data.command
    local args = data.args
    if args == nil then args = {} end

    local ligne = GFAdminCommands.build(command, args)
    if not ligne then
        repondre(cb, { ok = false })
        return
    end

    -- Les commandes qui ouvrent un autre menu rendent d'abord le focus au jeu.
    if GFAdminCommands.opensUi(command) then fermer() end

    ExecuteCommand(ligne)
    SetTimeout(600, function()
        if ouvert then TriggerServerEvent('gf_admin:requestData') end
    end)
    repondre(cb, { ok = true })
end)

-- -------------------------------------------------------------- Fin de ressource

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if ouvert then fermer() end
end)
