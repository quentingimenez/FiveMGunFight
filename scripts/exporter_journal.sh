#!/usr/bin/env bash
# Exporte les lignes du journal d'un match depuis MariaDB (développement).
#
# Usage : scripts/exporter_journal.sh <match_id> [fichier]
#
# Sans fichier, les lignes JSON vont sur la sortie standard. Le mot de passe
# n'est jamais écrit ici : il est lu dans l'environnement du conteneur par
# `sh -c`, avec un heredoc pour le SQL. Le `donnees` est réintégré comme JSON
# (JSON_EXTRACT) et non comme une chaîne échappée. Aucun identifiant de licence
# n'est affiché en console : seul le nombre de lignes exportées est compté.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage : %s <match_id> [fichier]\n' "$0" >&2
    exit 2
fi

match_id="$1"
if [[ ! "$match_id" =~ ^[A-Za-z0-9_-]{1,40}$ ]]; then
    printf 'match_id invalide (attendu : [A-Za-z0-9_-]{1,40})\n' >&2
    exit 2
fi

sortie="${2:-}"

# Les variables MARIADB_* sont lues dans l'environnement du conteneur :
# ni le mot de passe ni la chaîne de connexion n'apparaissent dans ce script.
sql="SELECT JSON_OBJECT(
    'id', id,
    'match_id', match_id,
    'mode', mode,
    'manche', manche,
    't_ms', t_ms,
    'type', type,
    'donnees', JSON_EXTRACT(donnees, '$')
) FROM gf_match_events
WHERE match_id = '$match_id'
ORDER BY id;"

if [[ -n "$sortie" ]]; then
    docker compose -f docker-compose.yml -f docker-compose.dev.yml exec -T mariadb \
        sh -c 'exec mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" --batch --raw --skip-column-names' \
        <<<"$sql" >"$sortie"
    printf 'Journal exporté : %s ligne(s) -> %s\n' "$(wc -l <"$sortie")" "$sortie"
else
    docker compose -f docker-compose.yml -f docker-compose.dev.yml exec -T mariadb \
        sh -c 'exec mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" --batch --raw --skip-column-names' \
        <<<"$sql"
fi
