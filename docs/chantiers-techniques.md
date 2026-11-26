# Chantiers techniques

Ce qu'il faut revoir, modifier ou ajouter pour que le dépôt respecte les
[règles de code](regles-de-code.md). La liste vient d'une revue du code faite
en novembre 2026. [`must-have.md`](must-have.md) dit quelles fonctionnalités
construire ; ce document dit ce qui doit changer pour que celles qui existent
soient justes, sûres et mesurées.

Chaque chantier donne :

- le **constat** : ce que fait le code aujourd'hui ;
- ce qu'il faut **faire** ;
- la **matière brute** : la donnée de première main dont partir ;
- les **outils** ;
- la **preuve** attendue, qui ne repose ni sur l'auteur ni sur le relecteur.

Un chantier = une branche et une PR (plusieurs au-delà de 400 lignes environ),
selon [`AGENTS.md`](../AGENTS.md). Les noms de convars, de natives et de
champs cités ici se confirment avant usage (`scripts/native.py`, code source
de FiveM) : la revue les donne de mémoire.

Légende : ⬜ à faire · 🟡 commencé · 🧪 code fusionné, preuve en jeu à
faire · ✅ fait · ❓ hypothèse à vérifier avant tout correctif.

## Vue d'ensemble

| # | Chantier | Priorité | État | Dépend de | Règles |
|---|---|---|---|---|---|
| C1 | Validation des tirs | haute | 🟡 | — | S4, S9 |
| C2 | Journal brut des matchs | haute | ✅ | — | D2, S9, P3 |
| C3 | Vie et soins contrôlés par le serveur | haute | 🧪 | C2 | S1 |
| C4 | State bags lus comme vérité | haute | 🧪 | — | S3 |
| C5 | Verrous FXServer et véhicules créés par le serveur | haute | ⬜ | — | S5, S8 |
| C6 | Équilibrage tiré des fichiers du jeu | moyenne | 🟡 | C2 | A3, V8 |
| C7 | Manche d'Attaque en machine à états testée | moyenne | 🧪 | — | A1, V5 |
| C8 | Charge et réseau mesurés | moyenne | ⬜ | C2 | P5, V7 |
| C9 | Playtests et équilibre des maps | moyenne | ⬜ | C2 | V8 |
| C10 | Une seule commande de vérification | moyenne | ✅ | — | V1 |
| C11 | Mutation, propriétés et fuzzing | moyenne | ⬜ | C10 | V4, U2, U3 |
| C12 | Migrations de schéma | haute avant [`must-have.md`](must-have.md) § 1 | 🟡 | — | D4 |
| C13 | Suivi d'oxmysql | basse | ✅ | — | E3 |
| C14 | Rendu du lobby comparé à une référence | basse | ⬜ | — | V6 |
| C15 | Documentation contradictoire | basse | ✅ | — | — |
| C16 | Délais, boucles par image et taille des fichiers | basse | 🟡 | C7 | A4, A6, P1 |

## Avancement (27 novembre 2026)

Ce qui est fusionné et ce qu'il reste à prouver. « En jeu » veut dire avec de
vrais clients FiveM (`FiveM.exe -cl2` pour un second client) sur le serveur
de développement.

| # | PR | Fait | Reste à faire |
|---|---|---|---|
| C1 | #55 | Module `ShotValidation` : arme hors loadout, plafond de dégât, cadence ; refus journalisés | Remplir `damageCaps` et `fireIntervals` à partir de C6, avec exemption des touches mortelles ou plafond au-dessus de 750 |
| C2 | #59 | Ressource `gf_journal` (table `gf_match_events`), `scripts/recalculer_match.py`, `scripts/exporter_journal.sh` | — |
| C3 | #62 | Ressource `gf_audit` : anomalies `soin-sans-objet` et `touche-mortelle-sans-mort`, sans sanction | Une anomalie quand une ressource de test force un soin ; mesurer le taux de fausses alertes sur plus de parties avant toute sanction |
| C4 | #61 | Le serveur décide depuis ses tables (`Proteges`, `Equipes`, `Modes`) ; un garde rétablit les state bags réécrits par un client et journalise l'anomalie | En jeu, un client : `LocalPlayer.state:set('gf_protected', true, true)` doit produire une ligne `anomalie` et la valeur revenir à `false` |
| C5 | — | Rien | Tout, avec une partie de test : le véhicule de mode devient créé par le serveur |
| C6 | #64 | Tableau des tirs et du temps pour tuer : [`equilibrage-armes.md`](equilibrage-armes.md) (build 1.0.3889.0) | Compter les tirs pour tuer en jeu, à 10, 25 et 50 m, et comparer au tableau ; puis la part des kills de chaque arme (C2) avant tout réglage |
| C7 | #58 | Module `AttackRules` (machine à états, 26 tests, 500 suites aléatoires) ; défaut du départ en sélection ou en placement vidant une équipe corrigé (branche `fix/attack-empty-team-at-live`) | Voir le correctif en jeu à deux clients |
| C12 | #56 | Ressource `gf_db` : migrations numérotées et table `gf_schema_version`, prouvées sur la base de développement | Sauvegarde puis restauration du runbook après migration |
| C13 | #57 | `vendorise.json` et `scripts/suivre_vendorise.py`, testés | — |
| C16 | #58 | Délais de `gf_attack` passés à `GetGameTimer()` | Mesurer chaque `Wait(0)` avec `resmon` ; découper `gf_lobby/server.lua`, `gf_lobby/client.lua` et `gf_attack/server.lua` (644 lignes) |

Le smoke de la CI vérifie aussi le démarrage de `gf_db`, `gf_journal` et
`gf_stats` (#60), mais pas encore celui de `gf_audit`.

### Preuves tirées du journal de production (26 novembre 2026)

Le 26 novembre 2026, trois joueurs ont joué en production, en Redzone et en
Attaque : le journal `gf_match_events`, lu par des requêtes en lecture seule,
contient 896 événements de 16 h 31 à 23 h 27.

| # | Résultat | Ce que montre le journal |
|---|---|---|
| C1 | 486 touches acceptées, aucun tir légitime refusé ; 39 refus `arme-hors-loadout` et 31 refus `regle-mode` | Les 39 refus viennent d'un même joueur entre 17 h 59 et 18 h 05, avec des armes que le serveur ne donne jamais : annulées et journalisées ; les 31 refus sont des tirs hors de la zone Redzone, attendus. Les plafonds et les cadences restent à remplir |
| C2 | 6 matchs terminés (4 Redzone, 2 Attaque), jusqu'à 3 joueurs et 26 morts | `scripts/recalculer_match.py` recalcule les 6 matchs à l'identique de la ligne `resultats` |
| C3 | 3 anomalies `touche-mortelle-sans-mort` entre 18 h 00 et 18 h 10, vie vue par le serveur à 200 ; aucune anomalie `soin-sans-objet` sur les 52 kills | Vrais positifs, pendant le bug de la Redzone où les joueurs ne pouvaient pas mourir, corrigé depuis. Restent la ressource de test qui force un soin et le taux de fausses alertes sur plus de parties |
| C6 | Dégât maximal au corps 31 pour `WEAPON_SPECIALCARBINE` (32 au tableau) et 50 pour `WEAPON_PISTOL50` (51 au tableau) | Premier relevé en jeu cohérent avec le tableau ; le nombre de tirs pour tuer reste à compter |
| C7 | Les manches d'Attaque ont enchaîné leurs phases normalement : scores, raisons de fin, départs en placement et en live | Un départ pendant la sélection ou le placement vidant une équipe laissait la manche passer en live et durer tout le chrono sans adversaire ; corrigé par la branche `fix/attack-empty-team-at-live`, à voir en jeu à deux clients |
| C12 | Migrations 1 et 2 le 26/11 à 16 h 30, puis migration 3 à chaud à 18 h 55 sur une base en version 2 | Preuve d'une base de la version précédente migrée, en production plutôt qu'en CI ; restent la sauvegarde et la restauration du runbook après migration |

Une touche mortelle à la tête annonce un dégât très supérieur à celui de
l'arme : jusqu'à 730 relevé, contre 31 à 50 pour une touche normale. Un
plafond tiré du tableau de C6 refuserait ces kills légitimes : il faut
exempter les touches mortelles ou fixer le plafond au-dessus de 750.

## C1 — Validation des tirs

- **Constat** : le handler `weaponDamageEvent` de `gf_core/server.lua` annule
  un tir entre deux modes, sur un joueur protégé ou sur un coéquipier. Il ne
  vérifie pas que `data.weaponType` est l'une des deux armes que le serveur a
  validées pour ce joueur (`S.choice[src]` dans `gf_attack/server.lua`, issu
  de `ResolveSelection`), ni que `data.weaponDamage` est plausible, ni que
  deux touches du même tireur respectent la cadence de l'arme. Les armes sont
  données par le client (`GiveWeaponToPed` dans `gf_core/client.lua`).
- **Faire** : un module pur de validation des tirs, appelé par le handler.
  Arme hors du loadout (Attaque) ou de l'équipement fixe (Redzone,
  `Config.Loadouts`) : refus. Dégât au-dessus du plafond de l'arme pour la
  partie du corps touchée : refus. Intervalle plus court que la cadence de
  l'arme, moins une tolérance réseau : refus. Chaque refus passe par
  `CancelEvent()` et le journal.
- **Matière brute** : les champs que le serveur reçoit à chaque touche
  (`weaponType`, `weaponDamage`, `willKill`, et `hitComponent`, `damageTime`
  à confirmer dans le code de FiveM) ; les valeurs de `weapons.meta` (C6) pour
  les plafonds.
- **Outils** : tests Lua dans `tests/lua/` ; deux clients (`FiveM.exe -cl2`)
  et un testeur humain.
- **Preuve** : sur une manche complète à deux clients, aucun tir légitime
  refusé ; un tir avec une arme hors loadout, donnée en développement par une
  ressource de test, est annulé et journalisé.

## C2 — Journal brut des matchs

- **Constat** : chaque touche est oubliée dès que `lastDamager` est mis à jour.
  `gf_stats_players` ne garde que quatre compteurs (kills, morts, parties,
  victoires). On ne peut ni auditer un kill contesté, ni mesurer un temps pour
  tuer, ni calculer un taux de victoire par map.
- **Faire** : un journal où l'on ne fait qu'ajouter, une ligne par événement :
  touche (refusée comprise, avec sa raison), mort, début et fin de phase, fin
  de manche (map, camp gagnant), arrivée et départ en cours de manche. Clé :
  identifiant de match, numéro de manche, `GetGameTimer()`. Écriture par lots,
  asynchrone. Les compteurs de `gf_stats` en deviennent vérifiables.
- **Matière brute** : les événements que le serveur voit déjà
  (`weaponDamageEvent`, `gf:playerKilled`, fins de phase de `gf_attack` et
  `gf_redzone`).
- **Outils** : table MariaDB (après C12) ou un fichier JSON lines par match
  dans un volume ; le choix se justifie dans la PR (volume, requêtes,
  sauvegarde).
- **Preuve** : un script indépendant recalcule, à partir du seul journal, le
  tableau de fin de match affiché en jeu, à l'identique.

## C3 — Vie et soins contrôlés par le serveur

- **Constat** : `gf_attack:useItem` décompte bien bandages et kevlars côté
  serveur, mais c'est le client qui remet la vie et l'armure
  (`SetEntityHealth`, `SetPedArmour` dans `gf_attack/client.lua`). Le serveur
  ne relit jamais la vie d'un joueur : un client invulnérable, ou qui se
  soigne seul, passe inaperçu.
- **Faire** : un audit côté serveur. Vie et armure relues au fil des touches ;
  une touche `willKill` sans mort qui suit, ou une vie qui remonte sans objet
  utilisé, est journalisée comme anomalie. Pas de sanction automatique avant
  d'avoir mesuré le taux de fausses alertes.
- **Matière brute** : le journal C2 et les valeurs que OneSync réplique au
  serveur (`GetEntityHealth`, `GetPedArmour` côté serveur, à confirmer).
- **Preuve** : aucune anomalie sur une manche normale à deux clients ; une
  anomalie quand une ressource de test force un soin en développement.

## C4 — State bags lus comme vérité ❓

- **Constat** : le handler des tirs lit `Player(victim).state.gf_protected` et
  `.gf_team` pour annuler un tir. Ces valeurs sont écrites par le serveur
  (`state:set(…, true)`), mais un client peut écrire dans ses propres state
  bags répliqués. Si FXServer accepte cette écriture, un joueur peut se
  déclarer protégé ou changer d'équipe aux yeux du serveur.
- **Faire** : d'abord vérifier, sans rien corriger (AGENTS.md : observer
  avant de corriger). En développement, depuis un client :
  `LocalPlayer.state:set('gf_protected', true, true)`, puis lire la valeur
  côté serveur. Si elle a changé : faire lire au serveur ses propres tables
  (`Modes`, `S.team`, un registre des joueurs protégés) et refuser l'écriture
  du client (`AddStateBagChangeHandler`).
- **Matière brute** : la valeur observée ; le traitement des state bags dans
  le code source de FiveM.
- **Preuve** : la valeur lue par le serveur après l'écriture du client.

## C5 — Verrous FXServer et véhicules créés par le serveur

- **Constat** : `server.cfg` ne pose que `sv_scriptHookAllowed 0`. Le
  véhicule de mode est créé par le client, en réseau
  (`CreateVehicle(…, true, false)` dans `gf_core/client.lua`), puis son
  identifiant réseau est envoyé au serveur (`gf_core:vehicle`) : cela interdit
  `sv_entityLockdown strict`.
- **Faire** : créer le véhicule de mode côté serveur
  (`CreateVehicleServerSetter`), le client ne faisant plus que monter dedans.
  Puis poser `sv_enforceGameBuild` (build exigé par les véhicules DLC et les
  tatouages), `sv_pureLevel` (1 ou 2, choix argumenté), `sv_entityLockdown`
  (`strict` si tout fonctionne) et `sv_filterRequestControl`, et les exiger
  dans la classe `ConfigurationServeur` de `tests/test_depot.py`.
- **Matière brute** : les messages de FXServer et du client avec chaque
  réglage ; ce qui casse, consigné réglage par réglage.
- **Preuve** : FXServer refuse lui-même un client aux fichiers modifiés et une
  entité créée par un client ; une manche d'Attaque et une partie de Redzone
  se jouent normalement, `/customveh` compris.

## C6 — Équilibrage tiré des fichiers du jeu

- **Constat** : `Config.Weapons` (`gf_core/config.lua`) ne contient que nom,
  libellé, catégorie et munitions, et cite un wiki pour les noms. Personne ne
  connaît le temps pour tuer de chaque arme contre 100 PV et 100 de kevlar.
- **Faire** : pour les 11 armes, le nombre de balles et les millisecondes pour
  tuer, au corps et à la tête, à 10, 25 et 50 m. Ensuite seulement, si des
  écarts sont jugés trop forts, des réglages (`SetWeaponDamageModifier`) dans
  `config.lua`, avec leur source.
- **Matière brute** : les `weapons.meta` du jeu, ceux de base et les dernières
  surcharges des DLC (`Damage`, `HeadShotDamageModifierPlayer`,
  `DamageFallOffRangeMin`, `DamageFallOffRangeMax`, `DamageFallOffModifier`,
  `TimeBetweenShots`). Puis le journal C2 : taux de choix et part des kills
  de chaque arme.
- **Outils** : CodeWalker ou OpenIV pour lire les archives du jeu (jamais
  commitées) ; un script Python pur, testé, qui calcule le tableau.
- **Preuve** : le nombre de balles mesuré en jeu sur une cible à distance
  fixe est celui du tableau.
- **Avancement** : tableau calculé pour le build 1.0.3889.0 dans
  [`equilibrage-armes.md`](equilibrage-armes.md) ; mesure en jeu et part des
  kills (C2) à faire.

## C7 — Manche d'Attaque en machine à états testée

- **Constat** : `gf_attack/server.lua` (801 lignes) mêle les phases
  (`waiting`, `select`, `place`, `live`…) et les natives. Aucun test ne couvre
  le déroulé d'une manche.
- **Faire** : extraire les règles dans un module pur, piloté par des
  événements : arrivée, départ, mort, fin de minuteur, attaquant dans la zone.
  Dans `tests/lua/`, des suites d'événements aléatoires à graine fixe
  vérifient ces invariants :
  - chaque manche se termine ;
  - un seul camp gagne ;
  - aucun score ne dépasse 2 ;
  - un joueur n'est que dans une équipe ;
  - l'écart d'effectif reste au plus de 1 après l'équilibrage sans escouade ; une escouade n'est jamais coupée ;
  - un départ, à n'importe quelle phase, ne bloque pas le match.
- **Preuve** : un défaut posé exprès fait échouer un invariant (sabotage) ; en
  jeu, une manche avec un départ volontaire à chaque phase.

## C8 — Charge et réseau mesurés

- **Constat** : les matchs d'Attaque visent 16 à 40 joueurs, le serveur a
  48 places. Le smoke de la CI prouve que les ressources démarrent, sans aucun
  client connecté ; aucun temps de tick n'est mesuré.
  `Config.KillCreditWindow = 10` (secondes) est une valeur choisie, pas
  mesurée.
- **Faire** : des mesures de référence sur un match réel ; la fenêtre de
  crédit réglée sur la distribution mesurée du délai entre la dernière touche
  et la mort (C2) ; les scénarios à deux clients rejoués sous 150 ms de
  latence et 2 % de perte. Cfx.re ne fournit pas de client sans écran : la
  vraie montée en charge demande de vrais joueurs (C9).
- **Matière brute** : le profileur de FXServer (`profiler record`, puis
  `profiler view`, lisible dans les DevTools de Chrome) ; le graphe de
  performances de txAdmin (svMain, svSync, svNetwork) ; les lignes
  « hitch warning » du journal ; `resmon` et `netgraph` côté client.
- **Outils** : `FiveM.exe -cl2` ; clumsy (Windows) pour la latence et la
  perte.
- **Preuve** : les chiffres du profileur et de txAdmin sur un match complet,
  sans aucun « hitch warning ».

## C9 — Playtests et équilibre des maps

- **Constat** : aucune donnée de match réel n'est gardée ; l'équilibre d'une
  map d'Attaque se juge sur impression.
- **Faire** : des playtests planifiés et enregistrés (journal C2 et vidéo).
  Pour chaque map, le taux de victoire de l'attaque avec son intervalle de
  confiance ; un questionnaire court aux joueurs.
- **Repères** : l'intervalle de confiance à 95 % fait environ ±10 points sur
  100 manches et ±5 points sur 400. Une map à 65 % sur 400 manches est
  déséquilibrée ; 55 % sur 100 manches ne permet aucune conclusion.
- **Preuve** : les données des joueurs, pas l'avis de l'auteur.

## C10 — Une seule commande de vérification

- **Constat** : la CI enchaîne `bash scripts/verifier.sh` et
  `python -m unittest discover -s tests -v`. En local, chaque outil absent est
  « ignoré ». Sur le poste de développement, le 26 novembre 2026 (Git Bash),
  6 contrôles (JSON, shellcheck, actionlint, hadolint, gitleaks, ruff) ont été
  sautés sur les 11 étapes du script, qui a conclu quand même « Toutes les
  vérifications statiques sont passées ». Les tests
  Lua et Node sont sautés (`skipTest`) quand `lua5.4` ou `node` manque.
- **Faire** : une commande unique, appelée telle quelle par la CI, qui échoue
  si un outil manque ; les outils installés en local, ou la commande lancée
  dans l'image de la CI par Docker.
- **Preuve** : la CI et le poste local affichent la même liste d'étapes
  exécutées.

## C11 — Mutation, propriétés et fuzzing

- **Constat** : aucun test de mutation, de propriété ni de fuzzing.
  `scripts/ajouter_vehicule.py` lit des packs fournis par des tiers (dossiers,
  `dlc.rpf` décompressé avec `zlib`) : c'est l'entrée non fiable du dépôt.
- **Faire** : mutation des lignes changées avant chaque fusion (mutmut,
  Stryker, à la main pour le Lua) ; Hypothesis sur les fonctions de lecture de
  pack et une cible atheris lancée chaque nuit en CI ; propriétés de la
  machine à états (C7).
- **Preuve** : le score de mutation des lignes changées dans chaque PR ; un
  corpus de fuzz qui ne fait rien planter.

## C12 — Migrations de schéma

- **Constat** : `docker/db/init/` ne s'exécute que sur un volume vide. Une
  nouvelle table (profil, monnaies : [`must-have.md`](must-have.md) § 1)
  n'arriverait jamais sur la base de production existante sans commande
  manuelle.
- **Faire** : des migrations numérotées et une table de version, appliquées
  au démarrage ou par `scripts/deployer.sh`, testées en CI sur une base créée
  par la version précédente.
- **Preuve** : en CI, une base de la version précédente migre vers le schéma
  attendu ; la sauvegarde puis la restauration du runbook passent après
  migration.

## C13 — Suivi d'oxmysql

- **Constat** : `oxmysql` 2.14.3 est recopié dans
  `server-data/resources/[standalone]/` ; Dependabot ne le suit pas.
- **Faire** : noter sa source et sa version, et les vérifier par un test ;
  surveiller les versions et les avis de sécurité du dépôt amont ; mettre à
  jour par une PR dédiée.
- **Preuve** : la version installée correspond à celle notée, et aucun avis
  de sécurité ouvert ne la concerne.

## C14 — Rendu du lobby comparé à une référence

- **Constat** : le rendu du lobby se juge sur des captures
  (`scripts/capturer-jeu.ps1`) regardées à l'œil.
- **Faire** : des images de référence versionnées ; une comparaison SSIM
  (scikit-image), avec un masque sur le personnage animé et un seuil fixé ;
  un échec au-delà du seuil.
- **Preuve** : le chiffre de similarité, pas un avis.

## C15 — Documentation contradictoire

- **Constat** :
  - [`docs/README.md`](README.md) dit que la protection de `main`
    « reste à activer » sur un dépôt privé ; le ruleset « Protection de main »
    est actif et le dépôt est public (vérifié avec l'API GitHub en novembre
    2026) ;
  - [`CONTRIBUTING.md`](../CONTRIBUTING.md) § 7 exige « 1 approbation » ;
    [`AGENTS.md`](../AGENTS.md) § 6 dit que le ruleset n'en exige pas ;
  - [`architecture.md`](architecture.md), « Limites connues », dit que la
    logique Lua n'a pas de tests unitaires ; `tests/lua/` en contient.
- **Faire** : une PR `docs` qui aligne ces trois points sur l'état réel.
- **Preuve** : `gh api repos/quentingimenez/FiveMGunFight/rulesets` et le
  contenu de `tests/lua/`.

## C16 — Délais, boucles par image et taille des fichiers

- **Constat** :
  - `gf_attack` mesure ses délais avec `os.time()`, à la seconde près ;
  - 24 appels `Wait(0)` dans les ressources `gf_*`, à justifier un par un ;
  - `gf_lobby/server.lua` (1 395 lignes), `gf_lobby/client.lua` (1 161) et
    `gf_attack/server.lua` (801) dépassent le seuil de la règle A6.
- **Faire** : passer les délais à `GetGameTimer()` pendant C7 ; mesurer chaque
  `Wait(0)` avec `resmon` et allonger l'attente hors des moments qui en ont
  besoin ; découper ces fichiers quand on y travaille, dans une PR `refactor`.
- **Preuve** : `resmon` au repos, avant et après.
