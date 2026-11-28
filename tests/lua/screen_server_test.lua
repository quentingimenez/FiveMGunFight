-- =============================================================================
--  Tests du serveur gf_screen : commande screen, relais d'images et suivi.
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/screen_server_test.lua
--  Les chunks Lua sont chargés avec loadfile(path, 't', env) dans un environnement
--  simulé : ni FiveM, ni base de données, ni dépendance externe. Aucune règle
--  métier n'est recopiée ici : les vrais handlers et la vraie commande enregistrés
--  par server.lua sont appelés, et seul le contrat observable est vérifié.
-- =============================================================================

local function repoRoot()
    local override = os.getenv('GF_ROOT')
    if override and override ~= '' then return override end
    local info = debug.getinfo(1, 'S')
    local path = info and info.source and info.source:sub(1, 1) == '@'
        and info.source:sub(2) or ''
    path = path:gsub('\\', '/')
    local prefix = path:match('^(.*)/tests/lua/[^/]+%.lua$')
    if prefix and prefix ~= '' then return prefix end
    return '.'
end

local base = repoRoot() .. '/server-data/resources/[gunfight]/gf_screen/'

local ok = 0

local function check(condition, message)
    if not condition then
        io.stderr:write(('ECHEC : %s\n'):format(tostring(message)))
        os.exit(1)
    end
    ok = ok + 1
end

-- ---------------------------------------------------------------------------
-- Constantes du contrat : valeurs attendues, jamais réimplémentées.
-- ---------------------------------------------------------------------------
local USAGE = 'Usage : screen <id> (ex. screen 12) ; screen seul pour arrêter.'
local REFUS = 'Réservé aux administrateurs.'
local CONSOLE = '[gf_screen] Commande à utiliser en jeu.'
local PREFIXE = 'data:image/jpeg;base64,'
local FPS, WIDTH, QUALITY = 3, 640, 0.5
local LATENT_OCTETS = 600000
local MAX_CHARS, MAX_SECONDS = 250000, 600

-- Ids distincts pour éviter tout état résiduel : 1 et 2 adminstrateurs,
-- 3 à 5 cibles ; 6 est un joueur non adminstrateur.
local admins = { [1] = true, [2] = true }
local names = {
    [1] = 'AdminUn',
    [2] = 'AdminDeux',
    [3] = 'CibleTrois',
    [4] = 'CibleQuatre',
    [5] = 'CibleCinq',
}

-- Un seul journal pour les événements locaux, client et latents : l'ordre
-- relatives des envois, notifications et audits reste observable.
local journal = {}       -- { { kind, name, target, data, bytes, ordre }, ... }
local notices = {}       -- { { src, message, ordre }, ... }
local prints = {}        -- lignes du print simulé
local audits = {}        -- { { src, action, cible, details, ordre }, ... }
local threads = {}       -- CreateThread : capturées, jamais lancées automatiquement
local commands = {}      -- RegisterCommand : commands[nom] = handler
local handlers = {}      -- RegisterNetEvent
local eventHandlers = {} -- AddEventHandler

local now = 1000
local sequence = 0
local function prochainOrdre()
    sequence = sequence + 1
    return sequence
end

-- Pilote : permet de vérifier que l'audit est protégé (pcall).
local logActionErreur = false

local function journaliser(kind, name, target, data, bytes)
    journal[#journal + 1] = {
        kind = kind, name = name, target = target, data = data,
        bytes = bytes, ordre = prochainOrdre(),
    }
end

local core = {
    IsAdmin = function(_, src) return admins[src] == true end,
    Notify = function(_, src, message)
        notices[#notices + 1] = { src = src, message = message, ordre = prochainOrdre() }
    end,
}

local env = setmetatable({
    source = 1,
    exports = {
        gf_core = core,
        gf_admin = {
            LogAction = function(_, src, action, cible, details)
                if logActionErreur then error('panne simulée LogAction') end
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
    GetPlayerName = function(id) return names[id] end,
    GetPlayers = function() return { '1', '2', '3', '4', '5', '6' } end,
    GetGameTimer = function() return now end,
    GetResourceState = function() return 'started' end,
    TriggerClientEvent = function(name, target, data)
        journaliser('client', name, target, data)
    end,
    -- Signature du contrat : name, target, bytes, data.
    TriggerLatentClientEvent = function(name, target, bytes, data)
        journaliser('latent', name, target, data, bytes)
    end,
    TriggerEvent = function(name, ...)
        journaliser('local', name, nil, { ... })
    end,
    RegisterCommand = function(name, handler) commands[name] = handler end,
    RegisterNetEvent = function(name, handler) handlers[name] = handler end,
    AddEventHandler = function(name, handler) eventHandlers[name] = handler end,
    -- On capture la boucle de suivi : chaque test décide du nombre de passes.
    CreateThread = function(fn) threads[#threads + 1] = fn end,
    Wait = function(ms) coroutine.yield(ms) end,
}, { __index = _G })
env._G = env

local chunkConfig = assert(loadfile(base .. 'config.lua', 't', env),
    'gf_screen/config.lua introuvable')
chunkConfig()
local chunkServer = assert(loadfile(base .. 'server.lua', 't', env),
    'gf_screen/server.lua introuvable')
chunkServer()

-- ---------------------------------------------------------------------------
-- Utilitaires du harnais.
-- ---------------------------------------------------------------------------
local function reinitialiser()
    journal, notices, prints, audits = {}, {}, {}, {}
    now = now + 2000 -- écarte toute fenêtre de débit résiduelle entre deux cas
    env.source = 1
end

local function appeler(src, args)
    assert(type(args) == 'table', 'les arguments doivent toujours être une table')
    env.source = src
    local handler = assert(commands.screen, 'commande screen absente')
    handler(src, args)
end

-- L'événement client lit `source` dans env ; l'image est son seul argument.
local function envoyerImage(src, image)
    env.source = src
    local handler = assert(handlers['gf_screen:frame'], 'event gf_screen:frame absent')
    handler(image)
end

local function depart(src)
    env.source = src
    local handler = assert(eventHandlers.playerDropped, 'handler playerDropped absent')
    handler()
end

local function entries(kind, name)
    local resultat = {}
    for _, e in ipairs(journal) do
        if e.kind == kind and (name == nil or e.name == name) then
            resultat[#resultat + 1] = e
        end
    end
    return resultat
end

local function entry(kind, name)
    return entries(kind, name)[1]
end

local function entriesVers(kind, name, target)
    local resultat = {}
    for _, e in ipairs(journal) do
        if e.kind == kind and (name == nil or e.name == name) and e.target == target then
            resultat[#resultat + 1] = e
        end
    end
    return resultat
end

local function notice(src, message)
    for _, n in ipairs(notices) do
        if n.src == src and n.message == message then return n end
    end
    return nil
end

-- `aucunAutreEffet` ignore les notifications (le cas en attend souvent une).
local function aucunAutreEffet()
    return #journal == 0 and #prints == 0 and #audits == 0
end

local function aucunEffet()
    return aucunAutreEffet() and #notices == 0
end

local function dataExact(e, nombreDeClefs, valeurs)
    if type(e) ~= 'table' or type(e.data) ~= 'table' then return false end
    local compte = 0
    for cle, valeur in pairs(e.data) do
        compte = compte + 1
        if valeurs[cle] == nil or valeur ~= valeurs[cle] then return false end
    end
    return compte == nombreDeClefs
end

-- Suite ordonnée des seuls effets observables (envois, notifications, audits).
local function suiteObservable()
    local constate = {}
    local liste = {}
    for _, e in ipairs(journal) do
        liste[#liste + 1] = {
            ordre = e.ordre,
            -- Affichage court : on retire le préfixe d'événement pour les
            -- libellés des suites, sans toucher aux assertions sur e.name.
            texte = ('%s %s -> %s'):format(
                e.kind, (e.name:gsub('^gf_screen:', '')), tostring(e.target)),
        }
    end
    for _, n in ipairs(notices) do
        liste[#liste + 1] = {
            ordre = n.ordre,
            texte = ('notice %d %s'):format(n.src, n.message),
        }
    end
    for _, a in ipairs(audits) do
        liste[#liste + 1] = {
            ordre = a.ordre,
            texte = ('audit %d %s %s'):format(a.src, a.action, tostring(a.cible)),
        }
    end
    table.sort(liste, function(a, b) return a.ordre < b.ordre end)
    for i, item in ipairs(liste) do constate[i] = item.texte end
    return constate
end

local function verifierSuite(attendu, label)
    local obtenu = suiteObservable()
    check(#obtenu == #attendu,
        ('%s : suite exacte (%d attendus, %d obtenus)')
            :format(label, #attendu, #obtenu))
    for i = 1, math.min(#obtenu, #attendu) do
        check(obtenu[i] == attendu[i],
            ('%s : élément %d = « %s » (attendu « %s »)')
                :format(label, i, tostring(obtenu[i]), tostring(attendu[i])))
    end
end

-- Une passe de la boucle de suivi = travail puis Wait(1000).
local function unePasse(label)
    local fonction = assert(threads[1], 'thread de suivi absent')
    local suivi = coroutine.create(fonction)
    local okPasse, attendu = coroutine.resume(suivi)
    check(okPasse and attendu == 1000,
        ('%s : une passe puis Wait(1000) sans erreur (yield=%s)')
            :format(label, tostring(attendu)))
end

-- Le départ peut être traité par playerDropped ou par la boucle de suivi :
-- on admet l'un ou l'autre, mais exige l'effet observable prescrit.
local function departCible(src, label)
    names[src] = nil
    depart(src)
    if entry('client', 'gf_screen:viewStop') == nil then unePasse(label) end
end

local function departAdmin(src, label)
    names[src] = nil
    depart(src)
    if entry('client', 'gf_screen:captureStop') == nil then unePasse(label) end
end

-- ---------------------------------------------------------------------------
-- 1. Enregistrements attendus.
-- ---------------------------------------------------------------------------
check(type(commands.screen) == 'function', "RegisterCommand('screen') enregistré")
check(type(handlers['gf_screen:frame']) == 'function',
    "RegisterNetEvent('gf_screen:frame') enregistré")
check(type(eventHandlers.playerDropped) == 'function',
    "AddEventHandler('playerDropped') enregistré")
check(#threads >= 1, 'CreateThread de suivi enregistré')

-- ---------------------------------------------------------------------------
-- 2. Refus non-admin : une notification exacte, aucun événement.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(6, { '3' })
check(#notices == 1 and notices[1] ~= nil and notices[1].src == 6
    and notices[1].message == REFUS,
    'non-admin : notification exacte')
check(aucunAutreEffet(), 'non-admin : aucun événement, print ni audit')

-- ---------------------------------------------------------------------------
-- 3. Console : un print exact, aucun événement ni notification.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(0, { '3' })
check(#prints == 1 and prints[1] == CONSOLE, 'console : print exact')
check(#journal == 0 and #notices == 0 and #audits == 0,
    'console : aucun événement, notification ni audit')

-- ---------------------------------------------------------------------------
-- 4. Usage sans vue en cours.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, {})
check(#notices == 1 and notice(1, USAGE) ~= nil, 'usage sans vue : message exact')
check(aucunAutreEffet(), 'usage sans vue : aucun événement, print ni audit')

-- ---------------------------------------------------------------------------
-- 5. Cible introuvable : l'id demandé apparaît dans le message.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '999' })
check(#notices == 1 and notice(1, 'Joueur 999 introuvable.') ~= nil,
    'cible introuvable : message exact avec l’id demandé')
check(aucunAutreEffet(), 'cible introuvable : aucun événement, print ni audit')

-- ---------------------------------------------------------------------------
-- 6. Refus de regarder son propre écran.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '1' })
check(#notices == 1 and notice(1, 'Tu ne peux pas regarder ton propre écran.') ~= nil,
    'soi-même : message exact')
check(aucunAutreEffet(), 'soi-même : aucun événement, print ni audit')

-- ---------------------------------------------------------------------------
-- 7. Départ réussi : ordre exact, charges utiles exactes, un seul audit.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3' })
verifierSuite({
    'client captureStart -> 3',
    'client viewStart -> 1',
    ('notice 1 Écran de %s. Tape screen pour arrêter.'):format(names[3]),
    'audit 1 screen 3',
}, 'départ réussi')

local capture = entry('client', 'gf_screen:captureStart')
check(capture ~= nil and capture.target == 3
    and dataExact(capture, 3, { fps = FPS, width = WIDTH, quality = QUALITY }),
    'départ réussi : captureStart exact vers la cible')
local vue = entry('client', 'gf_screen:viewStart')
check(vue ~= nil and vue.target == 1
    and dataExact(vue, 2, { target = 3, name = names[3] }),
    'départ réussi : viewStart exact vers l’admin')
check(#audits == 1 and audits[1] ~= nil and audits[1].src == 1
    and audits[1].action == 'screen' and audits[1].cible == 3
    and audits[1].details == nil,
    'départ réussi : exactement un LogAction(src, screen, cible, nil)')
local versCible = #entriesVers('client', nil, 3)
check(versCible == 1, 'départ réussi : un seul événement vers la cible')
local cibleNotifiee = false
for _, n in ipairs(notices) do
    if n.src == 3 then cibleNotifiee = true end
end
check(not cibleNotifiee, 'départ réussi : aucune notification à la cible')

-- ---------------------------------------------------------------------------
-- 8. Cible déjà regardée par un autre admin : refus, vue initiale intacte.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(2, { '3' })
check(#notices == 1 and notice(2,
        ('%s est déjà regardé par un administrateur.'):format(names[3])) ~= nil,
    'cible déjà regardée : message exact au second admin')
check(aucunAutreEffet(), 'cible déjà regardée : aucun événement ni audit')

reinitialiser()
local imageH = PREFIXE .. 'AAAABBBB'
envoyerImage(3, imageH)
local transH = entries('latent', 'gf_screen:frame')
check(#transH == 1 and transH[1] ~= nil and transH[1].target == 1
    and transH[1].bytes == LATENT_OCTETS and transH[1].data == imageH,
    'cible déjà regardée : la vue du premier admin reste active')

-- ---------------------------------------------------------------------------
-- 9. Même cible : arrêt dans l'ordre, sans audit.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3' })
verifierSuite({
    'client captureStop -> 3',
    'client viewStop -> 1',
    'notice 1 Écran arrêté.',
}, 'même cible : arrêt')
check(#audits == 0, 'même cible : aucun LogAction')
check(entry('client', 'gf_screen:captureStart') == nil
    and entry('client', 'gf_screen:viewStart') == nil,
    'même cible : aucun nouveau départ')

reinitialiser()
appeler(1, {})
check(#notices == 1 and notice(1, USAGE) ~= nil,
    'arrêt : la vue est oubliée (usage au prochain appel)')
check(aucunAutreEffet(), 'arrêt : aucun événement ni audit résiduel')

-- ---------------------------------------------------------------------------
-- 10. Image reçue sans vue en cours : aucun envoi.
-- ---------------------------------------------------------------------------
reinitialiser()
envoyerImage(3, PREFIXE .. 'SANSVIEWER')
check(aucunEffet(), 'frame sans viewer : aucun événement, notification ni audit')

-- ---------------------------------------------------------------------------
-- 11. Mauvais préfixe : aucun envoi malgré une vue active.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '4' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'mauvais préfixe : vue démarrée sur la cible 4')
reinitialiser()
envoyerImage(4, 'data:image/png;base64,AAAA')
check(aucunEffet(), 'mauvais préfixe : aucun envoi')

-- ---------------------------------------------------------------------------
-- 12. Image trop grande : aucun envoi malgré le bon préfixe.
-- ---------------------------------------------------------------------------
local imageGrande = PREFIXE .. string.rep('A', MAX_CHARS)
check(#imageGrande > MAX_CHARS, 'image trop grande : charge utile construite au-delà de la limite')
envoyerImage(4, imageGrande)
check(aucunEffet(), 'image trop grande : aucun envoi')

-- ---------------------------------------------------------------------------
-- 13. Débit : quatre images valides par fenêtre de 1000 ms, puis réinitialisation.
-- ---------------------------------------------------------------------------
local imagesM = {}
for i = 1, 4 do imagesM[i] = PREFIXE .. ('IMG%02d'):format(i) end
for i = 1, 4 do envoyerImage(4, imagesM[i]) end
local transM = entries('latent', 'gf_screen:frame')
check(#transM == 4,
    ('débit : quatre images transmises dans la fenêtre (obtenu %d)'):format(#transM))
for i = 1, math.min(#transM, 4) do
    check(transM[i].target == 1 and transM[i].bytes == LATENT_OCTETS
        and transM[i].data == imagesM[i],
        ('débit : image %d exacte vers le seul admin'):format(i))
end
envoyerImage(4, PREFIXE .. 'IMG05')
check(#entries('latent', 'gf_screen:frame') == 4, 'débit : cinquième image ignorée')
now = now + 1000
local image6 = PREFIXE .. 'IMG06'
envoyerImage(4, image6)
local trans6 = entries('latent', 'gf_screen:frame')
check(#trans6 == 5 and trans6[5] ~= nil and trans6[5].target == 1
    and trans6[5].bytes == LATENT_OCTETS and trans6[5].data == image6,
    'débit : image acceptée à GetGameTimer() + 1000')
check(#entries('client', 'gf_screen:frame') == 0,
    'débit : aucun envoi non latent de frame')

reinitialiser()
appeler(1, {})
check(notice(1, 'Écran arrêté.') ~= nil, 'débit : vue arrêtée pour la suite')

-- ---------------------------------------------------------------------------
-- 14. Transmission au seul admin qui regarde.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(2, { '5' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'transmission : vue démarrée sur 5 par l’admin 2')
reinitialiser()
local imageN = PREFIXE .. 'NSEUL'
envoyerImage(5, imageN)
local transN = entries('latent', 'gf_screen:frame')
check(#transN == 1 and transN[1] ~= nil and transN[1].target == 2
    and transN[1].bytes == LATENT_OCTETS and transN[1].data == imageN,
    'transmission : image envoyée au seul admin 2')
check(#entriesVers('latent', 'gf_screen:frame', 1) == 0,
    'transmission : aucun envoi à l’admin 1')
check(#entriesVers('client', nil, 5) == 0,
    'transmission : aucun événement vers la cible')
reinitialiser()
appeler(2, {})
check(notice(2, 'Écran arrêté.') ~= nil, 'transmission : vue arrêtée pour la suite')

-- ---------------------------------------------------------------------------
-- 15. Changement de cible : arrêt muet puis nouveau départ.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'changement de cible : vue initiale sur 3')
reinitialiser()
appeler(1, { '4' })
verifierSuite({
    'client captureStop -> 3',
    'client viewStop -> 1',
    'client captureStart -> 4',
    'client viewStart -> 1',
    ('notice 1 Écran de %s. Tape screen pour arrêter.'):format(names[4]),
    'audit 1 screen 4',
}, 'changement de cible')
check(notice(1, 'Écran arrêté.') == nil,
    'changement de cible : aucun message intermédiaire')
check(#notices == 1, 'changement de cible : une seule notification')
check(#audits == 1 and audits[1].cible == 4,
    'changement de cible : un seul LogAction, pour la nouvelle cible')
reinitialiser()
appeler(1, {})
check(notice(1, 'Écran arrêté.') ~= nil, 'changement de cible : vue arrêtée pour la suite')

-- ---------------------------------------------------------------------------
-- 16. Départ de la cible : viewStop, message exact, nettoyage complet.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'départ de la cible : vue démarrée sur 3')
reinitialiser()
departCible(3, 'départ de la cible : repli sur la boucle de suivi')
local stopO = entry('client', 'gf_screen:viewStop')
check(stopO ~= nil and stopO.target == 1,
    'départ de la cible : viewStop vers l’admin')
check(notice(1, 'Le joueur a quitté le serveur : écran arrêté.') ~= nil,
    'départ de la cible : message exact')
check(#audits == 0, 'départ de la cible : aucun LogAction')
reinitialiser()
appeler(1, {})
check(#notices == 1 and notice(1, USAGE) ~= nil,
    'départ de la cible : nettoyage complet (usage au prochain appel)')
names[3] = 'CibleTrois'

-- ---------------------------------------------------------------------------
-- 17. Départ de l'admin : captureStop vers la cible, aucun message à l'admin.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(2, { '4' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'départ de l’admin : vue démarrée sur 4')
reinitialiser()
departAdmin(2, 'départ de l’admin : repli sur la boucle de suivi')
local stopP = entry('client', 'gf_screen:captureStop')
check(stopP ~= nil and stopP.target == 4,
    'départ de l’admin : captureStop vers la cible')
local adminNotifie = false
for _, n in ipairs(notices) do
    if n.src == 2 then adminNotifie = true end
end
check(not adminNotifie, 'départ de l’admin : aucune notification à l’admin parti')
check(#audits == 0, 'départ de l’admin : aucun LogAction')
names[2] = 'AdminDeux'
reinitialiser()
appeler(2, {})
check(notice(2, USAGE) ~= nil, 'départ de l’admin : nettoyage complet')

-- ---------------------------------------------------------------------------
-- 18. screen sans argument avec une vue en cours : arrêt explicite.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '5' })
reinitialiser()
appeler(1, {})
verifierSuite({
    'client captureStop -> 5',
    'client viewStop -> 1',
    'notice 1 Écran arrêté.',
}, 'screen sans argument avec vue')
check(#audits == 0, 'screen sans argument avec vue : aucun LogAction')

-- ---------------------------------------------------------------------------
-- 19. Durée maximale : une passe de la boucle après MaxSeconds*1000 ms.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '5' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'MaxSeconds : vue démarrée sur 5')
reinitialiser()
now = now + MAX_SECONDS * 1000
unePasse('MaxSeconds')
verifierSuite({
    'client captureStop -> 5',
    'client viewStop -> 1',
    'notice 1 Durée maximale atteinte : écran arrêté.',
}, 'MaxSeconds')
check(#audits == 0, 'MaxSeconds : aucun LogAction')
reinitialiser()
appeler(1, {})
check(notice(1, USAGE) ~= nil, 'MaxSeconds : nettoyage complet')

-- ---------------------------------------------------------------------------
-- 20. LogAction protégé : une panne d'audit ne casse pas le départ.
-- ---------------------------------------------------------------------------
reinitialiser()
logActionErreur = true
local okAppel, err = pcall(appeler, 1, { '3' })
check(okAppel, ('LogAction protégé : aucune erreur propagée (%s)'):format(tostring(err)))
check(entry('client', 'gf_screen:captureStart') ~= nil
    and entry('client', 'gf_screen:viewStart') ~= nil
    and notice(1, ('Écran de %s. Tape screen pour arrêter.'):format(names[3])) ~= nil,
    'LogAction protégé : départ effectif malgré la panne d’audit')
logActionErreur = false
reinitialiser()
appeler(1, {})
check(notice(1, 'Écran arrêté.') ~= nil, 'LogAction protégé : vue arrêtée en fin de test')

print(('%d test(s) réussi(s), 0 échec(s)'):format(ok))
