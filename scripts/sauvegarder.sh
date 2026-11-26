#!/usr/bin/env bash
# =============================================================================
#  Sauvegarde de la production : base MariaDB, données txAdmin, maps et
#  données de jeu (personnages, photos des menus, véhicules).
#
#  Usage : bash scripts/sauvegarder.sh [dossier_de_destination]
#          (défaut : backups/, ignoré par Git)
#          bash scripts/sauvegarder.sh --help
#
#  À lancer sur le VPS, depuis la racine du dépôt, avec la pile de production
#  démarrée. Les trois archives sont écrites dans un sous-dossier horodaté.
#
#  Options par variables d'environnement (toutes facultatives) :
#    AGE_RECIPIENT   destinataire age ; chiffre chaque archive en .age
#    RCLONE_REMOTE   destination rclone ; copie le dossier après sauvegarde
#    AGE_IDENTITY    identité age (utile pour la restauration, pas ici)
#
#  Conservation : 14 sauvegardes quotidiennes (la plus récente de chaque jour)
#  et 4 sauvegardes hebdomadaires (la plus récente de chaque semaine ISO).
#
#  Restauration : docs/runbooks/restauration.md et scripts/restaurer.sh.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

usage() {
  cat <<'EOF'
Sauvegarde de la production FiveMGunFight

Usage :
  bash scripts/sauvegarder.sh [dossier_de_destination]
  bash scripts/sauvegarder.sh --help

Sans argument, les archives vont dans backups/<horodatage>/. Un argument
remplace la racine : <dossier_de_destination>/<horodatage>/.

Variables facultatives :
  AGE_RECIPIENT   destinataire age (age1…). Si défini, chaque archive est
                  chiffrée en <nom>.age et la version en clair est supprimée.
  RCLONE_REMOTE   destination rclone (ex. s3:gunfight/backups). Le dossier
                  horodaté y est copié après création du manifeste.
  AGE_IDENTITY    identité age, utilisée par scripts/restaurer.sh.

Contenu :
  base.sql.gz     dump MariaDB (mariadb-dump, cohérent, routines, triggers)
  txdata.tar.gz   /opt/fivem/txData
  maps.tar.gz     gf_maps/data
  jeu.tar.gz      gf_lobby/data, gf_thumbs/thumbs, gf_vehicles/custom
  manifeste.sha256  empreintes SHA256 des archives finales

Conservation : 14 quotidiennes + 4 hebdomadaires. Une sauvegarde plus ancienne
est conservée si elle est la plus récente de sa journée dans les 14 derniers
jours distincts, ou la plus récente de sa semaine ISO dans les 4 dernières.

Le script exige .env (présence seulement, contenu jamais lu) et la pile de
production démarrée. Code de sortie : 0 succès, 1 échec.
EOF
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --*) echo "Option inconnue : $1 (essaie --help)" >&2; exit 2 ;;
esac

if [ ! -f .env ]; then
  echo "ERREUR : .env absent. Copie .env.example en .env et renseigne-le." >&2
  exit 1
fi
if [ ! -f docker-compose.prod.yml ]; then
  echo "ERREUR : docker-compose.prod.yml absent (mauvaise racine de dépôt ?)." >&2
  exit 1
fi

racine_destination="${1:-backups}"
destination="$racine_destination/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$racine_destination" "$destination"

# Verrou local : deux sauvegardes simultanées produiraient un dump incohérent.
if command -v flock >/dev/null 2>&1; then
  mkdir -p backups
  exec 9>"backups/.sauvegarde.lock"
  if ! flock -n 9; then
    echo "Une autre sauvegarde est déjà en cours (verrou backups/.sauvegarde.lock)." >&2
    exit 1
  fi
fi

compose=(-f docker-compose.yml -f docker-compose.prod.yml)

echo "Sauvegarde vers $destination"

echo " - base MariaDB"
# En production, le mot de passe root n'est plus dans l'environnement : il est
# monté dans /run/secrets/db_root_password (voir docker-compose.prod.yml). En
# développement, la variable MARIADB_ROOT_PASSWORD reste la source de secours.
docker compose "${compose[@]}" exec -T mariadb sh -c '
  if [ -s /run/secrets/db_root_password ]; then
    mot_de_passe="$(cat /run/secrets/db_root_password)"
  elif [ -n "${MARIADB_ROOT_PASSWORD:-}" ]; then
    mot_de_passe="$MARIADB_ROOT_PASSWORD"
  else
    echo "Mot de passe root MariaDB introuvable (/run/secrets/db_root_password ou MARIADB_ROOT_PASSWORD)." >&2
    exit 1
  fi
  exec mariadb-dump --single-transaction --quick --routines --triggers \
    -uroot --password="$mot_de_passe" "$MARIADB_DATABASE"
' | gzip -9 > "$destination/base.sql.gz"

echo " - données txAdmin"
docker compose "${compose[@]}" exec -T fxserver \
  tar -czf - -C /opt/fivem/txData . > "$destination/txdata.tar.gz"

echo " - maps de l'éditeur"
docker compose "${compose[@]}" exec -T fxserver \
  tar -czf - -C "/opt/fivem/server-data/resources/[gunfight]/gf_maps/data" . > "$destination/maps.tar.gz"

echo " - données de jeu (personnages, photos, véhicules)"
docker compose "${compose[@]}" exec -T fxserver   tar -czf - -C "/opt/fivem/server-data/resources/[gunfight]"   gf_lobby/data gf_thumbs/thumbs gf_vehicles/custom > "$destination/jeu.tar.gz"

for fichier in base.sql.gz txdata.tar.gz maps.tar.gz jeu.tar.gz; do
  if [ ! -s "$destination/$fichier" ]; then
    echo "ECHEC : $destination/$fichier est vide (serveur arrêté ?)" >&2
    exit 1
  fi
done

# Chiffrement facultatif : le clair disparaît une fois le .age vérifié.
if [ -n "${AGE_RECIPIENT:-}" ]; then
  if ! command -v age >/dev/null 2>&1; then
    echo "AGE_RECIPIENT défini mais la commande age est introuvable." >&2
    exit 1
  fi
  echo " - chiffrement age"
  for fichier in base.sql.gz txdata.tar.gz maps.tar.gz jeu.tar.gz; do
    age --encrypt --recipient "$AGE_RECIPIENT" -o "$destination/$fichier.age" "$destination/$fichier"
    if [ ! -s "$destination/$fichier.age" ]; then
      echo "ECHEC : $destination/$fichier.age est vide." >&2
      exit 1
    fi
    rm -f -- "$destination/$fichier"
  done
fi

# Manifeste des fichiers réellement conservés (après chiffrement éventuel).
if command -v sha256sum >/dev/null 2>&1; then
  fonction_sha="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  fonction_sha="shasum -a 256"
else
  echo "Ni sha256sum ni shasum : manifeste impossible." >&2
  exit 1
fi
(
  cd "$destination"
  find . -type f ! -name 'manifeste.sha256' -print0 \
    | sort -z \
    | xargs -0 $fonction_sha > manifeste.sha256
)

# Copie hors site facultative. Le dossier horodaté évite de mélanger deux
# sauvegardes dans la même destination distante.
if [ -n "${RCLONE_REMOTE:-}" ]; then
  if ! command -v rclone >/dev/null 2>&1; then
    echo "RCLONE_REMOTE défini mais la commande rclone est introuvable ; sauvegarde locale conservée." >&2
    exit 1
  fi
  echo " - copie rclone vers $RCLONE_REMOTE"
  rclone copy "$destination" "$RCLONE_REMOTE/$(basename "$destination")"
fi

# --- Rétention ---------------------------------------------------------------
# 1. garder la plus récente de chaque journée, sur 14 jours distincts ;
# 2. garder la plus récente de chaque semaine ISO, sur 4 semaines distinctes ;
# 3. supprimer les autres dossiers horodatés du parent.
dossier_parent="$(dirname "$destination")"
if date -d "20260101" +%Y >/dev/null 2>&1; then
  declare -a gardes=()
  declare -a supprimes=()
  jours=""
  semaines=""
  nombre_jours=0
  nombre_semaines=0

  while IFS= read -r chemin; do
    nom="$(basename "$chemin")"
    case "$nom" in
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
      *) continue ;;
    esac
    jour="${nom:0:8}"
    semaine="$(date -d "$jour" +%G-%V 2>/dev/null || true)"
    if [ -z "$semaine" ]; then
      gardes+=("$chemin")
      continue
    fi
    garder=0
    if [ "$nombre_jours" -lt 14 ] && ! printf '%s\n' "$jours" | grep -qx "$jour"; then
      jours="$jours$jour"$'\n'
      nombre_jours=$((nombre_jours + 1))
      garder=1
    fi
    if [ "$nombre_semaines" -lt 4 ] && ! printf '%s\n' "$semaines" | grep -qx "$semaine"; then
      semaines="$semaines$semaine"$'\n'
      nombre_semaines=$((nombre_semaines + 1))
      garder=1
    fi
    if [ "$garder" -eq 1 ]; then
      gardes+=("$chemin")
    else
      supprimes+=("$chemin")
    fi
  done < <(find "$dossier_parent" -mindepth 1 -maxdepth 1 -type d -printf '%p\n' 2>/dev/null | sort -r)

  for chemin in "${supprimes[@]:-}"; do
    [ -n "$chemin" ] || continue
    rm -rf -- "$chemin"
  done
else
  # Repli portable : ancienne règle de 14 jours. La boucle traite les chemins
  # un par un, sans commande de suppression groupée sur une arborescence.
  while IFS= read -r -d '' ancien; do
    rm -rf -- "$ancien"
  done < <(find "$dossier_parent" -mindepth 1 -maxdepth 1 -type d -mtime +14 -print0 2>/dev/null)
fi

echo "Terminé : $(du -sh "$destination" 2>/dev/null | cut -f1) dans $destination"
