# Serveur FiveM Gunfight — Attaque de zone & Redzone

Serveur FiveM « standalone » (sans ESX/QBCore), qui tourne dans **Docker**.
Deux modes de jeu :

- **Attaque de zone** (`/attack`) : 2 équipes. L'une attaque une zone, l'autre la défend.
  Pas de réapparition pendant la manche : **la dernière équipe en vie gagne**.
  Si le temps est écoulé, la défense gagne. Les rôles s'inversent à chaque manche,
  premier à 5 manches gagne le match.
- **Redzone** (`/redzone`) : chacun pour soi dans une zone rouge, réapparition rapide,
  seuls les kills **dans** la zone comptent, classement en direct, la zone change toutes les 15 min.

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
| `/rotatezone` | admin | change la zone de la Redzone |
| `/resetredzone` | admin | remet le classement Redzone à zéro |
| `/setmode [id] [lobby\|attack\|redzone]` | admin | déplace un joueur |

> **Tester seul** : `/attack` puis `/startround`. Comme l'autre équipe est vide,
> la manche ne se termine qu'au chrono (mode test).

## 5. Personnaliser

Tout se règle dans les fichiers `config.lua`, sans toucher au reste :

| Fichier | Contenu |
|---|---|
| `server-data/resources/[gunfight]/gf_core/config.lua` | lobby, armes, gilet, régénération |
| `server-data/resources/[gunfight]/gf_attack/config.lua` | zones d'attaque, durées, manches gagnantes, couleurs d'équipes |
| `server-data/resources/[gunfight]/gf_redzone/config.lua` | zones redzone, délai de réapparition, rotation |

**Créer une zone** : va à l'endroit voulu en jeu, tape `/pos`, copie le `vector3(...)` affiché
dans la liste `Config.Zones` du mode voulu.

**Appliquer un changement** sans tout redémarrer : double-clic sur **`console.bat`**, puis tape
`restart gf_attack` (ou le nom de la ressource modifiée). Pour quitter la console sans arrêter
le serveur : **Ctrl+P puis Ctrl+Q**.

## 6. Fichiers du projet

```
Dockerfile              image du serveur (Debian + FXServer Linux officiel)
docker-compose.yml      serveur FiveM + base de données MariaDB
docker/entrypoint.sh    démarrage : crée secrets.cfg à partir de .env
docker/mariadb.cnf      réglages MariaDB (cache, connexions, encodage)
docker/db/init/         scripts SQL exécutés au tout premier démarrage
.env.example            modèle de configuration (.env = ta vraie config, secrète)
start.bat / stop.bat / status.bat / console.bat
.github/workflows/      intégration continue (image Docker + test de démarrage)
server-data/
  server.cfg            configuration FiveM
  resources/[cfx-default]/   ressources officielles Cfx.re (spawn, events)
  resources/[gunfight]/
    gf_core     modes, apparition, armes, morts, anti-tir sur coéquipier
    gf_attack   mode Attaque de zone
    gf_redzone  mode Redzone
    gf_ui       interface : HUD, kill feed, annonces, classement
```

Chaque mode a son propre « monde » (routing bucket) : les joueurs du lobby, de
l'Attaque et de la Redzone ne se voient pas. Le score et les victoires sont décidés
**uniquement par le serveur** ; les tirs sur coéquipiers ou joueurs protégés sont annulés
côté serveur.

## 7. Base de données MariaDB

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

## 8. Panneau web txAdmin

txAdmin est intégré à FXServer : **il démarre automatiquement** avec le serveur, il n'y a
rien à activer. Ouvre http://localhost:40120, entre le code PIN affiché dans les journaux,
connecte ton compte Cfx.re, puis choisis **« Existing Server Data »** avec le chemin
`/opt/fivem/server-data` et le fichier `server.cfg`.

Ses comptes administrateurs et sa configuration sont conservés dans le volume `txdata` :
un `docker compose down` ne les efface pas. Pour repartir de zéro, utiliser
`docker compose down -v` (**attention : efface aussi la base de données**).

txAdmin donne aussi un accès à distance (HTTP) aux personnes autorisées : garde des mots de
passe forts et n'ouvre le port 40120 que si tu en as besoin.

## 9. Intégration continue (GitHub Actions)

Le dépôt contient un workflow (`.github/workflows/docker.yml`) qui, à chaque envoi sur
`main` :

1. construit l'image Docker ;
2. démarre la pile complète avec une clé de licence fournie par le secret
   **`CFX_LICENSE_KEY`** ;
3. vérifie que les 11 ressources sont trouvées (`Found 11 resources`) et que les quatre
   ressources de jeu démarrent ;
4. envoie l'image sur GitHub Container Registry (`ghcr.io/<compte>/fivem-gunfight`).

Le test de démarrage est ignoré si le secret n'est pas configuré. Pour l'ajouter :

```
gh secret set CFX_LICENSE_KEY
```

Le vrai serveur de jeu, lui, tourne avec la clé de ton fichier `.env` : celle du secret
sert uniquement au test automatique.

## 10. Mettre le serveur en ligne (VPS)

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

## 11. Problèmes fréquents

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

- `gf_stats` : statistiques permanentes (kills, victoires) dans MariaDB avec **oxmysql**
  — la base est déjà prête dans `docker-compose.yml`, la chaîne de connexion
  (`mysql_connection_string`) est déjà générée par `docker/entrypoint.sh`.
- Un anti-cheat dédié est conseillé avant d'ouvrir au grand public.
