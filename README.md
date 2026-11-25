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

Pour connaître l'état du serveur à tout moment : double-clic sur **`status.bat`**
(conteneurs, santé de la base, dernières lignes de journal).

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
| touche **Z** (maintenue) | tous | classement |
| `/startround` | admin | force le lancement d'une manche (marche même seul pour tester) |
| `/endmatch` | admin | arrête le match, scores à zéro |
| `/nextzone` | admin | zone d'attaque suivante (hors match) |
| `/setteam [id] [A\|B]` | admin | change l'équipe d'un joueur |
| `/endgame` | admin | termine la partie Redzone en cours (podium puis map suivante) |
| `/nextmap` | admin | relance une partie Redzone sur la map suivante |
| `/setmode [id] [lobby\|attack\|redzone]` | admin | déplace un joueur |
| `/editor` ou `/maps` | admin | éditeur et liste des maps (voir ci-dessous) |
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
| `server-data/resources/[gunfight]/gf_attack/config.lua` | durées, manches gagnantes, couleurs d'équipes, zones de secours |
| `server-data/resources/[gunfight]/gf_redzone/config.lua` | durée de partie, véhicule, délai de réapparition, zones de secours |

Le volume des sons de touche et de kill se règle en haut de
`gf_ui/html/app.js` (`const VOLUME = 0.35`).

**Appliquer un changement** sans tout redémarrer : double-clic sur **`console.bat`**, puis tape
`restart gf_attack` (ou le nom de la ressource modifiée). Pour quitter la console sans arrêter
le serveur : **Ctrl+P puis Ctrl+Q**.

## 7. Fichiers du projet

```
Dockerfile              image du serveur (Debian + FXServer Linux officiel)
docker-compose.yml      serveur FiveM + base de données MariaDB
docker/entrypoint.sh    démarrage : crée secrets.cfg à partir de .env
docker/mariadb.cnf      réglages MariaDB (cache, connexions, encodage)
docker/db/init/         scripts SQL exécutés au tout premier démarrage
.env.example            modèle de configuration (.env = ta vraie config, secrète)
start.bat / stop.bat / status.bat / console.bat
.github/workflows/      intégration continue (qualité, image Docker, test de démarrage)
.github/                modèle de pull request, CODEOWNERS, règles de branche
scripts/verifier.sh     contrôles statiques (Lua, JSON, JS, shell, compose)
scripts/proteger-branche.sh  applique la protection de main (plan GitHub Pro requis)
tests/                  tests automatiques du dépôt (unittest)
docs/                   architecture, qualité, protection de branche
.githooks/pre-push      refuse un envoi direct sur main
CONTRIBUTING.md         branches, commits, pull requests, revue
SECURITY.md             signalement de faille, gestion des secrets
server-data/
  server.cfg            configuration FiveM
  resources/[cfx-default]/   ressources officielles Cfx.re (spawn, events)
  resources/[gunfight]/
    gf_core     modes, apparition, armes, morts, anti-tir sur coéquipier
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
docker compose exec mariadb mariadb -u gunfight -p gunfight
```

Sauvegarder la base :

```
docker compose exec mariadb mariadb-dump -u root -p gunfight > sauvegarde.sql
```

## 9. Panneau web txAdmin

txAdmin est **le lanceur** du serveur : au démarrage, FXServer se met en « mode moniteur »,
txAdmin ouvre son panneau web sur le port 40120, puis lance lui-même le serveur de jeu. C'est
le fonctionnement normal de FiveM (le même que sous Windows), il n'y a rien à installer.

1. Ouvre **http://127.0.0.1:40120** (`localhost` peut viser l'IPv6 sur Windows et échouer).
2. Le **code PIN** est affiché à chaque démarrage dans les journaux :
   `docker compose logs fxserver | Select-String "PIN"`.
3. Crée ton compte administrateur, puis, à l'étape « Existing Server Data », choisis le
   dossier **`/opt/fivem/server-data`** (c'est le volume de ce dépôt, avec ton `server.cfg`).
4. Enregistre : le serveur de jeu démarre juste après et apparaît dans `docker compose logs -f`.

Ce premier réglage n'est à faire qu'une fois : ensuite txAdmin redémarre le serveur tout seul.

Particularités du mode moniteur :

- le conteneur lance `run.sh +set monitorMode true`, **sans** `+exec server.cfg` : c'est txAdmin
  qui transmet les arguments de lancement (`+exec server.cfg`). Ajouter des arguments au
  conteneur fait planter txAdmin ;
- pour revenir à un démarrage direct (sans txAdmin, utile pour un test rapide), mets
  `TXADMIN=false` dans `.env` : le conteneur lance alors `run.sh +exec server.cfg` ;
- les commandes tapées dans `console.bat` vont au **mode moniteur**, pas au serveur de jeu :
  utilise la console de txAdmin pour les commandes de jeu.

Ses comptes administrateurs et sa configuration sont conservés dans le volume `txdata`
(`/opt/fivem/txData`) : un `docker compose down` ne les efface pas. Pour repartir de zéro,
utiliser `docker compose down -v` (**attention : efface aussi la base de données**).

txAdmin donne aussi un accès à distance (HTTP) aux personnes autorisées : garde des mots de
passe forts et n'ouvre le port 40120 que si tu en as besoin.

## 10. Intégration continue (GitHub Actions)

Le dépôt contient deux workflows, déclenchés à chaque **pull request** vers `main` et à
chaque envoi sur `main` :

| Workflow | Fichier | Rôle |
|---|---|---|
| **Qualité** | `.github/workflows/qualite.yml` | tests du dépôt + contrôles statiques |
| **Image Docker** | `.github/workflows/docker.yml` | construit l'image et vérifie que le serveur démarre |

**Qualité** installe Lua 5.4, Node et shellcheck, puis lance :

1. `bash scripts/verifier.sh` : syntaxe Lua (`luac -p`), JSON valide, JavaScript
   (`node --check`), scripts shell (`sh -n`/`bash -n` + `shellcheck -S error`) et
   `docker compose config` ;
2. `python3 -m unittest discover -s tests -v` : les tests de `tests/` (manifestes,
   configuration du serveur, maps, documentation, absence de secrets suivis).

**Image Docker** construit l'image, démarre la pile complète avec une clé de licence
fournie par le secret **`CFX_LICENSE_KEY`** (avec `TXADMIN=false`, pour tester le serveur
de jeu directement), vérifie que les 12 ressources sont trouvées (`Found 12 resources`) et
que les cinq ressources de jeu démarrent, puis envoie l'image sur GitHub Container
Registry (`ghcr.io/<compte>/fivem-gunfight`).

Le test de démarrage est ignoré si le secret n'est pas configuré. Pour l'ajouter :

```
gh secret set CFX_LICENSE_KEY
```

Le vrai serveur de jeu, lui, tourne avec la clé de ton fichier `.env` : celle du secret
sert uniquement au test automatique.

### Ces contrôles bloquent-ils le merge ?

Oui, **dès que la protection de `main` est active** : les deux vérifications
(« Qualité du dépôt » et « Construire et publier l'image ») sont déclarées comme *checks
obligatoires*, avec une approbation et la résolution des conversations. Tant que le dépôt
reste privé sur le plan gratuit de GitHub, la protection n'est pas disponible : c'est le
seul point à activer, voir [docs/protection-branche.md](docs/protection-branche.md).

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

1. Loue un VPS Linux (Ubuntu/Debian) avec disque NVMe. Ordre de grandeur :
   **4 vCPU / 8 Go** pour une trentaine de joueurs simultanés, **8 vCPU / 16 Go**
   pour viser plusieurs centaines de places.
2. Installe Docker : `curl -fsSL https://get.docker.com | sh`
3. Copie ce dossier sur le VPS (WinSCP, `scp` ou ce dépôt Git **privé**).
4. Sur le VPS : `cp .env.example .env`, remplis `.env`, puis :
   ```
   docker compose up -d --build
   docker compose logs -f fxserver
   ```
5. Ouvre les ports **30120 TCP et UDP** dans le pare-feu du VPS
   (et 40120 TCP seulement si tu accèdes à txAdmin à distance).
6. Les joueurs se connectent avec `connect IP_DU_VPS` (ou via la liste des serveurs FiveM).

Mettre à jour FXServer : `docker compose build --no-cache` puis `docker compose up -d`.

## 13. Problèmes fréquents

| Symptôme | Solution |
|---|---|
| `ERREUR : LICENSE_KEY est vide` | remplis `LICENSE_KEY` dans `.env` |
| `Docker n'est pas démarré` | lance Docker Desktop, attends l'icône verte |
| Erreur de licence / « too many slots » | `MAX_PLAYERS` dépasse la limite de ta clé (48 sans Element Club) |
| `Could not authenticate server license key` | clé invalide, révoquée ou mal copiée (`\r` : réenregistre `.env` en UTF-8 sans retour chariot) |
| Ressource `sessionmanager` / `hardcap` introuvable | n'existe plus dans les versions récentes de FXServer : les lignes ont été retirées de `server.cfg`, ne pas les remettre |
| `mariadb` reste `unhealthy` | regarde `docker compose logs mariadb` ; si le disque est plein ou le volume corrompu, `docker compose down -v` puis relance |
| Impossible de se connecter | vérifie dans les journaux qu'il n'y a pas d'erreur rouge ; essaie `connect 127.0.0.1` |
| Le port 30120 est déjà utilisé | un autre serveur FiveM tourne sur la machine : arrête-le |
| Le mode ne démarre pas | il faut 2 joueurs (un par équipe) ou `/startround` en admin |

## Pour la suite (phase 2)

- **Vote de map** : en fin de partie, vote entre 9 maps tirées parmi les maps **cochées**
  (Redzone et Attaque de zone). La case à cocher de `/maps` sert déjà à choisir les maps votables.
- **Menu de lobby permanent** (style Fortnite) : choix du mode, groupe d'amis / invitations,
  lancement de partie. Les commandes `/attack`, `/redzone`, `/lobby` seront remplacées par ce
  menu, qui passera par `exports.gf_core:SetMode` (déjà prévu pour ça). Un groupe d'amis
  devra être placé dans la même équipe en Attaque de zone.


- `gf_stats` : statistiques permanentes (kills, victoires) dans MariaDB avec **oxmysql**
  — la base est déjà prête dans `docker-compose.yml`, la chaîne de connexion
  (`mysql_connection_string`) est déjà générée par `docker/entrypoint.sh`.
- Un anti-cheat dédié est conseillé avant d'ouvrir au grand public.
