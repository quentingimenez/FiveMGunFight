-- =============================================================================
--  Tests du panneau admin gf_admin : liste blanche des commandes et event serveur.
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/admin_panel_test.lua
--  Les chunks Lua sont chargés avec loadfile(path, 't', env) dans un environnement
--  simulé : ni FiveM, ni base de données, ni dépendance externe. Aucune règle
--  métier n'est recopiée ici : seul le contrat exposé est vérifié.
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
local admins = { [1] = true, [2] = false }
local modes = { [1] = 'attack', [2] = 'lobby', [3] = 'redzone' }
local teams = { [1] = 'A', [2] = 'B', [3] = 'A' }
local names = { [1] = 'Alpha', [2] = 'Bravo', [3] = 'Charlie' }
local pings = { [1] = 11, [2] = 22, [3] = 33 }

local notices = {}       -- { { src, message }, ... }
local prints = {}        -- lignes produites par le print de env
local events = {}        -- { { name, target, data }, ... }
local handlers = {}      -- RegisterNetEvent
local eventHandlers = {} -- AddEventHandler

local now = 0

local catalogue = {
    { id = 'carbine', name = 'WEAPON_CARBINE', label = 'Carbine', category = 'rifle' },
    { id = 'pistol', name = 'WEAPON_PISTOL', label = 'Pistolet', category = 'pistol' },
}

local core = {
    IsAdmin = function(_, src) return admins[src] == true end,
    Notify = function(_, src, message)
        notices[#notices + 1] = { src = src, message = message }
    end,
    GetMode = function(_, src) return modes[src] end,
    GetTeam = function(_, src) return teams[src] end,
    GetWeaponCatalog = function() return catalogue end,
}

local env = setmetatable({
    source = 1,
    exports = { gf_core = core },
    GetPlayers = function() return { '3', '1', '2' } end,
    GetPlayerName = function(id) return names[id] end,
    GetPlayerPing = function(id) return pings[id] end,
    GetGameTimer = function() return now end,
    TriggerClientEvent = function(name, target, data)
        events[#events + 1] = { name = name, target = target, data = data }
    end,
    RegisterNetEvent = function(name, handler) handlers[name] = handler end,
    AddEventHandler = function(name, handler) eventHandlers[name] = handler end,
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[i] = tostring((select(i, ...))) end
        prints[#prints + 1] = table.concat(parts, ' ')
    end,
    CreateThread = function() end,
}, { __index = _G })

local base = root .. '/server-data/resources/[gunfight]/gf_admin/'
assert(loadfile(base .. 'commands.lua', 't', env))()
assert(loadfile(base .. 'server.lua', 't', env))()

local build = assert(env.GFAdminCommands and env.GFAdminCommands.build, 'GFAdminCommands.build absent')
local opensUi = assert(env.GFAdminCommands.opensUi, 'GFAdminCommands.opensUi absent')
local requestData = assert(handlers['gf_admin:requestData'], 'event gf_admin:requestData absent')
local onDrop = assert(eventHandlers.playerDropped, 'handler playerDropped absent')

local function reinitialiser()
    notices = {}
    prints = {}
    events = {}
end

local function ligne(command, args, attendu)
    check(build(command, args) == attendu,
        ('build(%s) doit renvoyer « %s »'):format(tostring(command), tostring(attendu)))
end

local function refuse(command, args, label)
    check(build(command, args) == nil, ('build(%s) doit refuser : %s'):format(tostring(command), label))
end

local function sansIdentifiant(texte)
    return type(texte) ~= 'string' or not (
        texte:find('license:', 1, true) or texte:find('ip:', 1, true) or texte:find('discord:', 1, true))
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

local function evenement(nom, cible)
    for _, e in ipairs(events) do
        if e.name == nom and e.target == cible then return e end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- A. Commandes valides : lignes exactes.
-- ---------------------------------------------------------------------------
ligne('setmode', { '3', 'attack' }, 'setmode 3 attack')
ligne('setmode', { '12', 'lobby' }, 'setmode 12 lobby')
ligne('setmode', { '7', 'redzone' }, 'setmode 7 redzone')
ligne('setteam', { '3', 'A' }, 'setteam 3 A')
ligne('setteam', { '12', 'B' }, 'setteam 12 B')
ligne('resetchar', { '3' }, 'resetchar 3')
ligne('give', { '3', 'carbine' }, 'give 3 carbine')
ligne('startround', {}, 'startround')
ligne('endmatch', {}, 'endmatch')
ligne('nextzone', {}, 'nextzone')
ligne('endgame', {}, 'endgame')
ligne('nextmap', {}, 'nextmap')
ligne('editor', {}, 'editor')
ligne('maps', {}, 'maps')
ligne('customveh', {}, 'customveh')

-- ---------------------------------------------------------------------------
-- B. Refus de la liste blanche.
-- ---------------------------------------------------------------------------
refuse('inconnue', {}, 'commande inconnue')
refuse('setmode', { '3' }, 'argument manquant')
refuse('give', { '3' }, 'argument manquant')
refuse('resetchar', {}, 'argument manquant')
refuse('setteam', { '3' }, 'argument manquant')
refuse('setmode', { '3', 'attack', 'x' }, 'argument en trop')
refuse('startround', { 'x' }, 'argument en trop')
refuse('resetchar', { '3', 'x' }, 'argument en trop')
refuse('resetchar', { '0' }, 'id zéro')
refuse('resetchar', { '-1' }, 'id négatif')
refuse('resetchar', { '3a' }, 'id non numérique')
refuse('give', { '0', 'carbine' }, 'id zéro')
refuse('give', { '-1', 'carbine' }, 'id négatif')
refuse('give', { '3a', 'carbine' }, 'id non numérique')
refuse('setmode', { '3', 'zombie' }, 'mode inconnu')
refuse('setteam', { '3', 'C' }, 'équipe inconnue')
refuse('give', { '3', 'carb ine' }, 'espace dans l’arme')
refuse('give', { '3', 'carbine;' }, 'point-virgule dans l’arme')
refuse('setmode', { 3, 'attack' }, 'id non chaîne')
refuse('give', { '3', 42 }, 'arme non chaîne')
refuse('resetchar', { true }, 'id booléen')
refuse('setmode', '3 attack', 'args non table')

-- ---------------------------------------------------------------------------
-- C. Normalisation de l'arme (mise en minuscules avant contrôle).
-- ---------------------------------------------------------------------------
ligne('give', { '3', 'CARBINE' }, 'give 3 carbine')
ligne('give', { '3', 'Weapon_Carbine' }, 'give 3 weapon_carbine')

-- ---------------------------------------------------------------------------
-- D. Commandes qui ouvrent une autre interface.
-- ---------------------------------------------------------------------------
check(opensUi('editor') == true, 'opensUi(editor) vrai')
check(opensUi('maps') == true, 'opensUi(maps) vrai')
check(opensUi('customveh') == true, 'opensUi(customveh) vrai')
check(opensUi('setmode') == false, 'opensUi(setmode) faux')
check(opensUi('give') == false, 'opensUi(give) faux')
check(opensUi('startround') == false, 'opensUi(startround) faux')
check(opensUi('inconnue') == false, 'opensUi(commande inconnue) faux')

-- ---------------------------------------------------------------------------
-- E. Non admin : notification exacte, denied, aucune donnée, aucun identifiant.
-- ---------------------------------------------------------------------------
reinitialiser()
now = 1000
env.source = 2
requestData()

check(#notices == 1, 'non admin : une seule notification')
check(notices[1] ~= nil and notices[1].src == 2
    and notices[1].message == 'Réservé aux administrateurs.', 'non admin : notification exacte')
check(#events == 1, 'non admin : un seul événement')
check(evenement('gf_admin:denied', 2) ~= nil, 'non admin : gf_admin:denied vers 2')
check(evenement('gf_admin:data', 2) == nil, 'non admin : aucun gf_admin:data')
check(evenement('gf_admin:denied', 1) == nil, 'non admin : aucun événement vers un autre joueur')
check(#prints == 1, 'non admin : un seul print')

local logsPropres = true
for _, line in ipairs(prints) do
    if not sansIdentifiant(line) then logsPropres = false end
end
check(logsPropres, 'non admin : aucun identifiant dans les prints')

-- ---------------------------------------------------------------------------
-- E2. Non admin rate-limité : le second appel immédiat est ignoré en silence.
-- ---------------------------------------------------------------------------
reinitialiser()
now = 1500
env.source = 2
requestData()
requestData()

check(#notices == 1, 'non admin rate-limité : une seule notification')
check(notices[1] ~= nil and notices[1].src == 2
    and notices[1].message == 'Réservé aux administrateurs.', 'non admin rate-limité : notification exacte')
check(#events == 1 and events[1] ~= nil and events[1].name == 'gf_admin:denied' and events[1].target == 2,
    'non admin rate-limité : un seul gf_admin:denied vers 2')
check(evenement('gf_admin:data', 2) == nil, 'non admin rate-limité : aucun gf_admin:data')
check(#prints == 1, 'non admin rate-limité : un seul print')

now = 2000
requestData()

check(#notices == 2, 'non admin rate-limité : deux notifications après 500 ms')
check(notices[2] ~= nil and notices[2].src == 2
    and notices[2].message == 'Réservé aux administrateurs.', 'non admin rate-limité : seconde notification exacte')
check(#events == 2, 'non admin rate-limité : deux événements après 500 ms')
check(events[2] ~= nil and events[2].name == 'gf_admin:denied' and events[2].target == 2,
    'non admin rate-limité : second gf_admin:denied vers 2')
check(evenement('gf_admin:data', 2) == nil, 'non admin rate-limité : toujours aucun gf_admin:data')
check(#prints == 2, 'non admin rate-limité : deux prints après 500 ms')

-- ---------------------------------------------------------------------------
-- F. Admin : données triées, champs exacts, catalogue d'armes, aucun denied.
-- ---------------------------------------------------------------------------
reinitialiser()
now = 2100
env.source = 1
requestData()

check(#events == 1, 'admin : un seul événement')
local dataEvent = events[1]
check(dataEvent ~= nil and dataEvent.name == 'gf_admin:data' and dataEvent.target == 1,
    'admin : gf_admin:data vers 1')
check(evenement('gf_admin:denied', 1) == nil, 'admin : aucun gf_admin:denied')
check(#notices == 0, 'admin : aucune notification')

local data = dataEvent and dataEvent.data
check(type(data) == 'table' and type(data.players) == 'table', 'admin : structure data.players')
check(#data.players == 3, 'admin : trois joueurs')

local attendus = {
    { id = 1, name = 'Alpha', mode = 'attack', team = 'A', ping = 11 },
    { id = 2, name = 'Bravo', mode = 'lobby', team = 'B', ping = 22 },
    { id = 3, name = 'Charlie', mode = 'redzone', team = 'A', ping = 33 },
}
local champsAttendus = { id = true, name = true, mode = true, team = true, ping = true }

local function joueurExact(p, attendu)
    if type(p) ~= 'table' then return false end
    local compte = 0
    for cle in pairs(p) do
        compte = compte + 1
        if not champsAttendus[cle] then return false end
    end
    if compte ~= 5 then return false end
    return p.id == attendu.id and p.name == attendu.name and p.mode == attendu.mode
        and p.team == attendu.team and p.ping == attendu.ping
end

for i = 1, 3 do
    check(joueurExact(data.players[i], attendus[i]), ('admin : joueur %d exact et trié'):format(i))
end

check(data.weapons == catalogue, 'admin : catalogue d’armes attendu')
check(#data.weapons == 2, 'admin : catalogue non vide')

local clesPropres = true
for _, p in ipairs(data.players) do
    for cle in pairs(p) do
        if not sansIdentifiant(cle) then clesPropres = false end
    end
end
check(clesPropres, 'admin : aucun identifiant parmi les clés des joueurs')

-- ---------------------------------------------------------------------------
-- G. Rate-limit : une requête / 500 ms, oubliée à la déconnexion.
-- ---------------------------------------------------------------------------
reinitialiser()
now = 2100
env.source = 1
requestData()
check(#events == 0, 'rate-limit : second appel immédiat ignoré')

now = 2600
requestData()
check(#events == 1 and events[1].name == 'gf_admin:data' and events[1].target == 1,
    'rate-limit : nouvel data après 500 ms')

reinitialiser()
env.source = 1
onDrop()
requestData()
check(#events == 1 and events[1].name == 'gf_admin:data' and events[1].target == 1,
    'rate-limit : data immédiat après playerDropped')

-- ---------------------------------------------------------------------------
-- H. Aucun identifiant ne fuit dans les notices, prints ou événements.
-- ---------------------------------------------------------------------------
local propres = true
for _, notice in ipairs(notices) do
    if not sansIdentifiant(notice.message) then propres = false end
end
check(propres, 'aucun identifiant dans les notifications')

propres = true
for _, line in ipairs(prints) do
    if not sansIdentifiant(line) then propres = false end
end
check(propres, 'aucun identifiant dans les prints')

propres = true
for _, e in ipairs(events) do
    if not sansIdentifiant(e.name) or not tableSansIdentifiant(e.data) then propres = false end
end
check(propres, 'aucun identifiant dans les événements')

print(('%d test(s) réussi(s), 0 échec(s)'):format(ok))
