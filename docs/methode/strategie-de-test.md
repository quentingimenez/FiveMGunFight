# Stratégie de test

Ce document dit **quel niveau de vérification** chaque type de changement
exige. Les règles de fond (test d'abord, sabotage, mutation, propriétés,
deux clients) sont dans [`regles-de-code.md`](../regles-de-code.md) § 8 ;
ce que la CI lance est dans [`qualite.md`](../qualite.md) ; comment lancer
le serveur et observer le jeu est dans [`debug-test.md`](../debug-test.md)
et [`pieges-fivem.md`](../pieges-fivem.md).

## Les niveaux T0 à T6

Du moins cher au plus cher. Un défaut se teste au **niveau le plus bas qui
peut le détecter** : une règle de manche se teste en T1, pas en jouant.

| Niveau | Ce qui est vérifié | Outil | Qui le lance | Automatique |
|---|---|---|---|---|
| **T0 statique** | syntaxe, lint, secrets, workflows, Dockerfile | `luac -p`, `luacheck`, `node --check`, `shellcheck`, `ruff`, `actionlint`, `hadolint`, `gitleaks` | `bash scripts/verifier-docker.sh`, CI | oui |
| **T1 module pur** | une règle sans natif : entrées → sorties ou liste d'effets ; machines à états par propriétés à graine fixe (V5) | `tests/lua/*.lua` (`dofile` + dépendances injectées), `node --test tests/js/`, `unittest` | idem | oui |
| **T2 ressource en bac à sable** | un vrai `server.lua` ou `client.lua` chargé dans un faux FiveM : handlers, exports, refus, journalisation | `tests/lua/*_test.lua` avec le harnais partagé `tests/lua/lib/fivem.lua` (C18) | idem | oui |
| **T3 contrats et structure** | ce qui relie les ressources et le dépôt : événements déclarés, exports fournis, manifestes, `server.cfg`, migrations, documentation synchronisée | `tests/test_depot.py`, `tests/test_evenements.py`, registre des contrats `tests/test_contrats.py` (C17) | idem | oui |
| **T4 serveur réel** | les ressources démarrent sans `SCRIPT ERROR` ; une commande console produit la ligne de journal attendue | job `smoke` de la CI ; en local `docker compose … up -d --force-recreate fxserver`, `scripts/fivem_rcon.py`, `scripts/verifier-journal-serveur.sh`, scénarios `scripts/scenario.py` (C19) | agent | en partie |
| **T5 client unique** | une page NUI s'ouvre au bon calque, se ferme, et son ouverture change le rendu ; journal client sans erreur | `scripts/verifier_nui.py` (passerelle `gf_testbridge`, `scripts/capturer-jeu.ps1`, `scripts/comparer_rendu.py`, `scripts/journal_client.py`) | agent | oui, client installé |
| **T6 humain** | tir, kill, conduite, deux joueurs, latence | `FiveM.exe -cl2`, clumsy | **humain** ; l'agent prépare le scénario et le demande | non |

Le T5 est **automatisé** par `scripts/verifier_nui.py` : le script démarre la
passerelle de test `gf_testbridge` (développement uniquement), lance le client
FiveM si besoin, ouvre puis ferme chaque page par rcon, capture l'écran ouvert
et fermé, compare les deux images (la page doit modifier le rendu) et lit le
journal client. Il referme le client s'il l'a lancé. Ce niveau n'est pas dans
la CI (le runner n'a ni client ni GPU) : il se lance en local avant la porte
G3, et sa sortie va dans la section « Tests et preuve » de la PR. Ne demande
jamais à l'utilisateur un test que ce script sait faire.

Un agent ne peut ni tirer ni conduire ([`debug-test.md`](../debug-test.md)
§ 6). Ce que le T5 automatisé ne couvre pas (une page qui n'apparaît qu'en
match, un clic précis dans une page, une action qui exige deux joueurs) reste
**T6** : l'agent écrit alors le scénario pas à pas (qui fait quoi, ce qu'on doit
voir, quelle ligne de journal le confirme) et le demande à l'utilisateur
**avant** la porte G3, jamais après la fusion.

## Matrice : ce qui est exigé

« Terminé » pour un type de changement = tous les niveaux cochés passés et
consignés dans la PR. Un changement qui couvre plusieurs lignes cumule leurs
exigences.

| Type de changement | T0 | T1 | T2 | T3 | T4 | T5 | T6 |
|---|---|---|---|---|---|---|---|
| Règle de jeu (manche, file, équipes, score, dégâts) | ✔ | ✔ propriétés si états | ✔ coque | si contrat | ✔ | — | ✔ si combat ou 2 joueurs |
| Lua serveur (handler, export, commande admin) | ✔ | si logique | ✔ | ✔ | ✔ | — | si 2 joueurs |
| Lua client (HUD, caméra, ped, contrôles) | ✔ | module pur pour le calcul | si handler | si contrat | ✔ | ✔ | si combat |
| Page NUI (HTML, JS, CSS) | ✔ | ✔ JS pur | — | calque NUI | ✔ | ✔ capture avant/après | — |
| Contrat entre ressources (export, `gf:*`, state bag, calque) | ✔ | — | ✔ des deux côtés | ✔ **obligatoire** | ✔ | si client | — |
| Base de données (table, migration, requête) | ✔ | ✔ plan de migration | ✔ | migrations numérotées | ✔ migration jouée sur une base existante | — | — |
| Modèle 3D, arme, véhicule (pack tiers) | ✔ | — | — | ✔ déclarations | ✔ sans « oversized » ni erreur | ✔ chargement en jeu | si l'arme tire |
| Docker, Compose, `server.cfg`, entrypoint | ✔ | — | — | ✔ | ✔ build et démarrage réels | — | — |
| Script ou outil (`scripts/`) | ✔ | ✔ cas nominal **et** cas d'erreur | — | — | si le script parle au serveur | — | — |
| CI, workflows | ✔ `actionlint` | ✔ test qui verrouille la règle | — | ✔ | run réel observé sur la PR | — | — |
| Documentation seule | ✔ | — | — | liens | — | — | — |

## Règles d'écriture

- **Le test d'abord** (V2) : écrit, lancé, vu rouge **pour la raison
  attendue** (le message d'échec le dit), puis le code.
- **Un correctif apporte son test de régression**, vu rouge sur le code
  d'avant. Sans test possible (rendu, natif), la PR dit pourquoi et donne la
  mesure T5 ou T6 qui le remplace.
- **Sabotage** (V3) : pour chaque test ajouté, casser l'invariant dans le
  code du produit, voir le test échouer, annuler. La PR dit ce qui a été
  cassé.
- **Mutation des lignes changées** (V4) : chaque comparaison, opérateur
  booléen et valeur retournée inversés un à un ; un mutant qui survit est
  tué par un test ou justifié.
- **Un test touche le comportement, pas l'implémentation** : il appelle
  l'export, déclenche l'événement, lit l'effet. Il ne vérifie pas qu'une
  fonction interne a été appelée.
- **Pas de test qui ne peut pas échouer** : pas d'assertion sur une valeur
  recopiée du code, pas de test qui saute en silence quand un outil manque
  (`GF_OUTILS_OBLIGATOIRES=1` en CI).
- **Un test faux se corrige dans une PR à part, expliquée**
  ([`CONTRIBUTING.md`](../../CONTRIBUTING.md)) ; on ne le supprime jamais
  pour faire passer une PR.

## Où mettre un nouveau test

| Le défaut est… | Le test va dans… |
|---|---|
| une règle sans natif | `tests/lua/<ressource>_<sujet>_test.lua` (T1), module pur à côté de la ressource |
| un handler, un export, une commande | `tests/lua/<ressource>_<sujet>_test.lua` qui charge le vrai fichier (T2) |
| un lien entre ressources, une déclaration, un fichier de config | `tests/test_depot.py`, `tests/test_evenements.py` ou le test du registre (T3) |
| une fonction JS de page NUI | `tests/js/<sujet>.test.js` (T1), la fonction exportée par un module sans DOM |
| un script Python ou shell | `tests/test_<script>.py` |
| un démarrage, une commande console | scénario rcon (T4, C19) |
| une page NUI qui s'ouvre ou se ferme | `scripts/verifier_nui.py` (T5) : la page est ajoutée à sa liste et la passerelle rapporte son calque |
| un rendu | `scripts/verifier_nui.py` et `scripts/comparer_rendu.py` (T5, C14) ; capture de référence si le seuil de similarité ne suffit pas |

## Les cas difficiles

- **Natif jamais utilisé** : un test minimal qui l'appelle seul, en jeu,
  avant de l'utiliser (`scripts/native.py` pour la signature). Un natif
  n'est jamais déclaré « cassé » sans ce test
  ([`pieges-fivem.md`](../pieges-fivem.md)).
- **Timing réseau** (mort annoncée avant que la vie soit à 0, #70) : le
  module pur reçoit le temps en paramètre, et le test rejoue l'ordre des
  événements observé dans le journal.
- **Calques NUI** : la matrice exige T5 pour toute page qui prend le focus.
  `scripts/verifier_nui.py` couvre l'ouverture et la fermeture de chaque page
  connue depuis un client connecté ; une page qui ne s'ouvre qu'en match, ou
  une action qui exige un clic précis, se vérifie en T6 (scénario écrit) ou en
  étendant la passerelle. Une feuille de calque qui reste empilée après la
  fermeture de la page fait échouer le T5 (`calques=0` attendu).
- **Pack tiers** : ce qu'il contient est une donnée, jamais exécutée ; le
  modèle se charge en jeu (T5) avant la fusion.
