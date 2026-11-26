-- =============================================================================
--  gf_ui - CLIENT
--  Reçoit les événements du serveur et les transmet à la page HTML (NUI).
--
--  Événements utilisables par les autres ressources (TriggerClientEvent) :
--    gf_ui:hud        (data | nil)   { title, subtitle, timer, badge{text,color},
--                                      left{label,value,sub,color}, right{...} }
--    gf_ui:announce   (data)         { title, subtitle, duration }
--    gf_ui:killfeed   (entry)        { killer, killerTeam, victim, victimTeam, weapon }
--    gf_ui:scoreboard (data | nil)   { title, columns{}, rows{ {cells{}, color} } }
-- =============================================================================

local WEAPON_LABELS = {
    WEAPON_PISTOL = 'Pistolet', WEAPON_PISTOL50 = 'Pistolet .50', WEAPON_COMBATPISTOL = 'Pistolet de combat',
    WEAPON_APPISTOL = 'Pistolet AP', WEAPON_HEAVYPISTOL = 'Pistolet lourd', WEAPON_REVOLVER = 'Revolver',
    WEAPON_MICROSMG = 'Micro SMG', WEAPON_SMG = 'SMG', WEAPON_COMBATPDW = 'PDW',
    WEAPON_ASSAULTRIFLE = 'Fusil d\'assaut', WEAPON_CARBINERIFLE = 'Carabine', WEAPON_SPECIALCARBINE = 'Carabine spéciale',
    WEAPON_BULLPUPRIFLE = 'Fusil bullpup', WEAPON_ADVANCEDRIFLE = 'Fusil avancé', WEAPON_COMPACTRIFLE = 'Fusil compact',
    WEAPON_PUMPSHOTGUN = 'Fusil à pompe', WEAPON_SAWNOFFSHOTGUN = 'Canon scié', WEAPON_ASSAULTSHOTGUN = 'Fusil à pompe d\'assaut',
    WEAPON_SNIPERRIFLE = 'Sniper', WEAPON_HEAVYSNIPER = 'Sniper lourd', WEAPON_MARKSMANRIFLE = 'Fusil de précision',
    WEAPON_MG = 'Mitrailleuse', WEAPON_COMBATMG = 'Mitrailleuse de combat',
    WEAPON_GRENADE = 'Grenade', WEAPON_KNIFE = 'Couteau', WEAPON_UNARMED = 'Poings',
}

local labels = {}
for name, label in pairs(WEAPON_LABELS) do
    local h = joaat(name)
    labels[h] = label
    labels[h & 0xFFFFFFFF] = label
    if h > 0x7FFFFFFF then labels[h - 0x100000000] = label end
end

RegisterNetEvent('gf_ui:hud', function(d)
    SendNUIMessage({ type = 'hud', data = d })
end)

RegisterNetEvent('gf_ui:announce', function(d)
    SendNUIMessage({ type = 'announce', data = d })
end)

-- Touché : chiffre de dégâts + marqueur + son
RegisterNetEvent('gf_ui:hit', function(d)
    SendNUIMessage({ type = 'hit', data = d })
end)

-- Kill : son + message (DOUBLÉ, TRIPLÉ, ...)
RegisterNetEvent('gf_ui:kill', function(d)
    SendNUIMessage({ type = 'kill', data = d })
end)

-- ---------------------------------------------------------------- Choix des armes
-- data = { title, weapons = { {id,label,category} }, selected = {id,id}, count, seconds }
local loadoutFocus = false
local requestWeaponPhotos
local currentLoadout

local function releaseLoadoutFocus()
    if loadoutFocus then
        loadoutFocus = false
        SetNuiFocus(false, false)
    end
end

RegisterNetEvent('gf_ui:loadout_open', function(d)
    loadoutFocus = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    currentLoadout = type(d) == 'table' and d.weapons or nil
    SendNUIMessage({ type = 'loadout_open', data = d })
    requestWeaponPhotos(currentLoadout)
end)

RegisterNetEvent('gf_ui:loadout_close', function()
    releaseLoadoutFocus()
    currentLoadout = nil
    SendNUIMessage({ type = 'loadout_close' })
end)

-- Chaque changement de sélection est envoyé au serveur (il valide)
RegisterNUICallback('loadout', function(d, cb)
    TriggerServerEvent('gf:loadoutChosen', d.ids)
    cb({ ok = true })
end)

-- Bouton « Valider » : on rend la main au joueur, le choix reste enregistré
RegisterNUICallback('loadout_done', function(_, cb)
    releaseLoadoutFocus()
    cb({ ok = true })
end)

-- Affiche le classement pendant X ms (fin de partie)
RegisterNetEvent('gf_ui:scoreboard_show', function(ms)
    SendNUIMessage({ type = 'scoreboard_visible', visible = true })
    SetTimeout(ms or 8000, function()
        SendNUIMessage({ type = 'scoreboard_visible', visible = false })
    end)
end)

RegisterNetEvent('gf_ui:killfeed', function(e)
    if not e then
        SendNUIMessage({ type = 'killfeed_clear' })
        return
    end
    local me = GetPlayerName(PlayerId())
    e.weaponLabel = e.weapon and labels[e.weapon] or nil
    e.involvesMe = (e.killer == me) or (e.victim == me)
    SendNUIMessage({ type = 'killfeed', data = e })
end)

RegisterNetEvent('gf_ui:scoreboard', function(d)
    SendNUIMessage({ type = 'scoreboard', data = d })
end)

-- Classement : maintenir la touche (Z par défaut, modifiable dans
-- Paramètres > Raccourcis clavier > FiveM)
RegisterCommand('+gf_scoreboard', function()
    SendNUIMessage({ type = 'scoreboard_visible', visible = true })
end, false)
RegisterCommand('-gf_scoreboard', function()
    SendNUIMessage({ type = 'scoreboard_visible', visible = false })
end, false)
RegisterKeyMapping('+gf_scoreboard', 'Gunfight : afficher le classement', 'keyboard', 'Z')

-- Résultat du match, conservé à l'écran jusqu'au changement de mode.
RegisterNetEvent('gf_ui:match_results', function(data)
    SendNUIMessage({ type = 'match_results', data = data })
end)


-- Objets de soin affichés sous les barres (envoyés par le mode de jeu, ex. gf_attack)
-- list = { { id, key, label, count }, ... } ou nil pour masquer
AddEventHandler('gf_ui:items', function(list)
    SendNUIMessage({ type = 'items', data = list })
end)

-- HUD des armes en bas à droite (envoyé par gf_core)
-- list = { { key, name, label, clip, clipMax, active }, ... } ou nil pour masquer
local weaponPhotoRequests = {}
local currentWeapons = nil

requestWeaponPhotos = function(list)
    if type(list) ~= 'table' or GetResourceState('gf_thumbs') ~= 'started' then return end
    local names = {}
    for _, weapon in ipairs(list) do
        local name = weapon.name
        if type(name) == 'string' and name:match('^[%w_]+$') and not weaponPhotoRequests[name] then
            weaponPhotoRequests[name] = true
            names[#names + 1] = name
        end
    end
    if #names == 0 then return end
    CreateThread(function()
        local ok, photos = pcall(function() return exports.gf_thumbs:Get('weapons', names) end)
        if not ok or type(photos) ~= 'table' then
            for _, name in ipairs(names) do weaponPhotoRequests[name] = nil end
            return
        end
        SendNUIMessage({ type = 'weapon_photos', data = photos })
    end)
end

AddEventHandler('gf_ui:weapons', function(list)
    currentWeapons = list
    SendNUIMessage({ type = 'weapons', data = list })
    requestWeaponPhotos(list)
end)

RegisterNetEvent('gf_thumbs:updated', function(kind, name)
    if kind ~= 'weapons' or type(name) ~= 'string' then return end
    weaponPhotoRequests[name] = nil
    -- L'autre ressource vide son cache pour ce même événement.
    SetTimeout(50, function()
        requestWeaponPhotos(currentWeapons)
        requestWeaponPhotos(currentLoadout)
    end)
end)

-- ---------------------------------------------------------------- Minimap sans barres GTA
-- Les barres vie (verte) / armure (bleue) de GTA sous la minimap font doublon avec
-- notre HUD : le mode « 3 » du scaleform minimap les masque. GTA le réinitialise
-- parfois (respawn, changement de taille), d'où l'envoi à chaque image.
CreateThread(function()
    local minimap = RequestScaleformMovie('minimap')
    while not HasScaleformMovieLoaded(minimap) do Wait(0) end
    -- bascule grande carte / petite carte pour forcer le scaleform à se réinitialiser
    SetRadarBigmapEnabled(true, false)
    Wait(0)
    SetRadarBigmapEnabled(false, false)
    while true do
        BeginScaleformMovieMethod(minimap, 'SETUP_HEALTH_ARMOUR')
        ScaleformMovieMethodAddParamInt(3)
        EndScaleformMovieMethod()
        Wait(0)
    end
end)

-- ---------------------------------------------------------------- Vie et kevlar
-- Barres en bas au centre, dans les modes de jeu (pas au lobby).
-- Vie d'un joueur GTA : 100 = mort, 200 = pleine -> affichée de 0 à 100.
CreateThread(function()
    local lastH, lastA, shown = -1, -1, false
    while true do
        local ped = PlayerPedId()
        local mode = LocalPlayer.state.gf_mode
        local visible = mode and mode ~= 'lobby' and IsEntityVisible(ped)
        if visible then
            local maxH = GetEntityMaxHealth(ped)
            local h = IsEntityDead(ped) and 0 or math.floor((GetEntityHealth(ped) - 100) / math.max(maxH - 100, 1) * 100 + 0.5)
            local a = GetPedArmour(ped)
            h = math.max(0, math.min(100, h))
            if h ~= lastH or a ~= lastA or not shown then
                SendNUIMessage({ type = 'vitals', data = { health = h, armour = a } })
                lastH, lastA, shown = h, a, true
            end
            Wait(50)
        else
            if shown then
                SendNUIMessage({ type = 'vitals', data = nil })
                shown, lastH, lastA = false, -1, -1
            end
            Wait(250)
        end
    end
end)
