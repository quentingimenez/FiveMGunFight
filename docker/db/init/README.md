# Scripts d'initialisation MariaDB

Tout fichier `.sql`, `.sh` ou `.sql.gz` déposé dans ce dossier est exécuté
**une seule fois**, par ordre alphabétique, au tout premier démarrage du
conteneur MariaDB (volume `dbdata` vide).

## Règles à connaître

- Les scripts sont ignorés dès que le volume `dbdata` contient déjà une base.
- Pour les rejouer, il faut repartir d'un volume vide :
  `docker compose down -v` puis `docker compose up -d`.
  **Attention : `-v` supprime toutes les bases et toutes les stats.**
- Privilégier les noms préfixés par un numéro : `01-schema.sql`,
  `02-seed.sql`.
- Les variables `MARIADB_*` du fichier `.env` ne changent plus rien une fois le
  volume initialisé (l'image ne recrée pas l'utilisateur).

## Phase 2

C'est ici que viendra le schéma `gf_stats` (kills, manches, victoires) utilisé
par la ressource `oxmysql`.
