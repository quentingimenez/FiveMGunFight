# Serveur FiveM Gunfight — Attaque de zone & Redzone

Serveur FiveM « standalone » (sans ESX/QBCore), qui tourne dans **Docker**.
Deux modes de jeu :

- **Attaque de zone** (`/attack`) : 2 équipes. L'une attaque une zone, l'autre la défend.
  Pas de réapparition pendant la manche : **la dernière équipe en vie gagne**.
  Si le temps est écoulé, la défense gagne. Les rôles s'inversent à chaque manche,
  premier à 5 manches gagne le match.
- **Redzone** (`/redzone`) : chacun pour soi. Une seule partie à la fois (10 min).
  On apparaît **à pied** près de la zone, on va au **point véhicule** (marqueur bleu) et on
  appuie sur **E** pour monter dans sa voiture, on roule jusqu'à la zone rouge, on appuie sur
  **F** : la voiture disparaît et on se bat. On ne peut tirer et être touché **que dans la zone**.
  À la mort, retour au point d'apparition, à pied.
  À la fin de la partie : podium, puis nouvelle partie sur la map suivante.

Sur tous les modes : chiffre de dégâts + son à chaque touche, son de kill, messages
**DOUBLÉ / TRIPLÉ / QUADRUPLÉ / QUINTUPLÉ…** et kill feed propre au mode (en haut à droite).

Les maps (redzones et zones d'attaque) se créent **en jeu** avec l'éditeur `/editor`.

À sa première connexion, le joueur crée son personnage puis arrive dans un **lobby
statique** : caméra fixe, personnage visible, escouade de 4 joueurs maximum avec
invitations, barre de modes et bouton **Jouer**. Les onglets **Armes** et
**Personnage** sont déjà présents mais réservés aux prochaines versions. Le détail
de l'interface, du protocole NUI et des règles d'escouade est dans
[docs/lobby.md](docs/lobby.md).

---

## 1. Ce qu'il te faut (une seule fois)

1. **GTA V** sur PC + **FiveM** installé (https://fivem.net).
2. Un compte **Cfx.re** (https://forum.cfx.re).
3. Une **clé de licence serveur** : https://portal.cfx.re → *Server Registration Keys* → crée une clé.
   Garde-la secrète.
4. **Docker Desktop** pour Windows : https://www.docker.com/products/docker-desktop/
   - Pendant l'installation, laisse **« Use WSL 2 »** coché.
   - Redémarre le PC, puis lance Docker Desktop et attends que l'icône baleine soit verte.

> **Plus de 48 joueurs ?** La clé gratuite est limitée à 48 places. Pour 64 joueurs ou plus,
> il faut un abonnement *Element Club* Cfx.re (via https://portal.cfx.re) lié à ton compte.
> Le nombre de places est aussi plafonné par ce que couvre ton abonnement : si FiveM refuse
> le `300` demandé, baisse `MAX_PLAYERS` dans le fichier `.env` à la valeur autorisée.
> Une clé peut être **révoquée à tout moment** si elle circule : ne la mets jamais dans un dépôt,
> une capture d'écran ou un message.

## 2. Premier démarrage

1. Double-clique sur **`start.bat`**.
   La première fois, il crée le fichier **`.env`** et l'ouvre dans le Bloc-notes.
2. Dans `.env`, remplace `change_moi` après `LICENSE_KEY=` par ta clé. Change aussi
   les deux mots de passe `MARIADB_...` (sans caractères `@ : / ? #`). Enregistre et ferme.
3. Double-clique à nouveau sur **`start.bat`**. La première fois, Docker télécharge et
   construit tout (quelques minutes). Les journaux du serveur s'affichent ensuite.
   Quand tu vois `Started resource gf_redzone`, c'est prêt.
4. Lance FiveM, appuie sur **F8** et tape :
   ```
   connect localhost
   ```
5. À la première connexion, crée ton personnage (nom, genre, apparence) : tu arrives
   ensuite dans le lobby. Les connexions suivantes ouvrent directement le lobby.

Pour connaître l'état du serveur à tout moment : double-clic sur **`status.bat`**
(conteneurs, santé de la base, dernières lignes de journal).

`start.bat`, `stop.bat` et `status.bat` combinent déjà le socle et la surcouche
de développement. Pour piloter Docker à la main, garde toujours **les deux**
fichiers (le socle seul ne définit ni image ni build et ne peut pas démarrer) :

```
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f fxserver
docker compose -f docker-compose.yml -f docker-compose.dev.yml down
```

## 3. Devenir administrateur

1. Connecte-toi une fois au serveur. Dans les journaux (fenêtre de `start.bat`) tu verras :
   `[gf_core] TonPseudo connecté. Identifiants : license:xxxx, fivem:1234567, ...`
2. Copie par exemple `fivem:1234567` dans `.env` :
   ```
   ADMIN_IDENTIFIERS=fivem:1234567
   ```
   (plusieurs admins : séparés par des virgules)
3. Relance `start.bat`.

## 4. Commandes en jeu

| Commande | Qui | Effet |
|---|---|---|
| `/lobby` | tous | retour au lobby |
| `/attack` | tous | rejoindre l'Attaque de zone |
| `/redzone` | tous | rejoindre la Redzone |
| `/pos` | tous | affiche ta position (pour créer de nouvelles zones) |
| `/lobbyui` | tous | réaffiche l'interface du lobby si elle a disparu |
| touche **Z** (maintenue) | tous | classement |
| `/startround` | admin | force le lancement d'une manche (marche même seul pour tester) |
| `/endmatch` | admin | arrête le match, scores à zéro |
| `/nextzone` | admin | zone d'attaque suivante (hors match) |
| `/setteam [id] [A\|B]` | admin | change l'équipe d'un joueur |
| `/endgame` | admin | termine la partie Redzone en cours (podium puis map suivante) |
| `/nextmap` | admin | relance une partie Redzone sur la map suivante |
| `/setmode [id] [lobby\|attack\|redzone]` | admin | déplace un joueur |
| `/editor` ou `/maps` | admin | éditeur et liste des maps (voir ci-dessous) |
| `/resetchar [id]` | admin | efface le personnage d'un joueur pour retester la création |
| touche **E** en Redzone | tous | prendre son véhicule sur un point véhicule |
| touche **F** en Redzone | tous | sortir du véhicule (il disparaît) |

> **Tester seul** : `/attack` puis `/startround`. Comme l'autre équipe est vide,
> la manche ne se termine qu'au chrono (mode test).

## 5. Créer des maps en jeu (`/editor`)

Tape `/editor` (admin). Tu passes au lobby et un panneau s'ouvre à gauche avec deux onglets :
**Redzone** et **Attaque de zone**. Choisis « + Nouvelle… » ou « Modifier » sur une map existante.

La caméra passe en **vue du ciel** :
- **Z Q S D** (ou W A S D) : déplacer la caméra, **Maj** pour aller plus vite
- **Molette** : zoomer / dézoomer
- **Clic gauche** : placer · **Clic droit** : retirer le dernier élément

**Redzone** (4 étapes)
1. *Cercle* : clic pour placer le centre ; taille avec le curseur ou **Maj + molette**.
2. *Points d'apparition* (vert) : clic pour chaque point où les joueurs apparaissent **à pied**
   (en dehors du cercle).
3. *Points véhicule* (bleu) : clic pour chaque point où l'on prend sa voiture avec **E**,
   près des points d'apparition. Les voitures sont automatiquement tournées vers la zone.
4. *Nom* puis **Enregistrer**.

**Attaque de zone** (4 étapes)
1. *Délimitation* : clic pour chaque coin de la zone, dans l'ordre. Clique sur le premier point
   (jaune) ou sur « Fermer la zone » pour la refermer.
2. *Départ des attaquants* : un clic, en dehors de la zone.
3. *Départ des défenseurs* : un clic, à l'intérieur de la zone.
4. *Nom* puis **Enregistrer**.

Les maps sont sauvegardées dans `server-data/resources/[gunfight]/gf_maps/data/maps.json`
(pense à le sauvegarder !). Une nouvelle map est utilisée à la **prochaine partie / prochain match**.
Tant qu'aucune map n'est cochée pour un mode, les zones de secours des `config.lua` sont utilisées.

**Maps en jeu / retirées** : dans la liste (`/maps`), chaque map a une **case à cocher**.
Cochée = la map est jouée (et sera proposée au vote plus tard). Décochée = elle reste
sauvegardée mais n'est plus jouée. Le changement compte à partir de la prochaine partie.

## 6. Personnaliser

Les autres réglages sont dans les fichiers `config.lua` :

| Fichier | Contenu |
|---|---|
| `server-data/resources/[gunfight]/gf_core/config.lua` | lobby, armes, gilet, régénération, délai des multi-kills |
| `server-data/resources/[gunfight]/gf_lobby/config.lua` | scène et caméra du lobby, taille d'escouade, catalogue des modes, apparence |
| `server-data/resources/[gunfight]/gf_attack/config.lua` | durées, manches gagnantes, couleurs d'équipes, zones de secours |
| `server-data/resources/[gunfight]/gf_redzone/config.lua` | durée de partie, véhicule, délai de réapparition, zones de secours |

Le volume des sons de touche et de kill se règle en haut de
`gf_ui/html/app.js` (`const VOLUME = 0.35`).

**Appliquer un changement** sans tout redémarrer : double-clic sur **`console.bat`**, puis tape
`restart gf_attack` (ou le nom de la ressource modifiée). Pour quitter la console sans arrêter
le serveur : **Ctrl+P puis Ctrl+Q**.

## 7. Fichiers du projet

```
Dockerfile              image du serveur (Debian + FXServer + server-data par défaut)
docker-compose.yml      socle commun : fxserver + MariaDB (ne se lance jamais seul)
docker-compose.dev.yml  surcouche dev : build local et montage de ./server-data
docker-compose.prod.yml surcouche prod : image GHCR, volumes gunfight-prod-*
docker/entrypoint.sh    démarrage : secrets.cfg, amorçage de maps.json en prod
docker/mariadb.cnf      réglages MariaDB (cache, connexions, encodage)
docker/db/init/         scripts SQL exécutés au tout premier démarrage
.env.example            modèle de configuration (.env = ta vraie config, secrète)
start.bat / stop.bat / status.bat / console.bat
.github/workflows/      intégration continue (qualité, image Docker, test de démarrage)
.github/dependabot.yml  mises à jour des actions et des images Docker
.github/                modèle de pull request, CODEOWNERS, règles de branche
scripts/verifier.sh     contrôles statiques (Lua, JSON, JS, shell, compose)
scripts/sauvegarder.sh  sauvegarde de la production (base, txdata, maps)
scripts/proteger-branche.sh  applique la protection de main (plan GitHub Pro requis)
tests/                  tests automatiques du dépôt (unittest)
docs/                   architecture, lobby, qualité, protection de branche
.githooks/pre-push      refuse un envoi direct sur main
CONTRIBUTING.md         branches, commits, pull requests, revue
SECURITY.md             signalement de faille, gestion des secrets
server-data/
  server.cfg            configuration FiveM
  resources/[cfx-default]/   ressources officielles Cfx.re (spawn, events)
  resources/[gunfight]/
    gf_core     modes, apparition, armes, morts, anti-tir sur coéquipier
    gf_lobby    création de personnage, caméra fixe, escouade, invitations, choix du mode
    gf_attack   mode Attaque de zone
    gf_redzone  mode Redzone
    gf_maps     éditeur de maps en jeu (/editor) + sauvegarde data/maps.json
    gf_ui       interface : HUD, kill feed, dégâts, multi-kills, sons, classement
```

Chaque mode a son propre « monde » (routing bucket) : les joueurs du lobby, de
l'Attaque et de la Redzone ne se voient pas. Le score et les victoires sont décidés
**uniquement par le serveur** ; les tirs sur coéquipiers ou joueurs protégés sont annulés
côté serveur.

## 8. Base de données MariaDB

Le serveur FiveM n'en a pas besoin pour tourner : elle est prête pour la phase 2
(statistiques permanentes via `oxmysql`). Ce qui est déjà en place :

- Base `gunfight`, utilisateur `gunfight` et mot de passe root créés au premier démarrage
  à partir des valeurs `MARIADB_*` de `.env`.
- **Aucun port n'est exposé** : la base n'est joignable que depuis le réseau Docker,
  via le nom d'hôte `mariadb`. Rien à ouvrir sur le pare-feu.
- Réglages dans `docker/mariadb.cnf` : 1 Go de cache InnoDB, 200 connexions, `utf8mb4`.
- Le serveur attend que la base soit **saine** avant de démarrer, et non simplement
  que le conteneur existe : plus de course au démarrage.
- Scripts SQL ajoutés dans `docker/db/init/` : exécutés **une seule fois**, sur une base vide.

Ouvrir la console SQL :

```
docker compose -f docker-compose.yml -f docker-compose.dev.yml exec mariadb mariadb -u gunfight -p gunfight
```

Sauvegarder la base en développement :

```
docker compose -f docker-compose.yml -f docker-compose.dev.yml exec mariadb \
  mariadb-dump -u root -p gunfight > sauvegarde.sql
```

En production, utilise plutôt [`scripts/sauvegarder.sh`](scripts/sauvegarder.sh) :
il sauvegarde la base **et** les volumes `txdata` et `maps` (voir section 12).

## 9. Panneau web txAdmin

txAdmin est **le lanceur** du serveur : au démarrage, FXServer se met en « mode moniteur »,
txAdmin ouvre son panneau web sur le port 40120, puis lance lui-même le serveur de jeu. C'est
le fonctionnement normal de FiveM (le même que sous Windows), il n'y a rien à installer.

1. Ouvre **http://127.0.0.1:40120** (`localhost` peut viser l'IPv6 sur Windows et échouer).
2. Le **code PIN** est affiché à chaque démarrage dans les journaux :
   `docker compose -f docker-compose.yml -f docker-compose.dev.yml logs fxserver | Select-String "PIN"`.
3. Crée ton compte administrateur, puis, à l'étape « Existing Server Data », choisis le
   dossier **`/opt/fivem/server-data`** (les données du serveur : montées depuis le dépôt
   en développement, fournies par l'image en production).
4. Enregistre : le serveur de jeu démarre juste après et apparaît dans
   `docker compose -f docker-compose.yml -f docker-compose.dev.yml logs -f fxserver`.

Ce premier réglage n'est à faire qu'une fois : ensuite txAdmin redémarre le serveur tout seul.

Particularités du mode moniteur :

- le conteneur lance `run.sh +set monitorMode true`, **sans** `+exec server.cfg` : c'est txAdmin
  qui transmet les arguments de lancement (`+exec server.cfg`). Ajouter des arguments au
  conteneur fait planter txAdmin ;
- pour revenir à un démarrage direct (sans txAdmin, utile pour un test rapide), mets
  `TXADMIN=false` dans `.env` : le conteneur lance alors `run.sh +exec server.cfg` ;
- les commandes tapées dans `console.bat` vont au **mode moniteur**, pas au serveur de jeu :
  utilise la console de txAdmin pour les commandes de jeu.

Ses comptes administrateurs et sa configuration sont conservés dans le volume `gunfight_txdata`
en développement (`gunfight-prod-txdata` en production), monté sur `/opt/fivem/txData` :
un `docker compose -f docker-compose.yml -f docker-compose.dev.yml down` ne les efface pas.
Pour repartir de zéro, ajoute `-v` (**attention : efface aussi la base de données et les maps ;
ne le fais jamais sur les volumes de production sans sauvegarde**).

Le port 40120 n'est publié que sur **127.0.0.1** : le panneau reste invisible depuis le
réseau, même sur un VPS. Pour y accéder depuis ton PC quand le serveur tourne ailleurs,
utilise un tunnel SSH (le trafic est chiffré, aucun port de plus à ouvrir) :

```
ssh -L 40120:127.0.0.1:40120 utilisateur@IP_DU_VPS
```

puis ouvre http://127.0.0.1:40120 sur ton PC. Un reverse proxy TLS (Caddy, nginx) est
l'autre option si plusieurs personnes doivent y accéder ; dans les deux cas, garde des
mots de passe forts et active la double authentification de txAdmin.

## 10. Intégration continue (GitHub Actions)

Le dépôt contient deux workflows : **Qualité** tourne sur chaque pull request vers
`main` et chaque envoi sur `main` ; **Image Docker** tourne aux mêmes moments et aussi
sur les tags `v*`, qui publient l'image :

| Workflow | Fichier | Rôle |
|---|---|---|
| **Qualité** | `.github/workflows/qualite.yml` | tests du dépôt + contrôles statiques |
| **Image Docker** | `.github/workflows/docker.yml` | construit ou publie l'image, puis vérifie le démarrage réel |

**Qualité** installe Lua 5.4, Node et shellcheck, puis lance :

1. `bash scripts/verifier.sh` : syntaxe Lua (`luac -p`), JSON valide, JavaScript
   (`node --check`), scripts shell (`sh -n`/`bash -n` + `shellcheck -S error`) et
   validation des **deux** combinaisons Compose (`socle + dev` et `socle + prod`) ;
2. `python3 -m unittest discover -s tests -v` : les tests de `tests/` (manifestes,
   configuration du serveur, maps, documentation, environnements Compose, chaîne CI,
   absence de secrets suivis).

**Image Docker** construit l'image et lance le job **`Vérifier le démarrage des
ressources`** :

- sur une **pull request**, lorsque le secret est disponible, l'image est construite
  localement (sans envoi au registre) puis démarrée avec `TXADMIN=false` ;
- sur `main` et les tags, l'image est publiée sur GitHub Container Registry
  (`ghcr.io/<compte>/fivemgunfight`), puis le job télécharge et démarre cette image.

Le test vérifie que le serveur scanne bien ses ressources et que les six
ressources de jeu `gf_*` démarrent réellement. Il utilise le secret dédié
**`CFX_LICENSE_KEY`** (une clé de test, distincte de celle du serveur de production) :

```
gh secret set CFX_LICENSE_KEY
```

Le secret doit être configuré **au niveau du dépôt** pour être visible sur les
pull requests.

Sans ce secret (PR d'un fork ou de Dependabot, secret non configuré), le job
affiche une note et saute les étapes de démarrage : il reste vert, et les autres
vérifications continuent de bloquer la fusion.

Les actions GitHub sont **épinglées par un SHA de commit** et les images Docker par un
**digest** : une mise à jour ne peut pas arriver par surprise. `.github/dependabot.yml`
ouvre chaque semaine une PR pour les actions et pour les images ; les versions de
MariaDB ≥ 11.5 sont volontairement ignorées et restent une décision manuelle.

### Ces contrôles bloquent-ils le merge ?

Oui, **dès que la protection de `main` est active** : les trois vérifications
(« Qualité du dépôt », « Construire et publier l'image » et « Vérifier le démarrage des
ressources ») sont déclarées comme *checks obligatoires*, avec une approbation et la
résolution des conversations. Tant que le dépôt reste privé sur le plan gratuit de
GitHub, la protection n'est pas disponible : c'est le seul point à activer, voir
[docs/protection-branche.md](docs/protection-branche.md).

## 11. Contribuer au code

Le dépôt n'accepte plus de modifications directes sur `main` : tout passe par une
**branche** et une **pull request** relue par au moins une personne.

1. Crée ta branche depuis `main` : `git switch -c feat/ma-fonctionnalite`.
2. Fais tes modifications, puis lance les contrôles en local :
   ```
   bash scripts/verifier.sh
   python -m unittest discover -s tests -v
   ```
3. Commit avec un message conventionnel (`feat: …`, `fix: …`, `docs: …`).
4. Envoie la branche et ouvre la pull request : `gh pr create --fill`.
5. La CI doit être verte, une revue est approuvée, puis la PR est fusionnée en
   *squash* et la branche supprimée.

Un hook fourni refuse un envoi direct sur `main` :

```
git config core.hooksPath .githooks
```

Pour contourner volontairement ce hook en cas d'urgence : `GF_ALLOW_MAIN=1 git push`.

Détails complets : [CONTRIBUTING.md](CONTRIBUTING.md) et [docs/](docs/README.md).

## 12. Mettre le serveur en ligne (VPS)

La production **ne clone pas le dépôt et ne construit rien** : elle télécharge l'image
publiée sur GitHub Container Registry (GHCR) par la CI. Le dossier de déploiement ne
contient que :

- `docker-compose.yml` et `docker-compose.prod.yml` ;
- `.env.example` (modèle) et `.env` (configuration, dont `IMAGE_REF`) ;
- `docker/` (`mariadb.cnf` et `db/init/`, montés par le socle) ;
- `scripts/sauvegarder.sh` (facultatif, mais recommandé).

`server-data/` n'est **pas** copié : il vient de l'image. Seul le volume des maps est
conservé séparément pour que les maps créées en jeu survivent aux mises à jour.

1. Loue un VPS Linux (Ubuntu/Debian) avec disque NVMe. Ordre de grandeur :
   **4 vCPU / 8 Go** pour une trentaine de joueurs simultanés, **8 vCPU / 16 Go**
   pour viser plusieurs centaines de places.
2. Installe Docker : `curl -fsSL https://get.docker.com | sh`
3. Crée un dossier de déploiement (par exemple `/opt/gunfight`) et copies-y les fichiers
   listés ci-dessus depuis ton poste (WinSCP, `scp`). Git n'est pas nécessaire sur le VPS.
4. L'image GHCR est **privée** : connecte-toi avec un token GitHub limité à
   `read:packages` (Settings → Developer settings → Personal access tokens).
   ```
   echo "$GHCR_TOKEN" | docker login ghcr.io -u TON_COMPTE --password-stdin
   ```
   Ne mets jamais ce token dans `.env`, dans une commande enregistrée ou dans le dépôt.
5. `cp .env.example .env`, remplis `LICENSE_KEY`, `MAX_PLAYERS` et les mots de passe
   `MARIADB_*`, puis décommente `IMAGE_REF` et mets le tag publié, par exemple :
   ```
   IMAGE_REF=ghcr.io/compte/fivemgunfight:v1.2.3
   ```
6. Télécharge l'image et démarre la pile :
   ```
   docker compose -f docker-compose.yml -f docker-compose.prod.yml pull
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
   docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
   docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f fxserver
   ```
7. Ouvre seulement les ports **30120 TCP et UDP** dans le pare-feu du VPS : c'est tout
   pour le jeu. txAdmin (40120) n'écoute que sur la boucle locale ; pour y accéder, vois
   le tunnel SSH de la section 9.
8. Les joueurs se connectent avec `connect IP_DU_VPS` (ou via la liste des serveurs FiveM).

Les volumes de production s'appellent **`gunfight-prod-txdata`** (comptes txAdmin),
**`gunfight-prod-dbdata`** (base MariaDB) et **`gunfight-prod-maps`** (`maps.json`). Ils
sont distincts de ceux du développement (`gunfight_txdata`, `gunfight_dbdata`) : lancer
le mauvais fichier Compose ne peut donc pas écrire dans l'autre environnement.

Au premier démarrage, la base est initialisée par MariaDB et Docker recopie le contenu
de l'image dans le volume `maps` neuf. Si le volume existait déjà mais sans `maps.json`
(volume préparé à la main, ancien déploiement), `docker/entrypoint.sh` copie le modèle
fourni par l'image (amorçage automatique, activé par `GF_SEED_MAPS: "true"` dans la
surcouche prod). Ne supprime pas ces volumes : `down -v` efface la base, txAdmin et les
maps. Si tu reprends des données d'un ancien déploiement, copie-les dans les volumes,
conteneurs arrêtés, **avant** le premier démarrage.

**Mise à jour** : quand un tag `v*` est publié, la CI produit l'image correspondante.
Change `IMAGE_REF` dans `.env`, puis `pull` et `up -d` avec la surcouche prod. Aucun
build n'est nécessaire.

**Retour arrière** : remets l'ancien tag dans `IMAGE_REF`, puis `pull` et `up -d` avec la
surcouche prod. Les volumes ne sont pas supprimés par ce changement d'image.

### Sauvegarde et restauration

Depuis le dossier de déploiement (avec `.env` et les deux fichiers Compose) :

```
bash scripts/sauvegarder.sh
```

Le script crée `backups/<horodatage>/` avec trois archives : `base.sql.gz` (dump
MariaDB), `txdata.tar.gz` (volume txAdmin) et `maps.tar.gz` (données `gf_maps`), puis
purge les sauvegardes de plus de 14 jours. Il utilise la surcouche prod et exige
`IMAGE_REF`.

Pour restaurer, arrête d'abord `fxserver` (pour que la base et les maps ne bougent plus) :

```
docker compose -f docker-compose.yml -f docker-compose.prod.yml stop fxserver
gunzip -c backups/<horodatage>/base.sql.gz | \
  docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T mariadb \
  sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"'
```

Pour `txdata` et `maps`, extrais chaque archive dans un conteneur jetable avec le volume
correspondant monté (`tar -xzf ... -C /data`), puis relance `up -d`. Ces commandes de
restauration ne sont pas automatisées : répète-les sur une copie avant d'en dépendre en
production.

## 13. Problèmes fréquents

| Symptôme | Solution |
|---|---|
| `ERREUR : LICENSE_KEY est vide` | remplis `LICENSE_KEY` dans `.env` |
| `Docker n'est pas démarré` | lance Docker Desktop, attends l'icône verte |
| Erreur de licence / « too many slots » | `MAX_PLAYERS` dépasse la limite de ta clé (48 sans Element Club) |
| `Could not authenticate server license key` | clé invalide, révoquée ou mal copiée (`\r` : réenregistre `.env` en UTF-8 sans retour chariot) |
| Ressource `sessionmanager` / `hardcap` introuvable | n'existe plus dans les versions récentes de FXServer : les lignes ont été retirées de `server.cfg`, ne pas les remettre |
| `docker compose up` échoue : « service fxserver has neither an image nor a build context » | le socle seul ne démarre pas : ajoute `-f docker-compose.dev.yml` (local) ou `-f docker-compose.prod.yml` (VPS) ; `start.bat` le fait déjà |
| `IMAGE_REF` manquante ou vide (prod) | renseigne `IMAGE_REF=ghcr.io/...:tag` dans `.env` ; en développement, utilise la surcouche dev, qui n'en a pas besoin |
| `mariadb` reste `unhealthy` | regarde `docker compose -f docker-compose.yml -f docker-compose.dev.yml logs mariadb` ; si le disque est plein ou le volume corrompu, `down -v` puis relance (**efface les données**) |
| Impossible de se connecter | vérifie dans les journaux qu'il n'y a pas d'erreur rouge ; essaie `connect 127.0.0.1` |
| Le port 30120 est déjà utilisé | un autre serveur FiveM tourne sur la machine : arrête-le |
| Le mode ne démarre pas | il faut 2 joueurs (un par équipe) ou `/startround` en admin |
| L'interface du lobby ne s'affiche pas | tape `/lobbyui` ; vérifie que `gf_lobby` est démarrée et que `data/characters.json` est accessible |
| Le personnage n'apparaît pas / est invisible | attends la fin du fondu de connexion ; vérifie que `gf_core` et `gf_lobby` sont démarrées dans cet ordre |
| Je veux recommencer la création de personnage | un admin lance `/resetchar [id]` ; le joueur retourne à l'écran de création |
| `fxserver` reste `unhealthy` | normal en mode moniteur tant que txAdmin n'est pas configuré : termine l'assistant du panneau, le healthcheck passe ensuite au vert |
| Comptes txAdmin, base ou maps vides en production | vérifie `docker volume ls` : la prod utilise `gunfight-prod-*`, pas `gunfight_txdata`/`gunfight_dbdata` ; un `up` avec la surcouche dev ne voit pas les données de prod |
| `denied` ou `manifest unknown` au `pull` | l'image GHCR est privée : reconnecte-toi avec un token `read:packages` (`docker login ghcr.io`) |
| Le smoke est « sauté » sur une PR | normal sans secret `CFX_LICENSE_KEY` (PR de fork ou Dependabot) : la CI le signale sans échouer |

## Pour la suite (phase 2)

- **Vote de map** : en fin de partie, vote entre 9 maps tirées parmi les maps **cochées**
  (Redzone et Attaque de zone). La case à cocher de `/maps` sert déjà à choisir les maps votables.
- **Escouade persistante** : le lobby regroupe déjà jusqu'à 4 joueurs et lance le mode pour
  tous, mais l'escouade est dissoute au lancement. La prochaine étape est de la conserver
  entre les parties et de placer ses membres dans la même équipe en Attaque de zone.
- **Personnalisation** : les onglets Armes et Personnage du lobby sont des placeholders.
  L'onglet Personnage remplacera la génération actuelle (nom, genre, carnation, style) par
  un vrai éditeur de vêtements et de visage ; l'onglet Armes ajoutera les finitions et
  accessoires. Les points d'extension sont décrits dans [docs/lobby.md](docs/lobby.md).
- `gf_stats` : statistiques permanentes (kills, victoires) dans MariaDB avec **oxmysql**
  — la base est déjà prête dans `docker-compose.yml`, la chaîne de connexion
  (`mysql_connection_string`) est déjà générée par `docker/entrypoint.sh`.
- Un anti-cheat dédié est conseillé avant d'ouvrir au grand public.
