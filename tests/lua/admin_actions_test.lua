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
local archive = { journal = {}, notices = {}, prints = {}, drops = {}, freezes = {}, audits = {} }

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
    CreateThread = function() end,
}, { __index = _G })

local base = root .. '/server-data/resources/[gunfight]/gf_admin/'
assert(loadfile(base .. 'commands.lua', 't', env))()
assert(loadfile(base .. 'server.lua', 't', env))()

local onDrop = assert(eventHandlers.playerDropped, 'handler playerDropped absent')
assert(handlers['gf_admin:requestData'], 'event gf_admin:requestData absent')

for _, nom in ipairs({ 'kick', 'goto', 'bring', 'heal', 'freeze', 'announce' }) do
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
    journal, notices, prints, drops, freezes, audits = {}, {}, {}, {}, {}, {}
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
            and #audits == 0
    end
    return #entries(kind) == 0 and #drops == 0 and #freezes == 0 and #prints == 0
        and #audits == 0
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
