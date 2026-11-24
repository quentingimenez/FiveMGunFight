#!/bin/sh
# =============================================================================
#  Démarrage du conteneur :
#  1. génère server-data/secrets.cfg à partir des variables du fichier .env
#  2. lance FXServer (txAdmin est intégré à FXServer et démarre avec lui)
# =============================================================================
set -e

DATA=/opt/fivem/server-data
SERVER=/opt/fivem/server

# Le fichier .env est écrit sous Windows : un "\r" en fin de valeur casserait la
# clé de licence ou les mots de passe. On nettoie chaque variable lue.
strip_cr() {
  printf '%s' "$1" | tr -d '\r'
}

LICENSE_KEY="$(strip_cr "${LICENSE_KEY:-}")"
SERVER_NAME="$(strip_cr "${SERVER_NAME:-Gunfight}")"
MAX_PLAYERS="$(strip_cr "${MAX_PLAYERS:-300}")"
ADMIN_IDENTIFIERS="$(strip_cr "${ADMIN_IDENTIFIERS:-}")"
STEAM_WEB_API_KEY="$(strip_cr "${STEAM_WEB_API_KEY:-}")"
DB_HOST="$(strip_cr "${DB_HOST:-mariadb}")"
DB_NAME="$(strip_cr "${MARIADB_DATABASE:-gunfight}")"
DB_USER="$(strip_cr "${MARIADB_USER:-gunfight}")"
DB_PASS="$(strip_cr "${MARIADB_PASSWORD:-}")"
TXADMIN="$(strip_cr "${TXADMIN:-true}")"

if [ -z "$LICENSE_KEY" ] || [ "$LICENSE_KEY" = "change_moi" ]; then
  echo "=================================================================="
  if [ -z "$LICENSE_KEY" ]; then
    echo " ERREUR : LICENSE_KEY est vide dans le fichier .env"
  else
    echo " ERREUR : LICENSE_KEY vaut encore change_moi dans le fichier .env"
  fi
  echo " Crée ta clé sur https://portal.cfx.re puis colle-la dans .env"
  echo "=================================================================="
  exit 1
fi

if [ ! -f "$DATA/server.cfg" ]; then
  echo " ERREUR : $DATA/server.cfg est introuvable (volume monté ?)"
  exit 1
fi

case "$DB_PASS" in
  *[@:/?\#]*)
    echo " AVERTISSEMENT : MARIADB_PASSWORD contient un caractère (@ : / ? #)"
    echo " qui casse la chaîne de connexion mysql://. Utilise un mot de passe"
    echo " alphanumérique, sinon la phase 2 (oxmysql) ne pourra pas se connecter."
    ;;
esac

# --- Fichier généré automatiquement (ne pas modifier à la main) ---
{
  echo "# FICHIER GÉNÉRÉ AUTOMATIQUEMENT AU DÉMARRAGE - ne pas modifier, voir .env"
  echo "sv_licenseKey \"$LICENSE_KEY\""
  echo "sv_maxclients $MAX_PLAYERS"
  echo "sv_hostname \"$SERVER_NAME\""
  echo "set mysql_connection_string \"mysql://$DB_USER:$DB_PASS@$DB_HOST/$DB_NAME?charset=utf8mb4\""
  if [ -n "$STEAM_WEB_API_KEY" ]; then
    echo "set steam_webApiKey \"$STEAM_WEB_API_KEY\""
  fi
  # Administrateurs : ADMIN_IDENTIFIERS=fivem:123456,license:abcdef...
  # Une entrée est ignorée si elle ne ressemble pas à un identifiant (type:valeur),
  # pour éviter d'inscrire un groupe admin à partir d'une faute de frappe.
  if [ -n "$ADMIN_IDENTIFIERS" ]; then
    echo "$ADMIN_IDENTIFIERS" | tr ',' '\n' | while read -r id; do
      id="$(printf '%s' "$id" | tr -d ' \t\r')"
      case "$id" in
        :*|*:|"") ;;   # vide ou sans valeur
        *:*) echo "add_principal identifier.$id group.admin" ;;
        *) echo "AVERTISSEMENT : identifiant admin ignoré (format attendu type:valeur) : $id" >&2 ;;
      esac
    done
  fi
} > "$DATA/secrets.cfg"

echo "secrets.cfg généré (joueurs max : $MAX_PLAYERS)"
echo "Version FXServer : $(cat "$SERVER/FX_VERSION.txt" 2>/dev/null)"
echo "Connexion en jeu : touche F8 puis  connect localhost"

# Le répertoire courant devient le "data dir" de FXServer : c'est lui qui
# contient server.cfg, resources/ et secrets.cfg.
cd "$DATA"

if [ "$TXADMIN" = "true" ]; then
  # Mode moniteur : txAdmin démarre en même temps que FXServer, sert le panneau
  # web sur le port 40120 et lance lui-même le serveur de jeu.
  #
  # IMPORTANT : dans ce mode il ne faut AUCUN argument (+exec, etc.) après
  # run.sh, sinon txAdmin plante (SIGSEGV) au démarrage.
  echo "txAdmin          : activé -> http://localhost:40120"
  echo "  Premier lancement : choisis un compte admin dans le navigateur, puis"
  echo "  indique $DATA comme dossier de données du serveur."
  exec "$SERVER/run.sh" +set monitorMode true
fi

echo "txAdmin          : désactivé (TXADMIN=false)"
exec "$SERVER/run.sh" +exec server.cfg
