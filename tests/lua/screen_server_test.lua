-- =============================================================================
--  Tests du serveur gf_screen : commande screen, préréglages, relais d'images
--  avec métadonnées et suivi du débit.
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
local QUALITE_INCONNUE = 'Qualité inconnue : basse, moyenne, haute ou ultra.'
local PREFIXE_WEBP = 'data:image/webp;base64,'
local PREFIXE_JPEG = 'data:image/jpeg;base64,'
local DEFAUT = 'haute'
local PRESETS = {
    basse = { width = 640, fps = 3, quality = 0.5 },
    moyenne = { width = 960, fps = 5, quality = 0.6 },
    haute = { width = 1280, fps = 8, quality = 0.7 },
    ultra = { width = 1280, fps = 15, quality = 0.6 },
}
local UPLOAD_BPS = 1000000
local LATENT_OCTETS = 1500000
local MAX_CHARS = 600000
local MAX_SECONDS = 600

-- Ids distincts pour éviter tout état résiduel : 1 et 2 administrateurs,
-- 3 à 5 cibles ; 6 est un joueur non administrateur.
local admins = { [1] = true, [2] = true }
local names = {
    [1] = 'AdminUn',
    [2] = 'AdminDeux',
    [3] = 'CibleTrois',
    [4] = 'CibleQuatre',
    [5] = 'CibleCinq',
}

-- Un seul journal pour les événements locaux, client et latents : l'ordre
-- relatif des envois, notifications et audits reste observable.
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
local Config = env.Config

-- ---------------------------------------------------------------------------
-- Utilitaires du harnais.
-- ---------------------------------------------------------------------------
-- reinitialiser() vide les journaux et écarte toute fenêtre de débit, mais ne
-- touche ni à Watching ni à Viewer : chaque cas arrête explicitement sa vue.
local function reinitialiser()
    journal, notices, prints, audits = {}, {}, {}, {}
    now = now + 2000
    env.source = 1
end

local function appeler(src, args)
    assert(type(args) == 'table', 'les arguments doivent toujours être une table')
    env.source = src
    local handler = assert(commands.screen, 'commande screen absente')
    handler(src, args)
end

-- L'événement client lit `source` dans env et reçoit une table { image, meta }.
local function envoyerPayload(src, payload)
    env.source = src
    local handler = assert(handlers['gf_screen:frame'], 'event gf_screen:frame absent')
    handler(payload)
end

local function envoyerImage(src, image, meta)
    envoyerPayload(src, { image = image, meta = meta })
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

-- Arrêt explicite d'une vue : défini APRÈS notice, dont il dépend.
local function arret(admin, label)
    appeler(admin, {})
    check(notice(admin, 'Écran arrêté.') ~= nil,
        ('%s : vue arrêtée explicitement'):format(label or 'arrêt'))
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

-- Métadonnées valides : exactement dix champs, modifiables pour les cas invalides.
local function metaValide(changes)
    local meta = {
        hp = 82, armour = 35, weapon = 'WEAPON_CARBINE', clip = 12, ammo = 90,
        mode = 'attack', vehicle = false, speed = 42.5, w = 640, h = 360,
    }
    if changes then
        for cle, valeur in pairs(changes) do meta[cle] = valeur end
    end
    return meta
end

-- Comparaison profonde exacte d'une meta relayée (dix clés, aucune en trop).
local function metaExact(meta, attendu)
    if type(meta) ~= 'table' or type(attendu) ~= 'table' then return false end
    local compte = 0
    for cle, valeur in pairs(meta) do
        compte = compte + 1
        if attendu[cle] == nil or valeur ~= attendu[cle] then return false end
    end
    return compte == 10
end

-- Donnée latente exacte : image, preset et, seulement si elle est valide, meta.
-- Quand meta est nil, la clé `meta` doit être ABSENTE (data a deux clés).
local function frameDataExact(e, image, preset, meta)
    if type(e) ~= 'table' or type(e.data) ~= 'table' then return false end
    local compte = 0
    for cle, valeur in pairs(e.data) do
        compte = compte + 1
        if cle ~= 'image' and cle ~= 'meta' and cle ~= 'preset' then return false end
        if cle == 'image' and valeur ~= image then return false end
        if cle == 'preset' and valeur ~= preset then return false end
        if cle == 'meta' then
            if meta == nil or not metaExact(valeur, meta) then return false end
        end
    end
    if meta == nil then return compte == 2 end
    return compte == 3
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
-- 1. Configuration exacte chargée depuis config.lua.
-- ---------------------------------------------------------------------------
check(type(Config) == 'table', 'Config chargé depuis config.lua')
check(type(Config.Presets) == 'table', 'Config.Presets présent')
local comptePresets = 0
for _ in pairs(Config.Presets or {}) do comptePresets = comptePresets + 1 end
check(comptePresets == 4, 'Config.Presets : exactement quatre préréglages')
for _, nom in ipairs({ 'basse', 'moyenne', 'haute', 'ultra' }) do
    local preset = Config.Presets[nom]
    local attendu = PRESETS[nom]
    local compte = 0
    if type(preset) == 'table' then
        for cle in pairs(preset) do compte = compte + 1 end
    end
    check(type(preset) == 'table' and compte == 3
        and preset.width == attendu.width and preset.fps == attendu.fps
        and preset.quality == attendu.quality,
        ('Config.Presets.%s exact (3 clés : width, fps, quality)'):format(nom))
end
check(Config.DefaultPreset == DEFAUT, 'Config.DefaultPreset = haute')
check(Config.UploadBps == UPLOAD_BPS, 'Config.UploadBps exact')
check(Config.ForwardBps == LATENT_OCTETS, 'Config.ForwardBps exact')
check(Config.MaxFrameChars == MAX_CHARS, 'Config.MaxFrameChars exact')
check(Config.MaxSeconds == MAX_SECONDS, 'Config.MaxSeconds exact')

-- ---------------------------------------------------------------------------
-- 2. Enregistrements attendus.
-- ---------------------------------------------------------------------------
check(type(commands.screen) == 'function', "RegisterCommand('screen') enregistré")
check(type(handlers['gf_screen:frame']) == 'function',
    "RegisterNetEvent('gf_screen:frame') enregistré")
check(type(eventHandlers.playerDropped) == 'function',
    "AddEventHandler('playerDropped') enregistré")
check(#threads >= 1, 'CreateThread de suivi enregistré')

-- ---------------------------------------------------------------------------
-- 3. Refus non-admin : une notification exacte, aucun événement.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(6, { '3' })
check(#notices == 1 and notices[1] ~= nil and notices[1].src == 6
    and notices[1].message == REFUS,
    'non-admin : notification exacte')
check(aucunAutreEffet(), 'non-admin : aucun événement, print ni audit')

-- ---------------------------------------------------------------------------
-- 4. Console : un print exact, aucun événement ni notification.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(0, { '3' })
check(#prints == 1 and prints[1] == CONSOLE, 'console : print exact')
check(#journal == 0 and #notices == 0 and #audits == 0,
    'console : aucun événement, notification ni audit')

-- ---------------------------------------------------------------------------
-- 5. Usage sans vue en cours.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, {})
check(#notices == 1 and notice(1, USAGE) ~= nil, 'usage sans vue : message exact')
check(aucunAutreEffet(), 'usage sans vue : aucun événement, print ni audit')

-- ---------------------------------------------------------------------------
-- 6. Cible introuvable : l'id demandé apparaît dans le message.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '999' })
check(#notices == 1 and notice(1, 'Joueur 999 introuvable.') ~= nil,
    'cible introuvable : message exact avec l’id demandé')
check(aucunAutreEffet(), 'cible introuvable : aucun événement, print ni audit')

-- ---------------------------------------------------------------------------
-- 7. Refus de regarder son propre écran.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '1' })
check(#notices == 1 and notice(1, 'Tu ne peux pas regarder ton propre écran.') ~= nil,
    'soi-même : message exact')
check(aucunAutreEffet(), 'soi-même : aucun événement, print ni audit')

-- ---------------------------------------------------------------------------
-- 8. Préréglage inconnu : message exact, aucun autre effet.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3', 'turbo' })
check(#notices == 1 and notice(1, QUALITE_INCONNUE) ~= nil,
    'préréglage inconnu : message exact')
check(aucunAutreEffet(), 'préréglage inconnu : aucun événement, print ni audit')

-- ---------------------------------------------------------------------------
-- 9. Départ réussi : préréglage par défaut, ordre exact, charges utiles exactes.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3' })
verifierSuite({
    'client captureStart -> 3',
    'client viewStart -> 1',
    ('notice 1 Écran de %s (%s). Tape screen pour arrêter.'):format(names[3], DEFAUT),
    'audit 1 screen 3',
}, 'départ réussi : préréglage par défaut')

local capture = entry('client', 'gf_screen:captureStart')
check(capture ~= nil and capture.target == 3
    and dataExact(capture, 4, {
        fps = PRESETS[DEFAUT].fps, width = PRESETS[DEFAUT].width,
        quality = PRESETS[DEFAUT].quality, format = 'webp',
    }),
    'départ réussi : captureStart exact (4 clés, format webp) vers la cible')
local vue = entry('client', 'gf_screen:viewStart')
check(vue ~= nil and vue.target == 1
    and dataExact(vue, 3, { target = 3, name = names[3], preset = DEFAUT }),
    'départ réussi : viewStart exact (3 clés) vers l’admin')
check(#audits == 1 and audits[1] ~= nil and audits[1].src == 1
    and audits[1].action == 'screen' and audits[1].cible == 3
    and audits[1].details == ('qualite=%s'):format(DEFAUT),
    'départ réussi : un seul LogAction avec details qualite=haute')
local versCible = #entriesVers('client', nil, 3)
check(versCible == 1, 'départ réussi : un seul événement vers la cible')
local cibleNotifiee = false
for _, n in ipairs(notices) do
    if n.src == 3 then cibleNotifiee = true end
end
check(not cibleNotifiee, 'départ réussi : aucune notification à la cible')

-- ---------------------------------------------------------------------------
-- 10. Cible déjà regardée par un autre admin : refus, vue initiale intacte.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(2, { '3', 'basse' })
check(#notices == 1 and notice(2,
        ('%s est déjà regardé par un administrateur.'):format(names[3])) ~= nil,
    'cible déjà regardée : message exact au second admin')
check(aucunAutreEffet(), 'cible déjà regardée : aucun événement ni audit')

reinitialiser()
local imageH = PREFIXE_WEBP .. 'AAAABBBB'
envoyerImage(3, imageH)
local transH = entries('latent', 'gf_screen:frame')
check(#transH == 1 and transH[1] ~= nil and transH[1].target == 1
    and transH[1].bytes == LATENT_OCTETS
    and frameDataExact(transH[1], imageH, DEFAUT, nil),
    'cible déjà regardée : la vue du premier admin reste active avec son preset')
reinitialiser()
arret(1, 'cible déjà regardée')

-- ---------------------------------------------------------------------------
-- 11. Préréglage inconnu pendant une vue : vue intacte, frame relayée.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3', 'haute' })
reinitialiser()
appeler(1, { '3', 'turbo' })
check(#notices == 1 and notice(1, QUALITE_INCONNUE) ~= nil,
    'préréglage inconnu pendant une vue : message exact')
check(aucunAutreEffet(), 'préréglage inconnu pendant une vue : aucun autre effet')
local imageInconnue = PREFIXE_WEBP .. 'VUEINTACTE'
envoyerImage(3, imageInconnue)
local transInconnue = entries('latent', 'gf_screen:frame')
check(#transInconnue == 1
    and frameDataExact(transInconnue[1], imageInconnue, 'haute', nil),
    'préréglage inconnu pendant une vue : la vue et son préréglage restent actifs')
reinitialiser()
arret(1, 'préréglage inconnu pendant une vue')

-- ---------------------------------------------------------------------------
-- 12. Même cible sans préréglage : arrêt dans l'ordre, sans audit.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3', 'haute' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'même cible sans préréglage : vue active sur 3 avant l’arrêt')
reinitialiser()
appeler(1, { '3' })
verifierSuite({
    'client captureStop -> 3',
    'client viewStop -> 1',
    'notice 1 Écran arrêté.',
}, 'même cible sans préréglage : arrêt')
check(#audits == 0, 'même cible sans préréglage : aucun LogAction')
check(entry('client', 'gf_screen:captureStart') == nil
    and entry('client', 'gf_screen:viewStart') == nil,
    'même cible sans préréglage : aucun nouveau départ')

reinitialiser()
appeler(1, {})
check(#notices == 1 and notice(1, USAGE) ~= nil,
    'arrêt : la vue est oubliée (usage au prochain appel)')
check(aucunAutreEffet(), 'arrêt : aucun événement ni audit résiduel')

-- ---------------------------------------------------------------------------
-- 13. Préréglages choisis : charges utiles, notification et audit exacts.
-- ---------------------------------------------------------------------------
local function verifierPreset(preset, admin, cible)
    reinitialiser()
    appeler(admin, { tostring(cible), preset })
    local p = PRESETS[preset]
    local capturePreset = entry('client', 'gf_screen:captureStart')
    check(capturePreset ~= nil and capturePreset.target == cible
        and dataExact(capturePreset, 4, {
            fps = p.fps, width = p.width, quality = p.quality, format = 'webp',
        }),
        ('préréglage %s : captureStart exact (4 clés)'):format(preset))
    local vuePreset = entry('client', 'gf_screen:viewStart')
    check(vuePreset ~= nil and vuePreset.target == admin
        and dataExact(vuePreset, 3, {
            target = cible, name = names[cible], preset = preset,
        }),
        ('préréglage %s : viewStart exact (3 clés)'):format(preset))
    check(notice(admin,
            ('Écran de %s (%s). Tape screen pour arrêter.'):format(names[cible], preset)) ~= nil,
        ('préréglage %s : notification exacte avec le préréglage'):format(preset))
    check(#audits == 1 and audits[1].details == ('qualite=%s'):format(preset),
        ('préréglage %s : audit avec details'):format(preset))
    reinitialiser()
    local imagePreset = PREFIXE_JPEG .. ('PRESET%s'):format(preset)
    envoyerImage(cible, imagePreset)
    local transPreset = entries('latent', 'gf_screen:frame')
    check(#transPreset == 1 and transPreset[1].target == admin
        and transPreset[1].bytes == LATENT_OCTETS
        and frameDataExact(transPreset[1], imagePreset, preset, nil),
        ('préréglage %s : frame relayée avec le bon preset'):format(preset))
    reinitialiser()
    arret(admin, ('préréglage %s'):format(preset))
end
verifierPreset('basse', 1, 3)
verifierPreset('moyenne', 2, 4)
verifierPreset('ultra', 1, 5)

-- ---------------------------------------------------------------------------
-- 14. Même cible avec préréglage : nouveau captureStart, aucun arrêt,
--     fenêtre de débit remise à zéro, durée initiale conservée.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3', 'basse' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'changement de préréglage : vue initiale basse')
reinitialiser()
for i = 1, PRESETS.basse.fps + 1 do
    envoyerImage(3, PREFIXE_JPEG .. ('VIEUX%02d'):format(i))
end
check(#entries('latent', 'gf_screen:frame') == PRESETS.basse.fps + 1,
    'changement de préréglage : quota basse consommé')
appeler(1, { '3', 'haute' })
check(#entries('client', 'gf_screen:captureStop') == 0
    and #entries('client', 'gf_screen:viewStop') == 0
    and #entries('client', 'gf_screen:viewStart') == 0
    and #notices == 0 and #audits == 0 and #prints == 0,
    'changement de préréglage : aucun arrêt, notification ni audit')
local nouveaux = entries('client', 'gf_screen:captureStart')
check(#nouveaux == 1 and dataExact(nouveaux[1], 4, {
        fps = PRESETS.haute.fps, width = PRESETS.haute.width,
        quality = PRESETS.haute.quality, format = 'webp',
    }),
    'changement de préréglage : un seul nouveau captureStart aux valeurs haute')
for i = 1, PRESETS.haute.fps + 1 do
    envoyerImage(3, PREFIXE_JPEG .. ('NOUVEAU%02d'):format(i))
end
local transChangement = entries('latent', 'gf_screen:frame')
local totalAttendu = (PRESETS.basse.fps + 1) + (PRESETS.haute.fps + 1)
check(#transChangement == totalAttendu,
    ('changement de préréglage : fenêtre remise à zéro (%d images attendues, %d obtenues)')
        :format(totalAttendu, #transChangement))
for i = PRESETS.basse.fps + 2, totalAttendu do
    check(transChangement[i] ~= nil
        and frameDataExact(transChangement[i],
            PREFIXE_JPEG .. ('NOUVEAU%02d'):format(i - PRESETS.basse.fps - 1), 'haute', nil),
        ('changement de préréglage : image %d relayée avec le nouveau preset'):format(i))
end
envoyerImage(3, PREFIXE_JPEG .. 'AUDELA')
check(#entries('latent', 'gf_screen:frame') == totalAttendu,
    'changement de préréglage : image au-delà du nouveau quota ignorée')
reinitialiser()
arret(1, 'changement de préréglage')

reinitialiser()
appeler(1, { '3', 'basse' })
local departInitial = now
reinitialiser()
now = departInitial + MAX_SECONDS * 1000 - 1000
appeler(1, { '3', 'moyenne' })
check(entry('client', 'gf_screen:captureStop') == nil,
    'durée conservée : pas d’arrêt au changement de préréglage')
unePasse('durée conservée')
check(entry('client', 'gf_screen:viewStop') == nil,
    'durée conservée : aucune expiration avant MaxSeconds depuis le départ')
now = departInitial + MAX_SECONDS * 1000 + 1
unePasse('durée conservée : expiration')
check(entry('client', 'gf_screen:viewStop') ~= nil
    and notice(1, 'Durée maximale atteinte : écran arrêté.') ~= nil,
    'durée conservée : expiration après MaxSeconds depuis le départ initial')
reinitialiser()
appeler(1, {})
check(notice(1, USAGE) ~= nil, 'durée conservée : nettoyage complet')

-- ---------------------------------------------------------------------------
-- 15. Image reçue sans vue en cours : aucun envoi.
-- ---------------------------------------------------------------------------
reinitialiser()
envoyerImage(3, PREFIXE_JPEG .. 'SANSVIEWER', metaValide())
check(aucunEffet(), 'frame sans viewer : aucun événement, notification ni audit')

-- ---------------------------------------------------------------------------
-- 16. Formats et charges utiles acceptées / refusées.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '4', 'moyenne' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'formats : vue démarrée sur la cible 4 en moyenne')
reinitialiser()

local imageWebp = PREFIXE_WEBP .. 'WEBPACCEPTEE'
envoyerImage(4, imageWebp)
local transWebp = entries('latent', 'gf_screen:frame')
check(#transWebp == 1 and transWebp[1].target == 1
    and transWebp[1].bytes == LATENT_OCTETS
    and frameDataExact(transWebp[1], imageWebp, 'moyenne', nil),
    'image webp : acceptée et relayée')

local imageJpeg = PREFIXE_JPEG .. 'JPEGACCEPTEE'
envoyerImage(4, imageJpeg)
local transJpeg = entries('latent', 'gf_screen:frame')
check(#transJpeg == 2 and frameDataExact(transJpeg[2], imageJpeg, 'moyenne', nil),
    'image jpeg : acceptée et relayée')

local avantRefus = #entries('latent', 'gf_screen:frame')
envoyerImage(4, 'data:image/png;base64,AAAA')
check(#entries('latent', 'gf_screen:frame') == avantRefus,
    'autre préfixe : aucun envoi')
envoyerPayload(4, PREFIXE_JPEG .. 'CHAINESEULE')
check(#entries('latent', 'gf_screen:frame') == avantRefus,
    'payload chaîne seule : aucun envoi')
local imageGrande = PREFIXE_JPEG .. string.rep('A', MAX_CHARS)
check(#imageGrande > MAX_CHARS,
    'image trop grande : charge utile construite au-delà de la limite')
envoyerImage(4, imageGrande)
check(#entries('latent', 'gf_screen:frame') == avantRefus,
    'image trop longue : aucun envoi')

-- Les images invalides ne consomment pas de quota : les images valides suivantes
-- passent encore après les trois refus, puis la suivante est bien bloquée.
local quota = PRESETS.moyenne.fps + 1
for i = 3, quota do envoyerImage(4, PREFIXE_JPEG .. ('VALIDE%02d'):format(i)) end
check(#entries('latent', 'gf_screen:frame') == quota,
    'images invalides : aucun quota consommé')
envoyerImage(4, PREFIXE_JPEG .. 'EXCEDENT')
check(#entries('latent', 'gf_screen:frame') == quota,
    'images invalides : image suivante ignorée après épuisement du quota')
reinitialiser()
arret(1, 'formats et charges utiles')

-- ---------------------------------------------------------------------------
-- 17. Métadonnées valides : transmises champ par champ avec l'image.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '5', 'haute' })
reinitialiser()
local metaComplete = metaValide({
    hp = 100, armour = 0, weapon = 'WEAPON_SNSPISTOL', clip = 7, ammo = 1234,
    mode = 'lobby', vehicle = true, speed = 999, w = 4096, h = 1,
})
local imageMeta = PREFIXE_WEBP .. 'METACOMPLETE'
envoyerImage(5, imageMeta, metaComplete)
local transMeta = entries('latent', 'gf_screen:frame')
check(#transMeta == 1 and transMeta[1].target == 1
    and transMeta[1].bytes == LATENT_OCTETS
    and frameDataExact(transMeta[1], imageMeta, 'haute', metaComplete),
    'meta valide : dix champs transmis exactement avec l’image')
check(metaExact(transMeta[1] and transMeta[1].data.meta, metaComplete),
    'meta valide : comparaison profonde exacte')
reinitialiser()
arret(1, 'meta valide')

-- ---------------------------------------------------------------------------
-- 18. Métadonnées invalides : l'image est relayée, meta absente du data.
-- ---------------------------------------------------------------------------
local metaSansHp = metaValide()
metaSansHp.hp = nil
local casMetaInvalides = {
    { 'meta non table', 'pas une table' },
    { 'clé manquante', metaSansHp },
    { 'clé en trop', metaValide({ extra = 1 }) },
    { 'hp hors borne', metaValide({ hp = 101 }) },
    { 'hp non entier', metaValide({ hp = 50.5 }) },
    { 'weapon non chaîne', metaValide({ weapon = 42 }) },
    { 'clip hors borne', metaValide({ clip = 10000 }) },
    { 'ammo non entier', metaValide({ ammo = 12.5 }) },
    { 'mode non chaîne', metaValide({ mode = true }) },
    { 'vehicle non booléen', metaValide({ vehicle = 1 }) },
    { 'speed hors borne', metaValide({ speed = 1000 }) },
    { 'w hors borne', metaValide({ w = 4097 }) },
    { 'h non entier', metaValide({ h = 720.25 }) },
}
for _, cas in ipairs(casMetaInvalides) do
    reinitialiser()
    appeler(1, { '3', 'basse' })
    reinitialiser()
    local imageCas = PREFIXE_JPEG .. 'METAINVALIDE'
    envoyerImage(3, imageCas, cas[2])
    local transCas = entries('latent', 'gf_screen:frame')
    check(#transCas == 1 and transCas[1].bytes == LATENT_OCTETS
        and transCas[1].target == 1
        and frameDataExact(transCas[1], imageCas, 'basse', nil),
        ('meta invalide (%s) : image relayée avec data à deux clés'):format(cas[1]))
    check(transCas[1] == nil or transCas[1].data.meta == nil,
        ('meta invalide (%s) : clé meta absente'):format(cas[1]))
    reinitialiser()
    arret(1, ('meta invalide (%s)'):format(cas[1]))
end

-- ---------------------------------------------------------------------------
-- 19. Troncature des textes libres de la meta.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3', 'haute' })
reinitialiser()
local imageLongue = PREFIXE_JPEG .. 'TRONCATURE'
envoyerImage(3, imageLongue, metaValide({
    weapon = string.rep('w', 40), mode = string.rep('m', 20),
}))
local transLongue = entries('latent', 'gf_screen:frame')
check(#transLongue == 1
    and frameDataExact(transLongue[1], imageLongue, 'haute', metaValide({
        weapon = string.rep('w', 32), mode = string.rep('m', 16),
    })),
    'troncature : weapon à 32 et mode à 16 caractères, meta conservée')
reinitialiser()
arret(1, 'troncature')

-- ---------------------------------------------------------------------------
-- 20. Débit : nombre exact d'images par fenêtre pour chaque préréglage.
-- ---------------------------------------------------------------------------
local function verifierDebit(preset, admin, cible)
    local label = preset
    reinitialiser()
    appeler(admin, { tostring(cible), preset })
    check(entry('client', 'gf_screen:captureStart') ~= nil,
        ('débit %s : vue démarrée'):format(label))
    reinitialiser()
    local limite = PRESETS[preset].fps + 1
    local images = {}
    for i = 1, limite do
        images[i] = PREFIXE_JPEG .. ('%s-%03d'):format(label, i)
        envoyerImage(cible, images[i])
    end
    local trans = entries('latent', 'gf_screen:frame')
    check(#trans == limite,
        ('débit %s : %d images transmises dans la fenêtre (obtenu %d)')
            :format(label, limite, #trans))
    for i = 1, math.min(#trans, limite) do
        check(trans[i].target == admin and trans[i].bytes == LATENT_OCTETS
            and frameDataExact(trans[i], images[i], preset, nil),
            ('débit %s : image %d exacte vers le seul admin'):format(label, i))
    end
    envoyerImage(cible, PREFIXE_JPEG .. label .. '-REFUSEE')
    check(#entries('latent', 'gf_screen:frame') == limite,
        ('débit %s : image suivante ignorée'):format(label))
    now = now + 1000
    local imagePlus = PREFIXE_JPEG .. label .. '-PLUS'
    envoyerImage(cible, imagePlus)
    local transPlus = entries('latent', 'gf_screen:frame')
    check(#transPlus == limite + 1 and transPlus[limite + 1] ~= nil
        and frameDataExact(transPlus[limite + 1], imagePlus, preset, nil),
        ('débit %s : image acceptée à GetGameTimer() + 1000'):format(label))
    check(#entries('client', 'gf_screen:frame') == 0,
        ('débit %s : aucun envoi non latent de frame'):format(label))
    reinitialiser()
    arret(admin, ('débit %s'):format(label))
end
verifierDebit('basse', 1, 3)
verifierDebit('moyenne', 2, 4)
verifierDebit('haute', 1, 5)
verifierDebit('ultra', 2, 3)
check(PRESETS.ultra.fps + 1 == 16, 'débit ultra : plafond explicite de 16 images/s')

-- ---------------------------------------------------------------------------
-- 21. Transmission au seul admin qui regarde.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(2, { '5', 'basse' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'transmission : vue démarrée sur 5 par l’admin 2')
reinitialiser()
local imageN = PREFIXE_WEBP .. 'NSEUL'
envoyerImage(5, imageN, metaValide())
local transN = entries('latent', 'gf_screen:frame')
check(#transN == 1 and transN[1] ~= nil and transN[1].target == 2
    and transN[1].bytes == LATENT_OCTETS
    and frameDataExact(transN[1], imageN, 'basse', metaValide()),
    'transmission : image envoyée au seul admin 2')
check(#entriesVers('latent', 'gf_screen:frame', 1) == 0,
    'transmission : aucun envoi à l’admin 1')
check(#entriesVers('client', nil, 5) == 0,
    'transmission : aucun événement vers la cible')
reinitialiser()
arret(2, 'transmission')

-- ---------------------------------------------------------------------------
-- 22. Changement de cible avec préréglage : arrêt muet puis nouveau départ.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3', 'basse' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'changement de cible : vue initiale sur 3 en basse')
reinitialiser()
appeler(1, { '4', 'moyenne' })
verifierSuite({
    'client captureStop -> 3',
    'client viewStop -> 1',
    'client captureStart -> 4',
    'client viewStart -> 1',
    ('notice 1 Écran de %s (%s). Tape screen pour arrêter.'):format(names[4], 'moyenne'),
    'audit 1 screen 4',
}, 'changement de cible avec préréglage')
check(notice(1, 'Écran arrêté.') == nil,
    'changement de cible : aucun message intermédiaire')
check(#notices == 1, 'changement de cible : une seule notification')
check(#audits == 1 and audits[1].cible == 4
    and audits[1].details == 'qualite=moyenne',
    'changement de cible : un seul LogAction avec qualite=moyenne')
local captureChangement = entry('client', 'gf_screen:captureStart')
check(captureChangement ~= nil
    and dataExact(captureChangement, 4, {
        fps = PRESETS.moyenne.fps, width = PRESETS.moyenne.width,
        quality = PRESETS.moyenne.quality, format = 'webp',
    }),
    'changement de cible : captureStart aux valeurs du nouveau préréglage')
reinitialiser()
arret(1, 'changement de cible avec préréglage')

-- ---------------------------------------------------------------------------
-- 23. Départ de la cible : viewStop, message exact, nettoyage complet.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '3', 'haute' })
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
-- 24. Départ de l'admin : captureStop vers la cible, aucun message à l'admin.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(2, { '4', 'basse' })
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
-- 25. screen sans argument avec une vue en cours : arrêt explicite.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '5', 'moyenne' })
reinitialiser()
appeler(1, {})
verifierSuite({
    'client captureStop -> 5',
    'client viewStop -> 1',
    'notice 1 Écran arrêté.',
}, 'screen sans argument avec vue')
check(#audits == 0, 'screen sans argument avec vue : aucun LogAction')

-- ---------------------------------------------------------------------------
-- 26. Durée maximale : une passe après MaxSeconds*1000 ms depuis le départ.
-- ---------------------------------------------------------------------------
reinitialiser()
appeler(1, { '5', 'haute' })
check(entry('client', 'gf_screen:captureStart') ~= nil,
    'MaxSeconds : vue démarrée sur 5 en haute')
check(notice(1, ('Écran de %s (%s). Tape screen pour arrêter.'):format(names[5], 'haute')) ~= nil,
    'MaxSeconds : message de départ avec le préréglage')
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
-- 27. LogAction protégé : une panne d'audit ne casse pas le départ.
-- ---------------------------------------------------------------------------
reinitialiser()
logActionErreur = true
local okAppel, err = pcall(appeler, 1, { '3', 'moyenne' })
check(okAppel, ('LogAction protégé : aucune erreur propagée (%s)'):format(tostring(err)))
check(entry('client', 'gf_screen:captureStart') ~= nil
    and entry('client', 'gf_screen:viewStart') ~= nil
    and notice(1, ('Écran de %s (%s). Tape screen pour arrêter.'):format(names[3], 'moyenne')) ~= nil,
    'LogAction protégé : départ effectif malgré la panne d’audit')
logActionErreur = false
reinitialiser()
arret(1, 'LogAction protégé')

print(('%d test(s) réussi(s), 0 échec(s)'):format(ok))
