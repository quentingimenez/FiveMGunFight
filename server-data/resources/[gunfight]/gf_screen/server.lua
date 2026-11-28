-- =============================================================================
--  gf_screen - SERVEUR
--  Visionnage discret de l'écran d'un joueur par un administrateur : la cible
--  n'est jamais prévenue. Aucune image n'est stockée côté serveur : elle est
--  relayée au seul administrateur qui regarde, sous limite de débit.
-- =============================================================================

local core = exports.gf_core
local PREFIXES = {
    'data:image/webp;base64,',
    'data:image/jpeg;base64,',
}
local FENETRE_MS = 1000

-- Clés exactes de la table meta acceptée (ni plus, ni moins).
local META_KEYS = {
    hp = true, armour = true, weapon = true, clip = true, ammo = true,
    mode = true, vehicle = true, speed = true, w = true, h = true,
}
local META_COUNT = 10

local Watching = {} -- [admin] = { target = id, startedAt = GetGameTimer(), preset = nom }
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

local function nombreFini(valeur)
    if type(valeur) ~= 'number' then return false end
    if valeur ~= valeur then return false end
    return valeur ~= math.huge and valeur ~= -math.huge
end

-- Entier au sens mathématique : 50.0 passe, 50.5 est refusé.
local function entier(valeur, min, max)
    if not nombreFini(valeur) or valeur % 1 ~= 0 then return nil end
    if valeur < min or valeur > max then return nil end
    return math.floor(valeur)
end

-- Méta strictement validée : table invalide ou incomplète → nil (non bloquant).
local function metaValide(meta)
    if type(meta) ~= 'table' then return nil end
    local count = 0
    for key in pairs(meta) do
        if not META_KEYS[key] then return nil end
        count = count + 1
    end
    if count ~= META_COUNT then return nil end

    local hp = entier(meta.hp, 0, 100)
    local armour = entier(meta.armour, 0, 100)
    local clip = entier(meta.clip, 0, 9999)
    local ammo = entier(meta.ammo, 0, 9999)
    local w = entier(meta.w, 1, 4096)
    local h = entier(meta.h, 1, 4096)
    if not hp or not armour or not clip or not ammo or not w or not h then return nil end
    if type(meta.weapon) ~= 'string' or type(meta.mode) ~= 'string' then return nil end
    if type(meta.vehicle) ~= 'boolean' then return nil end
    if not nombreFini(meta.speed) or meta.speed < 0 or meta.speed > 999 then return nil end

    return {
        hp = hp, armour = armour, clip = clip, ammo = ammo,
        weapon = meta.weapon:sub(1, 32), mode = meta.mode:sub(1, 16),
        vehicle = meta.vehicle, speed = meta.speed, w = w, h = h,
    }
end

local function imageValide(image)
    if type(image) ~= 'string' or #image > Config.MaxFrameChars then return false end
    for _, prefixe in ipairs(PREFIXES) do
        if image:sub(1, #prefixe) == prefixe then return true end
    end
    return false
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

local function demarrerVue(src, cible, nom, preset)
    local P = Config.Presets[preset]
    Watching[src] = { target = cible, startedAt = GetGameTimer(), preset = preset }
    Viewer[cible] = src
    Debit[cible] = { fenetre = GetGameTimer(), images = 0 }

    TriggerClientEvent('gf_screen:captureStart', cible, {
        fps = P.fps, width = P.width, quality = P.quality, format = 'webp',
    })
    TriggerClientEvent('gf_screen:viewStart', src, { target = cible, name = nom, preset = preset })
    reply(src, ('Écran de %s (%s). Tape screen pour arrêter.'):format(nom, preset))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'screen', cible, 'qualite=' .. preset) end)
    end
end

-- screen <id> [basse|moyenne|haute|ultra] : ouvre une vue ; screen seul : arrête la vue.
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

    -- Validation du préréglage avant toute modification d'état.
    local preset = args[2] or Config.DefaultPreset
    if not Config.Presets[preset] then
        reply(src, 'Qualité inconnue : basse, moyenne, haute ou ultra.')
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
        local etat = Watching[src]
        if etat.target == cible then
            if args[2] ~= nil then
                -- Même cible, nouvelle qualité : on ne fait que réorienter la capture.
                local P = Config.Presets[preset]
                etat.preset = preset
                Debit[cible] = { fenetre = GetGameTimer(), images = 0 }
                TriggerClientEvent('gf_screen:captureStart', cible, {
                    fps = P.fps, width = P.width, quality = P.quality, format = 'webp',
                })
            else
                stop(src) -- même cible sans qualité : arrêt simple
            end
            return
        end
        stop(src, nil, true) -- autre cible : arrêt muet puis nouvelle vue
    end

    demarrerVue(src, cible, nom, preset)
end, false)

-- Une image reçue du joueur regardé, relayée à son admin avec sa méta.
RegisterNetEvent('gf_screen:frame', function(payload)
    local src = source

    -- Seul le joueur effectivement regardé peut émettre ; tout le reste est
    -- ignoré silencieusement (pas de notify, pas d'event, rien de stocké).
    local admin = Viewer[src]
    if not admin then return end
    if type(payload) ~= 'table' then return end
    if not imageValide(payload.image) then return end

    -- Fenêtre fixe de 1 000 ms, au plus (préréglage courant + 1) images. Les
    -- images invalides sont écartées avant ce comptage : aucun quota consommé.
    local maintenant = GetGameTimer()
    local etat = Debit[src]
    if not etat or maintenant - etat.fenetre >= FENETRE_MS then
        etat = { fenetre = maintenant, images = 0 }
        Debit[src] = etat
    end
    local watch = Watching[admin]
    if not watch then return end
    local P = Config.Presets[watch.preset]
    if not P then return end
    if etat.images >= P.fps + 1 then return end
    etat.images = etat.images + 1

    TriggerLatentClientEvent('gf_screen:frame', admin, Config.ForwardBps, {
        image = payload.image,
        meta = metaValide(payload.meta),
        preset = watch.preset,
    })
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
