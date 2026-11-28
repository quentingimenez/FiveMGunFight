-- =============================================================================
--  gf_admin - CLIENT
--  Panneau d'administration NUI (touche F10). Les droits sont revérifiés côté
--  serveur : aucun état d'administrateur n'est conservé ici.
--  Toute fermeture passe par fermer() : un seul endroit remet le focus.
-- =============================================================================

local ouvert = false

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
    exports.gf_ui:PushLayer(GetCurrentResourceName())
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
    exports.gf_ui:PopLayer(GetCurrentResourceName())
end

-- Passerelle de test NUI : fermeture demandée par la console serveur.
RegisterNetEvent('gf_testbridge:fermer', function(page)
    if page ~= GetCurrentResourceName() then return end
    if ouvert then fermer() end
end)

-- ---------------------------------------------------------------------- État

RegisterNetEvent('gf_core:modeChanged', function(mode)
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

-- --------------------------------------------------- Actions demandées au client

-- Téléportation validée côté serveur : la table et ses coordonnées doivent être
-- des nombres finis. Aucun effet si le ped n'existe pas (joueur en chargement).
RegisterNetEvent('gf_admin:teleport', function(p)
    if type(p) ~= 'table' then return end
    local x, y, z = p.x, p.y, p.z
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end
    if x ~= x or y ~= y or z ~= z then return end -- NaN
    if x == math.huge or x == -math.huge
        or y == math.huge or y == -math.huge
        or z == math.huge or z == -math.huge then return end

    local ped = PlayerPedId()
    if ped == 0 then return end
    SetEntityCoords(ped, x, y, z, false, false, false, false)
end)

-- Soin accordé par un administrateur (le serveur a déjà tracé l'audit).
RegisterNetEvent('gf_admin:heal', function()
    local ped = PlayerPedId()
    if ped == 0 or IsEntityDead(ped) then return end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
end)

-- ----------------------------------------------------------------- Spectate

-- Une seule vue active à la fois. session sert de garde : si une vue est
-- arrêtée (ou remplacée) pendant l'attente de la cible, l'ancien thread ne
-- doit jamais réactiver le mode spectateur après coup.
-- spectateEnCours couvre aussi l'attente de 5 s : un arrêt pendant celle-ci
-- doit restaurer le ped, sinon il resterait invisible et gelé.
local spectateActif = false
local spectateEnCours = false
local session = 0
local spectateCible = nil -- id serveur de la cible
local spectateNom = ''
local spectatePed = 0 -- ped de la cible actuellement suivi
local spectatePos = nil -- dernières coordonnées reçues (x, y, z)
local spectateSauvegarde = nil
local spectateDernierMouvement = 0

--- Un nombre doit être fini : NaN et infinis sont rejetés.
local function nombreFini(valeur)
    if type(valeur) ~= 'number' then return false end
    if valeur ~= valeur then return false end
    return valeur ~= math.huge and valeur ~= -math.huge
end

--- Identifiant serveur : entier strictement positif et fini.
local function idValide(valeur)
    return nombreFini(valeur) and valeur % 1 == 0 and valeur > 0
end

--- Coordonnées : table avec trois nombres finis (x, y, z).
local function coordsValides(p)
    if type(p) ~= 'table' then return false end
    return nombreFini(p.x) and nombreFini(p.y) and nombreFini(p.z)
end

--- Remettre le ped exactement dans son état d'origine. Ne pas forcer false :
--- gf_core peut avoir gelé ou protégé le joueur avant la vue.
local function restaurerEtat(ped, etat)
    if ped == 0 or not DoesEntityExist(ped) or etat == nil then return end
    SetEntityCoords(ped, etat.x, etat.y, etat.z, false, false, false, false)
    SetEntityHeading(ped, etat.heading)
    SetEntityVisible(ped, etat.visible, false)
    SetEntityCollision(ped, not etat.collisionDesactivee, true)
    FreezeEntityPosition(ped, etat.gele)
    SetEntityInvincible(ped, etat.invincible)
    SetPlayerInvincible(PlayerId(), etat.invincible)
end

--- SEUL chemin d'arrêt : idempotent. Par défaut aucun événement serveur n'est
--- envoyé : le serveur restaurera le monde à la prochaine commande.
--- Les arrêts décidés par le client le préviennent avec prevenirServeur = true.
local function arreter(prevenirServeur)
    if prevenirServeur == nil then prevenirServeur = false end
    if not spectateEnCours then return end
    spectateActif = false
    spectateEnCours = false
    -- Invalider l'attente en cours avant toute autre opération.
    session = session + 1

    local ped = spectateSauvegarde and spectateSauvegarde.ped or PlayerPedId()
    DoScreenFadeOut(250)
    -- Le natif attend le ped du spectateur (celui du joueur admin).
    NetworkSetInSpectatorMode(false, PlayerPedId())
    restaurerEtat(ped, spectateSauvegarde)

    spectatePed = 0
    spectateCible = nil
    spectateNom = ''
    spectatePos = nil
    spectateSauvegarde = nil
    DoScreenFadeIn(250)
    if prevenirServeur then TriggerServerEvent('gf_admin:spectateEnded') end
end

--- Résoudre le ped de la cible et conserver ses dernières coordonnées.
local function resoudreCible()
    if spectateCible == nil then return nil end
    local player = GetPlayerFromServerId(spectateCible)
    if player == -1 then return nil end
    local ped = GetPlayerPed(player)
    if ped == 0 or not DoesEntityExist(ped) then return nil end
    local coords = GetEntityCoords(ped)
    if coordsValides(coords) then
        spectatePos = { x = coords.x, y = coords.y, z = coords.z }
    end
    return ped
end

--- Thread unique de la vue : texte chaque frame, déplacement toutes les 500 ms.
local function threadSpectate(maSession)
    CreateThread(function()
        while spectateActif and session == maSession do
            Wait(0)
            -- arreter() peut être intervenu pendant le Wait : sortir sans
            -- rien réactiver ni toucher à un état déjà remis à nil.
            if not spectateActif or session ~= maSession then break end

            SetTextFont(4)
            SetTextScale(0.35, 0.35)
            SetTextColour(255, 255, 255, 215)
            SetTextCentre(true)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(
                ('VUE DE %s — spectate (F8) ou F10 > Arrêter la vue'):format(spectateNom))
            EndTextCommandDisplayText(0.5, 0.95)

            local maintenant = GetGameTimer()
            if maintenant - spectateDernierMouvement >= 500 then
                spectateDernierMouvement = maintenant
                if not spectateActif or session ~= maSession or spectateSauvegarde == nil then
                    break
                end
                local ped = resoudreCible()
                if ped and ped ~= 0 and ped ~= spectatePed then
                    -- Respawn : quitter l'ancien ped avant d'activer le nouveau.
                    if spectatePed ~= 0 and DoesEntityExist(spectatePed) then
                        NetworkSetInSpectatorMode(false, spectatePed)
                    end
                    spectatePed = ped
                    NetworkSetInSpectatorMode(true, ped)
                end
                local admin = spectateSauvegarde.ped
                if spectatePos and admin ~= 0 and DoesEntityExist(admin) then
                    SetEntityCoords(admin, spectatePos.x, spectatePos.y, spectatePos.z - 10.0,
                        false, false, false, false)
                end
            end
        end
    end)
end

--- Démarrage : arrêter une vue existante, puis préparer le ped admin et
--- attendre jusqu'à 5 s l'apparition de la cible.
local function demarrer(d)
    if not coordsValides(d) or not idValide(d.target) or type(d.name) ~= 'string' then return end

    if spectateEnCours then arreter() end

    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then return end

    local coordsAdmin = GetEntityCoords(ped)
    spectateSauvegarde = {
        ped = ped,
        x = coordsAdmin.x,
        y = coordsAdmin.y,
        z = coordsAdmin.z,
        heading = GetEntityHeading(ped),
        visible = IsEntityVisible(ped),
        -- GetEntityCollisionDisabled : true signifie collision désactivée.
        collisionDesactivee = GetEntityCollisionDisabled(ped),
        gele = IsEntityPositionFrozen(ped),
        invincible = GetPlayerInvincible(PlayerId()),
    }

    spectateCible = d.target
    spectateNom = d.name
    spectatePos = { x = d.x, y = d.y, z = d.z }
    spectatePed = 0
    spectateEnCours = true
    local maSession = session + 1
    session = maSession

    DoScreenFadeOut(250)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetPlayerInvincible(PlayerId(), true)
    SetEntityCoords(ped, d.x, d.y, d.z - 10.0, false, false, false, false)
    RequestCollisionAtCoord(d.x, d.y, d.z)

    local deadline = GetGameTimer() + 5000
    local cible = nil
    while GetGameTimer() < deadline and session == maSession do
        cible = resoudreCible()
        if cible ~= 0 and cible ~= nil then break end
        Wait(50)
    end

    -- Arrêt, remplacement ou respawn pendant l'attente : ne rien activer.
    if session ~= maSession or not spectateSauvegarde then return end

    if cible == nil or cible == 0 then
        arreter(true)
        TriggerEvent('gf_ui:notify', {
            text = 'Joueur introuvable à proximité : vue annulée.',
            level = 'error',
        })
        return
    end

    spectatePed = cible
    spectateActif = true
    spectateDernierMouvement = GetGameTimer()
    NetworkSetInSpectatorMode(true, cible)
    DoScreenFadeIn(250)
    threadSpectate(maSession)
end

RegisterNetEvent('gf_admin:spectateStart', function(d)
    if type(d) ~= 'table' then return end
    demarrer(d)
end)

RegisterNetEvent('gf_admin:spectatePos', function(p)
    if not spectateEnCours or not coordsValides(p) then return end
    spectatePos = { x = p.x, y = p.y, z = p.z }
end)

RegisterNetEvent('gf_admin:spectateStop', function()
    arreter()
end)

-- gf_core dégèle le ped à chaque spawn : arrêter immédiatement et prévenir le
-- serveur, qui doit savoir que la vue n'est plus active.
RegisterNetEvent('gf_core:spawned', function()
    if spectateEnCours then arreter(true) end
end)

-- -------------------------------------------------------------- Fin de ressource

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if spectateEnCours then arreter() end
    if ouvert then fermer() end
end)
