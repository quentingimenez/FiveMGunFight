#!/usr/bin/env bash
# =============================================================================
#  Contrôle de santé de la pile de production FiveMGunFight.
#
#  Usage :
#    bash scripts/verifier-sante.sh [--quiet] [--dry-run]
#    bash scripts/verifier-sante.sh --help
#
#  Contrôles effectués :
#    1. réponse HTTP de FXServer sur /dynamic.json ;
#    2. état des conteneurs fxserver et mariadb (docker compose ps) ;
#    3. healthcheck MariaDB (healthcheck.sh --connect --innodb_initialized) ;
#    4. espace disque libre (15 % par défaut) ;
#    5. redémarrages récents des conteneurs.
#
#  Variables (toutes facultatives) :
#    HEALTH_URL                 URL de contrôle (défaut 127.0.0.1:30120/dynamic.json)
#    SANTE_COMPOSE_FILES        fichiers Compose (défaut socle + prod)
#    DISK_MIN_FREE_PERCENT      seuil d'espace libre en pourcentage (défaut 15)
#    RESTART_WINDOW_MINUTES     fenêtre de « redémarrage récent » (défaut 15)
#    ALERT_WEBHOOK              URL de webhook, prévenue en cas d'échec
#    SANTE_STATE_FILE           fichier de déduplication (défaut backups/.sante-alerte)
#
#  Le script ne lit jamais les secrets de .env et n'affiche jamais l'URL du
#  webhook. Code de sortie : 0 si tout va bien, 1 si un contrôle échoue.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

readonly URL_SANTE="${HEALTH_URL:-http://127.0.0.1:30120/dynamic.json}"
readonly FICHIERS_COMPOSE="${SANTE_COMPOSE_FILES:-docker-compose.yml docker-compose.prod.yml}"
readonly SEUIL_DISQUE="${DISK_MIN_FREE_PERCENT:-15}"
readonly FENETRE_REDEMARRAGE="${RESTART_WINDOW_MINUTES:-15}"
readonly FICHIER_ETAT="${SANTE_STATE_FILE:-backups/.sante-alerte}"

QUIET=0
DRY_RUN=0

for argument in "$@"; do
  case "$argument" in
    --quiet|-q) QUIET=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      cat <<'EOF'
Contrôle de santé de la production

Usage :
  bash scripts/verifier-sante.sh [--quiet] [--dry-run]
  bash scripts/verifier-sante.sh --help

Options :
  --quiet     N'affiche que les échecs (et le bilan final).
  --dry-run   Décrit les contrôles sans contacter Docker, le réseau ni le disque.
  --help      Affiche cette aide.

Contrôles :
  - HTTP   : GET $HEALTH_URL (surchargeable par la variable HEALTH_URL) ;
  - Docker : conteneurs fxserver et mariadb en marche (docker compose ps) ;
  - MariaDB: healthcheck.sh --connect --innodb_initialized dans le conteneur ;
  - disque : au moins DISK_MIN_FREE_PERCENT % libres (15 par défaut) ;
  - arrêts : redémarrages survenus dans RESTART_WINDOW_MINUTES (15 par défaut).

Variables :
  HEALTH_URL               URL de contrôle HTTP.
  SANTE_COMPOSE_FILES      fichiers Compose, séparés par des espaces.
  DISK_MIN_FREE_PERCENT    seuil d'espace libre (défaut 15).
  RESTART_WINDOW_MINUTES   fenêtre de redémarrage récent (défaut 15).
  ALERT_WEBHOOK            webhook POST JSON, optionnel. Les alertes identiques
                           ne sont envoyées qu'une fois grâce à un fichier
                           d'état (SANTE_STATE_FILE, défaut backups/.sante-alerte).
  SANTE_STATE_FILE         fichier de déduplication des alertes.

Code de sortie : 0 si tous les contrôles passent, 1 sinon. Le script ne lit
jamais .env et n'affiche jamais l'URL du webhook.
EOF
      exit 0
      ;;
    *)
      echo "Option inconnue : $argument (essaie --help)" >&2
      exit 2
      ;;
  esac
done

echecs=0
declare -a details_echecs=()

echec() {
  printf 'ECHEC   %s\n' "$*" >&2
  details_echecs+=("$*")
  echecs=$((echecs + 1))
}

ok() {
  if [ "$QUIET" -eq 0 ]; then
    printf 'ok      %s\n' "$*"
  fi
}

info() {
  if [ "$QUIET" -eq 0 ]; then
    printf '%s\n' "$*"
  fi
}

compose() {
  local -a fichiers=()
  local -a arguments=()
  local fichier
  read -r -a fichiers <<< "$FICHIERS_COMPOSE"
  for fichier in "${fichiers[@]}"; do
    arguments+=(-f "$fichier")
  done
  docker compose "${arguments[@]}" "$@"
}

premier_conteneur() {
  local service="$1"
  local sortie
  sortie="$(compose ps -q "$service" 2>/dev/null || true)"
  printf '%s\n' "${sortie%%$'\n'*}"
}

http_get() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 5 "$URL_SANTE"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout=5 "$URL_SANTE"
  else
    return 127
  fi
}

empreinte() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | cksum | awk '{print $1}'
  fi
}

echapper_json() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '
}

envoyer_alerte() {
  local message="$1"
  local empreinte_message corps reponse

  if [ -z "${ALERT_WEBHOOK:-}" ]; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "avertissement : curl absent, webhook non envoyé." >&2
    return 0
  fi

  empreinte_message="$(empreinte "$message")"
  if [ -f "$FICHIER_ETAT" ] && [ "$(cat "$FICHIER_ETAT" 2>/dev/null || true)" = "$empreinte_message" ]; then
    info "alerte déjà envoyée (même état), pas de doublon."
    return 0
  fi

  mkdir -p "$(dirname "$FICHIER_ETAT")" 2>/dev/null || true
  corps="$(printf '{"text":"%s","source":"gunfight","host":"%s"}' \
    "$(echapper_json "$message")" "$(echapper_json "$(hostname 2>/dev/null || echo inconnu)")")"

  # L'URL du webhook n'est jamais affichée : elle peut contenir un jeton.
  if reponse="$(curl -fsS --max-time 5 -X POST -H 'Content-Type: application/json' \
    --data "$corps" "$ALERT_WEBHOOK" 2>/dev/null)"; then
    printf '%s\n' "$empreinte_message" > "$FICHIER_ETAT" 2>/dev/null || true
    info "alerte webhook envoyée."
  else
    echo "avertissement : envoi du webhook impossible (vérifie ALERT_WEBHOOK)." >&2
  fi
  return 0
}

if [ "$DRY_RUN" -eq 1 ]; then
  cat <<EOF
Mode à blanc : aucun contrôle réel n'est exécuté.

Contrôles prévus :
  1. GET $URL_SANTE
  2. docker compose (${FICHIERS_COMPOSE}) ps : fxserver et mariadb
  3. docker compose exec -T mariadb healthcheck.sh --connect --innodb_initialized
  4. espace disque libre >= ${SEUIL_DISQUE} %
  5. redémarrages des conteneurs dans les ${FENETRE_REDEMARRAGE} dernières minutes

Webhook : $(if [ -n "${ALERT_WEBHOOK:-}" ]; then echo "configuré (URL masquée)"; else echo "non configuré"; fi)
Fichier d'état : $FICHIER_ETAT
EOF
  exit 0
fi

info "Contrôle de santé de la pile FiveMGunFight"
info "URL : $URL_SANTE"
info ""

# --- 1. FXServer répond ? ----------------------------------------------------
if http_get >/dev/null 2>&1; then
  ok "FXServer répond sur $URL_SANTE"
else
  echec "FXServer injoignable sur $URL_SANTE"
fi

# --- 2. Conteneurs en marche ------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echec "docker introuvable"
elif ! docker compose version >/dev/null 2>&1; then
  echec "docker compose v2 indisponible"
else
  for service in fxserver mariadb; do
    conteneur="$(premier_conteneur "$service")"
    if [ -z "$conteneur" ]; then
      echec "$service : conteneur absent (docker compose ps)"
      continue
    fi
    etat="$(docker inspect --format '{{.State.Status}}' "$conteneur" 2>/dev/null || true)"
    if [ "$etat" = "running" ]; then
      ok "$service : running"
    else
      echec "$service : état '$etat' au lieu de running"
    fi
    sante="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}aucun{{end}}' "$conteneur" 2>/dev/null || true)"
    case "$sante" in
      healthy) ok "$service : healthcheck healthy" ;;
      unhealthy) echec "$service : healthcheck unhealthy" ;;
      starting) echec "$service : healthcheck encore en démarrage" ;;
      aucun) info "$service : aucun healthcheck défini" ;;
      *) info "$service : healthcheck '$sante'" ;;
    esac
  done

  # --- 3. Healthcheck MariaDB ------------------------------------------------
  if compose exec -T mariadb healthcheck.sh --connect --innodb_initialized >/dev/null 2>&1; then
    ok "MariaDB accepte les connexions et InnoDB est initialisé"
  else
    echec "healthcheck MariaDB en échec (healthcheck.sh --connect --innodb_initialized)"
  fi
fi

# --- 4. Espace disque --------------------------------------------------------
if espace="$(df -Pk . 2>/dev/null | awk 'NR==2 {print $4 " " $2}')" && [ -n "$espace" ]; then
  libre="${espace%% *}"
  total="${espace##* }"
  if [ "${total:-0}" -gt 0 ]; then
    pourcentage=$((libre * 100 / total))
    if [ "$pourcentage" -lt "$SEUIL_DISQUE" ]; then
      echec "espace disque libre ${pourcentage} % < ${SEUIL_DISQUE} %"
    else
      ok "espace disque libre ${pourcentage} % (seuil ${SEUIL_DISQUE} %)"
    fi
  else
    echec "espace disque illisible (df)"
  fi
else
  echec "espace disque illisible (df)"
fi

# --- 5. Redémarrages récents -------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  maintenant="$(date +%s)"
  for service in fxserver mariadb; do
    conteneur="$(premier_conteneur "$service")"
    [ -n "$conteneur" ] || continue
    lecture="$(docker inspect --format '{{.RestartCount}}|{{.State.StartedAt}}' "$conteneur" 2>/dev/null || true)"
    compte="${lecture%%|*}"
    debut="${lecture#*|}"
    case "$compte" in
      ''|*[!0-9]*) info "$service : redémarrages illisibles" ; continue ;;
    esac
    [ "$compte" -gt 0 ] || continue
    case "$debut" in
      *.*) debut="${debut%%.*}Z" ;;
      *Z) ;;
      *) debut="${debut}Z" ;;
    esac
    if ! debut_epoch="$(date -d "$debut" +%s 2>/dev/null)"; then
      info "avertissement : $service a redémarré $compte fois (date illisible)"
      continue
    fi
    age=$((maintenant - debut_epoch))
    if [ "$age" -ge 0 ] && [ "$age" -lt $((FENETRE_REDEMARRAGE * 60)) ]; then
      echec "$service : $compte redémarrage(s), dernier il y a ${age} s"
    else
      info "avertissement : $service a redémarré $compte fois (ancien)"
    fi
  done
fi

# --- Bilan -------------------------------------------------------------------
printf '\n' >&2
if [ "$echecs" -eq 0 ]; then
  if [ -n "${ALERT_WEBHOOK:-}" ] && [ -f "$FICHIER_ETAT" ]; then
    rm -f "$FICHIER_ETAT" 2>/dev/null || true
  fi
  if [ "$QUIET" -eq 0 ]; then
    echo "Santé OK : tous les contrôles passent."
  fi
  exit 0
fi

message="$(printf 'Santé FiveMGunFight en échec sur %s : %s' \
  "$(hostname 2>/dev/null || echo inconnu)" "$(printf '%s' "${details_echecs[*]}")")"
envoyer_alerte "$message"

echo "$echecs contrôle(s) en échec." >&2
exit 1
