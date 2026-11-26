-- =============================================================================
--  gf_attack - RÈGLES DU MATCH (module serveur pur)
--
--  Ce module ne contient AUCUNE native FiveM, aucune horloge interne et aucun
--  hasard maison : toutes les dépendances sont injectées.
--    - la configuration est fournie à AttackRules.nouveau(config, aleatoire) ;
--    - le temps est fourni à chaque appel sous forme de millisecondes ;
--    - le hasard vient de aleatoire(n), qui rend un entier entre 1 et n.
--
--  Les durées de `config` sont DÉJÀ en millisecondes :
--    SelectTimeMs, PlacementTimeMs, RoundTimeMs, EndDelayMs, MatchEndDelayMs.
--
--  Chaque fonction publique renvoie une liste ORDONNÉE d'effets. Le serveur
--  (server.lua) est le seul à interpréter ces effets (appels natives, timers,
--  messages réseau). Les états sont mutables et gérés par l'appelant.
-- =============================================================================

AttackRules = {}

-- ---------------------------------------------------------------------------
--  Utilitaires internes (tous locaux : `AttackRules` est la seule globale).
-- ---------------------------------------------------------------------------

local function autreCamp(camp)
    return camp == 'A' and 'B' or 'A'
end

local function ajouter(liste, effet)
    liste[#liste + 1] = effet
end

-- L'ordre de `pairs` n'étant pas garanti, on trie les sources par numéro
-- croissant : les effets sont ainsi reproductibles pour une même graine.
local function listeJoueurs(etat)
    local srcs = {}
    for src in pairs(etat.equipes) do srcs[#srcs + 1] = src end
    table.sort(srcs)
    return srcs
end

local function copieScore(score)
    return { A = score.A, B = score.B }
end

-- Un src valide est un numéro entier strictement positif.
local function estSrcValide(src)
    return type(src) == 'number' and math.floor(src) == src and src > 0
end

-- Clé de groupe effective : l'affectation explicite s'il y en a une, sinon
-- -src, ce qui fait de chaque joueur sans escouade un groupe d'une personne.
local function cleGroupe(etat, src)
    return etat.groupes[src] or -src
end

-- ---------------------------------------------------------------------------
--  Placement d'un joueur selon la phase courante (arrivée, /setteam, soin).
--  L'ancien server.lua appelait setAlive(src, ...) dans chacun de ces cas :
--  on rend donc systématiquement l'effet `vivant` avant l'apparition, pour que
--  le serveur mette à jour le state bag gf_alive du client.
-- ---------------------------------------------------------------------------

local function placementSelonPhase(etat, liste, src)
    local phase = etat.phase
    if phase == 'select' then
        etat.vivants[src] = true
        ajouter(liste, { type = 'vivant', src = src, vivant = true })
        ajouter(liste, { type = 'apparition', src = src, mode = 'select' })
        ajouter(liste, { type = 'menuArmes', src = src })
        ajouter(liste, { type = 'objets', src = src, action = 'reset' })
        ajouter(liste, { type = 'zone', src = src })
    elseif phase == 'place' then
        etat.vivants[src] = true
        ajouter(liste, { type = 'vivant', src = src, vivant = true })
        ajouter(liste, { type = 'apparition', src = src, mode = 'place' })
        ajouter(liste, { type = 'objets', src = src, action = 'reset' })
        ajouter(liste, { type = 'zone', src = src })
    elseif phase == 'live' then
        etat.vivants[src] = false
        ajouter(liste, { type = 'vivant', src = src, vivant = false })
        ajouter(liste, { type = 'spectateur', src = src })
        ajouter(liste, { type = 'annonce', modele = 'mancheEnCours', src = src, dureeMs = 4000 })
        ajouter(liste, { type = 'zone', src = src })
    else
        etat.vivants[src] = false
        ajouter(liste, { type = 'vivant', src = src, vivant = false })
        ajouter(liste, { type = 'apparition', src = src, mode = 'attente' })
        ajouter(liste, { type = 'zone', src = src })
    end
end

-- ---------------------------------------------------------------------------
--  Équilibrage des camps : au plus 64 itérations, toujours depuis le camp le
--  plus peuplé. On ne déplace que des escouades ENTIÈRES (une escouade = la
--  clé de groupe effective, ou un joueur seul s'il n'a pas d'escouade) : jamais
--  une partie d'une escouade, quitte à accepter un écart supérieur à 1.
--  Les groupes candidats sont triés par plus petit src (déterministe) ; le
--  hasard ne intervient qu'au tirage final avec `aleatoire`.
-- ---------------------------------------------------------------------------

local function autobalance(etat, liste)
    for _ = 1, 64 do
        local a = AttackRules.compter(etat, 'A')
        local b = AttackRules.compter(etat, 'B')
        local d = math.abs(a - b)
        if d <= 1 then return end
        local from = a > b and 'A' or 'B'
        local vers = autreCamp(from)

        -- Groupes du camp surpeuplé : clé effective -> liste de src triée.
        local groupes = {}
        for src, camp in pairs(etat.equipes) do
            if camp == from then
                local cle = cleGroupe(etat, src)
                if not groupes[cle] then groupes[cle] = {} end
                local membres = groupes[cle]
                membres[#membres + 1] = src
            end
        end

        local ordonnes = {}
        for _, membres in pairs(groupes) do
            table.sort(membres)
            ordonnes[#ordonnes + 1] = membres
        end
        table.sort(ordonnes, function(x, y) return x[1] < y[1] end)

        -- Seuls les groupes de taille s avec 0 < s < d réduisent l'écart.
        local candidats = {}
        for _, membres in ipairs(ordonnes) do
            local s = #membres
            if s > 0 and s < d then candidats[#candidats + 1] = membres end
        end
        if #candidats == 0 then return end

        -- On garde les déplacements qui approchent le plus de l'égalité.
        local meilleur = nil
        for _, membres in ipairs(candidats) do
            local ecart = math.abs(d - 2 * #membres)
            if not meilleur or ecart < meilleur then meilleur = ecart end
        end
        local retenus = {}
        for _, membres in ipairs(candidats) do
            if math.abs(d - 2 * #membres) == meilleur then
                retenus[#retenus + 1] = membres
            end
        end

        local groupe = retenus[etat.aleatoire(#retenus)]
        for _, src in ipairs(groupe) do
            etat.equipes[src] = vers
            ajouter(liste, { type = 'equipe', src = src, equipe = vers })
            ajouter(liste, {
                type = 'notifier', modele = 'equilibrage', src = src,
                equipe = vers, escouade = #groupe > 1,
            })
        end
    end
end

local function peutDemarrer(etat)
    local a = AttackRules.compter(etat, 'A')
    local b = AttackRules.compter(etat, 'B')
    return a >= 1 and b >= 1 and a + b >= etat.config.PlayersToStart
end

-- ---------------------------------------------------------------------------
--  Transitions de phase internes.
-- ---------------------------------------------------------------------------

local function demarrerSelection(etat, liste, maintenantMs)
    -- Début de match : on recharge la carte puis on équilibre avant la manche 1.
    if etat.manche == 0 then
        ajouter(liste, { type = 'chargerCarte', mode = 'recharger' })
        autobalance(etat, liste)
    end

    etat.manche = etat.manche + 1
    etat.phase = 'select'
    etat.echeance = maintenantMs + etat.config.SelectTimeMs
    etat.solo = AttackRules.compter(etat, 'A') == 0 or AttackRules.compter(etat, 'B') == 0

    local dureeAnnonce = etat.echangeDeCamp and 4500 or 4000
    for _, src in ipairs(listeJoueurs(etat)) do
        etat.vivants[src] = true
        ajouter(liste, { type = 'vivant', src = src, vivant = true })
        ajouter(liste, { type = 'apparition', src = src, mode = 'select' })
        ajouter(liste, { type = 'menuArmes', src = src })
        ajouter(liste, { type = 'objets', src = src, action = 'reset' })
        ajouter(liste, {
            type = 'annonce', modele = 'debutManche', src = src,
            manche = etat.manche, role = AttackRules.roleDe(etat, src),
            changementDeCamp = etat.echangeDeCamp, dureeMs = dureeAnnonce,
        })
    end
    etat.echangeDeCamp = false

    if etat.solo then
        ajouter(liste, { type = 'annonce', modele = 'debutMancheTest', manche = etat.manche, dureeMs = 5000 })
    end

    ajouter(liste, { type = 'phase', phase = 'select' })
    ajouter(liste, { type = 'classement' })
end

local function demarrerPlacement(etat, liste, maintenantMs)
    etat.phase = 'place'
    etat.echeance = maintenantMs + etat.config.PlacementTimeMs

    for _, src in ipairs(listeJoueurs(etat)) do
        ajouter(liste, { type = 'fermerMenuArmes', src = src })
        if etat.vivants[src] then
            ajouter(liste, { type = 'armes', src = src })
            ajouter(liste, { type = 'degeler', src = src })
            ajouter(liste, {
                type = 'annonce', modele = 'placement', src = src,
                role = AttackRules.roleDe(etat, src),
                secondes = math.floor(etat.config.PlacementTimeMs / 1000), dureeMs = 3000,
            })
        end
    end
    ajouter(liste, { type = 'phase', phase = 'place' })
end

local function demarrerLive(etat, liste, maintenantMs)
    etat.phase = 'live'
    etat.echeance = maintenantMs + etat.config.RoundTimeMs
    etat.chronoMisAJourA = maintenantMs
    etat.chronoEnPause = false

    for _, src in ipairs(listeJoueurs(etat)) do
        if etat.vivants[src] then
            ajouter(liste, { type = 'protection', src = src, protege = false })
        end
    end
    ajouter(liste, { type = 'annonce', modele = 'go', dureeMs = 2500 })
    ajouter(liste, { type = 'phase', phase = 'live' })
end

local function terminerManche(etat, liste, gagnant, raison, maintenantMs)
    if etat.phase ~= 'live' then return end

    etat.phase = 'ended'
    etat.score[gagnant] = etat.score[gagnant] + 1
    etat.echeance = maintenantMs + etat.config.EndDelayMs

    for _, src in ipairs(listeJoueurs(etat)) do
        ajouter(liste, { type = 'protection', src = src, protege = true })
    end

    local matchOver = etat.score[gagnant] >= etat.config.WinRounds
    if matchOver then
        etat.matchOver = true
        etat.echeance = maintenantMs + etat.config.MatchEndDelayMs
    end

    local score = copieScore(etat.score)
    ajouter(liste, {
        type = 'finManche', gagnant = gagnant, raison = raison,
        score = score, matchOver = matchOver, dureeMs = etat.config.EndDelayMs - 1000,
    })

    if matchOver then
        local participants = {}
        for _, src in ipairs(listeJoueurs(etat)) do
            local st = etat.stats[src] or { kills = 0, deaths = 0 }
            participants[#participants + 1] = {
                src = src, equipe = etat.equipes[src], kills = st.kills, deaths = st.deaths,
            }
        end
        local partis = {}
        for i, entree in ipairs(etat.partis) do
            partis[i] = {
                src = entree.src, equipe = entree.equipe,
                kills = entree.kills, deaths = entree.deaths,
            }
        end
        ajouter(liste, {
            type = 'finMatch', gagnant = gagnant, score = score,
            participants = participants, partis = partis,
        })
    end

    ajouter(liste, { type = 'phase', phase = 'ended' })
    ajouter(liste, { type = 'classement' })
end

-- Attaquants d'abord, comme dans l'ancien checkWin.
local function verifierVictoire(etat, liste, maintenantMs)
    if etat.phase ~= 'live' or etat.solo then return end

    local att = etat.attaquants
    local def = autreCamp(att)
    local a = AttackRules.compterVivants(etat, att)
    local d = AttackRules.compterVivants(etat, def)

    if a == 0 then
        terminerManche(etat, liste, def, 'Tous les attaquants ont été éliminés', maintenantMs)
    elseif d == 0 then
        terminerManche(etat, liste, att, 'Tous les défenseurs ont été éliminés', maintenantMs)
    end
end

local function mancheSuivante(etat, liste, maintenantMs)
    if etat.matchOver then
        for _, src in ipairs(listeJoueurs(etat)) do
            ajouter(liste, { type = 'retourLobby', src = src })
        end
        AttackRules.reinitialiser(etat)
        ajouter(liste, { type = 'chargerCarte', mode = 'suivante' })
        return
    end

    if etat.config.SwapSidesEveryRound then
        etat.attaquants = autreCamp(etat.attaquants)
        etat.echangeDeCamp = true
    end
    demarrerSelection(etat, liste, maintenantMs)
end

-- ---------------------------------------------------------------------------
--  API publique : requêtes.
-- ---------------------------------------------------------------------------

function AttackRules.compter(etat, equipe)
    local n = 0
    for _, camp in pairs(etat.equipes) do
        if camp == equipe then n = n + 1 end
    end
    return n
end

function AttackRules.compterVivants(etat, equipe)
    local n = 0
    for src, camp in pairs(etat.equipes) do
        if camp == equipe and etat.vivants[src] then n = n + 1 end
    end
    return n
end

function AttackRules.nombreJoueurs(etat)
    return AttackRules.compter(etat, 'A') + AttackRules.compter(etat, 'B')
end

function AttackRules.estOuvert(etat)
    return etat.phase == 'waiting'
end

function AttackRules.peutRejoindre(etat)
    return AttackRules.estOuvert(etat) and AttackRules.nombreJoueurs(etat) < etat.config.MaxPlayers
end

function AttackRules.roleEquipe(etat, equipe)
    return equipe == etat.attaquants and 'attack' or 'defense'
end

function AttackRules.roleDe(etat, src)
    return AttackRules.roleEquipe(etat, etat.equipes[src])
end

-- ---------------------------------------------------------------------------
--  API publique : création et remises à zéro.
-- ---------------------------------------------------------------------------

function AttackRules.nouveau(config, aleatoire)
    return {
        config = config,
        aleatoire = aleatoire,
        phase = 'waiting',
        equipes = {},
        groupes = {},          -- [src] = clé de groupe (entier > 0)
        prochainGroupe = 0,
        vivants = {},
        stats = {},
        partis = {},
        score = { A = 0, B = 0 },
        attaquants = 'A',
        manche = 0,
        echeance = 0,          -- millisecondes, 0 si aucune
        chronoEnPause = false,
        chronoMisAJourA = 0,   -- millisecondes du dernier tic pendant 'live'
        solo = false,
        matchOver = false,
        echangeDeCamp = false,
    }
end

function AttackRules.reinitialiser(etat)
    etat.phase = 'waiting'
    etat.equipes = {}
    etat.groupes = {}
    -- `prochainGroupe` continue : les clés déjà distribuées ne sont pas réutilisées.
    etat.vivants = {}
    etat.stats = {}
    etat.partis = {}
    etat.score = { A = 0, B = 0 }
    etat.attaquants = 'A'
    etat.manche = 0
    etat.echeance = 0
    etat.chronoEnPause = false
    etat.chronoMisAJourA = 0
    etat.solo = false
    etat.matchOver = false
    etat.echangeDeCamp = false
end

-- Affecte une clé de groupe à chaque escouade. Peut être appelé avant
-- l'arrivée des joueurs (cas normal) ou pendant qu'ils sont déjà dans le mode :
-- un src déjà affecté est simplement réaffecté. Les entrées invalides sont
-- ignorées sans erreur. Aucun effet : les escouades ne changent pas de camp.
function AttackRules.definirGroupes(etat, escouades)
    if type(escouades) ~= 'table' then return {} end
    for _, escouade in ipairs(escouades) do
        if type(escouade) == 'table' then
            local valides = {}
            for _, src in ipairs(escouade) do
                if estSrcValide(src) then valides[#valides + 1] = src end
            end
            if #valides > 0 then
                etat.prochainGroupe = etat.prochainGroupe + 1
                local cle = etat.prochainGroupe
                for _, src in ipairs(valides) do
                    etat.groupes[src] = cle
                end
            end
        end
    end
    return {}
end

-- ---------------------------------------------------------------------------
--  API publique : entrées, sorties, morts et déplacements.
-- ---------------------------------------------------------------------------

function AttackRules.arrivee(etat, src)
    local liste = {}
    local camp

    -- Un membre d'escouade rejoint toujours le camp de son escouade, même si
    -- ce camp est déjà le plus rempli.
    if etat.groupes[src] then
        local cle = cleGroupe(etat, src)
        for _, s in ipairs(listeJoueurs(etat)) do
            if s ~= src and cleGroupe(etat, s) == cle and etat.equipes[s] then
                camp = etat.equipes[s]
                break
            end
        end
    end

    if not camp then
        -- Sinon, camp le moins rempli, ou tirage au sort en cas d'égalité.
        local a = AttackRules.compter(etat, 'A')
        local b = AttackRules.compter(etat, 'B')
        if a < b then
            camp = 'A'
        elseif b < a then
            camp = 'B'
        else
            camp = etat.aleatoire(2) == 1 and 'A' or 'B'
        end
    end

    etat.equipes[src] = camp
    etat.stats[src] = { kills = 0, deaths = 0 }
    ajouter(liste, { type = 'equipe', src = src, equipe = camp })
    ajouter(liste, { type = 'notifier', modele = 'rejoint', src = src, equipe = camp })
    placementSelonPhase(etat, liste, src)
    ajouter(liste, { type = 'classement' })
    return liste
end

function AttackRules.placer(etat, src)
    if not etat.equipes[src] then return {} end
    local liste = {}
    placementSelonPhase(etat, liste, src)
    return liste
end

function AttackRules.depart(etat, src, maintenantMs)
    if not etat.equipes[src] then return {} end

    local liste = {}
    ajouter(liste, { type = 'objets', src = src, action = 'clear' })

    if etat.manche > 0 and not etat.matchOver then
        local st = etat.stats[src]
        if st then
            etat.partis[#etat.partis + 1] = {
                src = src, equipe = etat.equipes[src], kills = st.kills, deaths = st.deaths,
            }
        end
    end

    ajouter(liste, { type = 'effacerResultats', src = src })
    ajouter(liste, { type = 'nettoyerJoueur', src = src })
    etat.equipes[src] = nil
    etat.groupes[src] = nil
    etat.vivants[src] = nil
    etat.stats[src] = nil
    ajouter(liste, { type = 'classement' })

    if AttackRules.nombreJoueurs(etat) == 0 and etat.phase ~= 'waiting' then
        AttackRules.reinitialiser(etat)
        return liste
    end

    verifierVictoire(etat, liste, maintenantMs)
    return liste
end

function AttackRules.mort(etat, victime, tueur, maintenantMs)
    if not etat.equipes[victime] then return {} end

    local liste = {}
    local stVictime = etat.stats[victime]
    if stVictime then stVictime.deaths = stVictime.deaths + 1 end

    local credited = false
    if tueur and etat.equipes[tueur] and etat.equipes[tueur] ~= etat.equipes[victime] and etat.stats[tueur] then
        credited = true
        etat.stats[tueur].kills = etat.stats[tueur].kills + 1
        if etat.vivants[tueur] then
            ajouter(liste, { type = 'recompenseKevlar', src = tueur })
        end
    end

    ajouter(liste, { type = 'statistiquesKill', victime = victime, tueur = credited and tueur or false })
    ajouter(liste, { type = 'classement' })

    if etat.phase == 'live' and etat.vivants[victime] then
        etat.vivants[victime] = false
        ajouter(liste, { type = 'vivant', src = victime, vivant = false })
        ajouter(liste, { type = 'annonce', modele = 'elimine', src = victime, dureeMs = 3000 })
        ajouter(liste, { type = 'spectateurDiffere', src = victime, delaiMs = 3000 })
        verifierVictoire(etat, liste, maintenantMs)
    else
        ajouter(liste, { type = 'placementDiffere', src = victime, delaiMs = 2000 })
    end
    return liste
end

function AttackRules.changerEquipe(etat, src, equipe, maintenantMs)
    if not etat.equipes[src] or (equipe ~= 'A' and equipe ~= 'B') then return {} end

    local liste = {}
    etat.equipes[src] = equipe
    ajouter(liste, { type = 'equipe', src = src, equipe = equipe })
    placementSelonPhase(etat, liste, src)
    ajouter(liste, { type = 'classement' })
    verifierVictoire(etat, liste, maintenantMs)
    return liste
end

-- ---------------------------------------------------------------------------
--  API publique : horloge et commandes serveur.
-- ---------------------------------------------------------------------------

function AttackRules.tic(etat, maintenantMs, attaquantDansZone)
    local liste = {}
    local phase = etat.phase

    if phase == 'waiting' then
        if peutDemarrer(etat) then demarrerSelection(etat, liste, maintenantMs) end
    elseif phase == 'select' then
        if maintenantMs >= etat.echeance then demarrerPlacement(etat, liste, maintenantMs) end
    elseif phase == 'place' then
        if maintenantMs >= etat.echeance then demarrerLive(etat, liste, maintenantMs) end
    elseif phase == 'live' then
        etat.chronoEnPause = attaquantDansZone and true or false
        if etat.chronoEnPause then
            etat.echeance = etat.echeance + (maintenantMs - etat.chronoMisAJourA)
        end
        etat.chronoMisAJourA = maintenantMs
        if maintenantMs >= etat.echeance then
            if etat.solo and AttackRules.compter(etat, etat.attaquants) > 0 then
                terminerManche(etat, liste, etat.attaquants, 'Temps écoulé : manche de test terminée', maintenantMs)
            else
                terminerManche(etat, liste, autreCamp(etat.attaquants), 'Temps écoulé : la défense a tenu la zone', maintenantMs)
            end
        end
    elseif phase == 'ended' then
        if maintenantMs >= etat.echeance then mancheSuivante(etat, liste, maintenantMs) end
    end

    return liste
end

function AttackRules.debutTest(etat, maintenantMs)
    if etat.phase ~= 'waiting' or AttackRules.nombreJoueurs(etat) == 0 then return {} end
    local liste = {}
    demarrerSelection(etat, liste, maintenantMs)
    return liste
end

function AttackRules.finMatch(etat)
    local liste = {}
    local joueurs = listeJoueurs(etat)

    etat.score = { A = 0, B = 0 }
    etat.partis = {}
    for _, src in ipairs(joueurs) do
        local st = etat.stats[src]
        if st then st.kills, st.deaths = 0, 0 end
    end
    etat.manche = 0
    etat.matchOver = false
    etat.attaquants = 'A'
    etat.echeance = 0
    etat.phase = 'waiting'
    etat.solo = false
    etat.chronoEnPause = false
    etat.chronoMisAJourA = 0
    etat.echangeDeCamp = false

    for _, src in ipairs(joueurs) do
        ajouter(liste, { type = 'effacerResultats', src = src })
        etat.vivants[src] = false
        ajouter(liste, { type = 'vivant', src = src, vivant = false })
        ajouter(liste, { type = 'apparition', src = src, mode = 'attente' })
    end
    ajouter(liste, { type = 'phase', phase = 'waiting' })
    -- L'ancien /endmatch annonçait « Match arrêté » une seule fois : c'est
    -- l'effet matchArrete que le serveur interprète, sans effet annonce doublon.
    ajouter(liste, { type = 'matchArrete' })
    ajouter(liste, { type = 'classement' })
    return liste
end

function AttackRules.allerEnAttente(etat)
    etat.phase = 'waiting'
    etat.echeance = 0

    local liste = {}
    for _, src in ipairs(listeJoueurs(etat)) do
        etat.vivants[src] = false
        ajouter(liste, { type = 'vivant', src = src, vivant = false })
        ajouter(liste, { type = 'apparition', src = src, mode = 'attente' })
    end
    ajouter(liste, { type = 'phase', phase = 'waiting' })
    return liste
end
