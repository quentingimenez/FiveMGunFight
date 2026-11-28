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
| C3 | Vie et soins contrôlés par le serveur | haute | 🟡 | C2 | S1 |
| C4 | State bags lus comme vérité | haute | ✅ | — | S3 |
| C5 | Verrous FXServer et véhicules créés par le serveur | haute | ⬜ | — | S5, S8 |
| C6 | Équilibrage tiré des fichiers du jeu | moyenne | 🟡 | C2 | A3, V8 |
| C7 | Manche d'Attaque en machine à états testée | moyenne | 🧪 | — | A1, V5 |
| C8 | Charge et réseau mesurés | moyenne | ⬜ | C2 | P5, V7 |
| C9 | Playtests et équilibre des maps | moyenne | ⬜ | C2 | V8 |
| C10 | Une seule commande de vérification | moyenne | ✅ | — | V1 |
| C11 | Mutation, propriétés et fuzzing | moyenne | 🟡 | C10 | V4, U2, U3 |
| C12 | Migrations de schéma | haute avant [`must-have.md`](must-have.md) § 1 | ✅ | — | D4 |
| C13 | Suivi d'oxmysql | basse | ✅ | — | E3 |
| C14 | Rendu du lobby comparé à une référence | basse | ⬜ | — | V6 |
| C15 | Documentation contradictoire | basse | ✅ | — | — |
| C16 | Délais, boucles par image et taille des fichiers | basse | 🟡 | C7, C17 | A4, A6, P1 |
| C17 | Registre des contrats entre ressources | haute | ✅ | — | A2, S3 |
| C18 | Harnais Lua partagé | haute | 🟡 | — | V2, V3 |
| C19 | Démarrage sans erreur de script et scénarios console | haute | ✅ | — | V6, A7 |
| C20 | Documentation tenue par les tests | moyenne | ✅ | — | A6, V1 |
| C21 | Mesure du flux de correctifs | moyenne | ✅ | — | V8 |
| C22 | Calques NUI possédés par gf_ui | moyenne | 🧪 | C17, C18 | A2, N2 |
| C23 | gf_core sans connaissance des modes | moyenne | ⬜ | C17, C18, C19 | A1, A2 |
| C24 | Utilitaires communs et données d'armes exposées | basse | ✅ | C17 | A2, A3 |

Les chantiers C17 à C24 viennent de la [méthode de développement](methode/README.md)
(ADR [0003](adr/0003-methode-de-developpement.md) et
[0004](adr/0004-architecture-cible.md)) : C17 à C21 forment le filet de
vérification, livré avant les refactors C22 à C24 et C16.

## Avancement (27 novembre 2026)

Ce qui est fusionné et ce qu'il reste à prouver. « En jeu » veut dire avec de
vrais clients FiveM (`FiveM.exe -cl2` pour un second client) sur le serveur
de développement.

| # | PR | Fait | Reste à faire |
|---|---|---|---|
| C1 | #55 | Module `ShotValidation` : arme hors loadout, plafond de dégât, cadence ; refus journalisés | Les plafonds ne peuvent pas encore être remplis sans risque : une touche mortelle annonce 484, 572, 605 ou 730 de dégât, sans rapport stable avec l'arme, et `willKill` vient du client du tireur, donc exempter les touches mortelles ouvrirait une faille ; il faut d'abord la mesure de C6 en jeu |
| C2 | #59 | Ressource `gf_journal` (table `gf_match_events`), `scripts/recalculer_match.py`, `scripts/exporter_journal.sh` | — |
| C3 | #62 | Ressource `gf_audit` : anomalies `soin-sans-objet` et `touche-mortelle-sans-mort`, sans sanction | Mesurer le taux de fausses alertes sur de vraies parties avant toute sanction |
| C4 | #61 | Le serveur décide depuis ses tables (`Proteges`, `Equipes`, `Modes`) ; un garde rétablit les state bags réécrits par un client et journalise l'anomalie ; preuve en local avec un vrai client, voir ci-dessous | — |
| C5 | — | Rien | Tout, avec une partie de test : le véhicule de mode devient créé par le serveur |
| C6 | #64 | Tableau des tirs et du temps pour tuer : [`equilibrage-armes.md`](equilibrage-armes.md) (build 1.0.3889.0) | Compter les tirs pour tuer en jeu, à 10, 25 et 50 m, et comparer au tableau ; puis la part des kills de chaque arme (C2) avant tout réglage |
| C7 | #58, #90, #97 | Module `AttackRules` (machine à états, 26 tests, 500 suites aléatoires) ; #90 vu en jeu : la manche se termine au passage en live quand un départ en sélection ou en placement a vidé une équipe ; #97 : un match commencé avec deux équipes peuplées se termine par forfait dès qu'une équipe n'a plus de joueur, à toute phase y compris la pause entre deux manches, manches de test en solo inchangées, 43 tests | Voir le forfait de #97 en jeu à deux clients |
| C11 | #100 | Lecteur RPF7 de `scripts/ajouter_vehicule.py` durci : traversée de chemin, lectures hors bornes, cycles de répertoires, profondeur des `.rpf` imbriqués limitée à 8, bombe de décompression (512 Mo par fichier, 4 Go au total) ; 14 tests, dont un fuzz déterministe de 2 000 mutations (bibliothèque standard) ; 8 vrais packs extraits à l'identique de l'ancien code | Test de mutation, Hypothesis et atheris avec fuzz nocturne en CI (dépendance et CI à décider) |
| C12 | #56, #95 | Ressource `gf_db` : migrations numérotées et table `gf_schema_version` ; preuve #95 : une base en version 2 (migrations 1 et 2) a migré au démarrage jusqu'à la version 4, avec sauvegarde, vérification et restauration en local sur piles jetables, serveur restauré en marche | La seule variante « en CI » de la preuve n'est pas automatisée |
| C13 | #57 | `vendorise.json` et `scripts/suivre_vendorise.py`, testés | — |
| C17 | #129 | `contrat.json` pour les 18 ressources, `scripts/contrats.py`, `tests/test_contrats.py`, [`contrats.md`](contrats.md) généré ; dette relevée : cycles gf_core ↔ gf_admin, gf_core ↔ gf_attack, gf_attack ↔ gf_lobby, gf_thumbs ↔ gf_vehicles, dépendance cachée gf_journal → gf_core ; sabotage vu en échec | Les appels à travers une variable (`local inv = exports.gf_inventory`) échappent à l'extraction : les écrire en appel direct au fil des PR |
| C18 | #129 | `tests/lua/lib/assert.lua` et `fivem.lua` ; trois tests migrés sans perte d'assertion (3, 56 et 18), sabotage vu en échec ; les suites Lua ne tournent plus qu'une fois | Migrer les autres tests quand on les touche |
| C19 | #129 | `scripts/verifier-journal-serveur.sh` dans le smoke, qui attend aussi la dernière ressource de `server.cfg` ; `scripts/scenario.py` et deux scénarios joués sur le serveur de développement | — |
| C20 | #129 | Liste des ressources calculée, table et ordre de démarrage d'`architecture.md`, index de `docs/README.md`, cliquet de taille ; documents périmés corrigés | — |
| C21 | #129 | `scripts/mesurer_flux.py` : 24 fonctionnalités, 22 correctifs, 3 chaînes correctif après fonctionnalité sur les 60 derniers commits au 28 novembre 2026 | Relever le chiffre après chaque lot de PR |
| C22 | #130 | Pile de calques dans gf_ui (`layers.lua`, exports `PushLayer`/`PopLayer`, événement `gf_ui:layersChanged`, calque retiré à l'arrêt de sa ressource) ; gf_admin, gf_maps, gf_menu et gf_vehicles l'utilisent ; `gf_lobby:menuOverlay` supprimé, interdit par `tests/test_lobby_nui.py` | Captures de chaque page ouverte depuis le lobby, le menu pause et un match |
| C24 | #130 | `gf_core/crash_marker.lua` repris par gf_core et gf_thumbs (mêmes clés KVP) ; gf_thumbs limite ses requêtes avec `RateLimit` de gf_core ; gf_weapons expose `GetWeaponMeta`, gf_inventory ne lit plus ses fichiers. Le délai de gf_menu reste son module testé `menu_state.lua` | — |
| C16 | #58 | Délais de `gf_attack` passés à `GetGameTimer()` | Mesurer chaque `Wait(0)` avec `resmon` ; découper `gf_lobby/server.lua`, `gf_lobby/client.lua` et `gf_attack/server.lua` (775 lignes) |

Le smoke de la CI (#96) lit la liste des ressources vérifiées dans les lignes
`ensure gf_` de `server-data/server.cfg` : `gf_audit` et `gf_inventory`,
auparavant oubliées, sont désormais vérifiées.

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

Une touche mortelle à la tête annonce un dégât sans rapport stable avec
l'arme : 484, 572, 605 et 730 relevés, contre 31 à 50 pour une touche
normale. `willKill` vient du client du tireur : exempter les touches
mortelles ouvrirait une faille. Les plafonds ne peuvent donc pas encore
être remplis sans risque ; il faut d'abord la mesure de C6 en jeu.

### Preuves du 27 novembre 2026

Le 27 novembre 2026, #90 a été vu en jeu ; les autres preuves viennent de
tests, de piles jetables locales et du code de la CI. C3 et C4 ont été
vérifiés sur un banc de test : un serveur jetable construit depuis `main`
(sans base, `TXADMIN=false`), un vrai client FiveM connecté et une ressource
de test locale, hors dépôt, qui agit côté client.

| # | Résultat | Preuve |
|---|---|---|
| C3 | Anomalie `soin-sans-objet` prouvée en local | En Redzone sans protection, la vie du joueur est baissée à 150 puis, une fois stable et la grâce de 3 s passée, remise de force à 200 côté client, sans objet ni soin accordé ; `gf_audit` émet `gf:anomalie` de type `soin-sans-objet` (`[gf_audit] anomalie soin-sans-objet joueur 1`) ; la remontée de vie de la réapparition, pendant la grâce, n'a déclenché aucune fausse alerte. Reste à mesurer le taux de fausses alertes sur de vraies parties avant toute sanction |
| C4 | Anomalie `state-bag` prouvée en local avec un vrai client | Dans le lobby, le serveur considère le joueur protégé (`gf_protected = true`) ; le client écrit `LocalPlayer.state:set('gf_protected', false, true)` ; le serveur journalise `gf:anomalie` de type `state-bag` (`cle=gf_protected recu=false serveur=true`) et la ligne `[gf_core] anomalie state-bag`, garde `IsProtected = true`, et 2 s plus tard le client relit `gf_protected = true` : la valeur a été rétablie |
| C7 | #90 vu en jeu, #97 prouvé par 43 tests | En jeu, l'adversaire a quitté et l'utilisateur a gagné la manche aussitôt : un départ en sélection ou en placement vidant une équipe termine la manche au passage en live. Les 43 tests de #97 prouvent le forfait d'un match commencé avec deux équipes peuplées dès qu'une équipe n'a plus de joueur, à toute phase y compris la pause entre deux manches, sans changer les manches de test en solo. Reste à voir ce forfait en jeu à deux clients |
| C11 | #100, durcissement du lecteur RPF7 | Traversée de chemin démontrée (une entrée `../x` écrivait hors du dossier de sortie), lectures hors bornes, cycles de répertoires, profondeur des `.rpf` imbriqués limitée à 8, bombe de décompression (512 Mo par fichier, 4 Go au total) ; 14 tests, dont un fuzz déterministe de 2 000 mutations (bibliothèque standard) ; 8 vrais packs extraits à l'identique de l'ancien code |
| C12 | #95, preuve complète en local sur piles jetables | Une base en version 2 (migrations 1 et 2) a migré au démarrage jusqu'à la version 4 ; `scripts/sauvegarder.sh` (code 0), `scripts/restaurer.sh --verifier`, puis extraction et import dans la pile `gunfight-restore` du runbook. Le test a trouvé un défaut du runbook : le serveur restauré s'arrêtait aussitôt (« Ctrl-C pressed in server console », pas d'entrée standard) ; corrigé dans #95 (`init`, `stdin_open`, `tty`). Après correction : serveur restauré en marche, 15 ressources démarrées, `gf_db` « schéma à jour (version 4) » sans migration rejouée |
| Smoke | #96 : `gf_audit` et `gf_inventory`, auparavant oubliées, sont vérifiées | La liste des ressources vérifiées est lue dans les lignes `ensure gf_` de `server-data/server.cfg` |

Avec la preuve en production du 26/11, C12 passe à ✅ ; la variante « en CI »
de la preuve n'est pas automatisée.

En local, la vie vue par le serveur suit celle du client avec plusieurs
secondes de retard : client 200 et serveur 150, puis client 150 et serveur
200. C'est cohérent avec le refus « mort refusé … : vivant » vu en production
le 26/11 : la mort est vérifiée sur une vie serveur pas encore à jour.

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
  - `gf_lobby/server.lua` (1 527 lignes), `gf_lobby/client.lua` (1 172),
    `gf_attack/server.lua` (775) et `gf_attack/rules.lua` (693) dépassent le
    seuil de la règle A6 (relevé du 28 novembre 2026 ; le cliquet de C20 les
    empêche de grossir).
- **Faire** : passer les délais à `GetGameTimer()` pendant C7 ; mesurer chaque
  `Wait(0)` avec `resmon` et allonger l'attente hors des moments qui en ont
  besoin ; découper ces fichiers quand on y travaille, dans une PR `refactor`.
- **Preuve** : `resmon` au repos, avant et après.

## C17 — Registre des contrats entre ressources

- **Constat** : environ la moitié des appels entre ressources ne sont pas
  dans les `fxmanifest.lua` (16 fichiers passent par `GetResourceState` et
  `pcall`) ; le bus `gf:*` compte environ 17 événements, dont 3 décrits dans
  [`evenements-serveur.md`](evenements-serveur.md), et plusieurs ont deux
  émetteurs ; les state bags et le protocole `gf_lobby:menuOverlay` ne sont
  écrits nulle part. `tests/test_evenements.py` ne couvre que les
  événements client → serveur.
- **Faire** : un `contrat.json` par ressource `gf_*` (exports fournis et
  consommés, événements émis et écoutés, state bags écrits et lus, calques
  NUI, tables possédées, dépendances dures et optionnelles, dette connue) ;
  `scripts/contrats.py` qui extrait ces faits du code et génère
  `docs/contrats.md` ; `tests/test_contrats.py` : le code et le registre
  concordent dans les deux sens, toute consommation a un fournisseur, toute
  dépendance dure est dans le manifeste, la documentation générée est à
  jour.
- **Matière brute** : le code des ressources, `server.cfg`, les manifestes.
- **Outils** : expressions régulières dans l'esprit de
  `tests/test_evenements.py`, bibliothèque standard Python.
- **Preuve** : sabotage — un export non déclaré, un appel à un export
  inexistant et un nouvel événement `gf:*` non déclaré font chacun échouer
  le test avec un message clair.

## C18 — Harnais Lua partagé

- **Constat** : les 33 fichiers de `tests/lua/` (environ 9 800 lignes)
  recopient chacun leurs assertions, leurs compteurs et leur faux FiveM
  (événements, exports, horloge, threads, NUI), avec des différences d'un
  fichier à l'autre ; les noms ne suivent pas une convention
  (`*_test.lua` ou non) ; les suites Lua tournent deux fois (étape 5b de
  `scripts/verifier.sh` et `tests/test_lobby_nui.py`).
- **Faire** : `tests/lua/lib/assert.lua` et `tests/lua/lib/fivem.lua` (bac à
  sable qui charge un vrai fichier de ressource : bus d'événements, exports,
  horloge pilotable, threads pas à pas, state bags, NUI, fichiers de
  ressource) ; découverte limitée aux fichiers de premier niveau ; trois
  tests représentatifs migrés ; règle « un test touché est migré » ; un seul
  lancement des suites Lua.
- **Matière brute** : les faux FiveM existants, à unifier sans perdre
  d'assertion.
- **Outils** : `lua5.4` de l'image de vérification.
- **Preuve** : les tests migrés passent ; un sabotage du code produit (pas du
  harnais) les fait échouer.

## C19 — Démarrage sans erreur de script et scénarios console

- **Constat** : le job `smoke` vérifie que chaque ressource atteint
  « Started resource », mais ne cherche pas `SCRIPT ERROR` ni
  `Error loading script` dans le journal : une ressource peut démarrer et
  planter à la première exécution. Aucun scénario console n'est rejoué
  automatiquement.
- **Faire** : `scripts/verifier-journal-serveur.sh <journal>` (code 1 et
  lignes fautives sur erreur de script, code 2 sur journal absent ou vide),
  testé sur des journaux de fixture et appelé par le job `smoke` ;
  `scripts/scenario.py` qui rejoue un scénario JSON (commandes rcon par
  `scripts/fivem_rcon.py`, lignes de journal attendues, délais) ; deux
  scénarios de référence (lancement d'une manche, redémarrage de
  `gf_attack` sans erreur).
- **Matière brute** : journaux du serveur de développement et de la CI.
- **Outils** : `scripts/fivem_rcon.py`, Docker Compose de développement.
- **Preuve** : le script sort en code 1 sur la fixture fautive et 0 sur la
  propre ; un scénario dont l'attente est fausse échoue.

## C20 — Documentation tenue par les tests

- **Constat** : trois jours après le début du projet, la table des
  ressources de [`architecture.md`](architecture.md) en oublie sept, l'ordre
  de démarrage quatre, [`debug-test.md`](debug-test.md) parle de « six
  ressources », [`docs/README.md`](README.md) n'indexe pas tous les
  documents, et la liste `RESSOURCES_GUNFIGHT` de `tests/test_depot.py`
  oublie cinq ressources ; aucune garde n'empêche un fichier de dépasser
  600 lignes (A6).
- **Faire** : dériver la liste des ressources de `server.cfg` dans les
  tests ; vérifier la table et l'ordre de démarrage de `architecture.md` et
  l'index de `docs/README.md` ; un cliquet de taille (fichiers tolérés avec
  leur taille maximale, qui ne peut que baisser) ; corriger les documents
  périmés que ces tests trouvent.
- **Matière brute** : `server-data/server.cfg`, l'arborescence `docs/`.
- **Outils** : `unittest`.
- **Preuve** : ajouter une ligne `ensure gf_essai` sans documenter la
  ressource, ou allonger un fichier toléré, fait échouer la vérification.

## C21 — Mesure du flux de correctifs

- **Constat** : la part de correctifs (24 pour 25 fonctionnalités sur 60
  commits) a été comptée à la main ; rien ne dit si la méthode la fait
  baisser.
- **Faire** : `scripts/mesurer_flux.py`, en lecture seule sur `git log` :
  nombre de commits par type, rapport correctifs / fonctionnalités,
  correctifs par portée, correctifs qui suivent une fonctionnalité de la
  même portée de moins de N jours (7 par défaut), en texte ou en JSON.
- **Matière brute** : l'historique de `main` (titres en Conventional
  Commits).
- **Outils** : bibliothèque standard Python ; tests sur un dépôt Git
  temporaire.
- **Preuve** : le décompte du script concorde avec `git log` : 25
  fonctionnalités et 24 correctifs sur les 60 commits qui finissent à
  `8efec29` ; 24 et 22 sur les 60 derniers commits au 28 novembre 2026, après
  la fusion de la méthode (#128).

## C22 — Calques NUI possédés par gf_ui

- **Constat** : gf_admin, gf_maps, gf_menu et gf_vehicles émettent
  `gf_lobby:menuOverlay` pour masquer le lobby sous leur page ; le protocole
  n'est écrit nulle part. Quatre correctifs ont porté sur des pages ou
  effets NUI restés affichés ou mal superposés (#18, #63, #65, #117).
- **Faire** : une pile de calques dans gf_ui (`PushLayer`, `PopLayer`,
  événement de changement) ; gf_lobby, gf_menu, gf_maps, gf_admin et
  gf_vehicles l'utilisent ; `gf_lobby:menuOverlay` disparaît.
- **Matière brute** : les appels à `SetNuiFocus` et `menuOverlay` des
  ressources.
- **Outils** : harnais Lua (C18), `scripts/capturer-jeu.ps1`, clic NUI.
- **Preuve** : chaque page ouverte depuis le lobby, depuis le menu pause et
  pendant un match, une capture par situation, avant et après.

## C23 — gf_core sans connaissance des modes

- **Constat** : gf_core appelle `exports.gf_attack:CanJoin()`, expose
  `UpdateRedzoneWeapons` et nomme les ressources des modes dans sa
  configuration ; gf_attack et gf_redzone dépendent de gf_core : cycles au
  fonctionnement. `gf_core/server.lua` fait 913 lignes.
- **Faire** : un point d'enregistrement `RegisterMode(nom, contrat)` dans
  gf_core ; gf_attack et gf_redzone s'y enregistrent ; remplacement de
  `UpdateRedzoneWeapons` par une fonction générique ; registre des contrats
  mis à jour.
- **Matière brute** : `gf_core/server.lua`, `gf_core/config.lua`, les
  appels des modes.
- **Outils** : harnais Lua, scénarios console (C19).
- **Preuve** : le registre ne montre plus de cycle gf_core ↔ mode ;
  rejoindre chaque mode et changer d'arme en Redzone, vus en jeu par un
  humain.

## C24 — Utilitaires communs et données d'armes exposées

- **Constat** : `gf_core/rate_limit.lua` n'est utilisé que par gf_core ;
  gf_lobby, gf_menu et gf_thumbs écrivent chacun leur délai entre deux
  requêtes. Le marqueur de plantage en KVP existe deux fois (gf_core,
  gf_thumbs). gf_inventory lit les `weapons.meta` de gf_weapons avec
  `LoadResourceFile`.
- **Faire** : le limiteur de débit et le marqueur de plantage exposés par
  la plateforme et repris par ces ressources ; gf_weapons expose les
  données d'armes dont gf_inventory a besoin.
- **Matière brute** : les limiteurs existants et leurs valeurs, à conserver.
- **Outils** : harnais Lua (C18).
- **Preuve** : mêmes refus aux mêmes cadences qu'avant (tests T2) ; casier
  et accessoires inchangés en jeu.
