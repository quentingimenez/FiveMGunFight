-- =============================================================================
--  Tests unitaires du module serveur pur gf_journal/journal.lua.
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/journal_test.lua
--  Aucune native FiveM n'est appelée : le module est un simple module Lua.
-- =============================================================================

local function racineDuDepot()
    local surcharge = os.getenv('GF_ROOT')
    if surcharge and surcharge ~= '' then return surcharge end

    local info = debug.getinfo(1, 'S')
    local chemin = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    chemin = chemin:gsub('\\', '/')
    if chemin ~= '' and chemin:sub(1, 1) ~= '/' and not chemin:match('^%a:/') then chemin = './' .. chemin end

    local prefixe = chemin:match('^(.*)/tests/lua/journal_test%.lua$')
    if prefixe and prefixe ~= '' then return prefixe end
    return '.'
end

local RACINE = racineDuDepot()

dofile(RACINE .. '/server-data/resources/[gunfight]/gf_journal/journal.lua')

local reussis, echecs = 0, 0

local function verifier(nom, fonction)
    local ok, erreur = pcall(fonction)
    if ok then
        reussis = reussis + 1
        print(('ok      %s'):format(nom))
    else
        echecs = echecs + 1
        print(('ECHEC   %s\n        %s'):format(nom, tostring(erreur)))
    end
end

local function egal(attendu, obtenu, message)
    if attendu ~= obtenu then
        error(('%s : attendu %s, obtenu %s'):format(message, tostring(attendu), tostring(obtenu)), 2)
    end
end

local function vrai(valeur, message)
    if not valeur then error(message, 2) end
end

local function ligne(mode, typeLigne, t_ms, donnees)
    return { match_id = 'm1', mode = mode, manche = 2, t_ms = t_ms, type = typeLigne, donnees = donnees }
end

-- ---------------------------------------------------------------- encoderJson
verifier('JSON : nil devient null', function()
    egal('null', Journal.encoderJson(nil), 'nil')
end)

verifier('JSON : booléens', function()
    egal('true', Journal.encoderJson(true), 'vrai')
    egal('false', Journal.encoderJson(false), 'faux')
end)

verifier('JSON : nombres entiers et flottants', function()
    egal('42', Journal.encoderJson(42), 'entier')
    egal('-7', Journal.encoderJson(-7), 'entier négatif')
    egal('1.5', Journal.encoderJson(1.5), 'flottant')
    egal('0.0', Journal.encoderJson(0.0), 'flottant entier')
end)

verifier('JSON : NaN et infinis deviennent null', function()
    egal('null', Journal.encoderJson(0 / 0), 'NaN')
    egal('null', Journal.encoderJson(math.huge), 'infini positif')
    egal('null', Journal.encoderJson(-math.huge), 'infini négatif')
end)

verifier('JSON : échappements exacts des chaînes', function()
    egal('"a\\"b"', Journal.encoderJson('a"b'), 'guillemet')
    egal('"a\\\\b"', Journal.encoderJson('a\\b'), 'anti-slash')
    egal('"a\\nb"', Journal.encoderJson('a\nb'), 'saut de ligne')
    egal('"a\\tb"', Journal.encoderJson('a\tb'), 'tabulation')
    egal('"a\\rb"', Journal.encoderJson('a\rb'), 'retour chariot')
    egal('"a\\bb"', Journal.encoderJson('a\bb'), 'retour arrière')
    egal('"a\\fb"', Journal.encoderJson('a\fb'), 'saut de page')
    egal('"a\\u0001b"', Journal.encoderJson('a\1b'), 'caractère de contrôle')
end)

verifier('JSON : UTF-8 conservé', function()
    egal('"é"', Journal.encoderJson('é'), 'été')
end)

verifier('JSON : objet simple avec clés triées', function()
    egal('{"a":1,"b":2}', Journal.encoderJson({ b = 2, a = 1 }), 'objet trié')
end)

verifier('JSON : table imbriquée', function()
    local valeur = { joueur = { nom = 'Bob', actif = true }, score = 3 }
    egal('{"joueur":{"actif":true,"nom":"Bob"},"score":3}', Journal.encoderJson(valeur), 'imbriqué')
end)

verifier('JSON : tableau séquentiel', function()
    egal('[1,2,3]', Journal.encoderJson({ 1, 2, 3 }), 'tableau')
end)

verifier('JSON : tableau de tableaux', function()
    egal('[[1,2],[3,4]]', Journal.encoderJson({ { 1, 2 }, { 3, 4 } }), 'tableau de tableaux')
end)

verifier('JSON : table vide devient {}', function()
    egal('{}', Journal.encoderJson({}), 'vide')
end)

verifier('JSON : types non prévus deviennent null', function()
    egal('{"f":null}', Journal.encoderJson({ f = function() return 1 end }), 'fonction')
end)

verifier('JSON : cycle ne boucle pas', function()
    local t = {}
    t.self = t
    local ok, resultat = pcall(Journal.encoderJson, t)
    vrai(ok, 'encoderJson a levé une erreur sur un cycle')
    egal('{"self":null}', resultat, 'cycle')
end)

verifier('JSON : clefs non chaîne converties en chaîne', function()
    -- Une clé 2 seule n'est pas un tableau séquentiel (trou en position 1) :
    -- la table est donc encodée comme objet et la clé devient "2".
    egal('{"2":"x"}', Journal.encoderJson({ [2] = 'x' }), 'clé numérique')
end)

-- ---------------------------------------------------------------- nouveau / ajouter
verifier('tampon : nouveau est vide', function()
    local tampon = Journal.nouveau()
    egal(0, #tampon.lignes, 'lignes')
    egal(0, tampon.rejetees, 'rejetees')
end)

verifier('ajouter : ligne valide acceptée', function()
    local tampon = Journal.nouveau()
    local l = ligne('attack', 'kill', 1000, { tueur = 1 })
    vrai(Journal.ajouter(tampon, l), 'acceptée')
    egal(1, #tampon.lignes, 'lignes')
    egal(0, tampon.rejetees, 'rejetees')
    egal('attack', tampon.lignes[1].mode, 'mode')
    egal(1000, tampon.lignes[1].t_ms, 't_ms')
end)

verifier('ajouter : donnees nil devient {}', function()
    local tampon = Journal.nouveau()
    vrai(Journal.ajouter(tampon, ligne('attack', 'kill', 0)), 'acceptée')
    egal('table', type(tampon.lignes[1].donnees), 'donnees')
    egal(0, #tampon.lignes[1].donnees, 'donnees vide')
end)

verifier('ajouter : t_ms = 0 accepté, match_id et manche nil acceptés', function()
    local tampon = Journal.nouveau()
    local l = { mode = 'attack', type = 'start', t_ms = 0 }
    vrai(Journal.ajouter(tampon, l), 'acceptée')
    egal(1, #tampon.lignes, 'lignes')
    egal(nil, tampon.lignes[1].match_id, 'match_id')
    egal(nil, tampon.lignes[1].manche, 'manche')
end)

verifier('ajouter : lignes invalides refusées sans erreur', function()
    local invalides = {
        nil,
        'texte',
        42,
        true,
        {},
        { mode = nil, type = 'kill', t_ms = 1 },
        { mode = '', type = 'kill', t_ms = 1 },
        { mode = '   ', type = 'kill', t_ms = 1 },
        { mode = 5, type = 'kill', t_ms = 1 },
        { mode = 'attack', type = nil, t_ms = 1 },
        { mode = 'attack', type = '', t_ms = 1 },
        { mode = 'attack', type = 7, t_ms = 1 },
        { mode = 'attack', type = 'kill', t_ms = nil },
        { mode = 'attack', type = 'kill', t_ms = '1000' },
        { mode = 'attack', type = 'kill', t_ms = 0 / 0 },
        { mode = 'attack', type = 'kill', t_ms = math.huge },
        { mode = 'attack', type = 'kill', t_ms = -math.huge },
    }
    local tampon = Journal.nouveau()
    for i = 1, #invalides do
        local ok, accepte = pcall(Journal.ajouter, tampon, invalides[i])
        vrai(ok, 'exception pour la ligne invalide ' .. i)
        egal(false, accepte, 'acceptée ' .. i)
    end
    egal(0, #tampon.lignes, 'aucune ligne ajoutée')
    egal(#invalides, tampon.rejetees, 'rejetees')
end)

verifier('ajouter : ordre d’arrivée conservé', function()
    local tampon = Journal.nouveau()
    for i = 1, 3 do
        vrai(Journal.ajouter(tampon, ligne('attack', 't' .. i, i)), 'ligne ' .. i)
    end
    for i = 1, 3 do
        egal('t' .. i, tampon.lignes[i].type, 'ordre ' .. i)
    end
end)

-- ---------------------------------------------------------------- extraireLot
verifier('extraireLot : deux premières lignes puis la dernière', function()
    local tampon = Journal.nouveau()
    for i = 1, 3 do
        Journal.ajouter(tampon, ligne('attack', 't' .. i, i))
    end

    local lot = Journal.extraireLot(tampon, 2)
    egal(2, #lot, 'taille du premier lot')
    egal('t1', lot[1].type, 'première')
    egal('t2', lot[2].type, 'deuxième')
    egal(1, #tampon.lignes, 'reste une ligne')
    egal('t3', tampon.lignes[1].type, 'troisième restante')

    local reste = Journal.extraireLot(tampon, 10)
    egal(1, #reste, 'taille du second lot')
    egal('t3', reste[1].type, 'dernière')
    egal(0, #tampon.lignes, 'tampon vidé')
end)

verifier('extraireLot : tampon vide', function()
    egal(0, #Journal.extraireLot(Journal.nouveau(), 5), 'lot vide')
end)

verifier('extraireLot : max invalide ou nul', function()
    local tampon = Journal.nouveau()
    Journal.ajouter(tampon, ligne('attack', 'kill', 1))
    egal(0, #Journal.extraireLot(tampon, 0), 'max nul')
    egal(0, #Journal.extraireLot(tampon, -1), 'max négatif')
    egal(0, #Journal.extraireLot(tampon, 1.5), 'max flottant')
    egal(0, #Journal.extraireLot(tampon, '2'), 'max chaîne')
    egal(0, #Journal.extraireLot(tampon, nil), 'max nil')
    egal(1, #tampon.lignes, 'ligne intacte')
end)

-- ---------------------------------------------------------------- nouvelIdMatch
verifier('nouvelIdMatch : exemple attendu', function()
    egal('attack-1764150000-3', Journal.nouvelIdMatch('attack', 1764150000, 3), 'identifiant')
end)

verifier('nouvelIdMatch : longueur maximale 40', function()
    local identifiant = Journal.nouvelIdMatch('attack', 1764150000, 3)
    vrai(#identifiant <= 40, 'longueur ' .. #identifiant)
end)

verifier('nouvelIdMatch : mode nettoyé et tronqué', function()
    local sale = 'att!!!ack$$$with%%%lots___of---chars@@@and&&&more'
    local identifiant = Journal.nouvelIdMatch(sale, 1764150000, 3)
    vrai(#identifiant <= 40, 'longueur ' .. #identifiant)
    vrai(not identifiant:match('[%!%$%%@&]'), 'caractères inattendus présents')
end)

verifier('nouvelIdMatch : repli et entrées imparfaites', function()
    egal('match-0-0', Journal.nouvelIdMatch(nil, nil, nil), 'repli')
    egal('match-0-0', Journal.nouvelIdMatch('', 'abc', 'xyz'), 'entrées non numériques')
    egal('match-0-0', Journal.nouvelIdMatch(42, 0 / 0, math.huge), 'mode non chaîne')
end)

verifier('nouvelIdMatch : nombres arrondis à la baisse', function()
    egal('attack-1764150000-3', Journal.nouvelIdMatch('attack', 1764150000.9, 3.7), 'floor')
end)

print(('\n%d test(s) réussi(s), %d échec(s)'):format(reussis, echecs))
if echecs > 0 then os.exit(1) end
