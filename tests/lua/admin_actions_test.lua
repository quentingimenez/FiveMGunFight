-- =============================================================================
--  Tests des actions d'administration gf_admin (serveur).
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/admin_actions_test.lua
--  Les chunks Lua sont chargés avec loadfile(path, 't', env) dans un environnement
--  simulé : ni FiveM, ni base de données, ni dépendance externe. Aucune règle
--  métier n'est recopiée ici : les vrais handlers enregistrés par server.lua
--  sont appelés, et seul le contrat observable est vérifié.
-- =============================================================================

local root = os.getenv('GF_ROOT') or '.'

local ok = 0

local function check(condition, message)
    if not condition then
        io.stderr:write(('ECHEC : %s\n'):format(tostring(message)))
        os.exit(1)
    end
    ok = ok + 1
end

-- ---------------------------------------------------------------------------
-- Données de fonctionnement et enregistrements du harnais.
-- ---------------------------------------------------------------------------
local admins = { [1] = true, [2] = false, [3] = false }
local names = { [1] = 'Alpha', [2] = 'Bravo', [3] = 'Charlie' }
local pings = { [1] = 11, [2] = 22, [3] = 33 }
local buckets = { [1] = 0, [2] = 5, [3] = 0 }
local peds = { [1] = 101, [2] = 102, [3] = 103 }
local coords = {
    [101] = { x = 100, y = 200, z = 30 },
    [102] = { x = 200, y = 300, z = 40 },
    [103] = { x = 10, y = 20, z = 30 },
}

-- Un seul journal global : l'ordre entre événements locaux et réseau est observable.
local journal = {}      -- { { kind, name, target, data, ordre }, ... }
local notices = {}      -- { { src, message }, ... }
local prints = {}       -- lignes produites par le print de env
local drops = {}        -- { { src, reason, ordre }, ... }
local freezes = {}      -- { { src, etat }, ... }
local audits = {}       -- { { src, action, cible, details, ordre }, ... }
local routingSets = {}  -- { { src, bucket }, ... } : SetPlayerRoutingBucket
local threads = {}      -- CreateThread : fonctions capturées, jamais lancées automatiquement
local commands = {}     -- RegisterCommand : commands[nom] = handler
local handlers = {}     -- RegisterNetEvent
local eventHandlers = {} -- AddEventHandler

local now = 1000

-- Ordre partagé entre DropPlayer et LogAction : prouve que kick journalise
-- avant d'expulser une cible qui n'a alors plus de nom ni de licence.
local sequence = 0
local function prochainOrdre()
    sequence = sequence + 1
    return sequence
end

-- Archivage avant chaque remise à zéro : le contrôle d'absence d'identifiant
-- porte sur tout ce que la suite de tests a produit, pas seulement le dernier cas.
local archive = {
    journal = {}, notices = {}, prints = {}, drops = {}, freezes = {}, audits = {}, routingSets = {},
}

local core = {
    IsAdmin = function(_, src) return admins[src] == true end,
    Notify = function(_, src, message)
        notices[#notices + 1] = { src = src, message = message }
    end,
    Freeze = function(_, src, etat)
        freezes[#freezes + 1] = { src = src, etat = etat }
    end,
}

local env = setmetatable({
    source = 1,
    exports = {
        gf_core = core,
        gf_admin = {
            LogAction = function(_, src, action, cible, details)
                audits[#audits + 1] = {
                    src = src, action = action, cible = cible, details = details,
                    ordre = prochainOrdre(),
                }
            end,
        },
    },
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
        prints[#prints + 1] = table.concat(parts, ' ')
    end,
    GetPlayers = function() return { '3', '1', '2' } end,
    GetPlayerName = function(id) return names[id] end,
    GetPlayerPing = function(id) return pings[id] end,
    GetPlayerRoutingBucket = function(id) return buckets[id] end,
    -- Le mock reproduit l'effet réel de la native : le bucket du joueur change,
    -- ce qui est indispensable pour tester les restaurations de monde.
    SetPlayerRoutingBucket = function(src, bucket)
        routingSets[#routingSets + 1] = { src = src, bucket = bucket }
        buckets[src] = bucket
    end,
    GetPlayerPed = function(id) return peds[id] end,
    GetEntityCoords = function(ped) return coords[ped] end,
    GetGameTimer = function() return now end,
    GetResourceState = function() return 'started' end,
    DropPlayer = function(src, reason)
        drops[#drops + 1] = { src = src, reason = reason, ordre = prochainOrdre() }
    end,
    TriggerClientEvent = function(name, target, data)
        journal[#journal + 1] = {
            kind = 'client', name = name, target = target, data = data, ordre = #journal + 1,
        }
    end,
    TriggerEvent = function(name, ...)
        journal[#journal + 1] = {
            kind = 'local', name = name, target = nil, data = { ... }, ordre = #journal + 1,
        }
    end,
    RegisterCommand = function(name, handler) commands[name] = handler end,
    RegisterNetEvent = function(name, handler) handlers[name] = handler end,
    AddEventHandler = function(name, handler) eventHandlers[name] = handler end,
    -- On capture la boucle de suivi au lieu de la lancer : chaque test décide
    -- du nombre de passes via coroutine.resume (une passe puis Wait).
    CreateThread = function(fn) threads[#threads + 1] = fn end,
    Wait = function(ms) coroutine.yield(ms) end,
}, { __index = _G })

local base = root .. '/server-data/resources/[gunfight]/gf_admin/'
assert(loadfile(base .. 'commands.lua', 't', env))()
assert(loadfile(base .. 'server.lua', 't', env))()

local onDrop = assert(eventHandlers.playerDropped, 'handler playerDropped absent')
assert(handlers['gf_admin:requestData'], 'event gf_admin:requestData absent')
local spectateEnded = assert(handlers['gf_admin:spectateEnded'], 'event gf_admin:spectateEnded absent')

for _, nom in ipairs({ 'kick', 'goto', 'bring', 'heal', 'freeze', 'announce', 'spectate' }) do
    check(type(commands[nom]) == 'function', ('RegisterCommand(%s) enregistré'):format(nom))
end

-- ---------------------------------------------------------------------------
-- Utilitaires du harnais.
-- ---------------------------------------------------------------------------
local function reinitialiser()
    for _, v in ipairs(journal) do archive.journal[#archive.journal + 1] = v end
    for _, v in ipairs(notices) do archive.notices[#archive.notices + 1] = v end
    for _, v in ipairs(prints) do archive.prints[#archive.prints + 1] = v end
    for _, v in ipairs(drops) do archive.drops[#archive.drops + 1] = v end
    for _, v in ipairs(freezes) do archive.freezes[#archive.freezes + 1] = v end
    for _, v in ipairs(audits) do archive.audits[#archive.audits + 1] = v end
    for _, v in ipairs(routingSets) do archive.routingSets[#archive.routingSets + 1] = v end
    journal, notices, prints, drops, freezes, audits, routingSets = {}, {}, {}, {}, {}, {}, {}
    now = now + 1000
end

-- Le handler lit la globale `source` de env : elle doit être positionnée avant
-- l'appel, exactement comme FiveM le fait pour une commande serveur.
local function appeler(nom, src, args)
    assert(type(args) == 'table', 'les arguments doivent toujours être une table')
    env.source = src
    local handler = assert(commands[nom], ('commande %s absente'):format(nom))
    handler(src, args)
end

-- L'événement client lit `source` dans env : ses propres arguments, eux, sont
-- ceux que le client a transmis (le contrat n'en prévoit aucun).
local function finDeVue(src, ...)
    env.source = src
    spectateEnded(...)
end

local function entry(kind, name)
    for _, e in ipairs(journal) do
        if e.kind == kind and e.name == name then return e end
    end
    return nil
end

local function entries(kind, name)
    local result = {}
    for _, e in ipairs(journal) do
        if e.kind == kind and (name == nil or e.name == name) then
            result[#result + 1] = e
        end
    end
    return result
end

local function notice(src, message)
    for _, n in ipairs(notices) do
        if n.src == src and n.message == message then return n end
    end
    return nil
end

local function sansIdentifiant(texte)
    return type(texte) ~= 'string' or not (
        texte:find('license:', 1, true) or texte:find('ip:', 1, true)
        or texte:find('discord:', 1, true))
end

local function tableSansIdentifiant(valeur, vu)
    if type(valeur) ~= 'table' then return sansIdentifiant(valeur) end
    vu = vu or {}
    if vu[valeur] then return true end
    vu[valeur] = true
    for cle, item in pairs(valeur) do
        if not tableSansIdentifiant(cle, vu) or not tableSansIdentifiant(item, vu) then return false end
    end
    return true
end

local function aucunEffet(kind)
    if kind == nil then
        return #journal == 0 and #drops == 0 and #freezes == 0 and #prints == 0
            and #audits == 0 and #routingSets == 0
    end
    return #entries(kind) == 0 and #drops == 0 and #freezes == 0 and #prints == 0
        and #audits == 0 and #routingSets == 0
end

-- Cas console : le print est attendu, tout le reste doit rester muet.
local function aucunEffetSaufPrint()
    return #journal == 0 and #drops == 0 and #freezes == 0 and #audits == 0
        and #routingSets == 0
end

-- Un succès doit produire exactement un appel LogAction avec les valeurs exactes.
local function verifierAudit(src, action, cible, details, label)
    check(#audits == 1, ('%s : un seul appel LogAction'):format(label))
    local a = audits[1]
    check(a ~= nil and a.src == src and a.action == action
        and a.cible == cible and a.details == details,
        ('%s : src, action, cible et details exacts'):format(label))
end

local USAGE = 'Usage : announce <texte> (ex. announce Redémarrage dans 5 minutes)'
local USAGE_SPECTATE = 'Usage : spectate <id> (ex. spectate 12) ; spectate seul pour arrêter.'

-- Le suivi est une boucle « une passe puis Wait(1000) » : un seul resume
-- exécute exactement une passe et s'arrête sur le Wait. On vérifie le résultat
-- du resume (succès et valeur rendue par Wait) à chaque appel.
local function unePasseSuivi(label)
    local fonction = assert(threads[1], 'thread de suivi absent')
    local suivi = coroutine.create(fonction)
    local ok, attendu = coroutine.resume(suivi)
    check(ok and attendu == 1000,
        ('%s : une passe puis Wait(1000) sans erreur (yield=%s)')
            :format(label, tostring(attendu)))
end

-- ---------------------------------------------------------------------------
-- 1. Refus non-admin pour CHAQUE commande : une seule notification, aucun effet.
-- ---------------------------------------------------------------------------
local casNonAdmin = {
    { 'kick', { '3', 'triche' } },
    { 'goto', { '3' } },
    { 'bring', { '3' } },
    { 'heal', { '3' } },
    { 'freeze', { '3' } },
    { 'announce', { 'Bonjour' } },
    { 'spectate', { '3' } },
}
for _, cas in ipairs(casNonAdmin) do
    reinitialiser()
    appeler(cas[1], 2, cas[2])
    check(#notices == 1, ('non admin %s : une seule notification'):format(cas[1]))
    check(notices[1] ~= nil and notices[1].src == 2
        and notices[1].message == 'Réservé aux administrateurs.',
        ('non admin %s : notification exacte'):format(cas[1]))
    check(aucunEffet(nil), ('non admin %s : aucun drop, gel, événement ni print'):format(cas[1]))
end

-- ---------------------------------------------------------------------------
-- 1bis. Cible absente pour CHAQUE commande à cible : message d'usage exact et
--       aucun effet. src = 1 pour goto/bring : la garde console ne doit pas
--       prendre le dessus. Un argument PRÉSENT mais invalide doit, lui,
--       répondre "Joueur X introuvable." (distinction usage / introuvable).
-- ---------------------------------------------------------------------------
local casUsage = {
    { 'kick', 'Usage : kick <id> [raison] (ex. kick 12 triche)' },
    { 'goto', 'Usage : goto <id> (ex. goto 12)' },
    { 'bring', 'Usage : bring <id> (ex. bring 12)' },
    { 'heal', 'Usage : heal <id> (ex. heal 12)' },
    { 'freeze', 'Usage : freeze <id> (ex. freeze 12)' },
}
for _, cas in ipairs(casUsage) do
    reinitialiser()
    appeler(cas[1], 1, {})
    check(#notices == 1, ('cible absente %s : une seule notification'):format(cas[1]))
    check(notices[1] ~= nil and notices[1].src == 1
        and notices[1].message == cas[2],
        ('cible absente %s : message d’usage exact'):format(cas[1]))
    check(aucunEffet(nil), ('cible absente %s : aucun drop, gel, événement ni print'):format(cas[1]))

    reinitialiser()
    appeler(cas[1], 1, { 'abc' })
    check(#notices == 1, ('argument invalide %s : une seule notification'):format(cas[1]))
    check(notices[1] ~= nil and notices[1].src == 1
        and notices[1].message == 'Joueur abc introuvable.',
        ('argument invalide %s : message exact'):format(cas[1]))
    check(aucunEffet(nil), ('argument invalide %s : aucun drop, gel, événement ni print'):format(cas[1]))
end

-- ---------------------------------------------------------------------------
-- 2. kick : refus de s'expulser soi-même.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler('kick', 1, { '1' })
check(#notices == 1 and notices[1].src == 1
    and notices[1].message == 'Tu ne peux pas t’expulser toi-même.',
    'kick soi-même : message exact')
check(#drops == 0 and #journal == 0 and #prints == 0 and #audits == 0,
    'kick soi-même : aucun drop ni effet')

-- ---------------------------------------------------------------------------
-- 3. kick : raison nettoyée, raison par défaut, cible inconnue.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler('kick', 1, { '3', 'Triche ; | \\ ` "', 'rapide\n' })
check(#drops == 1, 'kick normal : un seul DropPlayer')
check(drops[1] ~= nil and drops[1].src == 3
    and drops[1].reason == 'Expulsé par un administrateur : Triche rapide',
    'kick normal : raison nettoyée et espaces réduits')
check(notice(1, 'Charlie expulsé.') ~= nil, 'kick normal : reply exact')
check(#notices == 1, 'kick normal : une seule notification')
verifierAudit(1, 'kick', 3, 'raison=Triche rapide', 'kick normal')
check(audits[1].ordre < drops[1].ordre, 'kick normal : LogAction avant DropPlayer')

reinitialiser()
appeler('kick', 1, { '3' })
check(#drops == 1 and drops[1].src == 3
    and drops[1].reason == 'Expulsé par un administrateur : aucune raison',
    'kick sans raison : raison par défaut')
check(notice(1, 'Charlie expulsé.') ~= nil, 'kick sans raison : reply exact')
verifierAudit(1, 'kick', 3, 'raison=aucune raison', 'kick sans raison')

reinitialiser()
appeler('kick', 1, { '3', string.rep('a', 100) })
check(#drops == 1 and drops[1].src == 3
    and drops[1].reason == 'Expulsé par un administrateur : ' .. string.rep('a', 80),
    'kick raison 100 caractères : tronquée à 80 par le serveur')
check(drops[1] ~= nil and drops[1].reason ~= 'Expulsé par un administrateur : ' .. string.rep('a', 100),
    'kick raison 100 caractères : la raison complète n’est pas transmise')
check(notice(1, 'Charlie expulsé.') ~= nil, 'kick raison 100 caractères : reply exact')
verifierAudit(1, 'kick', 3, 'raison=' .. string.rep('a', 80), 'kick raison 100 caractères')

reinitialiser()
appeler('kick', 1, { '999' })
check(notice(1, 'Joueur 999 introuvable.') ~= nil, 'kick cible inconnue : message exact')
check(#drops == 0 and #journal == 0 and #audits == 0,
    'kick cible inconnue : aucun drop ni événement')

-- ---------------------------------------------------------------------------
-- 4. goto / bring : buckets, téléportations, cible égale à soi, console.
-- ---------------------------------------------------------------------------
reinitialiser()
buckets[3] = 5
appeler('goto', 1, { '3' })
check(notice(1, 'Charlie est dans un autre mode : utilise d’abord setmode.') ~= nil,
    'goto bucket différent : message exact')
check(#entries('client', 'gf_admin:teleport') == 0 and #audits == 0,
    'goto bucket différent : aucun téléport ni audit')

reinitialiser()
appeler('bring', 1, { '3' })
check(notice(1, 'Charlie est dans un autre mode : utilise d’abord setmode.') ~= nil,
    'bring bucket différent : message exact')
check(#entries('client', 'gf_admin:teleport') == 0 and #audits == 0,
    'bring bucket différent : aucun téléport ni audit')
buckets[3] = 0

reinitialiser()
appeler('goto', 1, { '3' })
local tpGoto = entry('client', 'gf_admin:teleport')
check(tpGoto ~= nil and tpGoto.target == 1, 'goto : téléport vers l’administrateur 1')
check(tpGoto ~= nil and type(tpGoto.data) == 'table'
    and tpGoto.data.x == 11.5 and tpGoto.data.y == 20 and tpGoto.data.z == 30,
    'goto : coordonnées exactes de la cible')
check(notice(1, 'Téléporté près de Charlie.') ~= nil, 'goto : reply exact')
verifierAudit(1, 'goto', 3, nil, 'goto succès')

reinitialiser()
appeler('bring', 1, { '3' })
local tpBring = entry('client', 'gf_admin:teleport')
check(tpBring ~= nil and tpBring.target == 3, 'bring : téléport vers la cible 3')
check(tpBring ~= nil and type(tpBring.data) == 'table'
    and tpBring.data.x == 101.5 and tpBring.data.y == 200 and tpBring.data.z == 30,
    'bring : coordonnées exactes de l’administrateur')
check(notice(3, 'Un administrateur t’a téléporté.') ~= nil, 'bring : notification de la cible')
check(notice(1, 'Charlie téléporté près de toi.') ~= nil, 'bring : reply exact')
verifierAudit(1, 'bring', 3, nil, 'bring succès')

reinitialiser()
appeler('goto', 1, { '1' })
check(notice(1, 'Tu ne peux pas te téléporter toi-même.') ~= nil, 'goto soi-même : message exact')
check(#entries('client') == 0 and #audits == 0, 'goto soi-même : aucun téléport ni audit')

reinitialiser()
appeler('bring', 1, { '1' })
check(notice(1, 'Tu ne peux pas te ramener toi-même.') ~= nil, 'bring soi-même : message exact')
check(#entries('client') == 0 and #audits == 0, 'bring soi-même : aucun téléport ni audit')

reinitialiser()
appeler('goto', 0, { '3' })
check(#prints == 1 and prints[1] == '[gf_admin] Commande à utiliser en jeu.',
    'goto console : print exact')
check(#entries('client') == 0 and #notices == 0 and #audits == 0,
    'goto console : aucun téléport, notification ni audit')

reinitialiser()
appeler('bring', 0, { '3' })
check(#prints == 1 and prints[1] == '[gf_admin] Commande à utiliser en jeu.',
    'bring console : print exact')
check(#entries('client') == 0 and #notices == 0 and #audits == 0,
    'bring console : aucun téléport, notification ni audit')

-- Le harnais est bien pilotable : remettre la cible 2 dans le même bucket.
reinitialiser()
buckets[2] = 0
appeler('goto', 1, { '2' })
local tpPilote = entry('client', 'gf_admin:teleport')
check(tpPilote ~= nil and tpPilote.target == 1
    and type(tpPilote.data) == 'table' and tpPilote.data.x == 201.5,
    'bucket pilotable : goto réussi après changement de bucket')
verifierAudit(1, 'goto', 2, nil, 'bucket pilotable goto')
buckets[2] = 5

-- ---------------------------------------------------------------------------
-- 5. heal : audit local AVANT le signalement client.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler('heal', 1, { '3' })
local audit = entry('local', 'gf:healGranted')
local soinClient = entry('client', 'gf_admin:heal')
check(audit ~= nil and audit.target == nil and audit.data[1] == 3,
    'heal : gf:healGranted émis localement pour 3')
check(soinClient ~= nil and soinClient.target == 3, 'heal : gf_admin:heal envoyé à 3')
check(audit ~= nil and soinClient ~= nil and audit.ordre < soinClient.ordre,
    'heal : audit avant le client')
check(notice(3, 'Un administrateur t’a soigné.') ~= nil, 'heal : notification de la cible')
check(notice(1, 'Charlie soigné.') ~= nil, 'heal : reply exact')
verifierAudit(1, 'heal', 3, nil, 'heal')

-- ---------------------------------------------------------------------------
-- 6. freeze : bascule, messages exacts, remise à zéro à la déconnexion.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler('freeze', 1, { '3' })
check(#freezes == 1 and freezes[1].src == 3 and freezes[1].etat == true,
    'freeze premier appel : core:Freeze(3, true)')
check(#notices == 2 and notices[1].src == 3
    and notices[1].message == 'Un administrateur t’a gelé.'
    and notices[2].src == 1 and notices[2].message == 'Charlie gelé.',
    'freeze premier appel : notifications exactes')
verifierAudit(1, 'freeze', 3, 'etat=gele', 'freeze premier appel')

reinitialiser()
appeler('freeze', 1, { '3' })
check(#freezes == 1 and freezes[1].src == 3 and freezes[1].etat == false,
    'freeze second appel : core:Freeze(3, false)')
check(#notices == 2 and notices[1].src == 3
    and notices[1].message == 'Un administrateur t’a dégelé.'
    and notices[2].src == 1 and notices[2].message == 'Charlie dégelé.',
    'freeze second appel : notifications exactes')
verifierAudit(1, 'freeze', 3, 'etat=degele', 'freeze second appel')

reinitialiser()
appeler('freeze', 1, { '3' })
env.source = 3
onDrop()
reinitialiser()
appeler('freeze', 1, { '3' })
check(#freezes == 1 and freezes[1].src == 3 and freezes[1].etat == true,
    'freeze après playerDropped : état remis à zéro, toujours gelé')
check(notice(3, 'Un administrateur t’a gelé.') ~= nil, 'freeze après playerDropped : message exact')
verifierAudit(1, 'freeze', 3, 'etat=gele', 'freeze après playerDropped')

-- ---------------------------------------------------------------------------
-- 7. announce : événement global, reply, journal ; refus des textes invalides.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler('announce', 1, { 'Bonjour', 'monde' })
local annonce = entry('client', 'gf_ui:announce')
check(annonce ~= nil and annonce.target == -1, 'announce : gf_ui:announce vers -1')
check(annonce ~= nil and type(annonce.data) == 'table'
    and annonce.data.title == 'ANNONCE' and annonce.data.subtitle == 'Bonjour monde'
    and annonce.data.duration == 8000,
    'announce : charge utile exacte')
check(notice(1, 'Annonce envoyée.') ~= nil, 'announce : reply exact')
check(#prints == 1 and prints[1] == '[gf_admin] Annonce de Alpha : Bonjour monde',
    'announce : print avec auteur et texte')
check(prints[1]:find('Alpha', 1, true) ~= nil and prints[1]:find('Bonjour monde', 1, true) ~= nil,
    'announce : le print contient l’auteur et le texte')
verifierAudit(1, 'announce', nil, 'texte=Bonjour monde', 'announce normal')

-- Borne acceptée : exactement 120 caractères.
local texte120 = string.rep('a', 120)
reinitialiser()
appeler('announce', 1, { texte120 })
local annonce120 = entry('client', 'gf_ui:announce')
check(annonce120 ~= nil and annonce120.target == -1, 'announce 120 : gf_ui:announce vers -1')
check(annonce120 ~= nil and type(annonce120.data) == 'table'
    and annonce120.data.subtitle == texte120 and #annonce120.data.subtitle == 120,
    'announce 120 : subtitle exact de 120 caractères')
check(notice(1, 'Annonce envoyée.') ~= nil, 'announce 120 : reply exact')
check(#prints == 1 and prints[1] == '[gf_admin] Annonce de Alpha : ' .. texte120,
    'announce 120 : print avec auteur et texte')
verifierAudit(1, 'announce', nil, 'texte=' .. texte120, 'announce 120')

-- Console : reply et auteur passent par print, aucune notification.
reinitialiser()
appeler('announce', 0, { 'Test', 'console' })
local annonceConsole = entry('client', 'gf_ui:announce')
check(annonceConsole ~= nil and annonceConsole.target == -1
    and type(annonceConsole.data) == 'table'
    and annonceConsole.data.subtitle == 'Test console',
    'announce console : gf_ui:announce vers -1 avec le texte exact')
check(#prints == 2 and prints[1] == '[gf_admin] Annonce envoyée.'
    and prints[2] == '[gf_admin] Annonce de console : Test console',
    'announce console : deux prints dans l’ordre, reply puis auteur')
check(#notices == 0, 'announce console : aucune notification')
verifierAudit(0, 'announce', nil, 'texte=Test console', 'announce console')

reinitialiser()
appeler('announce', 1, {})
check(notice(1, USAGE) ~= nil, 'announce sans argument : message d’usage exact')
check(#journal == 0 and #prints == 0 and #audits == 0,
    'announce sans argument : aucun événement, print ni audit')

reinitialiser()
appeler('announce', 1, { string.rep('a', 121) })
check(notice(1, USAGE) ~= nil, 'announce 121 caractères : message d’usage exact')
check(#journal == 0 and #prints == 0 and #audits == 0,
    'announce 121 caractères : aucun événement ni print ni audit')

reinitialiser()
appeler('announce', 1, { '; | \\ ` " \n' })
check(notice(1, USAGE) ~= nil, 'announce vide après nettoyage : message d’usage exact')
check(#journal == 0 and #prints == 0 and #audits == 0,
    'announce vide après nettoyage : aucun événement ni print ni audit')

-- ---------------------------------------------------------------------------
-- 7bis. spectate : gardes, démarrage/arrêt, changement de cible, routing bucket
--       et boucle de suivi. Chaque cas repose explicitement ses buckets.
-- ---------------------------------------------------------------------------

-- Console : un seul print, aucun effet (pas même un SetPlayerRoutingBucket).
reinitialiser()
appeler('spectate', 0, { '3' })
check(#prints == 1 and prints[1] == '[gf_admin] Commande à utiliser en jeu.',
    'spectate console : print exact')
check(#notices == 0, 'spectate console : aucune notification')
check(aucunEffetSaufPrint(),
    'spectate console : aucun événement, audit, drop, gel ni Set')

-- Sans argument et sans vue en cours : usage exact, aucun effet.
reinitialiser()
appeler('spectate', 1, {})
check(#notices == 1 and notices[1].src == 1 and notices[1].message == USAGE_SPECTATE,
    'spectate sans argument sans vue : usage exact')
check(aucunEffet(nil), 'spectate sans argument sans vue : aucun effet')

-- Cible introuvable.
reinitialiser()
appeler('spectate', 1, { '999' })
check(#notices == 1 and notices[1].src == 1
    and notices[1].message == 'Joueur 999 introuvable.',
    'spectate cible inconnue : message exact')
check(aucunEffet(nil), 'spectate cible inconnue : aucun effet')

-- Soi-même.
reinitialiser()
appeler('spectate', 1, { '1' })
check(#notices == 1 and notices[1].src == 1
    and notices[1].message == 'Tu ne peux pas te regarder toi-même.',
    'spectate soi-même : message exact')
check(aucunEffet(nil), 'spectate soi-même : aucun effet')

-- Démarrage avec changement de monde : admin 1 en bucket 0, cible 3 en bucket 5.
reinitialiser()
buckets[1] = 0
buckets[3] = 5
appeler('spectate', 1, { '3' })
check(#routingSets == 1 and routingSets[1].src == 1 and routingSets[1].bucket == 5,
    'spectate démarrage avec changement de monde : un seul SetPlayerRoutingBucket(1, 5)')
check(buckets[1] == 5,
    'spectate démarrage avec changement de monde : bucket de l’admin mis à jour')
local startMonde = entry('client', 'gf_admin:spectateStart')
check(startMonde ~= nil and startMonde.target == 1,
    'spectate démarrage avec changement de monde : spectateStart vers l’admin')
check(startMonde ~= nil and type(startMonde.data) == 'table'
    and startMonde.data.target == 3 and startMonde.data.name == 'Charlie'
    and startMonde.data.x == 10 and startMonde.data.y == 20 and startMonde.data.z == 30,
    'spectate démarrage avec changement de monde : charge utile exacte')
check(notice(1, 'Vue de Charlie. Tape spectate pour arrêter.') ~= nil,
    'spectate démarrage avec changement de monde : reply exact')
check(#notices == 1,
    'spectate démarrage avec changement de monde : une seule notification')
check(#entries('client', 'gf_admin:spectatePos') == 0
    and #entries('client', 'gf_admin:spectateStop') == 0,
    'spectate démarrage avec changement de monde : aucun stop ni position')
local versCible = false
for _, e in ipairs(journal) do
    if e.target == 3 then versCible = true end
end
check(not versCible,
    'spectate démarrage avec changement de monde : aucun événement vers la cible')
verifierAudit(1, 'spectate', 3, nil, 'spectate démarrage avec changement de monde')

-- Rejouer la même commande sur la même cible : arrêt avec restauration du monde.
reinitialiser()
appeler('spectate', 1, { '3' })
check(#routingSets == 1 and routingSets[1].src == 1 and routingSets[1].bucket == 0,
    'spectate rejoué : SetPlayerRoutingBucket(1, 0) de restauration')
check(buckets[1] == 0, 'spectate rejoué : monde d’origine restauré')
local stopRejouer = entry('client', 'gf_admin:spectateStop')
check(stopRejouer ~= nil and stopRejouer.target == 1,
    'spectate rejoué : spectateStop vers l’admin')
check(entry('client', 'gf_admin:spectateStart') == nil,
    'spectate rejoué : aucun nouveau spectateStart')
check(notice(1, 'Vue arrêtée.') ~= nil, 'spectate rejoué : reply exact')
check(#audits == 0, 'spectate rejoué : aucun nouvel audit')

-- Démarrage sans changement de monde : aucun Set au démarrage.
reinitialiser()
buckets[1] = 0
buckets[2] = 0
appeler('spectate', 1, { '2' })
check(#routingSets == 0,
    'spectate sans changement de monde : aucun SetPlayerRoutingBucket au démarrage')
local startSame = entry('client', 'gf_admin:spectateStart')
check(startSame ~= nil and startSame.target == 1 and type(startSame.data) == 'table'
    and startSame.data.target == 2 and startSame.data.name == 'Bravo'
    and startSame.data.x == 200 and startSame.data.y == 300 and startSame.data.z == 40,
    'spectate sans changement de monde : charge utile exacte')
check(notice(1, 'Vue de Bravo. Tape spectate pour arrêter.') ~= nil,
    'spectate sans changement de monde : reply exact')
verifierAudit(1, 'spectate', 2, nil, 'spectate sans changement de monde')

-- spectate seul : arrêt de la vue courante.
reinitialiser()
appeler('spectate', 1, {})
local stopSeul = entry('client', 'gf_admin:spectateStop')
check(stopSeul ~= nil and stopSeul.target == 1, 'spectate seul : spectateStop vers l’admin')
check(notice(1, 'Vue arrêtée.') ~= nil, 'spectate seul : reply exact')
check(#notices == 1, 'spectate seul : une seule notification')
check(#audits == 0, 'spectate seul : aucun audit')

-- Changement de cible : arrêt silencieux de l'ancienne vue puis nouveau départ.
reinitialiser()
buckets[1] = 0
buckets[3] = 5
buckets[2] = 0
appeler('spectate', 1, { '3' })
verifierAudit(1, 'spectate', 3, nil, 'changement de cible : premier départ')

reinitialiser()
appeler('spectate', 1, { '2' })
check(#routingSets >= 1 and routingSets[1].src == 1 and routingSets[1].bucket == 0,
    'changement de cible : restauration du monde 0 avant le nouveau départ')
local stopChangement = entry('client', 'gf_admin:spectateStop')
local startChangement = entry('client', 'gf_admin:spectateStart')
check(stopChangement ~= nil and stopChangement.target == 1,
    'changement de cible : spectateStop vers l’admin pour l’ancienne vue')
check(startChangement ~= nil and startChangement.target == 1
    and type(startChangement.data) == 'table' and startChangement.data.target == 2
    and startChangement.data.name == 'Bravo'
    and startChangement.data.x == 200 and startChangement.data.y == 300
    and startChangement.data.z == 40,
    'changement de cible : nouveau spectateStart exact')
check(stopChangement ~= nil and startChangement ~= nil
    and stopChangement.ordre < startChangement.ordre,
    'changement de cible : stop avant le start')
check(notice(1, 'Vue de Bravo. Tape spectate pour arrêter.') ~= nil,
    'changement de cible : reply du nouveau départ')
check(notice(1, 'Vue arrêtée.') == nil,
    'changement de cible : aucun reply « Vue arrêtée. » intermédiaire')
check(#notices == 1, 'changement de cible : une seule notification')
check(#audits == 1 and audits[1].src == 1 and audits[1].action == 'spectate'
    and audits[1].cible == 2 and audits[1].details == nil,
    'changement de cible : second LogAction, pour la nouvelle cible seulement')

-- Puis arrêt explicite de la vue courante : 2 LogAction au total sur ce scénario.
reinitialiser()
appeler('spectate', 1, {})
check(#routingSets >= 1 and routingSets[1].src == 1 and routingSets[1].bucket == 0,
    'spectate seul après changement : restauration du monde 0')
check(entry('client', 'gf_admin:spectateStop') ~= nil,
    'spectate seul après changement : spectateStop')
check(notice(1, 'Vue arrêtée.') ~= nil, 'spectate seul après changement : reply exact')
check(#audits == 0, 'spectate seul après changement : aucun audit')

-- Boucle de suivi : une passe = position ; puis changement de monde ; puis départ.
reinitialiser()
buckets[1] = 0
buckets[3] = 5
names[3] = 'Charlie'
appeler('spectate', 1, { '3' })
check(entry('client', 'gf_admin:spectateStart') ~= nil,
    'suivi : vue démarrée sur Charlie avant les passes')
reinitialiser()

unePasseSuivi('suivi : première passe')
local pos = entry('client', 'gf_admin:spectatePos')
check(pos ~= nil and pos.target == 1 and type(pos.data) == 'table'
    and pos.data.x == 10 and pos.data.y == 20 and pos.data.z == 30,
    'suivi : spectatePos vers l’admin avec les coordonnées de Charlie')
check(#entries('client', 'gf_admin:spectatePos') == 1,
    'suivi : un seul spectatePos par passe')
check(#routingSets == 0, 'suivi : aucun Set quand le monde n’a pas changé')
check(entry('client', 'gf_admin:spectateStop') == nil,
    'suivi : aucun stop quand la cible est présente')
check(#audits == 0, 'suivi : aucun audit')
check(#notices == 0, 'suivi : aucune notification')

reinitialiser()
buckets[3] = 7
unePasseSuivi('suivi : changement de monde de la cible')
check(#routingSets == 1 and routingSets[1].src == 1 and routingSets[1].bucket == 7,
    'suivi : SetPlayerRoutingBucket(1, 7) au changement de monde')
check(buckets[1] == 7, 'suivi : bucket de l’admin mis à jour')
check(entry('client', 'gf_admin:spectatePos') ~= nil,
    'suivi : spectatePos toujours envoyé après changement de monde')
check(entry('client', 'gf_admin:spectateStop') == nil,
    'suivi : pas de stop au changement de monde')
check(#notices == 0, 'suivi changement de monde : aucune notification')

reinitialiser()
names[3] = nil
unePasseSuivi('suivi : départ de la cible')
check(#routingSets >= 1 and routingSets[1].src == 1 and routingSets[1].bucket == 0,
    'suivi : restauration du monde d’origine au départ de la cible')
check(buckets[1] == 0, 'suivi : bucket d’origine restauré')
local stopDepart = entry('client', 'gf_admin:spectateStop')
check(stopDepart ~= nil and stopDepart.target == 1,
    'suivi : spectateStop vers l’admin au départ de la cible')
check(notice(1, 'Le joueur a quitté le serveur : vue arrêtée.') ~= nil,
    'suivi : reply exact au départ de la cible')
check(#notices == 1, 'suivi : une seule notification au départ de la cible')
check(entry('client', 'gf_admin:spectatePos') == nil,
    'suivi : plus de spectatePos après le départ de la cible')
check(#audits == 0, 'suivi : aucun audit au départ de la cible')

-- L'entrée est vidée : spectate sans argument répond l'usage, sans effet.
names[3] = 'Charlie'
buckets[3] = 0
reinitialiser()
appeler('spectate', 1, {})
check(notice(1, USAGE_SPECTATE) ~= nil,
    'suivi : entrée vidée après le départ de la cible (usage)')
check(aucunEffet(nil), 'suivi : aucun effet après le départ de la cible')

-- playerDropped d'un admin qui regarde : entrée vidée sans Set ni événement.
reinitialiser()
buckets[1] = 0
buckets[3] = 5
names[3] = 'Charlie'
appeler('spectate', 1, { '3' })
check(entry('client', 'gf_admin:spectateStart') ~= nil,
    'playerDropped admin : vue démarrée avant la déconnexion')
reinitialiser()
env.source = 1
onDrop()
check(#routingSets == 0, 'playerDropped admin : aucun SetPlayerRoutingBucket')
check(buckets[1] == 5, 'playerDropped admin : monde de l’admin laissé inchangé')
check(#journal == 0, 'playerDropped admin : aucun événement')
check(#prints == 0, 'playerDropped admin : aucun print')
check(#audits == 0, 'playerDropped admin : aucun audit')
check(#drops == 0 and #freezes == 0, 'playerDropped admin : aucun drop ni gel')

reinitialiser()
appeler('spectate', 1, {})
check(notice(1, USAGE_SPECTATE) ~= nil, 'playerDropped admin : entrée vidée (usage)')
check(aucunEffet(nil), 'playerDropped admin : aucun effet après vidage')

-- ---------------------------------------------------------------------------
-- 7ter. gf_admin:spectateEnded : réconciliation d'un arrêt décidé par le client.
--       Aucun stop, aucun message, aucun audit : seul l'état de l'émetteur est
--       retiré, avec restauration silencieuse de son monde d'origine.
--       reinitialiser() avance `now` de 1000 ms : on ne l'utilise jamais entre
--       deux appels qui doivent rester dans la fenêtre de 500 ms.
-- ---------------------------------------------------------------------------

-- a) Vue en cours : un seul Set(1, 0), aucun stop/notice/audit, entrée vidée.
reinitialiser()
buckets[1] = 0
buckets[3] = 5
names[3] = 'Charlie'
appeler('spectate', 1, { '3' })
check(entry('client', 'gf_admin:spectateStart') ~= nil,
    '7ter a : vue démarrée sur 3 avant la fin locale')
reinitialiser() -- efface les enregistrements, garde l'état et avance l'horloge
finDeVue(1)
check(#routingSets == 1 and routingSets[1].src == 1 and routingSets[1].bucket == 0,
    '7ter a : exactement un SetPlayerRoutingBucket(1, 0)')
check(buckets[1] == 0, '7ter a : monde d’origine restauré')
check(#entries('client', 'gf_admin:spectateStop') == 0, '7ter a : aucun spectateStop')
check(#journal == 0 and #notices == 0 and #prints == 0 and #audits == 0
    and #drops == 0 and #freezes == 0,
    '7ter a : aucun événement, notification, print ni audit')
unePasseSuivi('7ter a : passe après fin locale')
check(#entries('client', 'gf_admin:spectatePos') == 0,
    '7ter a : plus aucun spectatePos après la fin locale')
appeler('spectate', 1, {})
check(notice(1, USAGE_SPECTATE) ~= nil,
    '7ter a : entrée vidée (spectate sans argument répond l’usage)')

-- b) Sans vue : aucun effet, y compris aucune notification et aucun audit.
reinitialiser()
finDeVue(1)
check(aucunEffet(nil),
    '7ter b : sans vue, aucun Set, événement, print ni audit')
check(#notices == 0, '7ter b : sans vue, aucune notification')

-- c) Argument présent : refus avant le rate-limit, qui n'est pas consommé.
reinitialiser()
buckets[1] = 0
buckets[3] = 5
names[3] = 'Charlie'
appeler('spectate', 1, { '3' })
check(buckets[1] == 5, '7ter c : vue démarrée dans le monde de la cible')
reinitialiser()
finDeVue(1, 'x')
check(#routingSets == 0 and #journal == 0 and #notices == 0
    and #prints == 0 and #audits == 0,
    '7ter c : avec un argument, aucun effet')
check(buckets[1] == 5, '7ter c : vue intacte après l’argument')
finDeVue(1) -- immédiatement, sans avancer l'horloge
check(#routingSets == 1 and routingSets[1].src == 1 and routingSets[1].bucket == 0,
    '7ter c : arrêt accepté juste après (l’argument n’a pas consommé le rate-limit)')
check(buckets[1] == 0, '7ter c : monde restauré')
check(#entries('client', 'gf_admin:spectateStop') == 0
    and #notices == 0 and #prints == 0 and #audits == 0,
    '7ter c : arrêt silencieux, sans stop ni message')

-- d) Deux appels rapprochés : le second est ignoré, puis accepté à +500 ms.
reinitialiser()
buckets[1] = 0
buckets[3] = 5
names[3] = 'Charlie'
appeler('spectate', 1, { '3' })
check(entry('client', 'gf_admin:spectateStart') ~= nil,
    '7ter d : vue démarrée avant le premier arrêt')
finDeVue(1)
check(#routingSets == 2 and routingSets[2].src == 1 and routingSets[2].bucket == 0
    and routingSets[1].bucket == 5 and buckets[1] == 0,
    '7ter d : premier arrêt restaure le monde et pose le rate-limit')
-- Redémarrage immédiat : pas de reinitialiser(), l'horloge ne bouge pas.
appeler('spectate', 1, { '3' })
check(buckets[1] == 5, '7ter d : vue redémarrée dans le monde de la cible')
local nRoutingD = #routingSets
local nJournalD = #journal
local nNoticesD = #notices
local nAuditsD = #audits
finDeVue(1)
check(#routingSets == nRoutingD and #journal == nJournalD
    and #notices == nNoticesD and #audits == nAuditsD,
    '7ter d : second appel dans la fenêtre ignoré')
check(buckets[1] == 5, '7ter d : vue intacte après le second appel ignoré')
check(#entries('client', 'gf_admin:spectateStop') == 0,
    '7ter d : aucun spectateStop sur le second appel')
unePasseSuivi('7ter d : suivi après refus')
check(#entries('client', 'gf_admin:spectatePos') > 0,
    '7ter d : une passe envoie encore spectatePos')
local nPosD = #entries('client', 'gf_admin:spectatePos')
now = now + 500
finDeVue(1)
check(#routingSets == nRoutingD + 1 and routingSets[#routingSets].src == 1
    and routingSets[#routingSets].bucket == 0,
    '7ter d : arrêt accepté après 500 ms')
check(buckets[1] == 0, '7ter d : monde restauré après 500 ms')
unePasseSuivi('7ter d : suivi après arrêt')
check(#entries('client', 'gf_admin:spectatePos') == nPosD,
    '7ter d : plus aucun spectatePos après l’arrêt accepté')

-- e) playerDropped oublie la table dédiée : arrêt accepté à la même horloge.
reinitialiser()
buckets[1] = 0
buckets[3] = 5
names[3] = 'Charlie'
appeler('spectate', 1, { '3' })
finDeVue(1)
check(buckets[1] == 0, '7ter e : premier arrêt restaure le monde')
env.source = 1
onDrop()
check(buckets[1] == 0, '7ter e : onDrop ne modifie pas le monde')
appeler('spectate', 1, { '3' })
check(buckets[1] == 5, '7ter e : vue redémarrée immédiatement après onDrop')
-- Le démarrage ci-dessus a légitimement notifié et journalisé : on compare aux
-- compteurs d'après-démarrage, sans avancer l'horloge ni remettre à zéro.
local nNoticesE, nAuditsE, nJournalE = #notices, #audits, #journal
local nRoutingE = #routingSets
finDeVue(1)
check(#routingSets == nRoutingE + 1 and routingSets[#routingSets].src == 1
    and routingSets[#routingSets].bucket == 0,
    '7ter e : arrêt accepté après onDrop (table dédiée vidée)')
check(buckets[1] == 0, '7ter e : monde restauré')
check(#entries('client', 'gf_admin:spectateStop') == 0
    and #notices == nNoticesE and #audits == nAuditsE and #journal == nJournalE,
    '7ter e : arrêt final sans stop, notification, audit ni événement')

-- Remise à zéro des données pilotées pour ne pas perturber le scan final.
names[1], names[2], names[3] = 'Alpha', 'Bravo', 'Charlie'
buckets[1], buckets[2], buckets[3] = 0, 5, 0
env.source = 1

-- ---------------------------------------------------------------------------
-- 8. Aucun identifiant (license:, ip:, discord:) dans notices, prints, drops,
--    gels et données d'événements (parcours récursif).
--    On archive d'abord les enregistrements du dernier cas pour que le scan
--    couvre la totalité des productions, courantes comprises.
-- ---------------------------------------------------------------------------
reinitialiser()

local propres = true
for _, n in ipairs(archive.notices) do
    if not sansIdentifiant(n.message) then propres = false end
end
check(propres, 'aucun identifiant dans les notifications')

propres = true
for _, line in ipairs(archive.prints) do
    if not sansIdentifiant(line) then propres = false end
end
check(propres, 'aucun identifiant dans les prints')

propres = true
for _, d in ipairs(archive.drops) do
    if not sansIdentifiant(d.reason) then propres = false end
end
check(propres, 'aucun identifiant dans les raisons d’expulsion')

propres = true
for _, e in ipairs(archive.journal) do
    if not sansIdentifiant(e.name) or not tableSansIdentifiant(e.data) then propres = false end
end
check(propres, 'aucun identifiant dans les événements locaux et réseau')

print(('%d test(s) réussi(s), 0 échec(s)'):format(ok))
