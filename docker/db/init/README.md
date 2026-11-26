# Scripts d'initialisation MariaDB

Ce dossier reste monté dans MariaDB sur
`/docker-entrypoint-initdb.d` (voir `docker-compose.yml` et ses surcouches). Il
ne contient plus le schéma du jeu : les scripts qui s'y trouvent ne s'exécutent
que sur un volume `dbdata` vide, lors du tout premier démarrage du conteneur.
Ils sont ignorés dès que le volume contient déjà une base.

Le schéma de `gf_stats` est désormais créé et mis à jour par la ressource
`gf_db` au démarrage de FXServer, via `oxmysql` : il est donc appliqué même sur
une base existante. Les migrations et leur somme sont enregistrées dans la
table `gf_schema_version`. Les fichiers de migration ne vont pas ici : ils se
trouvent dans `server-data/resources/[gunfight]/gf_db/migrations/`.

## Ajouter une migration

1. Crée un fichier `NNNN_nom.sql` dans
   `server-data/resources/[gunfight]/gf_db/migrations/`, en numérotant à partir
   de `0001`, sans trou, avec un nom en minuscules, chiffres et underscores.
   Le SQL doit rester idempotent (`CREATE TABLE IF NOT EXISTS`,
   `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`…) : MariaDB valide
   implicitement le DDL et une migration interrompue peut être rejouée au
   démarrage suivant.
2. Ajoute l'entrée correspondante dans
   `server-data/resources/[gunfight]/gf_db/migrations.lua` :
   `{ version = N, nom = '...', fichier = 'migrations/NNNN_nom.sql' }`.
3. Redémarre FXServer pour que `gf_db` applique la migration en attente.

Une migration déjà appliquée ne doit **jamais** être modifiée : sa somme est
enregistrée dans `gf_schema_version` et `gf_db` refuserait de démarrer avec
l'erreur `migration-modifiee:<version>`. Corrige le schéma par une nouvelle
migration.

## Volume vide et variables `MARIADB_*`

Pour rejouer les scripts de ce dossier, il faut repartir d'un volume vide :
`docker compose down -v` puis `docker compose up -d`.
**Attention : `-v` supprime toutes les bases et toutes les statistiques.**

Les variables `MARIADB_*` du fichier `.env` ne changent plus rien une fois le
volume initialisé (l'image ne recrée pas l'utilisateur).

## Où lire les logs

Les messages de `gf_db` apparaissent dans les logs du conteneur jeu
(`docker logs -f <conteneur>`), ou dans la console FXServer en développement :

- `[gf_db] migration NNNN <nom> appliquée` pour chaque migration jouée ;
- `[gf_db] schéma à jour (version N)` au démarrage suivant, quand il n'y a plus
  rien à appliquer ;
- `[gf_db] ERREUR ...` en cas de problème de connexion, de somme modifiée ou
  d'échec d'application d'une migration.

En cas d'erreur, corrige la configuration ou la migration, puis redémarre le
serveur : `gf_db` reprend là où il s'est arrêté.
