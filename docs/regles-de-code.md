# Règles de code

Ce que tout changement respecte, qu'il soit écrit par un humain ou par un
agent. L'objectif tient en trois phrases : sur un serveur de jeu de tir, le
client ne décide de rien ; le code se relit et se teste encore dans six mois ;
la preuve qu'un résultat est juste ne repose pas sur la parole de son auteur.

- [`CONTRIBUTING.md`](../CONTRIBUTING.md) renvoie ici pour le fond.
  [`AGENTS.md`](../AGENTS.md) fixe le déroulé : branche, exécution locale,
  accord, pull request, fusion.
- **Doit** : bloquant en revue. **Devrait** : un écart est possible s'il est
  justifié dans la PR.
- Chaque règle dit comment elle se vérifie : **CI** (automatique), **revue**
  (lecture du diff), **en jeu** (exécution locale, preuve jointe à la PR).
- Le code actuel n'est pas encore conforme partout. Les écarts connus et leur
  plan sont dans [`chantiers-techniques.md`](chantiers-techniques.md). Un
  changement qui touche une zone en écart ne l'aggrave pas ; il ne la corrige
  que si c'est son sujet.
- Les outils et pièges du test en jeu sont dans
  [`pieges-fivem.md`](pieges-fivem.md) ; ce document ne les répète pas.

## 1. Autorité du serveur et anti-triche

Le joueur contrôle entièrement son client. Tout ce qui en vient peut être
forgé : événements réseau, callbacks NUI, événements de jeu, state bags.

**S1 — Le client propose, le serveur décide.** Score, kills, dégâts, vie,
inventaire, monnaies, équipe et phase de manche : la valeur qui fait foi vit
dans une table du serveur. *Doit. Revue.*

**S2 — Chaque événement réseau entrant est validé.** Un handler
`RegisterNetEvent` côté serveur, dans cet ordre :

1. copie `source` dans une locale dès sa première ligne (la globale change
   après un `Wait` ou un appel asynchrone) ;
2. vérifie le type et les bornes de chaque argument (`type`, `math.type`,
   longueur d'une chaîne, nombre d'entrées d'une table) ;
3. vérifie que l'état serveur du joueur l'autorise : mode, phase, équipe,
   vivant, droits ;
4. passe par le limiteur de `gf_core/rate_limit.lua` ;
5. journalise le refus (S9).

`gf_attack:useItem` est le modèle des points 1 à 3. *Doit. Revue, et un test
Lua par règle de validation.*

**S3 — Une décision lit l'état tenu par le serveur.** Les tables du serveur
(`Modes`, `S.team`, `S.alive`…) font foi, pas une valeur que le client peut
réécrire. Un state bag (`Player(src).state`) informe les clients ; il ne sert
de vérité côté serveur que s'il est prouvé que le client ne peut pas l'écrire
(chantier C4). *Doit. Revue.*

**S4 — Un événement de jeu est une affirmation du client.**
`weaponDamageEvent`, `explosionEvent`, `giveWeaponEvent`, `removeWeaponEvent`,
`startProjectileEvent` et `ptFxEvent` partent du client. Le serveur les
valide (arme du loadout, dégât et cadence plausibles, distance) ou les annule
par `CancelEvent()`, et journalise. *Doit. Test Lua du module de validation ;
en jeu avec deux clients.*

**S5 — Les entités réseau sont créées par le serveur.** Véhicules et objets
partagés naissent côté serveur (`CreateVehicleServerSetter`…). Le client ne
crée que des entités locales, non réseau : aperçus, studio photo de
`gf_thumbs`. C'est la condition de `sv_entityLockdown strict` (C5). *Doit pour
tout nouveau code. Revue.*

**S6 — Un identifiant de joueur reçu n'est pas cru sur parole.** Un id dans
un payload (invitation, cible) est vérifié : le joueur existe
(`GetPlayerName`), il est dans le même mode ou la même escouade, l'émetteur a
le droit d'agir sur lui. *Doit. Revue, test Lua.*

**S7 — Les droits admin se vérifient côté serveur.** Par
`IsPlayerAceAllowed(src, 'gunfight.admin')` ou par une commande restreinte,
jamais par un drapeau venu du client ou de la NUI. *Doit. Revue.*

**S8 — Les convars de FXServer durcissent le serveur.**
`sv_scriptHookAllowed 0` est en place. `sv_pureLevel`, `sv_enforceGameBuild`,
`sv_entityLockdown` et `sv_filterRequestControl` sont à poser (C5), puis
exigés par `tests/test_depot.py`. *Doit. CI.*

**S9 — Tout refus est journalisé.** Sans journal, un bug et un tricheur ne se
distinguent pas. Une ligne préfixée `[ressource]`, avec la raison et le joueur
(nom et numéro de session, jamais l'identifiant de licence), limitée en débit
comme `Config.RefusLogRateLimit`. *Doit. Revue.*

## 2. Architecture et lisibilité

**A1 — Une règle de jeu est un module pur.** Pas de native ; temps,
coordonnées et état arrivent en paramètre ; un test dans `tests/lua/`.
`server.lua` et `client.lua` restent une couche mince qui appelle les natives
puis le module. Modèles : `gf_core/validation.lua`, `gf_core/rate_limit.lua`,
`gf_lobby/backdrop.lua`. *Doit pour toute règle nouvelle. Revue, test Lua.*

**A2 — Une ressource, une responsabilité.** Les ressources communiquent par
des exports et des événements documentés dans
[`evenements-serveur.md`](evenements-serveur.md). Aucune ne lit l'état
interne d'une autre. *Doit. Revue.*

**A3 — Pas de valeur magique.** Durées, distances, quantités et probabilités
vont dans `config.lua`, avec leur unité dans le nom ou le commentaire
(`KillCreditWindow` en secondes, `MaxKillDistance` en mètres). Une valeur
d'équilibrage dit d'où elle vient (V8). *Doit. Revue.*

**A4 — Les délais se mesurent avec `GetGameTimer()`.** Millisecondes, horloge
monotone, disponible côté client et serveur. `os.time()` (seconde entière,
qui suit l'horloge du système) ne sert qu'à dater. *Doit pour tout nouveau
code. Revue.*

**A5 — Pas de globale.** `local` partout ; `luacheck` refuse les globales
inconnues. *Doit. CI.*

**A6 — Un fichier qui dépasse 600 lignes environ se découpe.** Le découpage
suit les responsabilités (règles pures, réseau, NUI) et se fait dans une PR
`refactor` à part, quand on doit travailler dans ce fichier. *Devrait. Revue.*

**A7 — Une erreur ne disparaît pas.** `pcall` seulement autour d'un appel qui
peut légitimement échouer (export d'une ressource arrêtée), et le message
d'erreur est journalisé, pas remplacé par un texte générique. *Doit. Revue.*

## 3. Performance

**P1 — `Wait(0)` est réservé au travail par image.** Dessin, contrôles à
bloquer, marqueurs. Le reste attend selon l'état (par exemple 500 ms au repos,
0 seulement près de la zone) ou réagit à un événement. *Doit. Revue,
`resmon`.*

**P2 — Toute nouvelle boucle par image est mesurée.** `resmon` côté client,
avant et après, chiffres dans la PR. Au repos, une ressource reste proche de
0 ms. *Doit. En jeu.*

**P3 — Rien de lent dans un chemin chaud du serveur.** Pas de requête SQL ni
d'écriture de fichier à chaque touche ou à chaque tick : on accumule en
mémoire et on écrit par lots, de façon asynchrone. *Doit. Revue, profileur
FXServer.*

**P4 — Le réseau est un budget.** Pas d'envoi à tous les joueurs à chaque
tick ; un envoi groupé par changement d'état ; les gros contenus (listes,
images) par `TriggerLatentClientEvent`. *Doit. Revue, `netgraph` en jeu.*

**P5 — La charge se mesure, elle ne se suppose pas.** Un changement qui
ajoute du travail par joueur au serveur de match se juge avec le profileur
FXServer et le graphe de performances de txAdmin (C8). *Devrait. En jeu.*

## 4. Interface NUI

**N1 — Aucune donnée externe dans `innerHTML`.** Les noms de joueurs sont
choisis par les joueurs : `textContent` ou création de nœuds. `innerHTML`
reste possible pour des constantes du code, comme les icônes de
`gf_lobby/html/js/app.js`. *Doit. Revue.*

**N2 — Un callback NUI répond toujours.** Chaque `RegisterNUICallback`
appelle `cb` sur tous ses chemins, erreur comprise, sinon la page attend sans
fin (`tests/lua/lobby_nui_callbacks.lua`). *Doit. Test Lua.*

**N3 — Ce qui vient de la NUI est une entrée client.** Le Lua client relaie
au serveur, qui applique S2. *Doit. Revue.*

**N4 — Tout est embarqué.** Polices, images et scripts sont dans la
ressource, sans CDN : l'interface marche sans accès extérieur et n'expose pas
l'adresse IP des joueurs à un tiers. *Doit. Revue.*

## 5. Données et base

**D1 — Requêtes paramétrées.** Des `?` et un tableau de paramètres
d'oxmysql, jamais de concaténation (c'est déjà le cas dans `gf_stats`).
*Doit. Revue.*

**D2 — Les faits bruts d'abord.** On enregistre l'événement (touche, kill,
fin de manche) avec son horodatage ; compteurs et classements en dérivent. Un
agrégat seul ne s'audite pas et ne se corrige pas (C2). *Doit pour toute
nouvelle donnée de jeu. Revue.*

**D3 — Une opération sur monnaie ou inventaire est une transaction.** Une
transaction SQL, idempotente (identifiant d'opération unique), inscrite dans
une table d'historique : rejouer la même demande ne crédite pas deux fois.
*Doit. Test d'intégration sur MariaDB.*

**D4 — Le schéma évolue par migrations.** Fichiers numérotés dans
`gf_db/migrations/`, déclarés dans `gf_db/migrations.lua`, appliqués au
démarrage par `gf_db` sur une base existante, avec `gf_schema_version` pour
enregistrer version et somme : `docker/db/init/` ne s'exécute que sur un volume
vide et ne contient plus le schéma (C12). Une migration appliquée n'est jamais
modifiée et reste idempotente. *Doit avant la première table nouvelle. CI.*

**D5 — Données personnelles.** Les identifiants de licence ne vont ni dans le
dépôt, ni dans un journal public, ni dans un artefact de CI ; un joueur peut
être supprimé sur demande. *Doit. CI (`DepotGit`, gitleaks) et revue.*

## 6. Données non fiables

Un pack de modèle (dossier, `dlc.rpf`, archive), un fichier importé ou un JSON
fourni par un tiers est hostile jusqu'à preuve du contraire.

**U1 — Jamais exécuté, jamais commité tel quel.** Voir
[`AGENTS.md`](../AGENTS.md) § 9. *Doit. Revue.*

**U2 — La lecture tient dans une fonction pure.** Le lecteur (RPF, `.meta`,
archive) n'utilise ni réseau ni processus ; tailles et nombres d'entrées sont
plafonnés avant lecture ; un chemin extrait qui sort du dossier cible (`..`,
chemin absolu) est refusé. *Doit. Revue, tests.*

**U3 — Propriétés et fuzzing.** Tests de propriétés (Hypothesis) et une
cible de fuzz (atheris, sous Linux, lancée chaque nuit) visent ces fonctions :
aucune entrée ne les fait échouer autrement que par une erreur prévue (C11).
*Doit. CI.*

## 7. Exploitation et chaîne d'approvisionnement

Le détail est dans [`qualite.md`](qualite.md), [`architecture.md`](architecture.md)
et [`../SECURITY.md`](../SECURITY.md).

**E1 — Les secrets restent hors du dépôt**, des journaux et des artefacts.
*Doit. CI (gitleaks).*

**E2 — Tout est épinglé.** Actions par SHA, images par digest, FXServer par
URL et SHA256. *Doit. CI (`ChaineCI`).*

**E3 — Une dépendance recopiée est suivie.** `oxmysql` est recopié dans
`server-data/resources/[standalone]/` : Dependabot ne le voit pas. Sa version
et sa source sont notées, ses avis de sécurité surveillés, sa mise à jour
passe par une PR dédiée (C13). *Doit. Revue.*

**E4 — Après un déploiement, on regarde la santé.** Avertissements « hitch »
du journal FXServer, graphe de txAdmin, redémarrages ; procédures dans
[`runbooks/`](runbooks/incident.md). *Doit. En production.*

## 8. Tests et preuve

**V1 — Une seule commande rejoue la CI.** Mêmes commandes, mêmes options ; un
outil absent fait échouer la commande au lieu d'être ignoré (C10).
Aujourd'hui : `bash scripts/verifier-docker.sh`, la même commande en local et
en CI, dans l'image de vérification. *Doit. CI.*

**V2 — Le test d'abord.** Écrit, vu en échec pour la bonne raison, puis
l'implémentation. *Doit. Revue.*

**V3 — Sabotage.** Pour chaque nouveau test : casser exprès l'invariant dans
le code du produit (jamais dans le harnais de test), voir le test échouer,
annuler. Un test qui ne peut pas échouer ne compte pas. *Doit. Revue (la PR
dit ce qui a été cassé).*

**V4 — Mutation des lignes changées avant « terminé ».** Python : mutmut,
sous WSL ou Linux. JavaScript de la NUI : Stryker. Lua : à la main, en
inversant une à une chaque comparaison, chaque opérateur booléen et chaque
valeur retournée des lignes changées. Chaque mutant survivant est tué par un
nouveau test ou justifié comme équivalent dans la PR. *Doit. Revue.*

**V5 — Les règles à états se testent par propriétés.** Manche, équilibrage
des équipes, file d'attente : des suites d'événements aléatoires à graine
fixe (graine affichée en cas d'échec) contre des invariants (C7). *Doit pour
toute machine à états nouvelle. CI.*

**V6 — Exécuté en local, preuve consignée.** [`AGENTS.md`](../AGENTS.md)
§ 4.3 et [`pieges-fivem.md`](pieges-fivem.md) : commande lancée, résultat
observable, critère mesurable. *Doit. PR.*

**V7 — Plusieurs joueurs, vrai réseau.** Ce qui met en jeu deux joueurs (tir,
kill, équipe, escouade) se teste avec deux clients (`FiveM.exe -cl2`) ; ce
qui dépend du temps, sous latence et perte simulées (clumsy). Un agent ne
peut ni conduire ni tirer ([`debug-test.md`](debug-test.md) § 6) : ces essais
demandent un humain à la manette (C8). *Doit pour le combat. En jeu.*

**V8 — Un chiffre vient d'une mesure ou d'une source primaire.** Délai,
distance, dégât, probabilité : la PR dit d'où il vient (§ 10). *Doit. Revue.*

**V9 — Le « tout est vert » d'un auteur ne suffit pas.** Le relecteur, ou
l'orchestrateur pour un agent, relance la vérification et relit le diff.
*Doit. Revue.*

## 9. Ce qui prouve un résultat, hors de son auteur

| Domaine | Ce qui tranche |
|---|---|
| Dégâts et armes | le nombre de balles mesuré en jeu à distance fixe est celui calculé depuis `weapons.meta` |
| Kill, équipe, protection | un second client : ce que voit la victime correspond à la ligne du journal serveur |
| Verrous de la plateforme | FXServer refuse lui-même : client aux fichiers modifiés, entité créée par un client |
| Performance | profileur FXServer, graphe de txAdmin, aucun « hitch warning » sur un match complet |
| Équilibre des maps | taux de victoire de l'attaque par map, avec son intervalle de confiance (C9) |
| Rendu du lobby | écart mesuré (SSIM) à une image de référence, sous un seuil fixé (C14) |
| Ensemble | un playtest planifié et enregistré, et la relecture d'un CODEOWNER |

## 10. Sources primaires

Du plus sûr au moins sûr :

1. une mesure en jeu : `print` temporaire, journal, capture ;
2. le code source de FiveM (`citizenfx/fivem` sur GitHub) : ce que le serveur
   fait vraiment d'un événement ou d'une native ;
3. les fichiers du jeu (`weapons.meta`…, ceux de base et les dernières
   surcharges des DLC), lus avec CodeWalker ou OpenIV ; ils ne sont jamais
   commités, seules les valeurs utilisées le sont ;
4. les scripts du jeu décompilés : comment Rockstar appelle une native ;
5. les bases de natives (`scripts/native.py`) : signatures fiables,
   descriptions rédigées par la communauté ;
6. forums et wikis : des pistes à vérifier, jamais une preuve.

## 11. Checklist de revue

- [ ] S1 à S9 : aucune décision côté client ; chaque entrée validée, chaque
      refus journalisé.
- [ ] A1 : une règle nouvelle est un module pur testé.
- [ ] P1, P2 : pas de nouvelle boucle par image sans mesure `resmon`.
- [ ] N1 : pas d'`innerHTML` avec une donnée externe.
- [ ] D1 à D4 : requêtes paramétrées, transactions, migration fournie.
- [ ] V2 à V4 : test vu en échec, sabotage, mutation des lignes changées.
- [ ] V6 à V8 : preuve locale et origine des chiffres dans la PR.
