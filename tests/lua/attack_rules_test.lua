-- =============================================================================
--  gf_attack - tests autonomes de rules.lua (module serveur pur).
--
--  Lancement (depuis la racine du dépôt) : lua5.4 tests/lua/attack_rules_test.lua
--  La racine est calculée comme dans tests/lua/run.lua (debug.getinfo + GF_ROOT).
--  Aucune native FiveM, aucune horloge réelle et surtout aucun math.random :
--  le hasard vient d'un générateur déterministe écrit ci-dessous.
--
--  Le test ne rejoue PAS les effets différés du serveur (SetTimeout) : il ne
--  vérifie que les règles pures et les effets rendus par le module.
-- =============================================================================

local function racineDuDepot()
    local surcharge = os.getenv('GF_ROOT')
    if surcharge and surcharge ~= '' then return surcharge end

    local info = debug.getinfo(1, 'S')
    local chemin = info and info.source and info.source:sub(1, 1) == '@' and info.source:sub(2) or ''
    chemin = chemin:gsub('\\', '/')
    if chemin ~= '' and chemin:sub(1, 1) ~= '/' and not chemin:match('^%a:/') then chemin = './' .. chemin end

    local prefixe = chemin:match('^(.*)/tests/lua/attack_rules_test%.lua$')
    if prefixe and prefixe ~= '' then return prefixe end
    return '.'
end

local RACINE = racineDuDepot()
local MODULE = RACINE .. '/server-data/resources/[gunfight]/gf_attack/'
dofile(MODULE .. 'rules.lua')

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

-- ---------------------------------------------------------------------------
--  Hasard déterministe (Park-Miller), strictement sans math.random.
--  La même fonction sert aux règles et aux événements, avec des graines
--  dérivées de la graine de la suite.
-- ---------------------------------------------------------------------------

local function nouveauHasard(graine)
    local etat = graine % 2147483647
    if etat <= 0 then etat = etat + 2147483646 end
    return function(n)
        etat = (etat * 48271) % 2147483647
        return (etat % n) + 1
    end
end

local function nouveauJeu(graine)
    local derive = nouveauHasard(graine)
    local graineRegles = derive(2147483646)
    local graineEvenements = derive(2147483646)
    return nouveauHasard(graineRegles), nouveauHasard(graineEvenements)
end

local CONFIG = {
    PlayersToStart = 2,
    MaxPlayers = 40,
    WinRounds = 2,
    SwapSidesEveryRound = true,
    SelectTimeMs = 1000,
    PlacementTimeMs = 1000,
    RoundTimeMs = 10000,
    EndDelayMs = 1000,
    MatchEndDelayMs = 1000,
}

local TYPES_ATTENDUS = {
    phase = true, equipe = true, vivant = true, apparition = true, spectateur = true,
    menuArmes = true, fermerMenuArmes = true, objets = true, armes = true, degeler = true,
    protection = true, notifier = true, annonce = true, finManche = true, finMatch = true,
    retourLobby = true, chargerCarte = true, effacerResultats = true, nettoyerJoueur = true,
    recompenseKevlar = true, statistiquesKill = true, spectateurDiffere = true,
    placementDiffere = true, zone = true, classement = true, matchArrete = true,
}

local typesVus = {}
local typesInattendus = {}

local function enregistrerEffets(effets)
    for _, effet in ipairs(effets or {}) do
        if not TYPES_ATTENDUS[effet.type] then
            typesInattendus[tostring(effet.type)] = true
            error('type d’effet hors liste fermée : ' .. tostring(effet.type), 2)
        end
        typesVus[effet.type] = true
    end
end

-- ---------------------------------------------------------------------------
--  Aides générales.
-- ---------------------------------------------------------------------------

local function copieProfonde(valeur)
    if type(valeur) ~= 'table' then return valeur end
    local copie = {}
    for cle, v in pairs(valeur) do copie[cle] = copieProfonde(v) end
    return copie
end

local function copieScore(score)
    return { A = score.A, B = score.B }
end

local function autreCamp(camp)
    return camp == 'A' and 'B' or 'A'
end

local function nouveauContexte(graine, suite, evenement)
    return {
        graine = graine or 0,
        suite = suite or 0,
        evenement = evenement or 'scénario',
        manches = 0,
    }
end

local function echec(ctx, invariant, detail)
    error(('graine=%s suite=%s événement=%s invariant=%s : %s'):format(
        tostring(ctx and ctx.graine or '?'), tostring(ctx and ctx.suite or '?'),
        tostring(ctx and ctx.evenement or '?'), invariant, tostring(detail or '')), 2)
end

local function aEffet(effets, typeEffet, modele)
    for _, effet in ipairs(effets) do
        if effet.type == typeEffet and (modele == nil or effet.modele == modele) then return true end
    end
    return false
end

local function trouverEffet(effets, typeEffet, modele)
    for _, effet in ipairs(effets) do
        if effet.type == typeEffet and (modele == nil or effet.modele == modele) then return effet end
    end
    return nil
end

local function compterEffets(effets, typeEffet, modele)
    local n = 0
    for _, effet in ipairs(effets) do
        if effet.type == typeEffet and (modele == nil or effet.modele == modele) then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
--  Vérificateur d'invariants, appelé après CHAQUE événement du fuzz et aux
--  étapes clés des scénarios fixes. `avant` est un instantané du score et de
--  la phase juste avant l'événement.
-- ---------------------------------------------------------------------------

local function verifierInvariants(ctx, etat, effets, avant)
    effets = effets or {}
    avant = avant or { score = copieScore(etat.score), phase = etat.phase }
    enregistrerEffets(effets)

    -- Remises à zéro à prendre en compte dans le compteur de manches.
    if aEffet(effets, 'matchArrete') or aEffet(effets, 'retourLobby')
        or (etat.phase == 'waiting' and AttackRules.nombreJoueurs(etat) == 0) then
        ctx.manches = 0
    end

    -- 1) Un seul camp gagne une manche : +1 pile, l'autre inchangé, phase ended,
    --    et le total des scores suit le nombre de manches terminées.
    for _, effet in ipairs(effets) do
        if effet.type == 'finManche' then
            if effet.gagnant ~= 'A' and effet.gagnant ~= 'B' then
                echec(ctx, '1', 'gagnant invalide : ' .. tostring(effet.gagnant))
            end
            local gagnant, adverse = effet.gagnant, autreCamp(effet.gagnant)
            if avant.score[gagnant] + 1 ~= etat.score[gagnant] then
                echec(ctx, '1', ('score du gagnant %s : avant=%s après=%s'):format(
                    gagnant, tostring(avant.score[gagnant]), tostring(etat.score[gagnant])))
            end
            if avant.score[adverse] ~= etat.score[adverse] then
                echec(ctx, '1', ('score de %s a bougé'):format(adverse))
            end
            if etat.phase ~= 'ended' then
                echec(ctx, '1', 'phase après finManche : ' .. tostring(etat.phase))
            end
            ctx.manches = ctx.manches + 1
        end
    end
    if etat.score.A + etat.score.B ~= ctx.manches then
        echec(ctx, '1', ('total scores=%d, manches=%d'):format(
            etat.score.A + etat.score.B, ctx.manches))
    end

    -- 2) Aucun score ne dépasse WinRounds ; matchOver exactement à WinRounds.
    local max = etat.config.WinRounds
    if etat.score.A > max or etat.score.B > max or etat.score.A < 0 or etat.score.B < 0 then
        echec(ctx, '2', ('scores %s/%s hors bornes'):format(tostring(etat.score.A), tostring(etat.score.B)))
    end
    local attendu = (etat.score.A == max or etat.score.B == max)
    if etat.matchOver ~= attendu then
        echec(ctx, '2', ('matchOver=%s attendu=%s'):format(tostring(etat.matchOver), tostring(attendu)))
    end

    -- 3) Un joueur n'appartient qu'à une équipe ; stats/vivants cohérents.
    --    Note : un joueur parti peut revenir plus tard (gf:modeJoined) et
    --    l'ancienne entrée dans `partis` reste : ce n'est PAS une règle violée.
    for src, camp in pairs(etat.equipes) do
        if camp ~= 'A' and camp ~= 'B' then
            echec(ctx, '3', ('équipe invalide pour %s : %s'):format(tostring(src), tostring(camp)))
        end
        local st = etat.stats[src]
        if type(st) ~= 'table' or type(st.kills) ~= 'number' or type(st.deaths) ~= 'number' then
            echec(ctx, '3', ('stats manquantes pour %s'):format(tostring(src)))
        end
    end
    for src in pairs(etat.vivants) do
        if not etat.equipes[src] then echec(ctx, '3', ('vivant %s sans équipe'):format(tostring(src))) end
    end
    for src in pairs(etat.stats) do
        if not etat.equipes[src] then echec(ctx, '3', ('stats %s sans équipe'):format(tostring(src))) end
    end

    -- 4) Après l'équilibrage du premier select, l'écart d'effectif est <= 1.
    if etat.manche == 1 and avant.phase ~= 'select' and etat.phase == 'select' then
        local ecart = math.abs(AttackRules.compter(etat, 'A') - AttackRules.compter(etat, 'B'))
        if ecart > 1 then echec(ctx, '4', ('écart d’effectif=%d'):format(ecart)) end
    end

    -- 5) Un départ ne bloque pas la machine à états.
    if AttackRules.nombreJoueurs(etat) == 0 and etat.phase ~= 'waiting' then
        echec(ctx, '5', 'joueurs vides hors waiting : ' .. tostring(etat.phase))
    end
    if etat.phase == 'waiting' then
        if etat.echeance ~= 0 then
            echec(ctx, '5', ('waiting avec échéance=%s'):format(tostring(etat.echeance)))
        end
    elseif etat.echeance <= 0 then
        echec(ctx, '5', ('phase %s avec échéance=%s'):format(tostring(etat.phase), tostring(etat.echeance)))
    end
end

-- Applique une fonction publique, vérifie les invariants et rend les effets.
local function appliquer(ctx, etat, fonction, ...)
    local avant = { score = copieScore(etat.score), phase = etat.phase }
    local effets = fonction(etat, ...)
    verifierInvariants(ctx, etat, effets, avant)
    return effets
end

-- ---------------------------------------------------------------------------
--  Aides de scénario.
-- ---------------------------------------------------------------------------

local function etatDeTest(graine)
    return AttackRules.nouveau(CONFIG, nouveauHasard(graine))
end

-- Match à deux joueurs : 1 attaque (A), 2 défend (B), quel que soit le hasard.
local function matchDeDeux(graine)
    local etat = etatDeTest(graine)
    AttackRules.arrivee(etat, 1)
    AttackRules.arrivee(etat, 2)
    AttackRules.changerEquipe(etat, 1, 'A', 0)
    AttackRules.changerEquipe(etat, 2, 'B', 0)
    return etat
end

-- Sources encore libres pour une arrivée : seuls les src déjà dans une équipe
-- sont exclus (40 joueurs au plus). Un src présent dans `partis` peut parfaitement
-- revenir : l'ancien server.lua le réinsère dans S.team sans effacer son entrée
-- dans S.departed. Le fuzz couvre donc aussi ces ré-arrivées.
local function srcArrivee(etat, hasard)
    local libres = {}
    for src = 1, 40 do
        if not etat.equipes[src] then libres[#libres + 1] = src end
    end
    if #libres == 0 then return nil end
    return libres[hasard(#libres)]
end

-- Avance la machine jusqu'à 'live' et rend l'instant où 'live' commence.
local function avancerJusquALive(etat, t0)
    local t = t0 or 0
    for _ = 1, 12 do
        AttackRules.tic(etat, t, false)
        if etat.phase == 'live' then return t end
        t = t + 1000
    end
    error('phase live non atteinte depuis ' .. tostring(t0))
end

-- Drainage : uniquement des tics(false) avec +1000 ms jusqu'au retour en
-- 'waiting'. Le chrono en pause (attaquant vivant dans la zone) est une règle
-- existante : on utilise false pour borner, sans assimiler le gel à un échec.
local function drainer(ctx, etat, t0)
    local t = t0 or 0
    local phaseDepart = etat.phase
    local sortieLive
    local tics = 0
    for _ = 1, 10000 do
        if phaseDepart == 'live' and etat.phase ~= 'live' and not sortieLive then
            sortieLive = t - (t0 or 0)
        end
        if etat.phase == 'waiting' then break end
        local avant = { score = copieScore(etat.score), phase = etat.phase }
        local effets = AttackRules.tic(etat, t, false)
        verifierInvariants(ctx, etat, effets, avant)
        t = t + 1000
        tics = tics + 1
    end
    return tics, sortieLive
end

-- ===========================================================================
--  Scénarios fixes.
-- ===========================================================================

verifier('API : état initial, requêtes et capacité d’accueil', function()
    local etat = etatDeTest(11)
    egal('waiting', etat.phase, 'phase')
    egal(0, etat.manche, 'manche')
    egal(0, etat.echeance, 'échéance')
    egal('A', etat.attaquants, 'attaquants')
    egal(false, etat.solo, 'solo')
    egal(false, etat.matchOver, 'matchOver')
    egal(false, etat.echangeDeCamp, 'echangeDeCamp')
    egal(0, etat.score.A, 'score A')
    egal(0, etat.score.B, 'score B')
    egal(true, AttackRules.estOuvert(etat), 'estOuvert')
    egal(true, AttackRules.peutRejoindre(etat), 'peutRejoindre')
    egal('attack', AttackRules.roleEquipe(etat, 'A'), 'roleEquipe A')
    egal('defense', AttackRules.roleEquipe(etat, 'B'), 'roleEquipe B')

    AttackRules.arrivee(etat, 7)
    egal(AttackRules.roleEquipe(etat, etat.equipes[7]), AttackRules.roleDe(etat, 7), 'roleDe')
    egal(1, AttackRules.compter(etat, etat.equipes[7]), 'compter')
    egal(0, AttackRules.compterVivants(etat, etat.equipes[7]), 'compterVivants en attente')
    egal(1, AttackRules.nombreJoueurs(etat), 'nombreJoueurs')
    egal('waiting', etat.phase, 'phase inchangée')

    local config = {}
    for cle, valeur in pairs(CONFIG) do config[cle] = valeur end
    config.MaxPlayers = 1
    local plein = AttackRules.nouveau(config, nouveauHasard(12))
    AttackRules.arrivee(plein, 1)
    egal(false, AttackRules.peutRejoindre(plein), 'MaxPlayers atteint')
end)

verifier('arrivée : effets, notifier et placement selon la phase', function()
    local ctx = nouveauContexte(101, 0, 'arrivee')
    local etat = etatDeTest(13)
    local effets = appliquer(ctx, etat, AttackRules.arrivee, 5)
    egal('equipe', effets[1].type, 'premier effet')
    egal(true, aEffet(effets, 'notifier', 'rejoint'), 'notifier rejoint')
    egal(true, aEffet(effets, 'apparition'), 'apparition attente')
    egal(true, aEffet(effets, 'zone'), 'zone')
    egal(true, aEffet(effets, 'classement'), 'classement')
    egal('attente', trouverEffet(effets, 'apparition').mode, 'mode attente')
    egal(1, compterEffets(effets, 'vivant'), 'un effet vivant')
    egal(false, trouverEffet(effets, 'vivant').vivant, 'vivant false en attente')
    egal(false, etat.vivants[5], 'vivant en attente')
end)

verifier('condition de départ : 1 joueur n’est pas assez, 2 joueurs démarrent', function()
    local ctx = nouveauContexte(102, 0, 'tic waiting')
    local etat = etatDeTest(14)
    AttackRules.arrivee(etat, 1)
    appliquer(ctx, etat, AttackRules.tic, 0, false)
    egal('waiting', etat.phase, '1 joueur : waiting')
    egal(0, etat.manche, '1 joueur : manche 0')
    AttackRules.arrivee(etat, 2)
    local effets = appliquer(ctx, etat, AttackRules.tic, 1000, false)
    egal('select', etat.phase, '2 joueurs : select')
    egal(1, etat.manche, 'manche 1')
    egal(2, compterEffets(effets, 'vivant'), 'un vivant true par joueur')
    for _, effet in ipairs(effets) do
        if effet.type == 'vivant' then egal(true, effet.vivant, 'vivant true au select') end
    end
end)

verifier('début de match : chargerCarte(recharger) puis équilibrage', function()
    local ctx = nouveauContexte(103, 0, 'premier select')
    local etat = etatDeTest(15)
    for src = 1, 7 do AttackRules.arrivee(etat, src) end
    -- On force un déséquilibre (6 contre 1) avant le premier tic : les deux
    -- camps sont non vides, donc canStart est vrai et l'équilibrage s'applique.
    for src = 1, 6 do AttackRules.changerEquipe(etat, src, 'A', 0) end
    AttackRules.changerEquipe(etat, 7, 'B', 0)
    egal(true, AttackRules.peutRejoindre(etat), 'peut rejoindre')
    local effets = appliquer(ctx, etat, AttackRules.tic, 1000, false)
    egal('select', etat.phase, 'phase')
    egal(true, aEffet(effets, 'chargerCarte'), 'chargerCarte')
    egal('recharger', trouverEffet(effets, 'chargerCarte').mode, 'mode recharger')
    egal(true, aEffet(effets, 'notifier', 'equilibrage'), 'notifier equilibrage')
    vrai(math.abs(AttackRules.compter(etat, 'A') - AttackRules.compter(etat, 'B')) <= 1, 'écart <= 1')
    egal(7, compterEffets(effets, 'vivant'), 'un vivant true par joueur')
    for _, effet in ipairs(effets) do
        if effet.type == 'vivant' then egal(true, effet.vivant, 'vivant true au select') end
    end
end)

verifier('manche gagnée par élimination des défenseurs', function()
    local ctx = nouveauContexte(104, 0, 'mort defenseur')
    local etat = matchDeDeux(16)
    local t = avancerJusquALive(etat, 0)
    local effets = appliquer(ctx, etat, AttackRules.mort, 2, 1, t + 100)
    local fin = trouverEffet(effets, 'finManche')
    vrai(fin ~= nil, 'effet finManche')
    egal('A', fin.gagnant, 'gagnant = attaquants')
    egal('Tous les défenseurs ont été éliminés', fin.raison, 'raison')
    egal(1, etat.score.A, 'score A')
    egal(0, etat.score.B, 'score B')
    egal(false, fin.matchOver, 'matchOver')
    egal(true, aEffet(effets, 'recompenseKevlar'), 'kevlar au tueur')
    egal(true, aEffet(effets, 'vivant'), 'effet vivant')
    egal(true, aEffet(effets, 'spectateurDiffere'), 'spectateur différé')
    egal(1, etat.stats[1].kills, 'kills du tueur')
    egal(1, etat.stats[2].deaths, 'deaths de la victime')
end)

verifier('manche gagnée par élimination des attaquants', function()
    local ctx = nouveauContexte(105, 0, 'mort attaquant')
    local etat = matchDeDeux(17)
    local t = avancerJusquALive(etat, 0)
    local effets = appliquer(ctx, etat, AttackRules.mort, 1, 2, t + 100)
    local fin = trouverEffet(effets, 'finManche')
    vrai(fin ~= nil, 'effet finManche')
    egal('B', fin.gagnant, 'gagnant = défense')
    egal('Tous les attaquants ont été éliminés', fin.raison, 'raison')
end)

verifier('fin au chrono : la défense a tenu la zone', function()
    local ctx = nouveauContexte(106, 0, 'tic chrono')
    local etat = matchDeDeux(18)
    local t = avancerJusquALive(etat, 0)
    local effets = appliquer(ctx, etat, AttackRules.tic, t + CONFIG.RoundTimeMs + 2000, false)
    local fin = trouverEffet(effets, 'finManche')
    vrai(fin ~= nil, 'effet finManche')
    egal('B', fin.gagnant, 'gagnant = défense')
    egal('Temps écoulé : la défense a tenu la zone', fin.raison, 'raison')
end)

verifier('chrono en pause : gel puis reprise au premier tic sans attaquant', function()
    local ctx = nouveauContexte(107, 0, 'chrono pause')
    local etat = matchDeDeux(19)
    local t = avancerJusquALive(etat, 0)
    local echeanceInitiale = etat.echeance
    egal(CONFIG.RoundTimeMs, echeanceInitiale - t, 'échéance initiale')

    appliquer(ctx, etat, AttackRules.tic, t + 10000, true)
    egal(true, etat.chronoEnPause, 'chronoEnPause')
    egal(echeanceInitiale + 10000, etat.echeance, 'échéance repoussée')
    egal('live', etat.phase, 'toujours live après RoundTime')

    appliquer(ctx, etat, AttackRules.tic, t + 11000, true)
    egal(echeanceInitiale + 11000, etat.echeance, 'échéance repoussée encore')
    egal('live', etat.phase, 'toujours live')

    local effets = appliquer(ctx, etat, AttackRules.tic, t + 22000, false)
    egal(false, etat.chronoEnPause, 'chrono relancé')
    local fin = trouverEffet(effets, 'finManche')
    vrai(fin ~= nil, 'manche terminée après reprise')
    egal('Temps écoulé : la défense a tenu la zone', fin.raison, 'raison')
end)

verifier('match gagné à 2 manches puis retour en waiting', function()
    local ctx = nouveauContexte(108, 0, 'match complet')
    local etat = matchDeDeux(20)
    local t = avancerJusquALive(etat, 0)

    appliquer(ctx, etat, AttackRules.mort, 2, 1, t + 100)  -- A gagne la manche 1
    egal(1, etat.score.A, 'score après manche 1')
    egal(false, etat.matchOver, 'pas encore matchOver')

    -- La fin de manche pose une échéance de EndDelayMs(1000) à t+100 :
    -- on avance de 2000 ms pour être sûr d'entrer dans mancheSuivante.
    t = t + 2000
    local changement = appliquer(ctx, etat, AttackRules.tic, t, false)
    egal('select', etat.phase, 'manche 2 en select')
    egal('B', etat.attaquants, 'camps échangés')
    egal(false, etat.echangeDeCamp, 'drapeau consommé')
    local annonce = trouverEffet(changement, 'annonce', 'debutManche')
    vrai(annonce ~= nil, 'annonce debutManche')
    egal(true, annonce.changementDeCamp, 'changementDeCamp annoncé')
    egal(4500, annonce.dureeMs, 'durée changement de camp')

    t = avancerJusquALive(etat, t)
    local effets = appliquer(ctx, etat, AttackRules.mort, 2, 1, t + 100)  -- A gagne encore
    local fin = trouverEffet(effets, 'finManche')
    egal(true, fin.matchOver, 'matchOver')
    local match = trouverEffet(effets, 'finMatch')
    vrai(match ~= nil, 'effet finMatch')
    egal('A', match.gagnant, 'gagnant du match')
    egal(2, match.score.A, 'score du match')
    egal(2, etat.score.A, 'score final')
    egal(true, etat.matchOver, 'matchOver dans l’état')
    egal(2, #match.participants, 'participants')

    t = t + 2000
    local finEffets = appliquer(ctx, etat, AttackRules.tic, t, false)
    egal(2, compterEffets(finEffets, 'retourLobby'), 'retourLobby x2')
    egal('suivante', trouverEffet(finEffets, 'chargerCarte').mode, 'carte suivante')
    egal('waiting', etat.phase, 'retour waiting')
    egal(0, etat.score.A, 'score remis à zéro')
end)

verifier('changement de camp : annonce debutManche après manche non décisive', function()
    local ctx = nouveauContexte(109, 0, 'swap')
    local etat = matchDeDeux(21)
    local t = avancerJusquALive(etat, 0)
    appliquer(ctx, etat, AttackRules.mort, 2, 1, t + 100)
    egal('A', etat.attaquants, 'attaquants avant swap')
    local effets = appliquer(ctx, etat, AttackRules.tic, t + 2000, false)
    egal('B', etat.attaquants, 'attaquants après swap')
    local annonce = trouverEffet(effets, 'annonce', 'debutManche')
    egal(true, annonce.changementDeCamp, 'drapeau dans l’annonce')
    egal(4500, annonce.dureeMs, 'durée 4500')
    egal('attack', AttackRules.roleDe(etat, 2), 'B attaque maintenant')
end)

verifier('départ du dernier défenseur en live termine la manche', function()
    local ctx = nouveauContexte(110, 0, 'depart live')
    local etat = matchDeDeux(22)
    local t = avancerJusquALive(etat, 0)
    local effets = appliquer(ctx, etat, AttackRules.depart, 2, t + 100)
    local fin = trouverEffet(effets, 'finManche')
    vrai(fin ~= nil, 'finManche')
    egal('A', fin.gagnant, 'gagnant')
    egal('Tous les défenseurs ont été éliminés', fin.raison, 'raison')
    egal(true, aEffet(effets, 'objets'), 'objets clear')
    egal('clear', trouverEffet(effets, 'objets').action, 'action clear')
    egal(true, aEffet(effets, 'nettoyerJoueur'), 'nettoyerJoueur')
    egal(1, #etat.partis, 'joueur parti mémorisé')
end)

verifier('départ pendant select puis pendant place : la manche finit en live', function()
    local ctx = nouveauContexte(111, 0, 'depart select/place')
    local etat = matchDeDeux(23)
    appliquer(ctx, etat, AttackRules.tic, 0, false)
    egal('select', etat.phase, 'select')
    appliquer(ctx, etat, AttackRules.depart, 2, 1000)
    egal('select', etat.phase, 'toujours select')
    local effets = appliquer(ctx, etat, AttackRules.tic, 2000, false)
    egal('place', etat.phase, 'place')
    egal(true, aEffet(effets, 'fermerMenuArmes'), 'menu fermé')
    appliquer(ctx, etat, AttackRules.depart, 3, 2500)
    egal('place', etat.phase, 'toujours place après départ inexistant')

    -- Second scénario, cette fois avec un départ pendant 'place' : la victoire
    -- est constatée au tic qui passe en live, sans attendre la fin du chrono.
    local etat3 = matchDeDeux(25)
    appliquer(ctx, etat3, AttackRules.tic, 0, false)
    appliquer(ctx, etat3, AttackRules.tic, 1000, false)
    egal('place', etat3.phase, 'phase place')
    appliquer(ctx, etat3, AttackRules.depart, 2, 1500)
    local effetsLive = appliquer(ctx, etat3, AttackRules.tic, 2000, false)
    egal('ended', etat3.phase, 'ended dès le passage en live')
    vrai(aEffet(effetsLive, 'finManche'), 'finManche produit au passage en live')
end)

verifier('départ du dernier joueur remet l’état en waiting', function()
    local ctx = nouveauContexte(112, 0, 'depart dernier')
    local etat = etatDeTest(26)
    AttackRules.arrivee(etat, 1)
    appliquer(ctx, etat, AttackRules.debutTest, 1000)
    egal('select', etat.phase, 'select via debutTest')
    appliquer(ctx, etat, AttackRules.depart, 1, 1500)
    egal('waiting', etat.phase, 'waiting')
    egal(0, AttackRules.nombreJoueurs(etat), 'plus de joueurs')
    egal(0, etat.score.A, 'score remis')
    egal(0, etat.manche, 'manche remise')
end)

verifier('ré-arrivée d’un joueur parti : stats remises et match poursuivi', function()
    local ctx = nouveauContexte(121, 0, 'ré-arrivée')
    local etat = matchDeDeux(36)
    appliquer(ctx, etat, AttackRules.tic, 0, false)
    egal('select', etat.phase, 'select')

    etat.stats[2].kills, etat.stats[2].deaths = 4, 2
    appliquer(ctx, etat, AttackRules.depart, 2, 500)
    egal(1, #etat.partis, 'départ mémorisé')
    egal(4, etat.partis[1].kills, 'kills conservés dans partis')
    egal(nil, etat.equipes[2], 'joueur 2 retiré de son équipe')

    -- L'ancien gf:modeJoined réinsère le src sans effacer son entrée dans
    -- S.departed, et repart de stats {kills=0, deaths=0}.
    local effets = appliquer(ctx, etat, AttackRules.arrivee, 2)
    egal('select', etat.phase, 'phase inchangée')
    vrai(etat.equipes[2] ~= nil, 'joueur 2 a retrouvé une équipe')
    egal(0, etat.stats[2].kills, 'kills remis à zéro')
    egal(0, etat.stats[2].deaths, 'deaths remis à zéro')
    egal(1, #etat.partis, 'ancienne entrée de partis conservée')
    egal(true, aEffet(effets, 'menuArmes'), 'placement selon select')
    egal(1, compterEffets(effets, 'vivant'), 'un effet vivant')
    egal(true, trouverEffet(effets, 'vivant').vivant, 'vivant true')
end)

verifier('arrivée pendant live : spectateur et manche en cours', function()
    local ctx = nouveauContexte(113, 0, 'arrivee live')
    local etat = matchDeDeux(27)
    local t = avancerJusquALive(etat, 0)
    local effets = appliquer(ctx, etat, AttackRules.arrivee, 3)
    egal(false, etat.vivants[3], 'nouveau joueur non vivant')
    egal(true, aEffet(effets, 'spectateur'), 'spectateur')
    egal(true, aEffet(effets, 'annonce', 'mancheEnCours'), 'annonce mancheEnCours')
    egal(true, aEffet(effets, 'zone'), 'zone')
    egal('live', etat.phase, 'manche poursuivie')
    local fin = appliquer(ctx, etat, AttackRules.mort, 2, 1, t + 100)
    vrai(aEffet(fin, 'finManche'), 'manche toujours jouable')
end)

verifier('mort hors live : placement différé, pas de checkWin', function()
    local ctx = nouveauContexte(114, 0, 'mort hors live')
    local etat = matchDeDeux(28)
    appliquer(ctx, etat, AttackRules.tic, 0, false)
    local effets = appliquer(ctx, etat, AttackRules.mort, 2, 1, 500)
    egal(true, aEffet(effets, 'placementDiffere'), 'placement différé')
    egal(2000, trouverEffet(effets, 'placementDiffere').delaiMs, 'délai 2000')
    egal(false, aEffet(effets, 'finManche'), 'aucune fin de manche')
    egal('select', etat.phase, 'phase inchangée')
end)

verifier('kill non crédité : statistiquesKill avec tueur=false', function()
    local ctx = nouveauContexte(115, 0, 'kill non crédité')
    local etat = matchDeDeux(29)
    local t = avancerJusquALive(etat, 0)
    local effets = appliquer(ctx, etat, AttackRules.mort, 1, 1, t + 100)
    local stats = trouverEffet(effets, 'statistiquesKill')
    egal(false, stats.tueur, 'tueur false (même camp)')
    egal(false, aEffet(effets, 'recompenseKevlar'), 'pas de kevlar')
    egal(0, etat.stats[1].kills, 'aucun kill crédité')
end)

verifier('placer et changerEquipe : garde-fous et effets', function()
    local ctx = nouveauContexte(116, 0, 'placer/setteam')
    local etat = matchDeDeux(30)
    egal(0, #AttackRules.placer(etat, 99), 'placer joueur absent')
    egal(0, #AttackRules.changerEquipe(etat, 1, 'C', 0), 'equipe invalide')
    egal(0, #AttackRules.changerEquipe(etat, 99, 'A', 0), 'joueur absent')
    local effets = appliquer(ctx, etat, AttackRules.changerEquipe, 1, 'B', 0)
    egal('B', etat.equipes[1], 'équipe changée')
    egal(true, aEffet(effets, 'equipe'), 'effet equipe')
    egal(true, aEffet(effets, 'classement'), 'classement')
    appliquer(ctx, etat, AttackRules.placer, 1)
    egal('B', etat.equipes[1], 'placer ne change pas l’équipe')
end)

verifier('/endmatch : remise à zéro et effet matchArrete', function()
    local ctx = nouveauContexte(117, 0, 'finMatch admin')
    local etat = matchDeDeux(31)
    local t = avancerJusquALive(etat, 0)
    appliquer(ctx, etat, AttackRules.mort, 2, 1, t + 100)
    egal(1, etat.score.A, 'score avant arrêt')
    local effets = appliquer(ctx, etat, AttackRules.finMatch)
    egal('waiting', etat.phase, 'waiting')
    egal(0, etat.score.A, 'score A remis')
    egal(0, etat.score.B, 'score B remis')
    egal(0, etat.manche, 'manche remise')
    egal(false, etat.matchOver, 'matchOver remis')
    egal('A', etat.attaquants, 'attaquants remis')
    egal(0, etat.echeance, 'échéance remise')
    -- Une seule annonce côté serveur : l'effet matchArrete remplace l'annonce.
    egal(false, aEffet(effets, 'annonce', 'matchArrete'), 'pas d’annonce en doublon')
    egal(true, aEffet(effets, 'matchArrete'), 'effet matchArrete')
    egal(2, compterEffets(effets, 'vivant'), 'deux effets vivant')
    for _, effet in ipairs(effets) do
        if effet.type == 'vivant' then egal(false, effet.vivant, 'vivant false') end
    end
    egal(true, aEffet(effets, 'phase'), 'effet phase waiting')
    egal(true, aEffet(effets, 'effacerResultats'), 'résultats effacés')
    egal(0, etat.chronoMisAJourA, 'chronoMisAJourA remis')
    egal(0, etat.stats[1].kills, 'stats remises')
    egal(0, #etat.partis, 'partis vidés')
end)

verifier('allerEnAttente et reinitialiser : silencieux et sans score', function()
    local ctx = nouveauContexte(118, 0, 'goWaiting/reset')
    local etat = matchDeDeux(32)
    local t = avancerJusquALive(etat, 0)
    appliquer(ctx, etat, AttackRules.mort, 2, 1, t + 100)
    egal(1, etat.score.A, 'score avant goWaiting')
    local effets = appliquer(ctx, etat, AttackRules.allerEnAttente)
    egal('waiting', etat.phase, 'waiting')
    egal(0, etat.echeance, 'échéance')
    egal(1, etat.score.A, 'score conservé')
    egal(1, compterEffets(effets, 'phase'), 'un seul effet phase')
    egal(2, compterEffets(effets, 'apparition'), 'apparition pour chaque joueur')
    egal('attente', trouverEffet(effets, 'apparition').mode, 'mode attente')
    egal(2, compterEffets(effets, 'vivant'), 'deux effets vivant')
    for _, effet in ipairs(effets) do
        if effet.type == 'vivant' then egal(false, effet.vivant, 'vivant false') end
    end
    egal(false, etat.vivants[1], 'joueur non vivant')

    -- reinitialiser ne rend rien et efface tout, y compris le score.
    egal(nil, AttackRules.reinitialiser(etat), 'reinitialiser muet')
    egal(0, etat.score.A, 'score effacé')
    egal(0, etat.manche, 'manche effacée')
    egal(0, AttackRules.nombreJoueurs(etat), 'équipes vidées')
    egal(0, etat.chronoMisAJourA, 'chronoMisAJourA remis')
end)

verifier('manche de test en solo : annonce dédiée et fin au chrono', function()
    local ctx = nouveauContexte(119, 0, 'solo')
    local etat = etatDeTest(33)
    AttackRules.arrivee(etat, 1)
    -- On force le joueur seul dans le camp attaquant par défaut ('A').
    AttackRules.changerEquipe(etat, 1, 'A', 0)
    local effets = appliquer(ctx, etat, AttackRules.debutTest, 1000)
    egal('select', etat.phase, 'select')
    egal(true, etat.solo, 'solo')
    local solo = trouverEffet(effets, 'annonce', 'debutMancheTest')
    vrai(solo ~= nil, 'annonce debutMancheTest')
    egal(5000, solo.dureeMs, 'durée 5000')
    local t = avancerJusquALive(etat, 1000)
    local fin = appliquer(ctx, etat, AttackRules.tic, t + CONFIG.RoundTimeMs + 1000, false)
    local effet = trouverEffet(fin, 'finManche')
    vrai(effet ~= nil, 'finManche')
    egal('A', effet.gagnant, 'attaquant seul gagne')
    egal('Temps écoulé : manche de test terminée', effet.raison, 'raison test')
end)

verifier('durées des annonces et effets de transition', function()
    local ctx = nouveauContexte(120, 0, 'durées')
    local etat = matchDeDeux(34)
    local selectEffets = appliquer(ctx, etat, AttackRules.debutTest, 1000)
    local annonce = trouverEffet(selectEffets, 'annonce', 'debutManche')
    egal(4000, annonce.dureeMs, 'debutManche 4000')
    egal(1, annonce.manche, 'manche annoncée')
    local placeEffets = appliquer(ctx, etat, AttackRules.tic, 2000, false)
    local placement = trouverEffet(placeEffets, 'annonce', 'placement')
    egal(1, placement.secondes, 'secondes placement')
    egal(3000, placement.dureeMs, 'durée placement')
    local liveEffets = appliquer(ctx, etat, AttackRules.tic, 3000, false)
    egal(2500, trouverEffet(liveEffets, 'annonce', 'go').dureeMs, 'durée go')
    egal(true, aEffet(liveEffets, 'protection'), 'protection retirée')
    egal(false, trouverEffet(liveEffets, 'protection').protege, 'protege=false')
end)

-- ---------------------------------------------------------------------------
--  Escouades : les scénarios ci-dessous n'utilisent PAS appliquer() pour le
--  démarrage de manche. Avec des escouades, l'écart peut légitimement dépasser
--  1 : l'invariant 4 de verifierInvariants ne s'applique qu'aux suites sans
--  escouade, et les invariants propres à chaque scénario sont vérifiés ici.
-- ---------------------------------------------------------------------------

-- Mélange de Fisher-Yates, alimenté uniquement par le hasard déterministe.
local function melanger(liste, hasard)
    for i = #liste, 2, -1 do
        local j = hasard(i)
        liste[i], liste[j] = liste[j], liste[i]
    end
    return liste
end

verifier('definirGroupes : entrées invalides ignorées, clés distinctes, retour vide', function()
    local etat = etatDeTest(40)
    egal(0, etat.prochainGroupe, 'prochainGroupe initial')

    local retours = {
        AttackRules.definirGroupes(etat, nil),
        AttackRules.definirGroupes(etat, 42),
        AttackRules.definirGroupes(etat, 'escouade'),
        AttackRules.definirGroupes(etat, { false, 7, 'x' }),
        AttackRules.definirGroupes(etat, { { '1', -2, 0, 1.5 } }),
    }
    for i, effets in ipairs(retours) do
        egal(0, #effets, ('retour vide pour l’entrée invalide %d'):format(i))
    end
    egal(0, etat.prochainGroupe, 'aucune clé pour une liste sans src valide')
    egal(nil, next(etat.groupes), 'aucun groupe créé')

    local effets = AttackRules.definirGroupes(etat, { { 1, 2 }, { 3, 4 } })
    egal(0, #effets, 'retour vide')
    egal(2, etat.prochainGroupe, 'une clé par escouade valide')
    vrai(etat.groupes[1] ~= nil, 'clé pour src=1')
    egal(etat.groupes[1], etat.groupes[2], 'src 1 et 2 dans la même escouade')
    egal(etat.groupes[3], etat.groupes[4], 'src 3 et 4 dans la même escouade')
    vrai(etat.groupes[1] ~= etat.groupes[3], 'clés distinctes pour les deux escouades')

    -- Une liste mixte ne consomme qu'une seule clé, pour les src valides.
    AttackRules.definirGroupes(etat, { { 5, 'x', 6 }, { -1, 2.5 } })
    egal(3, etat.prochainGroupe, 'aucune clé pour la liste sans src valide')
    egal(etat.groupes[5], etat.groupes[6], 'src valides regroupés')
    egal(nil, etat.groupes['x'], 'src non numérique ignoré')
end)

verifier('arrivée : priorité au camp du coéquipier, même si ce camp est plus rempli', function()
    local ctx = nouveauContexte(130, 0, 'priorite escouade')
    local etat = etatDeTest(41)
    egal(0, #AttackRules.definirGroupes(etat, { { 1, 4 } }), 'escouade définie avant arrivée')
    for src = 1, 3 do appliquer(ctx, etat, AttackRules.arrivee, src) end
    for src = 1, 3 do appliquer(ctx, etat, AttackRules.changerEquipe, src, 'B', 0) end
    egal(0, AttackRules.compter(etat, 'A'), 'camp A vide')
    egal(3, AttackRules.compter(etat, 'B'), 'camp B déjà rempli')

    local effets = appliquer(ctx, etat, AttackRules.arrivee, 4)
    egal('B', etat.equipes[4], 'le coéquipier rejoint B')
    egal(4, AttackRules.compter(etat, 'B'), 'B reste le camp le plus rempli')
    local equipe = trouverEffet(effets, 'equipe')
    vrai(equipe ~= nil, 'effet equipe présent')
    egal(4, equipe.src, 'src de l’effet equipe')
    egal('B', equipe.equipe, 'équipe de l’effet equipe')
end)

verifier('arrivée sans escouade : camp le moins rempli, aucun groupe attribué', function()
    local ctx = nouveauContexte(131, 0, 'arrivee sans escouade')
    local etat = etatDeTest(42)
    for src = 1, 3 do appliquer(ctx, etat, AttackRules.arrivee, src) end
    for src = 1, 3 do appliquer(ctx, etat, AttackRules.changerEquipe, src, 'B', 0) end
    egal(0, AttackRules.compter(etat, 'A'), 'camp A vide')
    egal(3, AttackRules.compter(etat, 'B'), 'camp B rempli')

    local effets = appliquer(ctx, etat, AttackRules.arrivee, 4)
    egal('A', etat.equipes[4], 'joueur sans escouade rejoint le camp le moins rempli')
    egal(nil, etat.groupes[4], 'aucun groupe attribué')
    egal('A', trouverEffet(effets, 'equipe').equipe, 'effet equipe du camp choisi')
end)

verifier('escouades : 200 graines, groupes entiers et écart résiduel borné', function()
    local graineBase = 20261201
    local escouadesVerifiees = 0
    for suite = 1, 200 do
        local graine = graineBase + suite
        local hasardRegles, hasardEvenements = nouveauJeu(graine)
        local etat = AttackRules.nouveau(CONFIG, hasardRegles)
        local joueurs = 10 + hasardEvenements(21)  -- 10 à 30 joueurs
        local srcs = {}
        for i = 1, joueurs do srcs[i] = i end

        -- Escouades de 1 à 4, définies AVANT les arrivées.
        local escouades = {}
        local i = 1
        while i <= joueurs do
            local taille = math.min(hasardEvenements(4), joueurs - i + 1)
            local escouade = {}
            for j = 0, taille - 1 do escouade[#escouade + 1] = srcs[i + j] end
            escouades[#escouades + 1] = escouade
            i = i + taille
        end
        egal(0, #AttackRules.definirGroupes(etat, escouades),
            ('graine=%d definirGroupes'):format(graine))

        -- Arrivées dans un ordre mélangé.
        for _, src in ipairs(melanger(srcs, hasardEvenements)) do
            AttackRules.arrivee(etat, src)
        end
        egal(joueurs, AttackRules.nombreJoueurs(etat), ('graine=%d nombreJoueurs'):format(graine))

        -- Démarrage direct de la manche 1 : pas de appliquer() ici.
        local effets = AttackRules.tic(etat, 1000, false)
        vrai(#effets > 0, ('graine=%d effets de tic vides'):format(graine))
        egal('select', etat.phase, ('graine=%d phase'):format(graine))
        egal(1, etat.manche, ('graine=%d manche'):format(graine))

        local a = AttackRules.compter(etat, 'A')
        local b = AttackRules.compter(etat, 'B')
        local ecart = math.abs(a - b)
        local campPlein = a > b and 'A' or 'B'

        for indice, escouade in ipairs(escouades) do
            local camp = etat.equipes[escouade[1]]
            for _, src in ipairs(escouade) do
                egal(camp, etat.equipes[src],
                    ('graine=%d escouade=%d src=%d camp=%s attendu=%s'):format(
                        graine, indice, src, tostring(etat.equipes[src]), tostring(camp)))
            end
            -- Aucun groupe du camp le plus peuplé ne peut avoir une taille s
            -- strictement comprise entre 0 et l'écart résiduel d.
            local s = #escouade
            if camp == campPlein then
                vrai(not (s > 0 and s < ecart),
                    ('graine=%d camp=%d/%d d=%d escouade=%d taille=%d'):format(
                        graine, a, b, ecart, indice, s))
            end
            escouadesVerifiees = escouadesVerifiees + 1
        end
    end
    vrai(escouadesVerifiees >= 200, ('escouades vérifiées=%d'):format(escouadesVerifiees))
end)

verifier('sans escouade : 200 graines, écart final <= 1 après la manche 1', function()
    local graineBase = 20262201
    for suite = 1, 200 do
        local graine = graineBase + suite
        local hasardRegles, hasardEvenements = nouveauJeu(graine)
        local etat = AttackRules.nouveau(CONFIG, hasardRegles)
        local joueurs = 10 + hasardEvenements(21)
        local srcs = {}
        for i = 1, joueurs do srcs[i] = i end

        for _, src in ipairs(melanger(srcs, hasardEvenements)) do
            AttackRules.arrivee(etat, src)
        end
        egal(joueurs, AttackRules.nombreJoueurs(etat), ('graine=%d nombreJoueurs'):format(graine))

        local effets = AttackRules.tic(etat, 1000, false)
        vrai(#effets > 0, ('graine=%d effets de tic vides'):format(graine))
        egal('select', etat.phase, ('graine=%d phase'):format(graine))
        egal(1, etat.manche, ('graine=%d manche'):format(graine))
        local ecart = math.abs(AttackRules.compter(etat, 'A') - AttackRules.compter(etat, 'B'))
        vrai(ecart <= 1, ('graine=%d écart=%d'):format(graine, ecart))
        egal(nil, next(etat.groupes), ('graine=%d aucun groupe attribué'):format(graine))
    end
end)

verifier('départ retire le groupe du joueur ; reinitialiser vide les groupes', function()
    local etat = etatDeTest(43)
    egal(0, #AttackRules.definirGroupes(etat, { { 1, 2 } }), 'escouade définie')
    AttackRules.arrivee(etat, 1)
    AttackRules.arrivee(etat, 2)
    local cle = etat.groupes[1]
    vrai(cle ~= nil, 'clé de groupe attribuée')
    egal(cle, etat.groupes[2], 'même clé pour le coéquipier')

    AttackRules.depart(etat, 1, 0)
    egal(nil, etat.groupes[1], 'groupe du joueur parti retiré')
    egal(cle, etat.groupes[2], 'le coéquipier garde sa clé')

    AttackRules.reinitialiser(etat)
    egal(nil, next(etat.groupes), 'groupes vidés par reinitialiser')
    vrai(etat.prochainGroupe >= 1, 'prochainGroupe conservé')
end)

verifier('notifier equilibrage : escouade=true quand une escouade entière est déplacée', function()
    local etat = etatDeTest(44)
    AttackRules.definirGroupes(etat, { { 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 } })
    for src = 1, 9 do AttackRules.arrivee(etat, src) end
    for _, src in ipairs({ 1, 2, 3, 4, 5, 6 }) do AttackRules.changerEquipe(etat, src, 'A', 0) end
    for _, src in ipairs({ 7, 8, 9 }) do AttackRules.changerEquipe(etat, src, 'B', 0) end
    egal(6, AttackRules.compter(etat, 'A'), 'A avant équilibrage')
    egal(3, AttackRules.compter(etat, 'B'), 'B avant équilibrage (d=3)')

    local effets = AttackRules.tic(etat, 1000, false)
    local deplaces = {}
    for _, effet in ipairs(effets) do
        if effet.type == 'notifier' and effet.modele == 'equilibrage' then
            deplaces[#deplaces + 1] = effet
        end
    end
    egal(2, #deplaces, 'deux joueurs déplacés avec leur escouade')
    for _, effet in ipairs(deplaces) do
        egal(true, effet.escouade, 'escouade=true')
    end
    for _, paire in ipairs({ { 1, 2 }, { 3, 4 }, { 5, 6 } }) do
        egal(etat.equipes[paire[1]], etat.equipes[paire[2]], 'escouade restée entière')
    end
end)

verifier('notifier equilibrage : escouade=false quand un joueur seul est déplacé', function()
    local etat = etatDeTest(45)
    for src = 1, 4 do AttackRules.arrivee(etat, src) end
    for _, src in ipairs({ 1, 2, 3 }) do AttackRules.changerEquipe(etat, src, 'A', 0) end
    AttackRules.changerEquipe(etat, 4, 'B', 0)
    egal(3, AttackRules.compter(etat, 'A'), 'A avant équilibrage (d=2)')
    egal(1, AttackRules.compter(etat, 'B'), 'B avant équilibrage')

    local effets = AttackRules.tic(etat, 1000, false)
    local deplaces = {}
    for _, effet in ipairs(effets) do
        if effet.type == 'notifier' and effet.modele == 'equilibrage' then
            deplaces[#deplaces + 1] = effet
        end
    end
    egal(1, #deplaces, 'un seul joueur déplacé')
    egal(false, deplaces[1].escouade, 'escouade=false')
end)

-- ===========================================================================
--  Campagne aléatoire : 500 suites, 1 à 400 événements, graines fixes.
-- ===========================================================================

verifier('fuzz : 500 suites d’événements aléatoires + drainage', function()
    local graineBase = 20261126
    local totalEvenements = 0
    local totalDrainage = 0

    for suite = 1, 500 do
        local graine = graineBase + suite
        local hasardRegles, hasardEvenements = nouveauJeu(graine)
        local etat = AttackRules.nouveau(CONFIG, hasardRegles)
        local ctx = nouveauContexte(graine, suite, 'initialisation')
        local maintenantMs = 0
        local nombre = 1 + hasardEvenements(400)

        for _ = 1, nombre do
            local tirage = hasardEvenements(100)
            local evenement

            if tirage <= 30 then
                local src = srcArrivee(etat, hasardEvenements)
                evenement = ('arrivee(src=%s)'):format(tostring(src))
                ctx.evenement = evenement
                if src then
                    appliquer(ctx, etat, AttackRules.arrivee, src)
                else
                    verifierInvariants(ctx, etat, {}, { score = copieScore(etat.score), phase = etat.phase })
                end
            elseif tirage <= 50 then
                local presents = {}
                for src in pairs(etat.equipes) do presents[#presents + 1] = src end
                local src = #presents > 0 and presents[hasardEvenements(#presents)] or hasardEvenements(40)
                maintenantMs = maintenantMs + hasardEvenements(5000)
                evenement = ('depart(src=%d, t=%d)'):format(src, maintenantMs)
                ctx.evenement = evenement
                appliquer(ctx, etat, AttackRules.depart, src, maintenantMs)
            elseif tirage <= 70 then
                local presents = {}
                for src in pairs(etat.equipes) do presents[#presents + 1] = src end
                local victime = #presents > 0 and presents[hasardEvenements(#presents)] or hasardEvenements(40)
                local tueur = hasardEvenements(40)
                maintenantMs = maintenantMs + hasardEvenements(5000)
                evenement = ('mort(%d par %d, t=%d)'):format(victime, tueur, maintenantMs)
                ctx.evenement = evenement
                appliquer(ctx, etat, AttackRules.mort, victime, tueur, maintenantMs)
            elseif tirage <= 96 then
                maintenantMs = maintenantMs + hasardEvenements(5000)
                local dansZone = hasardEvenements(2) == 1
                evenement = ('tic(t=%d, zone=%s)'):format(maintenantMs, tostring(dansZone))
                ctx.evenement = evenement
                appliquer(ctx, etat, AttackRules.tic, maintenantMs, dansZone)
            elseif tirage <= 98 then
                evenement = ('debutTest(t=%d)'):format(maintenantMs)
                ctx.evenement = evenement
                appliquer(ctx, etat, AttackRules.debutTest, maintenantMs)
            else
                evenement = ('finMatch(t=%d)'):format(maintenantMs)
                ctx.evenement = evenement
                appliquer(ctx, etat, AttackRules.finMatch)
            end

            totalEvenements = totalEvenements + 1
        end

        -- Drainage : plus que des tics(false) de +1000 ms, jusqu'à 'waiting'.
        ctx.evenement = 'drainage'
        local phaseDepart = etat.phase
        local tics, sortieLive = drainer(ctx, etat, maintenantMs)
        totalDrainage = totalDrainage + tics
        egal('waiting', etat.phase, ('suite %d : drainage bloqué en %s'):format(suite, etat.phase))
        vrai(tics < 10000, ('suite %d : trop de tics de drainage'):format(suite))
        if phaseDepart == 'live' then
            vrai(sortieLive ~= nil and sortieLive <= CONFIG.RoundTimeMs + 3000,
                ('suite %d : sortie de live en %s ms'):format(suite, tostring(sortieLive)))
        end
    end

    print(('  fuzz : %d suites, %d événements, %d tics de drainage'):format(
        500, totalEvenements, totalDrainage))
end)

-- ===========================================================================
--  Sabotage : un état réel est corrompu ; le vérificateur DOIT échouer.
-- ===========================================================================

verifier('sabotage : +1 score sans manche gagnée détecté', function()
    local hasardRegles, _ = nouveauJeu(20261126)
    local etat = AttackRules.nouveau(CONFIG, hasardRegles)
    AttackRules.arrivee(etat, 1)
    AttackRules.arrivee(etat, 2)
    AttackRules.changerEquipe(etat, 1, 'A', 0)
    AttackRules.changerEquipe(etat, 2, 'B', 0)
    local t = avancerJusquALive(etat, 0)
    local effets = AttackRules.mort(etat, 2, 1, t + 100)  -- scénario réel : A marque
    local avant = { score = { A = 0, B = 0 }, phase = 'live' }
    verifierInvariants(nouveauContexte(1, 0, 'réel'), etat, effets, avant)

    local pirate = copieProfonde(etat)
    pirate.score.A = pirate.score.A + 1  -- point ajouté sans finManche
    local ctxPirate = nouveauContexte(1, 0, 'sabotage score')
    local ok, erreur = pcall(verifierInvariants, ctxPirate, pirate, effets, avant)
    egal(false, ok, 'le score faussé doit être détecté')
    vrai(tostring(erreur):find('invariant=1'), 'invariant 1 attendu : ' .. tostring(erreur))
end)

verifier('sabotage : double incrément lors d’un finManche détecté', function()
    local etat = etatDeTest(999)
    AttackRules.arrivee(etat, 1)
    AttackRules.arrivee(etat, 2)
    AttackRules.changerEquipe(etat, 1, 'A', 0)
    AttackRules.changerEquipe(etat, 2, 'B', 0)
    avancerJusquALive(etat, 0)
    etat.score.A = 2  -- deux points au lieu d'un seul
    local fauxEffet = { { type = 'finManche', gagnant = 'A', raison = 'x', score = copieScore(etat.score),
                          matchOver = true, dureeMs = 0 } }
    local ctxPirate = nouveauContexte(2, 0, 'sabotage double')
    local ok, erreur = pcall(verifierInvariants, ctxPirate, etat, fauxEffet,
        { score = { A = 0, B = 0 }, phase = 'live' })
    egal(false, ok, 'le double incrément doit être détecté')
    vrai(tostring(erreur):find('invariant=1'), 'invariant 1 attendu : ' .. tostring(erreur))
end)

-- ===========================================================================
--  Départ pendant select/place : la victoire est constatée au passage en live.
-- ===========================================================================

verifier('départ en select qui vide une équipe : victoire au passage en live', function()
    local ctx = nouveauContexte(130, 0, 'depart select vide équipe')
    local etat = etatDeTest(37)
    appliquer(ctx, etat, AttackRules.arrivee, 1)
    appliquer(ctx, etat, AttackRules.arrivee, 2)

    -- Équipes tirées au hasard : on lit les camps sans supposer A ou B.
    local campParti = etat.equipes[2]
    local gagnant = etat.equipes[1]
    vrai(campParti ~= gagnant, 'camps distincts')
    appliquer(ctx, etat, AttackRules.tic, 0, false)
    egal('select', etat.phase, 'select')

    appliquer(ctx, etat, AttackRules.depart, 2, 1500)
    egal('select', etat.phase, 'toujours select après le départ')
    appliquer(ctx, etat, AttackRules.tic, 2000, false)
    egal('place', etat.phase, 'place après select')

    -- Le tic 3000 passe en live : la victoire doit être constatée immédiatement.
    local effets = appliquer(ctx, etat, AttackRules.tic, 3000, false)
    egal('ended', etat.phase, 'ended au passage en live')
    egal(1, etat.score[gagnant], ('score du gagnant %s'):format(gagnant))
    local fin = trouverEffet(effets, 'finManche')
    vrai(fin ~= nil, 'finManche au passage en live')
    egal(gagnant, fin.gagnant, 'gagnant')
    if campParti == etat.attaquants then
        egal('Tous les attaquants ont été éliminés', fin.raison, 'raison attaquants')
    else
        egal('Tous les défenseurs ont été éliminés', fin.raison, 'raison défenseurs')
    end
end)

verifier('départ en place qui vide une équipe : victoire au passage en live', function()
    local ctx = nouveauContexte(131, 0, 'depart place vide équipe')
    local etat = etatDeTest(38)
    appliquer(ctx, etat, AttackRules.arrivee, 1)
    appliquer(ctx, etat, AttackRules.arrivee, 2)

    -- Équipes tirées au hasard : on lit les camps sans supposer A ou B.
    local campParti = etat.equipes[2]
    local gagnant = etat.equipes[1]
    vrai(campParti ~= gagnant, 'camps distincts')
    appliquer(ctx, etat, AttackRules.tic, 0, false)
    appliquer(ctx, etat, AttackRules.tic, 1000, false)
    egal('place', etat.phase, 'place')

    appliquer(ctx, etat, AttackRules.depart, 2, 1500)
    egal('place', etat.phase, 'toujours place après le départ')

    -- Le tic 3000 passe en live : la victoire doit être constatée immédiatement.
    local effets = appliquer(ctx, etat, AttackRules.tic, 3000, false)
    egal('ended', etat.phase, 'ended au passage en live')
    egal(1, etat.score[gagnant], ('score du gagnant %s'):format(gagnant))
    local fin = trouverEffet(effets, 'finManche')
    vrai(fin ~= nil, 'finManche au passage en live')
    egal(gagnant, fin.gagnant, 'gagnant')
    if campParti == etat.attaquants then
        egal('Tous les attaquants ont été éliminés', fin.raison, 'raison attaquants')
    else
        egal('Tous les défenseurs ont été éliminés', fin.raison, 'raison défenseurs')
    end
end)

verifier('manche solo : passage en live sans finManche', function()
    local ctx = nouveauContexte(132, 0, 'solo live sans fin')
    local etat = etatDeTest(39)
    appliquer(ctx, etat, AttackRules.arrivee, 1)
    appliquer(ctx, etat, AttackRules.debutTest, 1000)
    egal(true, etat.solo, 'solo')
    egal('select', etat.phase, 'select')

    -- avancerJusquALive n'enregistre pas les effets : on avance pas à pas avec
    -- appliquer() pour couvrir le tic qui passe en live, y compris ses effets.
    local t = 1000
    local effets
    for _ = 1, 12 do
        effets = appliquer(ctx, etat, AttackRules.tic, t, false)
        if etat.phase == 'live' then break end
        t = t + 1000
    end
    egal('live', etat.phase, 'live conservé en solo')
    egal(false, aEffet(effets, 'finManche'), 'aucun finManche au passage en live')
    egal(0, etat.score.A + etat.score.B, 'score inchangé au passage en live')
end)

-- ===========================================================================
--  Couverture de la liste fermée des effets.
-- ===========================================================================

verifier('effets : chaque type de la liste fermée est produit, aucun hors liste', function()
    for typeEffet in pairs(TYPES_ATTENDUS) do
        vrai(typesVus[typeEffet], ('type jamais produit : %s'):format(typeEffet))
    end
    for typeEffet in pairs(typesInattendus) do
        error(('type hors liste produit : %s'):format(typeEffet))
    end
end)

print(('\n%d test(s) réussi(s), %d échec(s)'):format(reussis, echecs))
if echecs > 0 then os.exit(1) end
