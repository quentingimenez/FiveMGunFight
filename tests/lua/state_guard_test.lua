-- =============================================================================
--  Tests unitaires du module serveur pur gf_core/state_guard.lua.
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/state_guard_test.lua
--  Aucune native FiveM n'est appelée : le module est un simple module Lua.
-- =============================================================================

local function racineDuDepot()
    local surcharge = os.getenv('GF_ROOT')
    if surcharge and surcharge ~= '' then return surcharge end

    local info = debug.getinfo(1, 'S')
    local chemin = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    chemin = chemin:gsub('\\', '/')
    if chemin ~= '' and chemin:sub(1, 1) ~= '/' and not chemin:match('^%a:/') then chemin = './' .. chemin end

    local prefixe = chemin:match('^(.*)/tests/lua/state_guard_test%.lua$')
    if prefixe and prefixe ~= '' then return prefixe end
    return '.'
end

local RACINE = racineDuDepot()

dofile(RACINE .. '/server-data/resources/[gunfight]/gf_core/state_guard.lua')

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
    if valeur ~= true then
        error(('%s : attendu true, obtenu %s'):format(message, tostring(valeur)), 2)
    end
end

-- ---------------------------------------------------------------- normaliser / booleen
verifier('booleen : vrai, faux, nil', function()
    egal(true, GardeEtat.normaliser('gf_protected', true), 'true')
    egal(false, GardeEtat.normaliser('gf_protected', false), 'false')
    egal(false, GardeEtat.normaliser('gf_protected', nil), 'nil')
end)

verifier('booleen : valeurs truthy', function()
    egal(true, GardeEtat.normaliser('gf_protected', 1), '1')
    egal(true, GardeEtat.normaliser('gf_protected', 'A'), "'A'")
end)

-- ---------------------------------------------------------------- normaliser / valeur
verifier('valeur : conservée telle quelle', function()
    egal(true, GardeEtat.normaliser('gf_team', true), 'true')
    egal(false, GardeEtat.normaliser('gf_team', false), 'false')
    egal(nil, GardeEtat.normaliser('gf_team', nil), 'nil')
    egal(1, GardeEtat.normaliser('gf_team', 1), '1')
    egal('A', GardeEtat.normaliser('gf_team', 'A'), "'A'")
end)

verifier('cle inconnue : normaliser renvoie nil', function()
    egal(nil, GardeEtat.normaliser('cle_inconnue', 'A'), 'cle inconnue')
end)

-- ---------------------------------------------------------------- decider
verifier('decider : cle inconnue ignorée', function()
    egal('ignorer', GardeEtat.decider('cle_inconnue', 'A', 'B'), 'cle inconnue')
end)

verifier('decider : booleen nil et false concordent', function()
    egal('ok', GardeEtat.decider('gf_protected', nil, false), 'nil vs false')
end)

verifier('decider : booleen divergents rétablis', function()
    egal('retablir', GardeEtat.decider('gf_protected', true, false), 'true vs false')
end)

verifier('decider : valeur égale acceptée', function()
    egal('ok', GardeEtat.decider('gf_team', 'A', 'A'), "'A' vs 'A'")
end)

verifier('decider : valeur différente rétablie', function()
    egal('retablir', GardeEtat.decider('gf_team', 'B', 'A'), "'B' vs 'A'")
end)

verifier('decider : nil reçu rétabli face à une valeur serveur', function()
    egal('retablir', GardeEtat.decider('gf_team', nil, 'A'), "nil vs 'A'")
end)

verifier('decider : valeur reçue rétablie face à nil serveur', function()
    egal('retablir', GardeEtat.decider('gf_team', 'A', nil), "'A' vs nil")
end)

verifier('decider : gf_mode divergent rétabli', function()
    egal('retablir', GardeEtat.decider('gf_mode', 'lobby', 'attack'), 'lobby vs attack')
end)

-- ---------------------------------------------------------------- joueurDuSac
verifier('joueurDuSac : identifiants valides', function()
    egal(12, GardeEtat.joueurDuSac('player:12'), 'player:12')
    egal('integer', math.type(GardeEtat.joueurDuSac('player:12')), 'type entier')
    egal(0, GardeEtat.joueurDuSac('player:0'), 'player:0')
end)

verifier('joueurDuSac : formes invalides', function()
    egal(nil, GardeEtat.joueurDuSac('entity:5'), 'entity:5')
    egal(nil, GardeEtat.joueurDuSac('player:'), 'player:')
    egal(nil, GardeEtat.joueurDuSac('player:abc'), 'player:abc')
    egal(nil, GardeEtat.joueurDuSac('player:12x'), 'player:12x')
    egal(nil, GardeEtat.joueurDuSac(nil), 'nil')
    egal(nil, GardeEtat.joueurDuSac(12), 'nombre')
end)

-- ---------------------------------------------------------------- signalable
verifier('signalable : premier signalement accepté avec ignores à 0', function()
    local etat = {}
    local ok, ignores = GardeEtat.signalable(etat, 1, 'gf_team', 1000, 5000)
    vrai(ok, 'premier signalement')
    egal(0, ignores, 'ignores au premier signalement')
end)

verifier('signalable : appel dans le même intervalle refusé', function()
    local etat = {}
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 5000), 'premier signalement')
    local ok, ignores = GardeEtat.signalable(etat, 1, 'gf_team', 1001, 5000)
    egal(false, ok, 'deuxième signalement')
    egal(nil, ignores, 'pas de compteur sur un refus')
end)

verifier('signalable : ignores restitue les refus après l’intervalle', function()
    local etat = {}
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 5000), 'premier signalement')
    egal(false, GardeEtat.signalable(etat, 1, 'gf_team', 1001, 5000), 'premier refus')
    egal(false, GardeEtat.signalable(etat, 1, 'gf_team', 2000, 5000), 'deuxième refus')
    local ok, ignores = GardeEtat.signalable(etat, 1, 'gf_team', 6000, 5000)
    vrai(ok, 'signalement après intervalle')
    egal(2, ignores, 'deux refus comptés')
end)

verifier('signalable : intervalle exactement écoulé autorisé', function()
    local etat = {}
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 5000), 'premier signalement')
    local ok, ignores = GardeEtat.signalable(etat, 1, 'gf_team', 6000, 5000)
    vrai(ok, 'signalement à intervalle exact')
    egal(0, ignores, 'aucun refus entre les deux')
end)

verifier('signalable : compteur repart à zéro après un signalement', function()
    local etat = {}
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 5000), 'premier signalement')
    egal(false, GardeEtat.signalable(etat, 1, 'gf_team', 2000, 5000), 'refus')
    local ok, ignores = GardeEtat.signalable(etat, 1, 'gf_team', 6000, 5000)
    vrai(ok, 'signalement après intervalle')
    egal(1, ignores, 'un refus compté')
    egal(false, GardeEtat.signalable(etat, 1, 'gf_team', 7000, 5000), 'refus après signalement')
    local ok2, ignores2 = GardeEtat.signalable(etat, 1, 'gf_team', 11000, 5000)
    vrai(ok2, 'signalement suivant')
    egal(1, ignores2, 'compteur remis à zéro puis un seul refus')
end)

verifier('signalable : clés indépendantes pour un même joueur', function()
    local etat = {}
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 5000), 'signalement gf_team')
    local ok, ignores = GardeEtat.signalable(etat, 1, 'gf_mode', 1001, 5000)
    vrai(ok, 'signalement gf_mode')
    egal(0, ignores, 'gf_mode a son propre compteur')
    egal(false, GardeEtat.signalable(etat, 1, 'gf_team', 1002, 5000), 'gf_team toujours refusé')
end)

verifier('signalable : joueurs indépendants pour la même clé', function()
    local etat = {}
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 5000), 'signalement joueur 1')
    local ok, ignores = GardeEtat.signalable(etat, 2, 'gf_team', 1000, 5000)
    vrai(ok, 'signalement joueur 2')
    egal(0, ignores, 'joueur 2 a son propre compteur')
    egal(false, GardeEtat.signalable(etat, 1, 'gf_team', 1001, 5000), 'joueur 1 toujours refusé')
end)

verifier('signalable : validation défensive sans modifier l’état', function()
    local etat = {}
    local function refus(who, cle, maintenant, intervalle)
        local ok = GardeEtat.signalable(etat, who, cle, maintenant, intervalle)
        egal(false, ok, 'entrée invalide refusée')
    end
    refus(nil, 'gf_team', 1000, 5000)
    refus(1 / 0, 'gf_team', 1000, 5000)
    refus(1, nil, 1000, 5000)
    refus(1, 12, 1000, 5000)
    refus(1, 'gf_team', nil, 5000)
    refus(1, 'gf_team', 0 / 0, 5000)
    refus(1, 'gf_team', 1000, -1)
    refus(1, 'gf_team', 1000, 0 / 0)
    egal(nil, etat[1], 'aucune entrée créée par une entrée invalide')
    egal(false, GardeEtat.signalable(nil, 1, 'gf_team', 1000, 5000), 'etat non-table')
end)

verifier('signalable : intervalle 0 autorise chaque appel', function()
    local etat = {}
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 0), 'premier signalement')
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 0), 'deuxième signalement')
end)

-- ---------------------------------------------------------------- oublier
verifier('oublier : efface toutes les clés et compteurs du joueur', function()
    local etat = {}
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 5000), 'joueur 1 gf_team')
    vrai(GardeEtat.signalable(etat, 1, 'gf_mode', 1000, 5000), 'joueur 1 gf_mode')
    vrai(GardeEtat.signalable(etat, 2, 'gf_team', 1000, 5000), 'joueur 2 gf_team')
    GardeEtat.oublier(etat, 1)
    egal(nil, etat[1], 'joueur 1 oublié')
    egal('table', type(etat[2]), 'joueur 2 conservé')

    -- Le joueur oublié peut signaler à nouveau immédiatement.
    local ok, ignores = GardeEtat.signalable(etat, 1, 'gf_team', 1001, 5000)
    vrai(ok, 'nouveau signalement du joueur oublié')
    egal(0, ignores, 'compteur reparti à zéro')

    -- L'autre joueur garde son horodatage et son compteur.
    egal(false, GardeEtat.signalable(etat, 2, 'gf_team', 1001, 5000), 'joueur 2 toujours refusé')
end)

verifier('oublier : sans effet sur entrées invalides', function()
    local etat = {}
    vrai(GardeEtat.signalable(etat, 1, 'gf_team', 1000, 5000), 'signalement initial')
    GardeEtat.oublier(etat, nil)
    GardeEtat.oublier(nil, 1)
    GardeEtat.oublier('pas une table', 1)
    egal('table', type(etat[1]), 'état inchangé')
    egal(false, GardeEtat.signalable(etat, 1, 'gf_team', 1001, 5000), 'toujours dans l’intervalle')
end)

print(('\n%d test(s) réussi(s), %d échec(s)'):format(reussis, echecs))
if echecs > 0 then os.exit(1) end
