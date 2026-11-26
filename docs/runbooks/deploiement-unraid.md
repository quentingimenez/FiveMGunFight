# Runbook — Déploiement sur Unraid

**Objectif** : le badge `BUILD <sha>` affiché dans le lobby doit suivre le sha de
l'image réellement déployée, sans intervention manuelle sur les fichiers à
l'intérieur du conteneur.

**Périmètre** : serveur de production hébergé sur Unraid, conteneur Docker
`Gunfight-FXServer`, image `ghcr.io/quentingimenez/fivemgunfight:main`. Les
commandes se lancent depuis une console SSH sur Unraid ou depuis le terminal
Unraid. Aucune commande de ce runbook ne modifie le dépôt ni le registre.

**Principe** : les ressources viennent de l'image. Seules les données qui doivent
survivre aux mises à jour sont montées depuis l'appdata : `maps.json` pour
l'éditeur de maps, `characters.json` pour les personnages du lobby, `txData` pour
txAdmin. Le modèle de production équivalent est `docker-compose.prod.yml` : il ne
monte aucun `server-data` complet, seulement `gf_maps/data` et `gf_lobby/data`,
avec `GF_SEED_MAPS: "true"`.

## Pourquoi le montage complet casse la version

Le conteneur monte actuellement le dossier complet
`/mnt/user/appdata/fivemgunfight/server-data` sur `/opt/fivem/server-data`. Un
montage masque le contenu de l'image à cet emplacement : toutes les ressources
embarquées dans l'image, y compris `gf_lobby/server.lua`, sont remplacées par les
fichiers figés de l'appdata. Le `Force Update` ne remplace donc que l'image,
jamais le code réellement servi. Au démarrage, `docker/entrypoint.sh` écrit bien
`set gf_build_sha "<sha>"` dans `server-data/secrets.cfg`, mais l'ancien
`gf_lobby/server.lua` du dossier monté ne lit pas cette convar : il affiche une
valeur codée à la main, ici `BUILD b8b4a5c · HOTFIX`, alors que ce texte n'existe
pas dans le commit `b8b4a5c`. Le badge devient menteur. La chaîne fiable reste
la convar : CI (`BUILD_SHA` = 7 premiers caractères de `github.sha`) →
`Dockerfile` (`ENV GF_BUILD_SHA`) → `entrypoint.sh` (`secrets.cfg`) →
`gf_lobby/server.lua` (`GetConvar('gf_build_sha')`) → NUI (`applyBuild`). Elle ne
fonctionne que si le code qui lit la convar vient de l'image.

## Prérequis

L'image déployée doit être au moins celle de la PR #27, c'est-à-dire contenir
`[standalone]/oxmysql` et `gf_stats`. Une image plus ancienne démarre sans ces
ressources : les statistiques ne sont pas enregistrées et les logs ne contiennent
pas les lignes attendues. En cas de doute, tirer `:main` avec *Force Update*
avant la migration.

Sur une base MariaDB déjà initialisée, le script `docker/db/init/01-schema.sql`
n'a pas été joué au premier démarrage : appliquer le schéma une seule fois. Depuis
un poste qui a le dépôt, copier le fichier sur l'hôte Unraid :

```bash
scp docker/db/init/01-schema.sql root@100.90.110.83:/tmp/
```

Puis, dans un shell Unraid, importer le schéma dans la base `gunfight` :

```bash
docker exec -i Gunfight-MariaDB sh -c 'mariadb -ugunfight -p"$MARIADB_PASSWORD" gunfight' < /tmp/01-schema.sql
```

Le `$MARIADB_PASSWORD` est étendu à l'intérieur du conteneur MariaDB, pas dans
l'historique du shell Unraid : le mot de passe n'apparaît pas en clair. Vérifier
la table créée :

```bash
docker exec Gunfight-MariaDB sh -c 'mariadb -ugunfight -p"$MARIADB_PASSWORD" gunfight -e "SHOW TABLES"' | grep gf_stats_players
```

La commande doit renvoyer `gf_stats_players`. `CREATE TABLE IF NOT EXISTS`
rend l'import sans danger si la table existe déjà.

## Migration d'un conteneur existant

Fais cette migration à un moment sans match, en prévenant les joueurs. Les étapes
1 à 3 se font avec le conteneur arrêté. Vérifie chaque chemin avant de copier :
les crochets dans `resources/[gunfight]/...` exigent des guillemets doubles.

1. Arrête le conteneur et crée une sauvegarde datée de l'ancien dossier :

   ```bash
   DATE=$(date +%Y%m%d-%H%M%S)
   docker stop Gunfight-FXServer
   mkdir -p "/mnt/user/appdata/fivemgunfight/sauvegardes/$DATE"
   cp -a /mnt/user/appdata/fivemgunfight/server-data/. \
     "/mnt/user/appdata/fivemgunfight/sauvegardes/$DATE/server-data/"
   ```

   Le dossier sauvegardé contient au minimum `server.cfg` et
   `resources/[gunfight]/gf_maps/data/maps.json`. La copie `-a` conserve les
   droits et les sous-dossiers.

2. Crée les dossiers de données persistantes et copies-y les fichiers existants :

   ```bash
   mkdir -p /mnt/user/appdata/fivemgunfight/maps
   src="/mnt/user/appdata/fivemgunfight/server-data/resources/[gunfight]/gf_maps/data/maps.json"
   if [ -f "$src" ]; then
     cp "$src" /mnt/user/appdata/fivemgunfight/maps/maps.json
   fi
   ls -l /mnt/user/appdata/fivemgunfight/maps/

   mkdir -p /mnt/user/appdata/fivemgunfight/characters
   src="/mnt/user/appdata/fivemgunfight/server-data/resources/[gunfight]/gf_lobby/data/characters.json"
   if [ -f "$src" ]; then
     cp "$src" /mnt/user/appdata/fivemgunfight/characters/characters.json
   fi
   chown -R 10001:10001 /mnt/user/appdata/fivemgunfight/characters
   ls -l /mnt/user/appdata/fivemgunfight/characters/

   # Photos des menus et véhicules : dossiers vides, remplis au démarrage
   # depuis l'image (GF_SEED_DATA=true), puis par /thumbs et /customveh.
   mkdir -p /mnt/user/appdata/fivemgunfight/thumbs /mnt/user/appdata/fivemgunfight/vehicles
   chown -R 10001:10001 /mnt/user/appdata/fivemgunfight/thumbs /mnt/user/appdata/fivemgunfight/vehicles
   ```

   La copie est conditionnelle : si le `maps.json` source est absent, le
   dossier reste vide et `GF_SEED_MAPS=true` amorcera le fichier depuis le
   modèle de l'image au premier démarrage. De même, si l'ancien `characters.json`
   est absent, le dossier personnages reste vide et `gf_lobby` le créera. Le
   conteneur tourne en uid 10001 : le `chown` évite les `Permission denied` sur
   `characters.json` après la migration.

3. Édite le conteneur dans l'UI Unraid (onglet Docker, clic sur
   `Gunfight-FXServer`, puis *Edit*) :

   - supprime le chemin `/mnt/user/appdata/fivemgunfight/server-data` →
     `/opt/fivem/server-data` ;
   - ajoute `/mnt/user/appdata/fivemgunfight/maps` →
     `/opt/fivem/server-data/resources/[gunfight]/gf_maps/data`, en lecture-écriture ;
   - ajoute `/mnt/user/appdata/fivemgunfight/characters` →
     `/opt/fivem/server-data/resources/[gunfight]/gf_lobby/data`, en lecture-écriture ;
   - ajoute `/mnt/user/appdata/fivemgunfight/thumbs` →
     `/opt/fivem/server-data/resources/[gunfight]/gf_thumbs/thumbs`, en lecture-écriture ;
   - ajoute `/mnt/user/appdata/fivemgunfight/vehicles` →
     `/opt/fivem/server-data/resources/[gunfight]/gf_vehicles/custom`, en lecture-écriture ;
   - ajoute les variables `GF_SEED_MAPS=true` et `GF_SEED_DATA=true` ;
   - conserve le montage txdata, le réseau `fivem-net`, les ports 30120 TCP et
     UDP, le port 40120 TCP et toutes les variables déjà présentes (licence,
     nom du serveur, joueurs max, identifiants admin, base MariaDB).

   Ne monte rien d'autre sur `/opt/fivem/server-data` lui-même : les sous-dossiers
   de données (maps, personnages, txData) sont les seules exceptions. Pour une nouvelle
   installation, le gabarit `deploy/unraid/Gunfight-FXServer.xml` contient déjà
   cette configuration.

4. Clique sur *Force Update* pour tirer `:main`, puis démarre le conteneur. Le
   `Force Update` est nécessaire : sans lui, Unraid peut relancer l'ancienne
   image en cache.

5. Lis les logs du conteneur (`docker logs Gunfight-FXServer` ou bouton *Log*
   dans l'UI) et vérifie, dans cet ordre : la ligne d'entrypoint
   `Build            : <sha court>`, `Started resource oxmysql`, `Started resource gf_stats`,
   `[gf_stats] MariaDB connectée, statistiques persistantes actives`, puis les
   lignes `Started resource gf_...` du jeu. Une ligne `maps.json amorcé depuis
   le modèle de l'image` est normale si le dossier maps était vide.

6. Compare le badge du lobby au sha courant de `origin/main`. `gh` n'est pas
   forcément installé sur Unraid : lance cette commande depuis un poste qui a
   `gh` authentifié, ou lis le sha directement sur la page GitHub du commit
   `main` :

   ```bash
   gh api repos/quentingimenez/FiveMGunFight/commits/main --jq '.sha[0:7]'
   ```

   Les trois valeurs doivent coïncider : sha dans les logs, sha lu sur GitHub,
   badge affiché en jeu.

## Mise à jour courante

Après la migration, chaque nouvelle image publiée se déploie par un
*Force Update* du conteneur. Les ressources sont relues depuis l'image, le badge
suit automatiquement le sha construit par la CI ; aucun fichier n'est à éditer à
la main dans l'appdata.

`:main` est un tag mobile : il pointe vers le dernier commit de la branche, donc
deux *Force Update* à des moments différents peuvent donner deux versions
différentes. Si une version précise doit être figée, remplace le tag par un
digest `@sha256:...` relevé avec `docker buildx imagetools inspect`, comme dans
[`mise-a-jour.md`](mise-a-jour.md). Le digest exige un renouvellement explicite à
chaque mise à jour, mais il rend le déploiement reproductible.

## Vérification

La vérification porte sur trois points : le montage, la convar et le rendu en
jeu. Après chaque mise à jour ou migration :

```bash
docker exec Gunfight-FXServer grep -n gf_build_sha /opt/fivem/server-data/secrets.cfg
docker inspect Gunfight-FXServer --format '{{json .Mounts}}'
docker logs Gunfight-FXServer 2>&1 | grep -E 'Build|Started resource gf_'
```

- la première commande affiche `set gf_build_sha "<sha>"`, sans `dev` ni valeur
  ancienne ;
- le `docker inspect` ne contient aucun montage dont la cible est exactement
  `/opt/fivem/server-data` ; il contient exactement les trois cibles
  `/opt/fivem/server-data/resources/[gunfight]/gf_maps/data`,
  `/opt/fivem/server-data/resources/[gunfight]/gf_lobby/data` et
  `/opt/fivem/txData` ;
- la table `gf_stats_players` existe dans la base `gunfight` (commande du
  paragraphe Prérequis) ;
- un personnage créé en jeu survit à un redémarrage du conteneur :
  `docker restart Gunfight-FXServer` puis reconnexion au lobby ;
- les logs affichent `Build            : <sha court>`, `Started resource oxmysql`,
  `Started resource gf_stats`, le message de connexion MariaDB de `gf_stats` et
  `Started resource gf_...` pour les ressources du jeu ;
- en jeu, le lobby affiche `BUILD <sha> · OK` avec le même sha. Une connexion et
  une manche de test confirment que les maps jouées sont les bonnes.

Ne considère pas la migration terminée si l'un de ces contrôles échoue.

## Retour arrière

Si le serveur ne démarre plus après la migration, réédite le conteneur dans
l'UI Unraid et remets l'ancien chemin complet
`/mnt/user/appdata/fivemgunfight/server-data` → `/opt/fivem/server-data`, en
retirant les deux nouveaux chemins (maps, personnages) et la variable
`GF_SEED_MAPS`. Redémarre le conteneur : le code figé de l'appdata reprend le
service.

Restaure ensuite, si besoin, les fichiers de la sauvegarde datée créée à
l'étape 1. Le badge redeviendra `BUILD b8b4a5c · HOTFIX` ou une autre valeur
figée : c'est le symptôme attendu de l'ancien montage, pas une régression de
l'image. Le retour arrière ne supprime ni `maps`, ni `characters`, ni `txdata` ;
il remet seulement le conteneur dans son état antérieur.

## Dépannage

| Symptôme | Cause probable | Action |
|---|---|---|
| `denied` ou `manifest unknown` au *Force Update* | image GHCR privée, session Docker non authentifiée | sur Unraid, `echo "$GHCR_TOKEN" | docker login ghcr.io -u TON_COMPTE --password-stdin` avec un token GitHub limité à `read:packages`, saisi depuis un gestionnaire de secrets ; ne mets jamais le token dans le dépôt ni dans une variable du conteneur |
| Badge `BUILD dev` | convar absente ou valeur filtrée | vérifie `gf_build_sha` dans `secrets.cfg` ; la valeur doit être hexadécimale (7 caractères), sinon `entrypoint.sh` la remplace par `dev` ; confirme que le code servi vient de l'image |
| Badge figé sur `b8b4a5c · HOTFIX` | montage complet toujours actif | relis `docker inspect Gunfight-FXServer` : toute cible `/opt/fivem/server-data` exacte masque l'image ; refais l'étape 3 |
| Maps vides ou éditeur repart de zéro | mauvais chemin de montage ou guillemets oubliés autour de `[gunfight]` | vérifie `ls -l /mnt/user/appdata/fivemgunfight/maps/maps.json` et la cible exacte du montage ; `GF_SEED_MAPS=true` ne remplace pas un fichier existant |
| `[gf_stats] MariaDB sans réponse` | schéma absent, mot de passe différent ou `DB_HOST` erroné | applique `01-schema.sql` une fois (paragraphe Prérequis), vérifie que `MARIADB_PASSWORD` du conteneur jeu correspond à celui du conteneur MariaDB, et que `DB_HOST=mariadb` sur le réseau `fivem-net` |
| `Permission denied` sur `characters.json` | dossier `characters` appartient à un autre uid | `chown -R 10001:10001 /mnt/user/appdata/fivemgunfight/characters`, puis redémarre `Gunfight-FXServer` |
| `server.cfg` personnalisé perdu après la migration | modifications faites à la main dans l'ancien `server-data` | porte-les dans `server-data/server.cfg` du dépôt par une pull request : un conteneur mis à jour ne lit plus l'ancien fichier |
| Erreur de licence au démarrage | variable `LICENSE_KEY` retirée par erreur pendant l'édition | conserve toutes les variables existantes ; la valeur est à saisir dans l'UI Unraid, jamais dans un fichier versionné |

## Ce que cette migration ne couvre pas

- Les personnalisations faites directement dans l'appdata (`server.cfg` édité à
  la main, `config.lua` modifié, resources ajoutées) ne sont pas conservées par
  l'image. Elles doivent être portées dans le dépôt via une pull request, sinon
  elles disparaissent au prochain *Force Update*.
- Les ressources tierces ajoutées manuellement dans l'ancien dossier ne sont pas
  héritées. Installe-les dans une image dérivée ou dans le dépôt, avec une
  procédure dédiée.
- `oxmysql` et `gf_stats` sont désormais dans l'image et embarqués par la PR
  #27 : aucun montage supplémentaire n'est nécessaire pour eux. Seul le schéma
  `01-schema.sql` doit être appliqué une fois sur une base déjà initialisée.
- La migration ne change pas MariaDB, txAdmin ni le réseau `fivem-net`. Elle ne
  modifie pas les sauvegardes, qui restent sous
  `/mnt/user/appdata/fivemgunfight/`.
