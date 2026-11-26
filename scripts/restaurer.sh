#!/usr/bin/env bash
# =============================================================================
#  Restauration d'une sauvegarde FiveMGunFight.
#
#  Usage :
#    bash scripts/restaurer.sh --verifier backups/20260101-030000
#    bash scripts/restaurer.sh [--oui] [--force] [--destination <dossier>] \
#        backups/20260101-030000
#
#  Le script ne touche JAMAIS la pile de production : il vérifie puis extrait
#  les archives dans un dossier local. L'import dans une pile jetable est
#  décrit à la fin et dans docs/runbooks/restauration.md.
#
#  Archives attendues (ou leur version chiffrée .age) :
#    base.sql.gz    dump MariaDB
#    txdata.tar.gz  contenu de /opt/fivem/txData
#    maps.tar.gz    contenu de gf_maps/data
#
#  Variables :
#    AGE_IDENTITY   identité age pour les archives .age (obligatoire si .age)
#
#  Code de sortie : 0 succès, 1 archives invalides ou opération refusée,
#  2 usage incorrect.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

readonly RACINE="$(pwd)"
readonly DOSSIER_DEFAUT="restauration"

usage() {
  cat <<'EOF'
Restauration d'une sauvegarde FiveMGunFight

Usage :
  bash scripts/restaurer.sh --verifier <dossier-archives>
  bash scripts/restaurer.sh [options] <dossier-archives>
  bash scripts/restaurer.sh --help

Options :
  --verifier            Vérifie l'intégrité des trois archives, sans extraire.
  --destination <dir>   Dossier d'extraction (défaut restauration/<nom>).
  --force               Remplace le dossier de destination s'il n'est pas vide.
  --oui                 Ne pose aucune question (confirmation explicite).
  --help                Affiche cette aide.

Archives attendues dans <dossier-archives> :
  base.sql.gz     dump MariaDB (ou base.sql.gz.age)
  txdata.tar.gz   données txAdmin (ou txdata.tar.gz.age)
  maps.tar.gz     cartes gf_maps (ou maps.tar.gz.age)

Sécurité :
  - le script n'écrit que dans le dossier de destination local ;
  - il ne démarre pas Docker et ne touche jamais aux volumes de production ;
  - sans --oui, une confirmation interactive est demandée avant extraction ;
  - sans terminal interactif et sans --oui, l'extraction est refusée.

Les archives chiffrées (.age) exigent la commande age et AGE_IDENTITY.
Après extraction, le script affiche les étapes d'import dans une pile jetable
(projet Compose « gunfight-restore »). Voir docs/runbooks/restauration.md.
EOF
}

die_usage() {
  echo "$*" >&2
  echo "Essaie --help." >&2
  exit 2
}

VERIFIER=0
FORCER=0
OUI=0
DESTINATION=""
ARCHIVES=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --verifier) VERIFIER=1 ;;
    --force) FORCER=1 ;;
    --oui) OUI=1 ;;
    --destination)
      shift
      [ "$#" -gt 0 ] || die_usage "--destination attend un chemin."
      DESTINATION="$1"
      ;;
    --help|-h) usage; exit 0 ;;
    --*) die_usage "Option inconnue : $1" ;;
    *)
      [ -z "$ARCHIVES" ] || die_usage "Un seul dossier d'archives est accepté."
      ARCHIVES="$1"
      ;;
  esac
  shift
done

[ -n "$ARCHIVES" ] || die_usage "Indique le dossier des archives."
[ -d "$ARCHIVES" ] || { echo "Dossier introuvable : $ARCHIVES" >&2; exit 1; }

# Normalisation relative à la racine, pour rester portable Windows/WSL.
ARCHIVES="${ARCHIVES%/}"

declare -a TEMPORAIRE=()
nettoyer() {
  local dossier
  for dossier in "${TEMPORAIRE[@]:-}"; do
    if [ -n "$dossier" ] && [ -d "$dossier" ]; then
      rm -rf -- "$dossier"
    fi
  done
  return 0
}
trap nettoyer EXIT

fichier_archive() {
  local nom="$1"
  if [ -f "$ARCHIVES/$nom" ]; then
    printf '%s\n' "$ARCHIVES/$nom"
  elif [ -f "$ARCHIVES/$nom.age" ]; then
    printf '%s\n' "$ARCHIVES/$nom.age"
  else
    return 1
  fi
}

# Prépare un fichier lisible (déchiffre .age dans un dossier temporaire).
preparer_lisible() {
  local source="$1"
  if [ "${source##*.}" = "age" ]; then
    command -v age >/dev/null 2>&1 || {
      echo "Archive chiffrée mais commande age introuvable : $source" >&2
      return 1
    }
    [ -n "${AGE_IDENTITY:-}" ] || {
      echo "Archive chiffrée : définis AGE_IDENTITY (identité age)." >&2
      return 1
    }
    local dossier
    dossier="$(mktemp -d "${TMPDIR:-/tmp}/restauration.XXXXXX")"
    TEMPORAIRE+=("$dossier")
    if ! age --decrypt --identity "$AGE_IDENTITY" "$source" > "$dossier/clair" 2>/dev/null; then
      echo "Déchiffrement impossible : $source" >&2
      return 1
    fi
    printf '%s\n' "$dossier/clair"
  else
    printf '%s\n' "$source"
  fi
}

verifier_une_archive() {
  local nom="$1"
  local source lisible
  if ! source="$(fichier_archive "$nom")"; then
    echo "MANQUANTE  $nom (ni $nom ni $nom.age)" >&2
    return 1
  fi
  if ! lisible="$(preparer_lisible "$source")"; then
    return 1
  fi
  case "$nom" in
    base.sql.gz)
      if gzip -t "$lisible" 2>/dev/null; then
        echo "ok         $nom ($(wc -c < "$source" | tr -d ' ') octets)"
        return 0
      fi
      echo "INVALIDE   $nom : gzip -t échoue" >&2
      return 1
      ;;
    *)
      if tar -tzf "$lisible" >/dev/null 2>&1; then
        local entrees
        entrees="$(tar -tzf "$lisible" 2>/dev/null | wc -l | tr -d ' ')"
        echo "ok         $nom ($(wc -c < "$source" | tr -d ' ') octets, $entrees entrées)"
        return 0
      fi
      echo "INVALIDE   $nom : tar -tzf échoue" >&2
      return 1
      ;;
  esac
}

verifier_tout() {
  local echecs=0
  echo "Vérification des archives : $ARCHIVES"
  verifier_une_archive "base.sql.gz" || echecs=$((echecs + 1))
  verifier_une_archive "txdata.tar.gz" || echecs=$((echecs + 1))
  verifier_une_archive "maps.tar.gz" || echecs=$((echecs + 1))
  # jeu.tar.gz : absente des sauvegardes antérieures, donc facultative
  if fichier_archive "jeu.tar.gz" >/dev/null; then
    verifier_une_archive "jeu.tar.gz" || echecs=$((echecs + 1))
  else
    echo "absente    jeu.tar.gz (sauvegarde antérieure aux données de jeu)"
  fi
  if [ "$echecs" -ne 0 ]; then
    echo "$echecs archive(s) manquante(s) ou invalide(s)." >&2
    return 1
  fi
  echo "Les archives sont valides."
}

if [ "$VERIFIER" -eq 1 ]; then
  verifier_tout
  exit $?
fi

verifier_tout || exit 1

NOM="$(basename "$ARCHIVES")"
DESTINATION="${DESTINATION:-$DOSSIER_DEFAUT/$NOM}"
DESTINATION="${DESTINATION%/}"

case "$DESTINATION" in
  ""|"/"|"."|"..") echo "Destination refusée : $DESTINATION" >&2; exit 1 ;;
  *"/../"*|*/..) echo "Destination refusée (chemin avec ..) : $DESTINATION" >&2; exit 1 ;;
esac

# Refuse aussi tout parent de la racine (\$RACINE, .., /home, etc.) : --force
# ne doit jamais pouvoir vider le dépôt ou son dossier parent.
if command -v realpath >/dev/null 2>&1; then
  DESTINATION_REELLE="$(realpath -m -- "$DESTINATION" 2>/dev/null || true)"
  if [ -n "$DESTINATION_REELLE" ]; then
    case "$RACINE/" in
      "$DESTINATION_REELLE"/*)
        echo "Destination refusée (parent de la racine) : $DESTINATION" >&2
        exit 1
        ;;
    esac
  fi
fi
if [ "$DESTINATION" = "$RACINE" ]; then
  echo "Destination refusée : la racine du dépôt." >&2
  exit 1
fi

if [ -e "$DESTINATION" ] && [ ! -d "$DESTINATION" ]; then
  echo "Destination existante mais ce n'est pas un dossier : $DESTINATION" >&2
  exit 1
fi

if [ -d "$DESTINATION" ] && [ -n "$(find "$DESTINATION" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  if [ "$FORCER" -eq 0 ]; then
    echo "Le dossier $DESTINATION n'est pas vide. Utilise --force pour le remplacer." >&2
    exit 1
  fi
fi

if [ "$OUI" -eq 0 ]; then
  if [ ! -t 0 ]; then
    echo "Aucun terminal interactif : ajoute --oui pour confirmer l'extraction." >&2
    exit 1
  fi
  printf 'Extraire les archives de %s vers %s ? [o/N] ' "$ARCHIVES" "$DESTINATION"
  read -r reponse
  case "$reponse" in
    o|O|oui|Oui|OUI) ;;
    *) echo "Restauration annulée."; exit 1 ;;
  esac
fi

if [ -d "$DESTINATION" ]; then
  while IFS= read -r -d '' entree; do
    rm -rf -- "$entree"
  done < <(find "$DESTINATION" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
fi
mkdir -p "$DESTINATION/txdata" "$DESTINATION/maps"

base="$(preparer_lisible "$(fichier_archive base.sql.gz)")"
txdata="$(preparer_lisible "$(fichier_archive txdata.tar.gz)")"
maps="$(preparer_lisible "$(fichier_archive maps.tar.gz)")"

echo "Extraction de base.sql.gz…"
gzip -dc "$base" > "$DESTINATION/base.sql"

echo "Extraction de txdata.tar.gz…"
tar -xzf "$txdata" -C "$DESTINATION/txdata"

echo "Extraction de maps.tar.gz…"
tar -xzf "$maps" -C "$DESTINATION/maps"

if source_jeu="$(fichier_archive jeu.tar.gz)"; then
  mkdir -p "$DESTINATION/jeu"
  jeu="$(preparer_lisible "$source_jeu")"
  echo "Extraction de jeu.tar.gz…"
  tar -xzf "$jeu" -C "$DESTINATION/jeu"
fi

cat <<EOF

Restauration extraite dans : $DESTINATION
  - $DESTINATION/base.sql
  - $DESTINATION/txdata/
  - $DESTINATION/maps/
  - $DESTINATION/jeu/ (personnages, photos, véhicules ; si la sauvegarde en contient)

Aucune pile de production n'a été touchée. Pour tester l'import dans une pile
jetable (projet « gunfight-restore », volumes séparés) :

  1. démarre une pile jetable sans publier les ports de production ;
  2. importe le dump dans son MariaDB ;
  3. copie txdata/ et maps/ dans ses volumes ;
  4. vérifie le démarrage, puis supprime la pile et ses volumes.

La procédure complète, avec les commandes exactes et les contrôles attendus,
est dans docs/runbooks/restauration.md.
EOF
