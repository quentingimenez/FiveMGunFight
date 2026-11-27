-- =============================================================================
--  gf_admin - SERVEUR
--  Seule source de vérité du panneau : droits et liste des joueurs sont lus
--  côté serveur. Aucune donnée d'identifiant (license, IP, Discord, nom) ne
--  transite dans les messages, les événements ou les journaux.
-- =============================================================================

local core = exports.gf_core
local RESOURCE = 'gf_admin'
local DERNIERE_DEMANDE = {}  -- [src] = GetGameTimer() de la dernière demande admise
local DERNIERE_FIN_SPECTATE = {} -- [src] = GetGameTimer() du dernier arrêt local signalé
local DELAI_MS = 500
local Geles = {}             -- [src] = true tant que le joueur est gelé par un admin
local Spectating = {}        -- [admin] = { target = id, bucket = monde d'origine }

-- Texte libre : supprime contrôles et séparateurs, réduit les espaces, tronque.
-- Aucun identifiant ne doit passer par là (license, IP, Discord, steam...).
local function nettoyerTexte(texte, max)
    if type(texte) ~= 'string' then return '' end
    local propre = texte:gsub('%c', ' '):gsub('[;|\\`"]', '')
    propre = propre:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if max and #propre > max then propre = propre:sub(1, max) end
    return propre
end

local function reply(src, msg)
    if src == 0 then
        print('[gf_admin] ' .. msg)
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

local function joindreArgs(args, depart)
    local morceaux = {}
    for i = depart, #args do
        morceaux[#morceaux + 1] = tostring(args[i])
    end
    return table.concat(morceaux, ' ')
end

-- Un seul événement réseau, sans argument : tout vient de `source`.
RegisterNetEvent('gf_admin:requestData', function()
    local src = source

    -- Rate-limit 1 requête / 500 ms, AVANT le contrôle admin et pour tout le monde.
    -- Refus silencieux : un non-admin ne peut pas déclencher Notify/denied/print en boucle.
    local maintenant = GetGameTimer()
    if DERNIERE_DEMANDE[src] and maintenant - DERNIERE_DEMANDE[src] < DELAI_MS then
        return
    end
    DERNIERE_DEMANDE[src] = maintenant

    -- Les droits sont vérifiés avant toute lecture de données.
    local okAdmin, admin = pcall(function() return core:IsAdmin(src) end)
    if not okAdmin or admin ~= true then
        core:Notify(src, 'Réservé aux administrateurs.')
        TriggerClientEvent('gf_admin:denied', src)
        print(('[%s] demande refusée : non-administrateur'):format(RESOURCE))
        return
    end

    local players = {}
    for _, valeur in ipairs(GetPlayers()) do
        local id = tonumber(valeur)
        if id then
            local okMode, mode = pcall(function() return core:GetMode(id) end)
            if not okMode then mode = nil end
            local okTeam, team = pcall(function() return core:GetTeam(id) end)
            if not okTeam then team = nil end
            players[#players + 1] = {
                id = id,
                name = GetPlayerName(id),
                mode = mode,
                team = team,
                ping = GetPlayerPing(id),
            }
        end
    end
    table.sort(players, function(a, b) return a.id < b.id end)

    local okCatalogue, catalogue = pcall(function() return core:GetWeaponCatalog() end)
    local weapons = okCatalogue and type(catalogue) == 'table' and catalogue or {}

    TriggerClientEvent('gf_admin:data', src, { players = players, weapons = weapons })
end)

-- ------------------------------------------------------------------ Commandes
-- kick <id> [raison...]
RegisterCommand('kick', function(src, args)
    if not estAdmin(src) then
        core:Notify(src, 'Réservé aux administrateurs.')
        return
    end
    if args[1] == nil then
        reply(src, 'Usage : kick <id> [raison] (ex. kick 12 triche)')
        return
    end

    local cible, nom = cibleValide(args)
    if not cible then
        reply(src, ('Joueur %s introuvable.'):format(tostring(args[1])))
        return
    end
    if src ~= 0 and cible == src then
        reply(src, 'Tu ne peux pas t’expulser toi-même.')
        return
    end

    local raison = nettoyerTexte(joindreArgs(args, 2), 80)
    if raison == '' then raison = 'aucune raison' end
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'kick', cible, 'raison=' .. raison) end)
    end
    DropPlayer(cible, 'Expulsé par un administrateur : ' .. raison)
    reply(src, ('%s expulsé.'):format(nom))
end, false)

-- goto <id> : déplace l'administrateur près de la cible (en jeu seulement).
RegisterCommand('goto', function(src, args)
    if not estAdmin(src) then
        core:Notify(src, 'Réservé aux administrateurs.')
        return
    end
    if src == 0 then
        reply(src, 'Commande à utiliser en jeu.')
        return
    end
    if args[1] == nil then
        reply(src, 'Usage : goto <id> (ex. goto 12)')
        return
    end

    local cible, nom = cibleValide(args)
    if not cible then
        reply(src, ('Joueur %s introuvable.'):format(tostring(args[1])))
        return
    end
    if cible == src then
        reply(src, 'Tu ne peux pas te téléporter toi-même.')
        return
    end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(cible) then
        reply(src, ('%s est dans un autre mode : utilise d’abord setmode.'):format(nom))
        return
    end

    local coords = GetEntityCoords(GetPlayerPed(cible))
    TriggerClientEvent('gf_admin:teleport', src, {
        x = coords.x + 1.5, y = coords.y, z = coords.z,
    })
    reply(src, ('Téléporté près de %s.'):format(nom))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'goto', cible, nil) end)
    end
end, false)

-- bring <id> : amène la cible près de l'administrateur (en jeu seulement).
RegisterCommand('bring', function(src, args)
    if not estAdmin(src) then
        core:Notify(src, 'Réservé aux administrateurs.')
        return
    end
    if src == 0 then
        reply(src, 'Commande à utiliser en jeu.')
        return
    end
    if args[1] == nil then
        reply(src, 'Usage : bring <id> (ex. bring 12)')
        return
    end

    local cible, nom = cibleValide(args)
    if not cible then
        reply(src, ('Joueur %s introuvable.'):format(tostring(args[1])))
        return
    end
    if cible == src then
        reply(src, 'Tu ne peux pas te ramener toi-même.')
        return
    end
    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(cible) then
        reply(src, ('%s est dans un autre mode : utilise d’abord setmode.'):format(nom))
        return
    end

    local coords = GetEntityCoords(GetPlayerPed(src))
    TriggerClientEvent('gf_admin:teleport', cible, {
        x = coords.x + 1.5, y = coords.y, z = coords.z,
    })
    core:Notify(cible, 'Un administrateur t’a téléporté.')
    reply(src, ('%s téléporté près de toi.'):format(nom))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'bring', cible, nil) end)
    end
end, false)

-- heal <id> : soin accordé, tracé par gf_audit avant le signalement client.
RegisterCommand('heal', function(src, args)
    if not estAdmin(src) then
        core:Notify(src, 'Réservé aux administrateurs.')
        return
    end
    if args[1] == nil then
        reply(src, 'Usage : heal <id> (ex. heal 12)')
        return
    end

    local cible, nom = cibleValide(args)
    if not cible then
        reply(src, ('Joueur %s introuvable.'):format(tostring(args[1])))
        return
    end

    TriggerEvent('gf:healGranted', cible)
    TriggerClientEvent('gf_admin:heal', cible)
    core:Notify(cible, 'Un administrateur t’a soigné.')
    reply(src, ('%s soigné.'):format(nom))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'heal', cible, nil) end)
    end
end, false)

-- freeze <id> : bascule le gel côté cible.
RegisterCommand('freeze', function(src, args)
    if not estAdmin(src) then
        core:Notify(src, 'Réservé aux administrateurs.')
        return
    end
    if args[1] == nil then
        reply(src, 'Usage : freeze <id> (ex. freeze 12)')
        return
    end

    local cible, nom = cibleValide(args)
    if not cible then
        reply(src, ('Joueur %s introuvable.'):format(tostring(args[1])))
        return
    end

    local nouvelEtat = not Geles[cible]
    if nouvelEtat then Geles[cible] = true else Geles[cible] = nil end
    core:Freeze(cible, nouvelEtat)
    if nouvelEtat then
        core:Notify(cible, 'Un administrateur t’a gelé.')
        reply(src, ('%s gelé.'):format(nom))
    else
        core:Notify(cible, 'Un administrateur t’a dégelé.')
        reply(src, ('%s dégelé.'):format(nom))
    end
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'freeze', cible, nouvelEtat and 'etat=gele' or 'etat=degele') end)
    end
end, false)

-- announce <texte...> : annonce globale, sans identifiant dans le texte.
RegisterCommand('announce', function(src, args)
    if not estAdmin(src) then
        core:Notify(src, 'Réservé aux administrateurs.')
        return
    end

    local usage = 'Usage : announce <texte> (ex. announce Redémarrage dans 5 minutes)'
    local texte = nettoyerTexte(joindreArgs(args, 1))
    if texte == '' or #texte > 120 then
        reply(src, usage)
        return
    end

    TriggerClientEvent('gf_ui:announce', -1, {
        title = 'ANNONCE', subtitle = texte, duration = 8000,
    })
    reply(src, 'Annonce envoyée.')

    local auteur = 'console'
    if src ~= 0 then auteur = GetPlayerName(src) or ('joueur %d'):format(src) end
    print(('[gf_admin] Annonce de %s : %s'):format(auteur, texte))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'announce', nil, 'texte=' .. texte) end)
    end
end, false)

-- spectate <id> : l'admin suit la cible sans la prévenir (jeu seulement).
-- stop : restaure le monde d'origine et coupe la vue ; silencieux = vrai uniquement
-- lors d'un changement de cible (aucun reply, mais spectateStop bien envoyé).
local function stop(admin, message, silencieux)
    local etat = Spectating[admin]
    if not etat then return end
    if admin ~= 0 then
        SetPlayerRoutingBucket(admin, etat.bucket)
    end
    Spectating[admin] = nil
    TriggerClientEvent('gf_admin:spectateStop', admin)
    if not silencieux and GetPlayerName(admin) ~= nil then
        reply(admin, message or 'Vue arrêtée.')
    end
end

RegisterCommand('spectate', function(src, args)
    if not estAdmin(src) then
        core:Notify(src, 'Réservé aux administrateurs.')
        return
    end
    if src == 0 then
        reply(src, 'Commande à utiliser en jeu.')
        return
    end

    -- Sans argument : arrêt si une vue est en cours, sinon l'usage.
    if args[1] == nil then
        if Spectating[src] then
            stop(src)
        else
            reply(src, 'Usage : spectate <id> (ex. spectate 12) ; spectate seul pour arrêter.')
        end
        return
    end

    local cible, nom = cibleValide(args)
    if not cible then
        reply(src, ('Joueur %s introuvable.'):format(tostring(args[1])))
        return
    end
    if cible == src then
        reply(src, "Tu ne peux pas te regarder toi-même.")
        return
    end

    -- Même cible : arrêt simple. Autre cible : arrêt muet puis nouvelle vue.
    if Spectating[src] then
        if Spectating[src].target == cible then
            stop(src)
            return
        end
        stop(src, nil, true)
    end

    local bucket = GetPlayerRoutingBucket(src)
    if GetPlayerRoutingBucket(cible) ~= bucket then
        SetPlayerRoutingBucket(src, GetPlayerRoutingBucket(cible))
    end
    local coords = GetEntityCoords(GetPlayerPed(cible))
    Spectating[src] = { target = cible, bucket = bucket }
    TriggerClientEvent('gf_admin:spectateStart', src, {
        target = cible, name = nom, x = coords.x, y = coords.y, z = coords.z,
    })
    reply(src, ('Vue de %s. Tape spectate pour arrêter.'):format(nom))
    if GetResourceState('gf_admin') == 'started' then
        pcall(function() exports.gf_admin:LogAction(src, 'spectate', cible, nil) end)
    end
end, false)

-- Suivi : une seule boucle, une passe complète avant chaque Wait (global).
CreateThread(function()
    while true do
        -- Une passe complète sur Spectating.
        for admin, etat in pairs(Spectating) do
            if GetPlayerName(admin) == nil then
                -- Admin parti : nettoyage muet, sans changer de monde ni d'événement.
                Spectating[admin] = nil
            elseif GetPlayerName(etat.target) == nil then
                -- Cible partie : retour dans le monde d'origine de l'admin.
                stop(admin, 'Le joueur a quitté le serveur : vue arrêtée.')
            else
                if GetPlayerRoutingBucket(etat.target) ~= GetPlayerRoutingBucket(admin) then
                    SetPlayerRoutingBucket(admin, GetPlayerRoutingBucket(etat.target))
                end
                local coords = GetEntityCoords(GetPlayerPed(etat.target))
                TriggerClientEvent('gf_admin:spectatePos', admin, {
                    x = coords.x, y = coords.y, z = coords.z,
                })
            end
        end
        Wait(1000)
    end
end)

-- Le client peut arrêter sa caméra seul (respawn de l'admin, cible introuvable
-- après 5 s). On réconcilie cet arrêt local sans rien renvoyer au client.
-- Aucun contrôle admin : cet événement ne retire que l'état propre à `src`
-- (Spectating[src]), il ne peut donc pas toucher un autre joueur.
RegisterNetEvent('gf_admin:spectateEnded', function(...)
    local src = source
    -- arguments ignorés : le contrat n'en transmet aucun
    if select('#', ...) > 0 then return end
    -- rate-limit 1 / 500 ms par joueur, AVANT le contrôle d'état
    local maintenant = GetGameTimer()
    if DERNIERE_FIN_SPECTATE[src] and maintenant - DERNIERE_FIN_SPECTATE[src] < 500 then return end
    DERNIERE_FIN_SPECTATE[src] = maintenant
    local etat = Spectating[src]
    if not etat then return end
    -- le client a déjà arrêté sa caméra : restauration silencieuse
    if src ~= 0 then SetPlayerRoutingBucket(src, etat.bucket) end
    Spectating[src] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    DERNIERE_DEMANDE[src] = nil
    DERNIERE_FIN_SPECTATE[src] = nil
    Geles[src] = nil
    -- Admin parti : nettoyage muet, sans changer son monde ni envoyer d'événement.
    if Spectating[src] then Spectating[src] = nil end
end)
