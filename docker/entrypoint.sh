#!/bin/sh
# =============================================================================
#  Démarrage du conteneur :
#  1. lit les secrets (Docker secrets /run/secrets/<nom>, sinon variables
#     d'environnement pour le développement)
#  2. génère server-data/secrets.cfg
#  3. lance FXServer (txAdmin est intégré à FXServer et démarre avec lui)
# =============================================================================
set -e

# Les fichiers générés par ce script (secrets.cfg) contiennent la clé de licence,
# le mot de passe MySQL et les identifiants admin : ils ne doivent être lisibles
# que par leur propriétaire (l'utilisateur fivem du conteneur en production).
umask 077

DATA=/opt/fivem/server-data
SERVER=/opt/fivem/server
SECRETS=/run/secrets

# Les fichiers .env sont écrits sous Windows : un "\r" en fin de valeur casserait
# la clé de licence ou les mots de passe. On nettoie les \r et les \n de chaque
# valeur, qu'elle vienne d'un fichier secret ou de l'environnement.
propre() {
  printf '%s' "$1" | tr -d '\r\n'
}

# Lit un secret dans /run/secrets/<nom> en priorité (production : fichiers
# Compose montés en lecture seule), sinon dans la variable d'environnement de
# repli (développement). La valeur n'est jamais affichée.
secret() {
  _secret_nom="$1"
  _secret_repli="$2"
  _secret_fichier="$SECRETS/$_secret_nom"
  if [ -r "$_secret_fichier" ]; then
    propre "$(cat "$_secret_fichier" 2>/dev/null || true)"
  else
    propre "$_secret_repli"
  fi
}

# Valeurs utiles conservées dans des variables locales : on retire ensuite les
# variables d'environnement, pour qu'elles ne soient pas héritées par FXServer
# ni visibles avec `docker exec ... env` (le jeu lit secrets.cfg, pas l'environnement).
CLE_LICENCE="$(secret license_key "${LICENSE_KEY:-}")"
CLE_STEAM="$(secret steam_web_api_key "${STEAM_WEB_API_KEY:-}")"
DB_PASS="$(secret db_password "${MARIADB_PASSWORD:-}")"
unset LICENSE_KEY STEAM_WEB_API_KEY MARIADB_PASSWORD

SERVER_NAME="$(propre "${SERVER_NAME:-Gunfight}")"
MAX_PLAYERS="$(propre "${MAX_PLAYERS:-48}")"
# La clé gratuite Cfx.re plafonne à 48 places : au-delà, FiveM refuse toute
# connexion avec « This server uses more slots than allowed by the current
# subscription ». On avertit sans bloquer : le choix d'un abonnement reste à
# l'exploitant. Le case garde le test arithmétique POSIX sûr (sh, pas bash).
case "$MAX_PLAYERS" in
  ''|*[!0-9]*)
    echo " AVERTISSEMENT : MAX_PLAYERS='$MAX_PLAYERS' n'est pas un entier :"
    echo " c'est le nombre de places par défaut (48) qui s'applique."
    MAX_PLAYERS=48
    ;;
  *)
    if [ "$MAX_PLAYERS" -gt 48 ]; then
      echo " AVERTISSEMENT : MAX_PLAYERS=$MAX_PLAYERS dépasse les 48 places de la clé gratuite."
      echo " FiveM refusera les connexions au-delà de 48 places."
      echo " Baisse MAX_PLAYERS à 48 dans .env, ou prends un abonnement Element Club"
      echo " Cfx.re : https://portal.cfx.re/subscriptions"
    fi
    ;;
esac
ADMIN_IDENTIFIERS="$(propre "${ADMIN_IDENTIFIERS:-}")"
DB_HOST="$(propre "${DB_HOST:-mariadb}")"
DB_NAME="$(propre "${MARIADB_DATABASE:-gunfight}")"
DB_USER="$(propre "${MARIADB_USER:-gunfight}")"
TXADMIN="$(propre "${TXADMIN:-true}")"

# Version du build, injectée à la construction de l'image (Dockerfile, argument
# BUILD_SHA). On ne garde que des caractères de sha : une valeur inattendue ne
# doit pas pouvoir casser server.cfg ni y injecter une commande.
BUILD_SHA="$(printf '%s' "${GF_BUILD_SHA:-}" | tr -cd '0-9a-fA-F' | cut -c1-40)"
[ -n "$BUILD_SHA" ] || BUILD_SHA=dev

if [ -z "$CLE_LICENCE" ] || [ "$CLE_LICENCE" = "change_moi" ]; then
  echo "=================================================================="
  if [ -z "$CLE_LICENCE" ]; then
    echo " ERREUR : LICENSE_KEY est vide."
    echo " Production : monte le secret license_key (/run/secrets/license_key)."
    echo " Développement : renseigne LICENSE_KEY dans .env."
  else
    echo " ERREUR : LICENSE_KEY vaut encore change_moi."
    echo " Remplace-la dans .env (développement) ou dans le secret license_key"
    echo " monté sous /run/secrets/license_key (production)."
  fi
  echo " Crée ta clé sur https://portal.cfx.re puis relance le conteneur."
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
  echo "# FICHIER GÉNÉRÉ AUTOMATIQUEMENT AU DÉMARRAGE - ne pas modifier, voir docker/entrypoint.sh"
  echo "sv_licenseKey \"$CLE_LICENCE\""
  echo "sv_maxclients $MAX_PLAYERS"
  echo "sv_hostname \"$SERVER_NAME\""
  echo "set gf_build_sha \"$BUILD_SHA\""
  echo "set mysql_connection_string \"mysql://$DB_USER:$DB_PASS@$DB_HOST/$DB_NAME?charset=utf8mb4\""
  if [ -n "$CLE_STEAM" ]; then
    echo "set steam_webApiKey \"$CLE_STEAM\""
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

# Le umask ne s'applique qu'à la création : lors d'une mise à jour, ">" réutilise
# le mode du fichier déjà présent (644 s'il a été créé par une ancienne version).
# Le chmod peut échouer sans conséquence sur certains montages Windows.
chmod 600 "$DATA/secrets.cfg" 2>/dev/null || true

# --- rcon de développement (scripts/fivem_rcon.py) ---
# Recharger une ressource sans recréer le conteneur : seule la surcouche
# docker-compose.dev.yml fixe GF_DEV_RCON=true, et seulement en mode direct
# (le mode moniteur passe par la console txAdmin). Le mot de passe est tiré au
# hasard à chaque démarrage et écrit dans cache/ (ignoré par git) pour le
# script de l'hôte. Sans ce bloc, rcon_password reste vide : rcon est fermé.
RCON_FICHIER="$DATA/cache/rcon_password"
rm -f "$RCON_FICHIER"
if [ "${GF_DEV_RCON:-}" = "true" ] && [ "$TXADMIN" != "true" ]; then
  RCON_MDP="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
  mkdir -p "$DATA/cache"
  printf '%s\n' "$RCON_MDP" > "$RCON_FICHIER"
  # `set` et non `rcon_password ...` : FXServer déclare cette convar en lecture
  # seule (ConVar_ReadOnly) ; la forme commande est ignorée depuis un .cfg.
  echo "set rcon_password \"$RCON_MDP\"" >> "$DATA/secrets.cfg"
  echo "rcon             : actif (développement, mot de passe dans cache/rcon_password)"
fi

# --- passerelle de test NUI (gf_testbridge) ---
# La ressource n'est JAMAIS assurée par server.cfg : seul le script de test
# l'ensure par rcon. La convar lue par guard.lua n'est posée qu'en développement
# via la surcouche docker-compose.dev.yml ; en production elle reste absente.
if [ "${GF_DEV_TESTBRIDGE:-}" = "true" ]; then
  echo "set gf_dev_testbridge \"true\"" >> "$DATA/secrets.cfg"
  echo "testbridge       : actif (développement)"
fi

# En production, gf_maps/data est un volume. Docker recopie le contenu de
# l'image dans un volume nommé neuf, mais un volume créé vide (ancien
# déploiement, volume préparé à la main) n'a pas de maps.json : on l'amorce avec
# la copie de référence, sinon l'éditeur de maps repartirait de zéro.
# GF_SEED_MAPS vaut "true" uniquement dans docker-compose.prod.yml ; en dev, le
# dossier du dépôt est monté.
MAPS_DATA="$DATA/resources/[gunfight]/gf_maps/data"
MAPS_DEFAUT="/opt/fivem/defaults/resources/[gunfight]/gf_maps/data"
if [ "${GF_SEED_MAPS:-false}" = "true" ] && [ ! -f "$MAPS_DATA/maps.json" ]; then
  mkdir -p "$MAPS_DATA"
  if [ -f "$MAPS_DEFAUT/maps.json" ]; then
    cp "$MAPS_DEFAUT/maps.json" "$MAPS_DATA/maps.json"
    echo "maps.json amorcé depuis le modèle de l'image"
  fi
fi

# Données créées en jeu (photos des menus, véhicule de base et customs) : en
# production ce sont des volumes. On y complète ce que l'image fournit SANS
# écraser l'existant (cp -n) : une photo ajoutée au dépôt arrive au prochain
# déploiement, une photo refaite en jeu (/thumbs) est conservée.
# GF_SEED_DATA vaut "true" en production/préproduction ; en dev, le dossier du
# dépôt est monté.
DEFAUTS_RES="/opt/fivem/defaults/resources/[gunfight]"
completer_depuis_image() {
  local relatif="$1"
  local source="$DEFAUTS_RES/$relatif"
  local cible="$DATA/resources/[gunfight]/$relatif"
  [ -d "$source" ] || return 0
  mkdir -p "$cible"
  if cp -Rn "$source/." "$cible/" 2>/dev/null; then
    echo "$relatif complété depuis l'image"
  else
    echo "AVERTISSEMENT : impossible de compléter $relatif (droits du volume ?)" >&2
  fi
}
if [ "${GF_SEED_DATA:-false}" = "true" ]; then
  completer_depuis_image "gf_thumbs/thumbs"
  completer_depuis_image "gf_vehicles/custom"
fi

echo "secrets.cfg généré (joueurs max : $MAX_PLAYERS)"
echo "Build            : $BUILD_SHA"
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
  echo "txAdmin          : activé -> http://127.0.0.1:40120"
  echo "  Premier lancement : choisis un compte admin dans le navigateur, puis"
  echo "  indique $DATA comme dossier de données du serveur."
  # Aucun argument après run.sh : c'est la condition pour que FXServer démarre
  # en mode moniteur et lance txAdmin (un "+exec" ou un "+set monitorMode"
  # explicite fait planter le serveur).
  exec "$SERVER/run.sh"
fi

echo "txAdmin          : désactivé (TXADMIN=false)"
exec "$SERVER/run.sh" +set onesync on +exec server.cfg
