# Runbook — Restauration d'une sauvegarde

**Objectif** : remettre en service la base, les données txAdmin et les maps à
partir d'une sauvegarde, en moins d'une heure, sans jamais écraser la
production par erreur.

**Objectifs de service** :

- **RPO 24 h** : une sauvegarde par jour au minimum ;
- **RTO 1 h** : sauvegarde vérifiée et pile jetable validée en moins d'une heure.

**Prérequis** : dossier de sauvegarde (`backups/<horodatage>/`), même image
(digest) que la production, dossier `secrets/` du VPS (`license_key`,
`db_password`, `db_root_password`), Docker Compose v2, espace disque suffisant
(au moins deux fois la taille des archives).

## 1. Choisir et vérifier la sauvegarde

```bash
ls -lh backups/
bash scripts/restaurer.sh --verifier backups/20260101-030000
```

Le script contrôle `base.sql.gz` avec `gzip -t` et les deux archives `tar.gz`
avec `tar -tzf`. Il refuse une archive manquante, vide ou corrompue. Les
archives chiffrées (`.age`) exigent `age` et `AGE_IDENTITY`.

## 2. Extraire hors production

```bash
bash scripts/restaurer.sh --oui --destination restauration/20260101-030000 \
  backups/20260101-030000
```

Le script extrait `base.sql`, `txdata/` et `maps/` dans `restauration/` et
**ne touche pas** aux volumes `gunfight-prod-*`. Sans `--oui`, il demande une
confirmation ; sans terminal interactif, il refuse.

## 3. Importer dans une pile jetable

Crée `restauration/20260101-030000/restore-compose.yml` :

```yaml
name: gunfight-restore
services:
  mariadb:
    image: mariadb:11.4@sha256:a8992b5e5404d11e03c54a31d0c1bdea3fd116d283aa6d1a627551f29045309b
    environment:
      MARIADB_ROOT_PASSWORD_FILE: /run/secrets/db_root_password
      MARIADB_DATABASE: ${MARIADB_DATABASE:-gunfight}
      MARIADB_USER: ${MARIADB_USER:-gunfight}
      MARIADB_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_root_password
      - db_password
    volumes:
      - restore-db:/var/lib/mysql
      - ./base.sql:/docker-entrypoint-initdb.d/00-base.sql:ro
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 20
      start_period: 30s
  fxserver:
    image: ${RESTORE_IMAGE_REF:?}
    environment:
      TXADMIN: "false"
      GF_SEED_MAPS: "false"
      TXHOST_DATA_PATH: /opt/fivem/txData
      MARIADB_PASSWORD: ""
      LICENSE_KEY: ""
    secrets:
      - license_key
      - db_password
    volumes:
      - restore-txdata:/opt/fivem/txData
      - restore-maps:/opt/fivem/server-data/resources/[gunfight]/gf_maps/data
    depends_on:
      mariadb:
        condition: service_healthy
  outils:
    image: mariadb:11.4@sha256:a8992b5e5404d11e03c54a31d0c1bdea3fd116d283aa6d1a627551f29045309b
    profiles: ["outils"]
    entrypoint: ["sh", "-c"]
    command: ["true"]
    volumes:
      - restore-txdata:/data-txdata
      - restore-maps:/data-maps
volumes:
  restore-db:
    name: gunfight-restore-db
  restore-txdata:
    name: gunfight-restore-txdata
  restore-maps:
    name: gunfight-restore-maps
secrets:
  license_key:
    file: ../../secrets/license_key
  db_password:
    file: ../../secrets/db_password
  db_root_password:
    file: ../../secrets/db_root_password
```

Puis, depuis `restauration/20260101-030000` :

```bash
export RESTORE_IMAGE_REF='ghcr.io/...@sha256:...'   # digest de production
docker compose -p gunfight-restore -f restore-compose.yml \
  up -d --wait mariadb

docker compose -p gunfight-restore -f restore-compose.yml \
  exec -T mariadb sh -c \
  'MYSQL_PWD="$(cat /run/secrets/db_root_password)" mariadb -uroot "$MARIADB_DATABASE" \
     -e "SHOW TABLES; SELECT COUNT(*) AS tables FROM information_schema.tables WHERE table_schema=DATABASE();"'
```

Le dump est importé automatiquement au premier démarrage du volume
`gunfight-restore-db` (fichier monté dans `/docker-entrypoint-initdb.d`). Si la
requête renvoie 0 table, attends la fin de l'import et relance le contrôle ; ne
supprime pas le volume avant d'avoir lu les logs.

Copie ensuite txdata et maps dans les volumes jetables :

```bash
docker compose -p gunfight-restore -f restore-compose.yml \
  --profile outils run --rm --no-deps --entrypoint sh \
  -v "$PWD/txdata:/src:ro" outils -c 'cp -a /src/. /data-txdata/ && ls /data-txdata | head'

docker compose -p gunfight-restore -f restore-compose.yml \
  --profile outils run --rm --no-deps --entrypoint sh \
  -v "$PWD/maps:/src:ro" outils -c 'cp -a /src/. /data-maps/ && ls /data-maps | head'
```

Démarre le serveur jetable (aucun port publié, aucun contact avec la prod) :

```bash
docker compose -p gunfight-restore -f restore-compose.yml \
  up -d --wait fxserver
docker compose -p gunfight-restore -f restore-compose.yml \
  logs --tail=100 fxserver
```

Tu dois retrouver `Started resource gf_…` et les comptes txAdmin dans les
données restaurées. Sans `TXADMIN=true`, txAdmin n'est pas lancé : c'est
volontaire pour ne pas exposer de panneau pendant l'essai. Pour tester aussi
txAdmin, passe `TXADMIN: "true"` et ajoute temporairement
`- "127.0.0.1:40122:40120/tcp"` au service `fxserver`.

## 4. Vérifier

- `restaurer.sh --verifier` sort en 0 sur les trois archives ;
- le nombre de tables et les comptages des tables critiques sont cohérents ;
- `maps.json` est présent dans `/data-maps/` et contient les maps attendues ;
- `txData/` contient la configuration et les comptes txAdmin ;
- le serveur jetable démarre ses ressources sans erreur ;
- aucun volume `gunfight-prod-*` n'a été modifié (`docker volume ls`).

Détruis ensuite la pile jetable **et ses volumes uniquement** :

```bash
docker compose -p gunfight-restore -f restore-compose.yml \
  down -v
```

## 5. Bascule réelle en production (si nécessaire)

Cette étape écrase les données. Ne la lance qu'après une sauvegarde fraîche et
un essai réussi ci-dessus.

1. Prends une sauvegarde de sécurité : `bash scripts/sauvegarder.sh`.
2. Arrête le serveur : `docker compose -f docker-compose.yml -f docker-compose.prod.yml stop fxserver`.
3. Recrée une base vide (le dump ne supprime pas les tables existantes) puis
   importe-le. **Cette commande efface la base de production** : elle ne se lance
   qu'après la sauvegarde de sécurité de l'étape 1.
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T mariadb \
     sh -c 'MYSQL_PWD="$(cat /run/secrets/db_root_password)" mariadb -uroot -e "DROP DATABASE IF EXISTS \`$MARIADB_DATABASE\`; CREATE DATABASE \`$MARIADB_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"'
   cat "restauration/<horodatage>/base.sql" | \
     docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T mariadb \
     sh -c 'MYSQL_PWD="$(cat /run/secrets/db_root_password)" exec mariadb -uroot "$MARIADB_DATABASE"'
   ```
4. Remplace txdata et maps dans leurs volumes, **conteneur fxserver arrêté**,
   avec un conteneur jetable monté sur `gunfight-prod-txdata` et
   `gunfight-prod-maps`. Vérifie deux fois les noms de volumes avant la copie :
   ```bash
   HORODATAGE='20260101-030000'
   docker run --rm \
     -v gunfight-prod-txdata:/dest \
     -v "$PWD/restauration/$HORODATAGE/txdata:/src:ro" \
     --entrypoint sh mariadb:11.4@sha256:a8992b5e5404d11e03c54a31d0c1bdea3fd116d283aa6d1a627551f29045309b \
     -c 'find /dest -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; cp -a /src/. /dest/'
   docker run --rm \
     -v gunfight-prod-maps:/dest \
     -v "$PWD/restauration/$HORODATAGE/maps:/src:ro" \
     --entrypoint sh mariadb:11.4@sha256:a8992b5e5404d11e03c54a31d0c1bdea3fd116d283aa6d1a627551f29045309b \
     -c 'find /dest -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +; cp -a /src/. /dest/'
   ```
   La commande vide d'abord le volume cible : ne l'inverse pas avec la source.
5. Relance : `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --wait`.
6. Contrôle : `bash scripts/verifier-sante.sh`, connexion d'un joueur, une manche.

## 6. Vérification finale

- `bash scripts/verifier-sante.sh` code 0 ;
- `curl -fsS http://127.0.0.1:30120/dynamic.json` répond ;
- les joueurs se connectent et les maps restaurées sont visibles ;
- les comptes txAdmin fonctionnent ;
- la sauvegarde de sécurité prise à l'étape 5 est conservée jusqu'à validation.
