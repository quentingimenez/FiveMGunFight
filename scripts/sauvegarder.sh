#!/usr/bin/env bash
# =============================================================================
#  Sauvegarde de la production : base MariaDB, données txAdmin et maps.
#
#  Usage : bash scripts/sauvegarder.sh [dossier_de_destination]
#          (défaut : backups/, ignoré par Git)
#
#  À lancer sur le VPS, depuis la racine du dépôt, avec la pile de production
#  démarrée. Les trois archives sont écrites dans un sous-dossier horodaté.
#  Conservation : les dossiers de plus de 14 jours sont supprimés.
#
#  Restauration : voir README.md, section « Sauvegarder et restaurer ».
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

if [ ! -f .env ]; then
  echo "ERREUR : .env absent. Copie .env.example en .env et renseigne-le." >&2
  exit 1
fi
if [ ! -f docker-compose.prod.yml ]; then
  echo "ERREUR : docker-compose.prod.yml absent (mauvaise racine de dépôt ?)." >&2
  exit 1
fi

destination="${1:-backups}/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$destination"

compose=(-f docker-compose.yml -f docker-compose.prod.yml)

echo "Sauvegarde vers $destination"

echo " - base MariaDB"
docker compose "${compose[@]}" exec -T mariadb sh -c \
  'exec mariadb-dump --single-transaction --quick --routines --triggers -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"' \
  | gzip -9 > "$destination/base.sql.gz"

echo " - données txAdmin"
docker compose "${compose[@]}" exec -T fxserver \
  tar -czf - -C /opt/fivem/txData . > "$destination/txdata.tar.gz"

echo " - maps de l'éditeur"
docker compose "${compose[@]}" exec -T fxserver \
  tar -czf - -C "/opt/fivem/server-data/resources/[gunfight]/gf_maps/data" . > "$destination/maps.tar.gz"

for fichier in base.sql.gz txdata.tar.gz maps.tar.gz; do
  if [ ! -s "$destination/$fichier" ]; then
    echo "ECHEC : $destination/$fichier est vide (serveur arrêté ?)" >&2
    exit 1
  fi
done

# Ne garde que les 14 derniers jours de sauvegardes.
dossier_parent="$(dirname "$destination")"
find "$dossier_parent" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf -- {} + 2>/dev/null || true

echo "Terminé : $(du -sh "$destination" 2>/dev/null | cut -f1) dans $destination"
