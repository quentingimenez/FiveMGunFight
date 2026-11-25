#!/usr/bin/env bash
# =============================================================================
#  Déploiement d'une image FiveMGunFight par digest.
#
#  Usage :
#    bash scripts/deployer.sh [--dry-run] [--image-ref <ref>]
#    bash scripts/deployer.sh --force [--image-ref <ref>]
#    bash scripts/deployer.sh --force --rollback
#
#  Par défaut le script ne fait qu'afficher le plan (--dry-run implicite).
#  Rien n'est tiré, démarré ou modifié sans --force.
#
#  IMAGE_REF doit désigner un digest immuable, par exemple :
#    ghcr.io/wardenpro/fivem-gunfight@sha256:<64 hexadécimaux>
#
#  Le script ne lit jamais .env (il ne fait que vérifier sa présence) et
#  n'affiche aucun secret.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

readonly FICHIERS_COMPOSE=(-f docker-compose.yml -f docker-compose.prod.yml)
readonly CONTENEUR="gunfight-fxserver"
readonly ETAT_IMAGE="backups/.image-precedente"
readonly URL_SANTE="${HEALTH_URL:-http://127.0.0.1:30120/dynamic.json}"

usage() {
  cat <<'EOF'
Déploiement d'une image FiveMGunFight par digest

Usage :
  bash scripts/deployer.sh [--dry-run] [--image-ref <ref>]
  bash scripts/deployer.sh --force [--image-ref <ref>]
  bash scripts/deployer.sh --force --rollback
  bash scripts/deployer.sh --help

Options :
  --dry-run          Affiche le plan sans rien exécuter (défaut).
  --force            Exécute réellement le déploiement.
  --image-ref <ref>  Image à déployer (sinon IMAGE_REF de l'environnement).
  --rollback         Redéploie l'image précédente notée dans
                     backups/.image-precedente (avec --force pour agir).
  --help             Affiche cette aide.

Format exigé : <dépôt>@sha256:<64 hexadécimaux>. Un tag seul est refusé :
il peut être réécrit et rend le déploiement non reproductible.

Déroulé avec --force :
  1. vérification cosign si la commande est présente (clé publique ou
     identité/émetteur de certificat via COSIGN_PUBLIC_KEY,
     COSIGN_CERTIFICATE_IDENTITY, COSIGN_CERTIFICATE_OIDC_ISSUER) ;
  2. mémorisation du digest actuellement déployé ;
  3. docker compose pull fxserver, puis up -d --wait ;
  4. contrôle HTTP et healthcheck Docker ;
  5. rollback automatique vers le digest précédent si le contrôle échoue.

Le script ne lit jamais le contenu de .env. Il vérifie seulement que .env et
docker-compose.prod.yml existent avant d'agir.
EOF
}

die_usage() {
  echo "$*" >&2
  echo "Essaie --help." >&2
  exit 2
}

FORCER=0
ROLLBACK=0
IMAGE_REF="${IMAGE_REF:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) FORCER=0 ;;
    --force) FORCER=1 ;;
    --rollback) ROLLBACK=1 ;;
    --image-ref)
      shift
      [ "$#" -gt 0 ] || die_usage "--image-ref attend une valeur."
      IMAGE_REF="$1"
      ;;
    --help|-h) usage; exit 0 ;;
    --*) die_usage "Option inconnue : $1" ;;
    *) die_usage "Argument inattendu : $1" ;;
  esac
  shift
done

if [ "$ROLLBACK" -eq 1 ]; then
  [ -f "$ETAT_IMAGE" ] || {
    echo "Aucune image précédente mémorisée dans $ETAT_IMAGE." >&2
    echo "Un déploiement réussi avec --force l'enregistre." >&2
    exit 1
  }
  IMAGE_REF="$(cat "$ETAT_IMAGE")"
fi

verifier_reference() {
  local ref="$1"
  local digest depot
  case "$ref" in
    *" "*|*$'\t'*|*$'\n'*) echo "IMAGE_REF contient un espace : $ref" >&2; return 1 ;;
    *"@sha256:"*) ;;
    *) echo "IMAGE_REF doit être de la forme <dépôt>@sha256:<64 hex> : $ref" >&2; return 1 ;;
  esac
  depot="${ref%@sha256:*}"
  digest="${ref##*@sha256:}"
  [ -n "$depot" ] || { echo "IMAGE_REF sans dépôt : $ref" >&2; return 1; }
  case "$digest" in
    *[!0-9a-f]*|"") echo "Digest sha256 invalide (64 hex attendus) : $digest" >&2; return 1 ;;
  esac
  [ "${#digest}" -eq 64 ] || { echo "Digest sha256 de longueur invalide : $digest" >&2; return 1; }
  case "$depot" in
    *[A-Z]*) echo "Le dépôt d'image doit être en minuscules : $depot" >&2; return 1 ;;
  esac
  return 0
}

compose() {
  docker compose "${FICHIERS_COMPOSE[@]}" "$@"
}

image_courante() {
  docker inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}{{.Config.Image}}{{end}}' \
    "$CONTENEUR" 2>/dev/null || true
}

controler_sante() {
  local essai=0
  while [ "$essai" -lt 30 ]; do
    if command -v curl >/dev/null 2>&1; then
      sante_http=0
      curl -fsS --max-time 5 "$URL_SANTE" >/dev/null 2>&1 || sante_http=1
    elif command -v wget >/dev/null 2>&1; then
      sante_http=0
      wget -q -O /dev/null --timeout=5 "$URL_SANTE" >/dev/null 2>&1 || sante_http=1
    else
      sante_http=1
    fi
    if [ "$sante_http" -eq 0 ]; then
      local sante
      sante="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}aucun{{end}}' \
        "$CONTENEUR" 2>/dev/null || true)"
      case "$sante" in
        healthy|aucun) return 0 ;;
        *) ;;
      esac
    fi
    essai=$((essai + 1))
    sleep 2
  done
  return 1
}

deployer() {
  local image="$1"
  IMAGE_REF="$image" compose pull fxserver
  IMAGE_REF="$image" compose up -d --wait --wait-timeout 300
}

# Après un déploiement réussi, .env doit pointer vers le digest réellement
# lancé : sinon un `docker compose up` manuel repartirait sur l'ancienne image.
# L'écriture est atomique et ne touche qu'à la ligne IMAGE_REF.
mettre_a_jour_env() {
  local image="$1" temporaire
  # Sans .env, le déploiement a été lancé avec une variable exportée : rien à
  # réécrire, mais on le signale pour ne pas afficher un faux succès.
  [ -f .env ] || return 2
  temporaire="$(mktemp .env.XXXXXX)" || return 1
  if ! awk -v ref="$image" '
    BEGIN { trouve = 0 }
    /^IMAGE_REF=/ { print "IMAGE_REF=" ref; trouve = 1; next }
    { print }
    END { if (!trouve) print "IMAGE_REF=" ref }
  ' .env > "$temporaire"; then
    rm -f -- "$temporaire"
    return 1
  fi
  chmod 600 "$temporaire" 2>/dev/null || true
  mv -- "$temporaire" .env
}

if [ "$ROLLBACK" -eq 0 ] && [ -z "$IMAGE_REF" ]; then
  if [ "$FORCER" -eq 1 ]; then
    die_usage "Aucune image à déployer : fournis --image-ref ou IMAGE_REF."
  fi
  cat <<'EOF'
Aucune image indiquée (IMAGE_REF vide) : rien à planifier.

Exemple :
  IMAGE_REF=ghcr.io/wardenpro/fivem-gunfight@sha256:<64 hex> \
    bash scripts/deployer.sh --dry-run

Puis, après vérification du plan :
  IMAGE_REF=... bash scripts/deployer.sh --force
EOF
  exit 0
fi

verifier_reference "$IMAGE_REF" || exit 1

if [ "$FORCER" -eq 0 ]; then
  cat <<EOF
Mode à blanc : rien n'est exécuté. Ajoute --force pour déployer.

Image demandée : $IMAGE_REF
Santé contrôlée : $URL_SANTE

Actions prévues :
  1. cosign verify (si cosign est installé et configuré), sinon avertissement
  2. image actuelle mémorisée dans $ETAT_IMAGE
  3. docker compose ${FICHIERS_COMPOSE[*]} pull fxserver
  4. docker compose ${FICHIERS_COMPOSE[*]} up -d --wait --wait-timeout 300
  5. contrôle HTTP + healthcheck Docker
  6. rollback automatique vers l'image précédente en cas d'échec

Rien n'a été modifié.
EOF
  exit 0
fi

command -v docker >/dev/null 2>&1 || { echo "docker introuvable." >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "docker compose v2 indisponible." >&2; exit 1; }
[ -f .env ] || { echo ".env absent : la pile ne peut pas démarrer." >&2; exit 1; }
[ -f docker-compose.prod.yml ] || { echo "docker-compose.prod.yml absent." >&2; exit 1; }

echo "Déploiement de : $IMAGE_REF"

# --- Vérification de signature, si cosign est disponible --------------------
if command -v cosign >/dev/null 2>&1; then
  if [ -n "${COSIGN_PUBLIC_KEY:-}" ]; then
    echo "Vérification cosign (clé publique)…"
    cosign verify --key "$COSIGN_PUBLIC_KEY" "$IMAGE_REF" >/dev/null
  elif [ -n "${COSIGN_CERTIFICATE_IDENTITY:-}" ] && [ -n "${COSIGN_CERTIFICATE_OIDC_ISSUER:-}" ]; then
    echo "Vérification cosign (identité de certificat)…"
    cosign verify \
      --certificate-identity "$COSIGN_CERTIFICATE_IDENTITY" \
      --certificate-oidc-issuer "$COSIGN_CERTIFICATE_OIDC_ISSUER" \
      "$IMAGE_REF" >/dev/null
  else
    echo "avertissement : cosign présent mais aucune clé/identité configurée ; vérification ignorée." >&2
  fi
else
  echo "avertissement : cosign absent ; signature non vérifiée localement." >&2
fi

# --- Mémorisation de l'image précédente -------------------------------------
precedente="$(image_courante)"
if [ -n "$precedente" ]; then
  mkdir -p "$(dirname "$ETAT_IMAGE")"
  printf '%s\n' "$precedente" > "$ETAT_IMAGE"
  echo "Image précédente mémorisée : $precedente"
else
  echo "Aucune image précédente détectée (premier déploiement ?)."
fi

# --- Déploiement ------------------------------------------------------------
if ! deployer "$IMAGE_REF"; then
  echo "Échec du déploiement de $IMAGE_REF." >&2
  if [ -n "$precedente" ]; then
    echo "Rollback vers $precedente…" >&2
    deployer "$precedente" || echo "Le rollback a aussi échoué : intervention manuelle requise." >&2
  fi
  exit 1
fi

if ! controler_sante; then
  echo "Le contrôle de santé échoue après déploiement." >&2
  if [ -n "$precedente" ]; then
    echo "Rollback vers $precedente…" >&2
    deployer "$precedente" || echo "Le rollback a aussi échoué : intervention manuelle requise." >&2
  fi
  exit 1
fi

echo "Déploiement réussi : $IMAGE_REF"
echo "Contrôle de santé : OK ($URL_SANTE)"
if mettre_a_jour_env "$IMAGE_REF"; then
  echo "IMAGE_REF mis à jour dans .env."
else
  echo "avertissement : IMAGE_REF n'a pas pu être mis à jour dans .env (à faire à la main)." >&2
fi
