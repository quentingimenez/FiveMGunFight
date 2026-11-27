#!/usr/bin/env bash
# =============================================================================
#  Commande unique de vérification du dépôt FiveMGunFight.
#
#  Usage : bash scripts/verifier-docker.sh
#
#  Construit l'image docker/verifier (tous les outils épinglés) puis exécute
#  scripts/verifier.sh dedans, avec le dépôt monté dans /depot. C'est la même
#  commande en local et en CI : aucun outil n'est installé sur l'hôte.
#
#  GF_VERIFIER_IMAGE=image:tag permet de réutiliser une image déjà construite
#  au lieu de la reconstruire (CI, ou essai hors ligne).
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

image="${GF_VERIFIER_IMAGE:-gunfight-verifier:local}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker est requis : démarre Docker Desktop." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker est requis : démarre Docker Desktop (démon injoignable)." >&2
  exit 1
fi

# Sous Git Bash (MSYS), pwd -W donne le chemin Windows attendu par Docker et
# MSYS_NO_PATHCONV=1 empêche la réécriture du montage « C:/...:/depot ».
# Sous Linux/WSL, pwd -W échoue et on monte le chemin POSIX habituel.
if racine="$(pwd -W 2>/dev/null)"; then
  export MSYS_NO_PATHCONV=1
else
  racine="$(pwd)"
fi

# En fin de course, réussite ou échec : images orphelines jetées et cache de
# construction borné (scripts/nettoyer-docker.sh). Sauté en CI (runner jetable)
# et avec GF_GARDER_CACHE=1. Le code de sortie de la vérification est conservé.
nettoyer() {
  statut=$?
  if [ -z "${CI:-}" ] && [ "${GF_GARDER_CACHE:-0}" != "1" ]; then
    if bash scripts/nettoyer-docker.sh >/dev/null 2>&1; then
      echo "Docker : images orphelines et cache de construction nettoyés."
    else
      echo "Docker : nettoyage impossible, relancer bash scripts/nettoyer-docker.sh." >&2
    fi
  fi
  exit "$statut"
}
trap nettoyer EXIT

if [ -z "${GF_VERIFIER_IMAGE:-}" ]; then
  docker build --tag "$image" --file docker/verifier/Dockerfile docker/verifier
fi

docker run --rm -v "${racine}:/depot" -w /depot "$image" bash scripts/verifier.sh
