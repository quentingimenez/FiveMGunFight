-- =============================================================================
--  gf_screen - SERVEUR
--  Visionnage discret de l'écran d'un joueur par un administrateur : la cible
--  n'est jamais prévenue. Aucune image n'est stockée côté serveur : elle est
--  relayée au seul administrateur qui regarde, sous limite de débit.
-- =============================================================================

local core = exports.gf_core
local PREFIXE = 'data:image/jpeg;base64,'
local FENETRE_MS = 1000

local Watching = {} -- [admin] = { target = id, startedAt = GetGameTimer() }
local Viewer = {}   -- [cible] = admin
local Debit = {}    -- [cible] = { fenetre = GetGameTimer(), images = n }

local function reply(src, msg)
    if src == 0 then
        print('[gf_screen] ' .. msg)
    else
        core:Notify(src, msg)
    end
end

-- Droits : un refus ne produit RIEN d'autre que la notification d'origine.
local function estAdmin(src)
    if src == 0 then return true end
    local ok, admin = pcall(function() return core:IsAdmin(src) end)
    return ok and admin == true
end

-- Cible connectée : GetPlayerName est vérifié avant toute action.
local function cibleValide(args)
    local cible = tonumber(args[1])
    if not cible then return nil, nil end
    local nom = GetPlayerName(cible)
    if not nom then return nil, nil end
    return cible, nom
end

-- Arrêt complet d'une vue. silencieux = vrai lors d'un changement de cible ou
-- d'un départ d'administrateur : aucun reply, mais les events partent quand même.
local function stop(admin, message, silencieux)
    local etat = Watching[admin]
    if not etat then return end
    local cible = etat.target
    TriggerClientEvent('gf_screen:captureStop', cible)
    TriggerClientEvent('gf_screen:viewStop', admin)
    Watching[admin] = nil
    if Viewer[cible] == admin then Viewer[cible] = nil end
    Debit[cible] = nil
    if not silencieux and GetPlayerName(admin) ~= nil then
        reply(admin, message or 'Écran arrêté.')
    end
end

-- screen <id> : ouvre une vue ; screen seul : arrête la vue en cours.
RegisterCommand('screen', function(src, args)
    if not estAdmin(src) then
        core:Notify(src, 'Réservé aux administrateurs.')
        return
    end
    if src == 0 then
        reply(src, 'Commande à utiliser en jeu.')
        return
    end

    if args[1] == nil then
        if Watching[src] then
            stop(src)
        else
            reply(src, 'Usage : screen <id> (ex. screen 12) ; screen seul pour arrêter.')
        end
        return
    end

    local cible, nom = cibleValide(args)
    if not cible then
        reply(src, ('Joueur %s introuvable.'):format(tostring(args[1])))
        return
    end
    if cible == src then
        reply(src, 'Tu ne peux pas regarder ton propre écran.')
        return
    end

    -- Deux administrateurs ne peuvent pas regarder la même cible : refus
    -- explicite, sans toucher à la vue déjà en cours.
    if Viewer[cible] ~= nil and Viewer[cible] ~= src then
        reply(src, ('%s est déjà regardé par un administrateur.'):format(nom))
        return
    end

    if Watching[src] then
        if Watching[src].target == cible then
            stop(src)           -- même cible : arrêt simple
            return
        end
        stop(src, nil, true)    -- autre cible : arrêt muet puis nouvelle vue
    end

    Watching[src] = { target = cible, startedAt = GetGameTimer() }
    Viewer[cible] = src
    Debit[cible] = { fenetre = GetGameTimer(), images = 0 }

    TriggerClientEvent('gf_screen:captureStart', cible, {
        fps = Config.Fps, width = Config.Width, quality = Config.Quality,
    })
    TriggerClientEvent('gf_screen:viewStart', src, { target = cible, name = nom })
    reply(src, ('Écran de %s. Tape screen pour arrêter.'):format(nom))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'screen', cible, nil) end)
    end
end, false)

-- Une seule image reçue du joueur regardé, relayée telle quelle à son admin.
RegisterNetEvent('gf_screen:frame', function(image)
    local src = source

    -- Seul le joueur effectivement regardé peut émettre ; tout le reste est
    -- ignoré silencieusement (pas de notify, pas d'event, rien de stocké).
    local admin = Viewer[src]
    if not admin then return end
    if type(image) ~= 'string' then return end
    if image:sub(1, #PREFIXE) ~= PREFIXE then return end
    if #image > Config.MaxFrameChars then return end

    -- Fenêtre fixe de 1 000 ms, au plus Fps + 1 images. Les images invalides
    -- sont écartées avant ce comptage : elles ne consomment aucun quota.
    local maintenant = GetGameTimer()
    local etat = Debit[src]
    if not etat or maintenant - etat.fenetre >= FENETRE_MS then
        etat = { fenetre = maintenant, images = 0 }
        Debit[src] = etat
    end
    if etat.images >= Config.Fps + 1 then return end
    etat.images = etat.images + 1

    TriggerLatentClientEvent('gf_screen:frame', admin, 600000, image)
end)

-- Expiration des vues : admin parti, cible partie, durée maximale atteinte.
CreateThread(function()
    while true do
        for admin, etat in pairs(Watching) do
            if GetPlayerName(admin) == nil then
                stop(admin, nil, true) -- nettoyage muet
            elseif GetPlayerName(etat.target) == nil then
                stop(admin, 'Le joueur a quitté le serveur : écran arrêté.')
            elseif GetGameTimer() - etat.startedAt >= Config.MaxSeconds * 1000 then
                stop(admin, 'Durée maximale atteinte : écran arrêté.')
            end
        end
        Wait(1000)
    end
end)

-- Déconnexion : libère les deux côtés (admin et cible) et les compteurs.
AddEventHandler('playerDropped', function()
    local src = source

    -- Admin parti : captureStop vers sa cible, aucun message, aucun viewStop
    -- inutile vers un joueur déjà déconnecté.
    if Watching[src] then
        local cible = Watching[src].target
        TriggerClientEvent('gf_screen:captureStop', cible)
        Watching[src] = nil
        if Viewer[cible] == src then Viewer[cible] = nil end
        Debit[cible] = nil
    end

    -- Cible partie : l'admin est prévenu et sa vue est arrêtée.
    local admin = Viewer[src]
    if admin then
        TriggerClientEvent('gf_screen:viewStop', admin)
        if Watching[admin] and Watching[admin].target == src then
            Watching[admin] = nil
            if GetPlayerName(admin) ~= nil then
                reply(admin, 'Le joueur a quitté le serveur : écran arrêté.')
            end
        end
        Viewer[src] = nil
        Debit[src] = nil
    end
end)
