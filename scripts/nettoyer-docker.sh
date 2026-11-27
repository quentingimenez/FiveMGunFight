#!/usr/bin/env bash
# =============================================================================
#  Libère l'espace disque pris par les constructions Docker du dépôt.
#
#  Usage : bash scripts/nettoyer-docker.sh [--tout]
#
#  Par défaut (lancé tout seul à la fin de scripts/verifier-docker.sh) :
#    - supprime les images « <none> » laissées par chaque reconstruction ;
#    - ramène le cache de construction sous GF_CACHE_MAX (défaut 4GB), en
#      jetant d'abord les couches les plus anciennes : les reconstructions
#      suivantes restent rapides.
#  --tout (fin de session, ou disque plein) :
#    - vide tout le cache de construction inutilisé ;
#    - supprime aussi les images qu'aucun conteneur n'utilise (images de
#      vérification, anciennes images du serveur). Elles se reconstruisent
#      au prochain besoin.
#
#  Jamais touchés : conteneurs, volumes (base de données, txAdmin), images
#  d'un conteneur existant, même arrêté.
#
#  Sous Windows, Docker Desktop garde son disque virtuel (docker_data.vhdx)
#  à sa taille maximale : l'espace libéré est réutilisé par Docker, mais ne
#  revient à Windows qu'après compactage (docs/debug-test.md, « Espace disque »).
# =============================================================================
set -euo pipefail

mode="borne"
case "${1:-}" in
  "") ;;
  --tout) mode="tout" ;;
  -h|--help) sed -n '3,23p' "$0" | sed 's/^#  \{0,1\}//'; exit 0 ;;
  *) echo "Option inconnue : $1 (attendu : --tout)" >&2; exit 2 ;;
esac

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker injoignable : rien à nettoyer (démarre Docker Desktop)." >&2
  exit 1
fi

cache_max="${GF_CACHE_MAX:-4GB}"

echo "== Espace Docker avant nettoyage"
docker system df

docker image prune --force >/dev/null
if [ "$mode" = "tout" ]; then
  docker builder prune --all --force >/dev/null
  docker image prune --all --force >/dev/null
else
  docker builder prune --all --force --max-used-space "$cache_max" >/dev/null
fi

echo "== Espace Docker après nettoyage ($mode)"
docker system df
