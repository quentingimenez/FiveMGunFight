# Accès, débogage et tests

Ce document rassemble les **points d'accès** au serveur local et le **déroulé
de débogage/test** pour les développeurs et les agents. Il complète le
[`README`](../README.md) (installation, commandes en jeu, dépannage) et
[`qualite.md`](qualite.md) (contrôles et CI) ; il ne remplace pas les
procédures de production.

> Toutes les commandes Compose de ce document utilisent **les deux fichiers** :
> `docker-compose.yml` (socle) et `docker-compose.dev.yml` (développement).
> Le socle seul ne définit ni image ni build et ne peut pas démarrer. En
> production, remplace la surcouche par `docker-compose.prod.yml`.
>
> Dans les commandes abrégées ci-dessous, `...` remplace ces deux options `-f`.

## 1. Accès rapides

| Accès | Adresse ou commande | Où c'est configuré | Remarque |
|---|---|---|---|
| Jeu (FiveM) | `connect 127.0.0.1:30120` dans la console **F8** | `server-data/server.cfg` (`endpoint_add_*`) | TCP **et** UDP ; `localhost` peut viser l'IPv6 et échouer |
| État HTTP | `http://127.0.0.1:30120/info.json`, `/dynamic.json`, `/players.json` | — | ne publie pas la sortie brute : elle contient la configuration et des identifiants |
| Panneau txAdmin | `http://127.0.0.1:40120` | `TXADMIN=true` (défaut) | publié uniquement sur la boucle locale ; voir section 9 du README |
| Journaux du serveur | `docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f fxserver` | — | `--since 10m`, `--tail 200` pour cibler |
| Console du serveur | `console.bat` ou `docker attach gunfight-fxserver` | `stdin_open`/`tty` du service | `Ctrl+P` puis `Ctrl+Q` pour se détacher sans arrêter |
| MariaDB | `docker compose ... exec mariadb mariadb -u gunfight -p gunfight` | `.env` (`MARIADB_*`) | aucun port exposé sur l'hôte ; la base n'est pas encore utilisée par le jeu |
| Fichiers montés | `server-data/` | `docker-compose.dev.yml` | les modifications Lua/NUI sont prises en compte sans reconstruire l'image |
| Personnages | `server-data/resources/[gunfight]/gf_lobby/data/characters.json` | `gf_lobby/config.lua` | ignoré par Git ; `/resetchar` pour repartir de zéro |
| Maps | `server-data/resources/[gunfight]/gf_maps/data/maps.json` | `gf_maps/server.lua` | suivi par Git ; sauvegarde-le après une création volontaire |
| Console de jeu | **F8** (client) et **T** (chat) | client FiveM | `connect`, `quit`, `reconnect` ; commandes `/...` dans le chat |
| Éditeur de maps | `/editor` (admin) | `gf_maps` | voir section 5 du README |
| Tests locaux | `bash scripts/verifier.sh` et `python -m unittest discover -s tests -v` | `scripts/`, `tests/` | outils absents = étape ignorée en local, la CI tranche |

Les scripts `start.bat`, `stop.bat`, `status.bat` et `console.bat` enveloppent
ces commandes sur Windows. `status.bat` affiche l'état des conteneurs et les
dernières lignes de journal ; c'est le premier réflexe avant de chercher.

## 2. Démarrer une session de test

### Démarrage normal

```powershell
# Windows
start.bat
```

```bash
# équivalent manuel, bash / WSL
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f fxserver
```

Attends les lignes `Server license key authentication succeeded` puis
`Started resource gf_*`. Le conteneur passe `healthy` quand
`http://127.0.0.1:30120/dynamic.json` répond.

### Démarrage direct, sans txAdmin (test rapide)

Le panneau txAdmin est utile pour la production, mais il ajoute un mode
« moniteur » et peut gêner un test local. Pour démarrer directement le serveur
de jeu :

```powershell
$env:TXADMIN='false'
$env:MAX_PLAYERS='48'
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

```bash
# bash / WSL
TXADMIN=false MAX_PLAYERS=48 \
  docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

`MAX_PLAYERS=48` correspond à la limite de la clé gratuite ; au-delà,
l'entrypoint affiche un avertissement et la clé peut refuser des joueurs.
`TXADMIN=false` lance `run.sh +exec server.cfg` : le serveur de jeu est
directement dans la console, mais **le panneau 40120 n'est pas disponible**.

### Panne connue de txAdmin en développement (`EACCES`)

Avec `TXADMIN=true` et la surcouche dev telle qu'elle est aujourd'hui, txAdmin
peut échouer au démarrage avec :

```text
FATAL ERROR: E2004 ... EACCES: permission denied, mkdir '/opt/fivem/txData/default'
FATAL ERROR: E5110 ... ENOENT ... /opt/fivem/txData/default/config.json
```

Cause : la surcouche dev force `user: "0:0"` tandis que le socle retire toutes
les capacités (`cap_drop: ALL`). Le volume `gunfight_txdata` appartient à
l'utilisateur `fivem` (UID 10001) en mode 755 : un processus root **sans**
`CAP_DAC_OVERRIDE` ne peut pas y écrire. Ce n'est pas un bug du jeu.

Contournement pour tester le jeu : `TXADMIN=false` (ci-dessus), ou préparer un
volume inscriptible. Un correctif propre (faire tourner la dev avec
l'utilisateur `fivem`, ou ajouter `cap_add: [DAC_OVERRIDE]` dans la seule
surcouche dev) mérite une **PR dédiée** : ne le bricole pas dans une PR de
gameplay, et ne touche pas aux volumes de production.

### Vérifier que le serveur est prêt

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml ps
curl -fsS http://127.0.0.1:30120/info.json
curl -fsS http://127.0.0.1:30120/dynamic.json
```

`info.json` doit répondre en 200 et annoncer le bon `sv_maxclients`.
`dynamic.json` est aussi la sonde de santé du conteneur. Si les deux
échouent, regarde `logs fxserver` avant de toucher au client.

## 3. Devenir administrateur pour tester

Les commandes de test (`/startround`, `/editor`, `/setteam`, `/resetchar`…)
sont réservées au groupe `admin`, déclaré dans `server-data/server.cfg`.

1. Connecte-toi une fois au serveur.
2. Cherche dans les journaux la ligne d'identification du joueur :
   ```text
   [gf_core] TonPseudo connecté. Identifiants : license:xxxx, fivem:1234567, ...
   ```
3. Renseigne `.env` avec un ou plusieurs identifiants séparés par des virgules :
   ```dotenv
   ADMIN_IDENTIFIERS=license:xxxx,fivem:1234567
   ```
4. Recrée le conteneur pour régénérer `server-data/secrets.cfg` :
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --force-recreate fxserver
   ```

L'entrypoint écrit `add_principal identifier.<identifiant> group.admin` dans
`secrets.cfg`. Préfère `license:` ou `fivem:` à `ip:` : l'adresse vue par le
serveur est celle de la passerelle Docker (souvent `172.19.0.1`), pas celle de
ton PC, et elle peut changer.

Pour une session ponctuelle, tu peux passer la variable sans modifier `.env` :

```powershell
$env:ADMIN_IDENTIFIERS='license:xxxx'
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --force-recreate fxserver
```

```bash
ADMIN_IDENTIFIERS='license:xxxx' \
  docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --force-recreate fxserver
```

`ADMIN_IDENTIFIERS` est une **donnée sensible** : ne la mets pas dans un
rapport, une capture ou un message public. Utilise les placeholders `xxxx` dans
la documentation et les exemples.

## 4. Scénarios de test

### Lobby et personnage

1. Première connexion : l'écran de création doit apparaître (nom, genre,
   carnation, style) puis le lobby avec le personnage visible.
2. Vérifie la caméra fixe, l'escouade (1/4), la barre de modes et le bouton
   **JOUER**. Les modes **Gun Game** et **TDM** doivent afficher « bientôt ».
3. Pour recommencer la création : un admin lance `/resetchar [id]`.
4. Si l'interface a disparu : `/lobbyui`.
5. Détails du protocole et des règles : [`lobby.md`](lobby.md).

### Redzone (testable en solo)

1. `/redzone`, ou sélectionne **Redzone** dans le lobby puis **JOUER**.
2. Approche-toi du **marqueur bleu** et appuie sur **E** : la Sultan doit
   apparaître et le personnage monter dedans. Le prompt E doit disparaître.
3. Roule jusqu'au cercle rouge de la minimap, puis **F** pour sortir (la
   voiture disparaît).
4. Tire uniquement **dans** la zone ; hors zone, le tir est bloqué et le joueur
   subit des dégâts.
5. Meurs : réapparition à pied après 3 s. Vérifie KILLS / MORTS / K/D et le
   classement avec **Z**.
6. En admin : `/endgame` termine la partie (podium puis map suivante),
   `/nextmap` relance sur la map suivante.

Valeurs par défaut : `GameDuration=600` (10 min), `RespawnDelay=3`, véhicule
`sultan` (`gf_redzone/config.lua`).

### Attaque de zone (seul ou à plusieurs)

1. En admin, `/startround` force une manche avec les joueurs déjà dans le mode.
   En solo, la manche se termine au chrono : pour la laisser défiler, sors de
   la zone (le chrono se met en pause tant qu'un attaquant vivant est dedans).
2. Déroulé : **10 s** de choix des armes (2 armes), **15 s** de placement,
   **180 s** de combat. Les camps s'inversent entre les manches ; la première
   équipe à **2 manches** gagne.
3. Commandes utiles : `/endmatch` (arrêt, scores à zéro), `/nextzone` (zone
   suivante hors match), `/setteam [id] [A|B]`, `/setmode [id] [lobby|attack|redzone]`.
4. Un match normal démarre à **20 joueurs** et en prend **30** au plus
   (`gf_lobby/config.lua`, `gf_attack/config.lua`). `/startround` est le
   contournement prévu pour tester seul.

### Cartes et éditeur

1. `/editor` (admin) : choisis **Redzone** ou **Attaque de zone**, puis
   « Nouvelle… » ou « Modifier ».
2. Place les éléments (cercle, apparitions, points véhicule pour la Redzone ;
   délimitation, départs attaquants/défenseurs pour l'Attaque), nomme et
   enregistre.
3. `/maps` liste les maps et permet de les cocher/décocher. Une map cochée est
   jouée à la prochaine partie ; une map décochée reste sauvegardée.
4. Le résultat est écrit dans `server-data/resources/[gunfight]/gf_maps/data/maps.json`.
   C'est un fichier **suivi par Git** : relis le diff avant de le committer, et
   évite de l'éditer à la main pendant que le serveur tourne.

### Persistance et remise à zéro

- En développement, les personnages sont dans `gf_lobby/data/characters.json`
  (ignoré par Git) ; ils survivent à un redémarrage du conteneur.
- Les maps sont dans `gf_maps/data/maps.json` (suivi par Git).
- `docker compose ... down` conserve les volumes nommés.
- `docker compose ... down -v` **supprime** la base MariaDB et le volume
  txAdmin (et, en production, le volume des maps) : ne l'utilise pas sans
  sauvegarde. En développement, `server-data/` est un bind mount et n'est pas
  supprimé par `-v`.

### Contrôles avant de proposer une modification

```bash
bash scripts/verifier.sh
python -m unittest discover -s tests -v
```

En local, `luac`, `shellcheck` ou `luacheck` peuvent manquer : le script
l'annonce et continue, la CI les exécute. Pour une modification de documentation
seule, déclare « sans exécution : documentation », vérifie les liens et lance
quand même `scripts/verifier.sh`. Voir [`qualite.md`](qualite.md) pour le détail
des contrôles et [`CONTRIBUTING.md`](../CONTRIBUTING.md) pour la boucle de PR.

## 5. Débogage

### Journaux et santé

```bash
# suivre le serveur
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f fxserver

# les 200 dernières lignes, ou depuis 10 minutes
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs --tail 200 fxserver
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs --since 10m fxserver

# la base
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs mariadb
```

Les ressources préfixent leurs messages : `[gf_core]`, `[gf_lobby]`,
`[gf_attack]`, `[gf_redzone]`, `[gf_maps]`, `[gf_ui]`. Cherche `Started resource
gf_` pour confirmer le démarrage, puis les lignes `^1` (erreurs) et `SCRIPT
ERROR` pour les erreurs Lua.

`docker compose ... ps` indique `healthy`/`unhealthy`. En mode moniteur
(`TXADMIN=true`), `fxserver` reste `unhealthy` tant que l'assistant txAdmin n'a
pas été terminé : c'est attendu, pas une panne du jeu.

### Console et rechargement

- En mode direct (`TXADMIN=false`), `console.bat` attache la console du serveur
  de jeu : `restart gf_attack`, `ensure gf_redzone`, `stop`, `quit`.
- En mode moniteur (`TXADMIN=true`), `console.bat` parle au **mode moniteur**,
  pas au serveur de jeu : utilise la console de txAdmin pour les commandes de
  jeu (voir section 9 du README).
- Après une modification Lua ou NUI sous `server-data/`, `restart gf_<nom>`
  suffit le plus souvent. Si l'interface NUI garde l'ancien fichier,
  reconnecte-toi ou redémarre `gf_lobby`.
- Après une modification de `Dockerfile`, `docker/entrypoint.sh`,
  `docker-compose*.yml` ou `server.cfg`, il faut recréer :
  ```bash
  docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
  ```
- `Ctrl+P` puis `Ctrl+Q` détache la console **sans** arrêter le serveur. Ne
  ferme pas la fenêtre brutalement si tu veux garder les logs.

### Erreurs fréquentes

| Symptôme | Piste |
|---|---|
| `LICENSE_KEY est vide` / licence invalide | `.env` : clé absente, révoquée ou avec un `\r` ; réenregistre en UTF-8 sans retour chariot |
| `MAX_PLAYERS` refusé / « too many slots » | la clé gratuite est limitée à 48 places ; baisse `MAX_PLAYERS` |
| `service fxserver has neither an image nor a build context` | il manque la surcouche dev (ou prod) : garde les deux fichiers Compose |
| `fxserver` reste `unhealthy` | normal en mode moniteur avant la configuration txAdmin ; sinon regarde `logs fxserver` |
| Port 30120 déjà utilisé | un autre serveur FiveM tourne sur la machine |
| Le mode ne démarre pas | 20 joueurs dans la recherche, ou `/startround` en admin |
| L'interface du lobby ne s'affiche pas | `/lobbyui` ; vérifie que `gf_lobby` est démarrée et que `characters.json` est accessible |
| Le personnage est invisible | attends la fin du fondu ; vérifie l'ordre `gf_core` puis `gf_lobby` |
| `E2004 ... EACCES ... txData` | panne dev de txAdmin décrite en section 2 ; `TXADMIN=false` pour tester le jeu |
| `denied` / `manifest unknown` au `pull` | image GHCR privée : `docker login ghcr.io` avec un token `read:packages` |

La section 13 du README contient la table de dépannage complète.

### Faux positifs connus

- Le prompt **« Appuie sur E pour prendre ton véhicule »** reste affiché tant
  que le joueur est **à pied** : c'est normal. Il doit disparaître une fois
  dans la Sultan. La minimap montre la flèche « joueur » dans ce cas.
- Le **marqueur bleu** du point véhicule est un `DrawMarker` 3D : il paraît
  énorme quand on est tout près. C'est esthétique, pas un bug de gameplay.
- Le libellé **« Fin de la partie dans »** est une étiquette au-dessus du
  chrono ; le temps réel est le chiffre du HUD, pas un second texte.
- En Redzone, une partie peut démarrer **seule** : c'est prévu pour les tests.
- Les **touches synthétiques** (voir section 6) ne sont pas prises en compte
  par FiveM : ce n'est pas un bug du serveur.

## 6. Débogage assisté par un agent (Windows)

Cette section décrit une technique locale utile aux agents et aux développeurs
qui doivent **observer** le client sans jouer à la main. Elle ne fait pas
partie du serveur et n'ajoute aucune dépendance au projet.

- **Capturer la fenêtre du jeu**, même en arrière-plan : `PrintWindow(hwnd,
  hdc, 2)` avec le drapeau `PW_RENDERFULLCONTENT`. `CopyFromScreen` ne capture
  que le premier plan : si la GUI de l'agent est devant, on obtient le bureau,
  pas le jeu.
- **Cliquer les boutons NUI** : `SetCursorPos` puis `mouse_event` avec
  `LEFTDOWN`/`LEFTUP`. Le bouton **JOUER** du lobby répond à un clic
  synthétique ; les coordonnées sont en pixels écran, à recalculer si la
  résolution ou l'échelle change.
- **Le clavier n'est pas injectable en pratique** : FiveM ignore
  `keybd_event` ; dans nos essais, **E**, **T**, **W**, etc. ne font rien. Un
  agent peut donc observer, capturer et cliquer les menus, mais **pas conduire
  ni tirer** :
  pour un test de gameplay, c'est un humain qui joue, l'agent lit les logs et
  les captures.
- **Lire les logs** : `docker compose ... logs -f fxserver` et la console
  donnent l'état serveur ; les captures donnent le HUD, le chrono, les scores.
- **Confidentialité** : ne publie jamais une capture du bureau (GUI de l'agent,
  notifications, comptes, e-mail). Recadre sur la fenêtre du jeu et vérifie
  qu'aucune donnée personnelle n'est visible. Les captures de jeu seules
  suffisent pour un rapport.

## 7. Sécurité et données sensibles

- Ne commite **jamais** `.env`, `server-data/secrets.cfg`,
  `server-data/cache/` ni la clé `CFX_LICENSE_KEY`. `.env` et `secrets.cfg`
  contiennent la licence, les mots de passe MariaDB et les identifiants admin.
- `secrets.cfg` est généré par l'entrypoint (mode 600) ; ne le copie pas dans
  un ticket, une PR ou une capture.
- `players.json`, les logs de connexion et les captures peuvent contenir des
  **identifiants license/fivem** : masque-les avant de partager.
- txAdmin n'écoute que sur `127.0.0.1:40120` : pour un accès distant, tunnel SSH
  ou reverse proxy TLS, mot de passe fort et double authentification.
- MariaDB n'expose aucun port sur l'hôte : ne publie pas 3306 pour « aller plus
  vite ».
- `docker compose ... down -v` efface les volumes ; sauvegarde avant, et ne
  touche jamais aux volumes `gunfight-prod-*` depuis un poste de dev.

## 8. Checklist de test avant une PR

- [ ] `bash scripts/verifier.sh` passe (ou seules les étapes « ignoré » locales
      restent, la CI tranche).
- [ ] `python -m unittest discover -s tests -v` passe.
- [ ] Le serveur démarre et les six ressources `gf_*` sont lancées.
- [ ] `http://127.0.0.1:30120/info.json` répond en 200.
- [ ] Le lobby s'affiche, le personnage est visible, **JOUER** lance le mode.
- [ ] Le scénario touché est reproduit : Redzone, Attaque `/startround`,
      éditeur de maps, commande admin…
- [ ] Aucun secret dans le diff : `git diff --cached` ne contient ni `.env`, ni
      `secrets.cfg`, ni clé de licence.
- [ ] La PR décrit **ce qui a été exécuté** et **comment le refaire** (section
      « Comment tester » du modèle de PR).
