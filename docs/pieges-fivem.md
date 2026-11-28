# Pièges FiveM et méthode d'essai en jeu

Ce document rassemble ce qui a coûté des heures à des agents (et à des
humains) sur ce dépôt, avec l'outil ou la règle qui l'évite. Chaque point a été
observé en jeu ; les chiffres viennent de mesures, pas d'estimations.

À lire avant de toucher au rendu, à la caméra, au ped ou à un natif que tu n'as
jamais appelé.

## 1. La boucle d'essai

Une boucle lente pousse à changer plusieurs choses à la fois, et on ne sait
plus laquelle produit quel effet. Une boucle courte permet **un changement par
essai**.

| Étape | Commande | Durée |
|---|---|---|
| Recharger une ressource | `python scripts/fivem_rcon.py restart gf_lobby` | 1 à 2 s |
| Lire les erreurs du client | `python scripts/journal_client.py --ressource gf_lobby` | immédiat |
| Voir l'écran | `powershell -File scripts\capturer-jeu.ps1` (image dans `%TEMP%\gf-captures`) | 1 s |
| Signature d'un natif | `python scripts/native.py CreateRuntimeTxd` | immédiat |

- `fivem_rcon.py` ne marche qu'avec la surcouche `docker-compose.dev.yml` et
  `TXADMIN=false` (voir [`debug-test.md`](debug-test.md) § 2) : le conteneur
  tire alors un mot de passe rcon aléatoire à chaque démarrage. Un conteneur
  créé avant cette fonctionnalité doit être recréé une fois.
- `restart` d'une ressource la recharge aussi chez les clients connectés (le
  journal client montre un nouveau « Creating script environments for … ») :
  pas besoin de relancer FiveM. Si la NUI garde l'ancien fichier, se
  reconnecter.
- `journal_client.py` sort en code 1 s'il trouve une erreur depuis le dernier
  chargement de la ressource : un agent peut s'en servir comme test.
- `native.py` lit un cache local (`~/.cache/fivem-natives`). Il se remplit une
  fois avec le réseau : `python scripts/native.py --update`. Un agent sans
  réseau demande à l'orchestrateur de le faire.

### Règles

1. **Un changement par essai**, et noter ce qu'on attend avant de regarder.
2. **Critère mesurable** : « les pieds à 80 % de la hauteur d'écran », « aucune
   erreur dans le journal client », pas « ça ressemble à la maquette ».
3. **Mesurer au lieu de deviner** : un `print` temporaire de la valeur en jeu
   (hauteur, coordonnées, retour du natif), puis le retirer.
4. **Trois essais ratés sur la même piste : s'arrêter** et écrire ce qui a été
   essayé, observé et supposé. Ne pas enchaîner un contournement de plus.
5. **Un seul agent par serveur et par client de test.** Deux agents sur le même
   conteneur ou le même FiveM se cassent mutuellement leurs essais (lancement
   d'un mode pendant que l'autre capture, changement de branche sous les pieds
   de l'autre).
6. **`restart` d'une dépendance arrête celles qui en dépendent, sans les
   relancer.** Mesuré le 28 novembre 2026 : après `restart gf_ui` et
   `restart gf_weapons`, `restart gf_thumbs` et `restart gf_inventory`
   répondent « Can't restart a stopped resource ». gf_ui (calques NUI) et
   gf_core sont des dépendances de beaucoup de ressources : pour les essayer,
   recréer le conteneur (`up -d --force-recreate fxserver`) plutôt que les
   redémarrer à chaud, puis vérifier que chaque ressource `ensure gf_` a
   démarré. `python scripts/contrats.py --doc` liste qui dépend de quoi.

## 2. Natifs

- **docs.fivem.net/natives n'est pas lisible par un outil de lecture web** :
  c'est une application JavaScript, chaque URL renvoie la même page. Utiliser
  `scripts/native.py`.
- **Un natif n'est pas « cassé » avant le test minimal** : une ressource de
  test qui appelle ce seul natif et affiche ce qu'il renvoie. Si le test
  minimal marche, l'erreur est dans l'appel.
- **`script error in native 00000000786d8bc3: invalid handle`** : le nombre
  est le hash du natif. `journal_client.py` le traduit
  (`CREATE_RUNTIME_TEXTURE_FROM_IMAGE`) et affiche sa signature ;
  `native.py 00000000786d8bc3` aussi.
- **`pcall` cache la vraie erreur** : afficher le message d'erreur du `pcall`,
  pas un texte générique (« image introuvable » a masqué un `invalid handle`).
- **Un natif qui retourne BOOL rend le nombre `1` pour vrai et `false` pour
  faux en Lua FiveM** : ne jamais comparer son résultat à `true` (une ressource
  qui exigeait `admin == true` refusait le panneau F10 et masquait l'entrée
  ADMIN du menu Échap).
  Tester sa valeur de vérité ou le normaliser en booléen — par exemple
  `core:IsAdmin` renvoie désormais un vrai booléen (`allowed == true or
  allowed == 1`) depuis cette correction, y compris via l'export.
- **`sender` des événements de jeu serveur est une chaîne** :
  `weaponDamageEvent`, `explosionEvent`, `ptFxEvent`… reçoivent l'identifiant
  du joueur en `"3"` et non en `3` (`std::to_string(client->GetNetId())` dans
  `ServerGameState.cpp`), même si la documentation indique `number`. Le
  convertir avec `tonumber` avant d'indexer une table par joueur : sinon la
  recherche rend `nil` sans erreur (tous les tirs entre joueurs étaient
  annulés pour « modes différents »).

## 3. Textures et fond de scène

- **`CreateRuntimeTextureFromImage(txd, nom, fichier)` attend le handle** que
  renvoie `CreateRuntimeTxd(nomDuDictionnaire)`, pas le nom du dictionnaire.
  Même règle pour `CreateRuntimeTextureFromDuiHandle`. Les natifs de dessin
  (`DRAW_TEXTURED_POLY`, `DrawSprite`…) prennent ensuite les **noms**.
  `tests/test_depot.py` refuse un nom passé à la place du handle.
- **L'image doit être déclarée dans `files {}`** du `fxmanifest.lua`, sinon le
  client ne la reçoit pas. `tests/test_depot.py` le vérifie pour toute image
  citée par un fichier client.
- **La NUI est dessinée par-dessus le jeu** : un fond CSS opaque cache le ped.
  Un fond « derrière le personnage » se dessine dans le monde 3D
  (`gf_lobby/backdrop.lua` + `DRAW_TEXTURED_POLY`, voir [`lobby.md`](lobby.md)
  § 8), la NUI garde un fond transparent.
- **`DRAW_TEXTURED_POLY` ne dessine qu'une face** : celle vers laquelle pointe
  `(b - a) × (c - a)`. Dans le mauvais ordre de sommets, rien ne s'affiche et
  aucune erreur n'apparaît.

## 4. Ped et caméra

- **La racine du ped est 1,03 m au-dessus des semelles** (mesuré avec
  `GetEntityHeightAboveGround` sur `mp_m_freemode_01`). Le bas de
  `GetModelDimensions` (-1,30) est 0,27 m **sous** les semelles : s'en servir
  pour poser les pieds les fait flotter.
- **`gf_core` dégèle le ped à la fin de chaque spawn**, puis émet
  `gf_core:spawned`. Une scène dans le vide doit regeler le ped **dans le
  gestionnaire de l'événement**, pas après un `SetTimeout` : sinon il tombe un
  court instant.
- **Calculer la géométrie dans un module pur** (sans natif), testé hors du jeu
  par `tests/lua/*.lua`, comme `gf_lobby/backdrop.lua` et
  `tests/lua/lobby_backdrop.lua`. Le jeu ne sert plus qu'à confirmer, et
  `scripts/verifier.sh` lance ces tests à chaque contrôle.

## 5. Client FiveM sous Windows

- **Lancer le client par l'explorateur** :
  `Start-Process explorer.exe 'fivem://connect/127.0.0.1:30120'`. Un
  lancement direct de `FiveM.exe` depuis un autre programme peut être refusé.
- **Refermer le client qu'on a lancé soi-même** (AGENTS.md § 5) : un agent qui
  a ouvert FiveM sans que l'utilisateur le demande le ferme en fin de tâche
  (`Get-Process -Name 'FiveM*' | Stop-Process -Force`).
- **Chargement bloqué (« Loading game », 64 %)** : fermer FiveM et relancer ;
  aucune modification du serveur n'est en cause.
- **Pas de captures en rafale** : plusieurs `PrintWindow` par seconde font
  clignoter le jeu en noir chez le joueur. `capturer-jeu.ps1` refuse une
  capture moins de 5 s après la précédente.
- **Aucun fichier de travail dans le dépôt** (AGENTS.md § 5) : captures,
  journaux copiés et notes vont hors de l'arbre. `capturer-jeu.ps1` écrit par
  défaut dans `%TEMP%\gf-captures` et refuse une sortie dans le dépôt.
- **Le clavier n'est pas injectable** (voir [`debug-test.md`](debug-test.md)
  § 6) : un agent peut cliquer la NUI, pas conduire ni tirer.
