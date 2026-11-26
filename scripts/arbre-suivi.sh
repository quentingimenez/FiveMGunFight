#!/usr/bin/env bash
# =============================================================================
#  Copie dans un dossier les fichiers que Git voit dans l'arbre de travail.
#
#  Usage : bash scripts/arbre-suivi.sh <dossier-destination>
#
#  gitleaks dir lit tout le contenu du dossier analysé, fichiers ignorés par
#  Git compris (.env, secrets/, server-data/secrets.cfg...). Pour contrôler les
#  secrets de ce qui sera réellement versionné, ce script recopie l'arbre tel
#  que Git le voit dans une destination vide, hors du dépôt : fichiers suivis
#  et fichiers non suivis non ignorés.
#
#  Codes de sortie :
#    0  copie terminée ;
#    2  destination absente ou non vide (ou usage incorrect) ;
#    3  dépôt Git illisible (git absent, pas un arbre de travail...).
# =============================================================================
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage : bash scripts/arbre-suivi.sh <dossier-destination>\n' >&2
  exit 2
fi

destination=$1

# Se placer à la racine du dépôt, quel que soit le dossier d'appel.
cd "$(dirname "$0")/.." || exit 1

# Un worktree dont le .git pointe hors du montage Docker, un dossier copié
# sans .git ou un git absent : la liste des fichiers ne peut pas être établie.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'arbre-suivi : dépôt Git illisible dans %s\n' "$PWD" >&2
  exit 3
fi

if [ ! -d "$destination" ]; then
  printf 'arbre-suivi : destination absente : %s\n' "$destination" >&2
  exit 2
fi

# La destination doit être vide : des restes d'un passage précédent
# fausseraient l'analyse des secrets.
if [ -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  printf 'arbre-suivi : destination non vide : %s\n' "$destination" >&2
  exit 2
fi

# --cached : fichiers suivis, même ceux dont la suppression n'est pas commitée ;
# --others --exclude-standard : non suivis, sans ceux ignorés par Git.
# -z et read -d '' protègent les noms contenant des espaces ou des retours à la
# ligne. Un fichier suivi puis supprimé du disque n'existe plus : il est ignoré.
if ! liste="$(mktemp)"; then
  printf 'arbre-suivi : fichier temporaire indisponible\n' >&2
  exit 3
fi
trap 'rm -f -- "$liste"' EXIT

# La liste est matérialisée avant la boucle : sans cela, un échec de
# `git ls-files` dans la substitution de processus passerait inaperçu et la
# copie vide ferait croire à tort qu'aucun secret n'est présent.
if ! git ls-files -z --cached --others --exclude-standard > "$liste"; then
  printf 'arbre-suivi : git ls-files a échoué dans %s\n' "$PWD" >&2
  exit 3
fi

while IFS= read -r -d '' chemin; do
  if [ -f "$chemin" ] || [ -L "$chemin" ]; then
    cp --parents -- "$chemin" "$destination"
  fi
done < "$liste"
