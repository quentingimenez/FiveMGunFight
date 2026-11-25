#!/usr/bin/env bash
# =============================================================================
#  Vérifications statiques du dépôt FiveMGunFight.
#
#  Usage : bash scripts/verifier.sh
#
#  Ces contrôles sont identiques en local et en CI (workflow « Qualité ») :
#  une erreur ici = une pull request bloquée. Tous les contrôles sont exécutés
#  même si l'un échoue, puis le script sort en code 1.
#
#  Un contrôle est ignoré (avec un message) quand l'outil correspondant
#  n'existe pas sur la machine ; la CI, elle, installe tout et ne saute rien.
# =============================================================================
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

echecs=0
titre() { printf '\n== %s\n' "$1"; }
ok() { printf '   ok      %s\n' "$1"; }
echec() { printf '   ECHEC   %s\n' "$1"; echecs=$((echecs + 1)); }
ignore() { printf '   ignore  %s\n' "$1"; }
details() { sed 's/^/           /'; }

# --- 1. Syntaxe Lua ---------------------------------------------------------
titre "Syntaxe Lua (luac -p)"
luac=""
for candidat in luac5.4 luac5.3 luac; do
  if command -v "$candidat" >/dev/null 2>&1; then
    luac="$candidat"
    break
  fi
done

if [ -z "$luac" ]; then
  ignore "luac absent (installe Lua 5.4 ; la CI le fournit)"
else
  avant=$echecs
  total_lua=0
  while IFS= read -r -d '' fichier; do
    total_lua=$((total_lua + 1))
    if ! sortie="$("$luac" -p "$fichier" 2>&1)"; then
      echec "$fichier"
      printf '%s\n' "$sortie" | details
    fi
  done < <(find server-data/resources -name '*.lua' -not -path '*/cache/*' -print0)
  if [ "$echecs" -eq "$avant" ]; then
    ok "$total_lua fichier(s) Lua"
  fi
fi

# --- 2. JSON valide ---------------------------------------------------------
titre "JSON valide"
python=""
for candidat in python3 python; do
  if command -v "$candidat" >/dev/null 2>&1; then
    python="$candidat"
    break
  fi
done
# Le raccourci "python" du Microsoft Store n'est pas un interpréteur : il ouvre
# la boutique et échoue. On le détecte pour ne pas signaler un faux échec.
if [ -z "$python" ]; then
  ignore "python absent (installe Python 3 ; la CI le fournit)"
elif ! "$python" -c 'import sys' >/dev/null 2>&1; then
  ignore "python inutilisable (raccourci Microsoft Store ?) ; la CI le fournit"
  python=""
fi

if [ -n "$python" ]; then
  avant=$echecs
  total_json=0
  while IFS= read -r -d '' fichier; do
    total_json=$((total_json + 1))
    if ! sortie="$("$python" -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$fichier" 2>&1)"; then
      echec "$fichier"
      printf '%s\n' "$sortie" | details
    fi
  done < <(find . -name '*.json' -not -path './.git/*' -not -path './node_modules/*' -not -path './server-data/cache/*' -print0)
  if [ "$echecs" -eq "$avant" ]; then
    ok "$total_json fichier(s) JSON"
  fi
fi

# --- 3. Syntaxe JavaScript (interfaces NUI) ---------------------------------
titre "Syntaxe JavaScript (node --check)"
if ! command -v node >/dev/null 2>&1; then
  ignore "node absent (la CI le fournit)"
else
  avant=$echecs
  total_js=0
  while IFS= read -r -d '' fichier; do
    total_js=$((total_js + 1))
    if ! sortie="$(node --check "$fichier" 2>&1)"; then
      echec "$fichier"
      printf '%s\n' "$sortie" | details
    fi
  done < <(find . -name '*.js' -not -path './.git/*' -not -path './node_modules/*' -not -path './server-data/cache/*' -print0)
  if [ "$echecs" -eq "$avant" ]; then
    ok "$total_js fichier(s) JS"
  fi
fi

# --- 4. Scripts shell -------------------------------------------------------
titre "Scripts shell (sh -n / bash -n, shellcheck)"
analyser_shell() {
  if head -n 1 "$1" | grep -q 'bash'; then
    bash -n "$1"
  else
    sh -n "$1"
  fi
}

avant=$echecs
total_sh=0
while IFS= read -r -d '' fichier; do
  total_sh=$((total_sh + 1))
  if ! sortie="$(analyser_shell "$fichier" 2>&1)"; then
    echec "$fichier (syntaxe)"
    printf '%s\n' "$sortie" | details
  fi
  if command -v shellcheck >/dev/null 2>&1; then
    # -S error : seuls les vrais problèmes (analyse impossible) bloquent ;
    # les remarques de style restent visibles sans casser la CI.
    if ! sortie="$(shellcheck -S error -x "$fichier" 2>&1)"; then
      echec "$fichier (shellcheck)"
      printf '%s\n' "$sortie" | details
    fi
  fi
done < <(find . \( -name '*.sh' -o -path './.githooks/*' \) -type f -not -path './.git/*' -not -path './server-data/cache/*' -print0)
if [ "$echecs" -eq "$avant" ]; then
  if command -v shellcheck >/dev/null 2>&1; then
    ok "$total_sh script(s) shell"
  else
    ok "$total_sh script(s) shell (shellcheck non exécuté)"
    ignore "shellcheck absent (la CI le fournit)"
  fi
fi

# --- 5. docker compose ------------------------------------------------------
titre "docker compose config"
if ! command -v docker >/dev/null 2>&1; then
  ignore "docker absent"
elif ! docker compose version >/dev/null 2>&1; then
  ignore "docker compose v2 indisponible (démon Docker arrêté ?)"
else
  # docker-compose.yml référence « env_file: .env », absent d'un clone neuf :
  # on valide alors avec le modèle, puis on retire le fichier temporaire.
  env_temporaire=0
  if [ ! -f .env ]; then
    cp .env.example .env
    env_temporaire=1
  fi

  # Le socle seul ne définit ni build ni image pour fxserver : on valide les
  # deux combinaisons réellement utilisées (développement puis production).
  if sortie="$(docker compose -f docker-compose.yml -f docker-compose.dev.yml config -q 2>&1)"; then
    ok "socle + dev valides"
  else
    echec "socle + dev"
    printf '%s\n' "$sortie" | details
  fi

  # La surcouche prod exige IMAGE_REF : on fournit une valeur de test si ni
  # l'environnement ni .env n'en définissent une, sans écraser la leur.
  image_ref_temporaire=0
  image_ref_definie=0
  if [ -n "${IMAGE_REF:-}" ]; then
    image_ref_definie=1
  elif [ -f .env ] && grep -Eq '^[[:space:]]*IMAGE_REF=[^[:space:]]' .env; then
    image_ref_definie=1
  fi
  if [ "$image_ref_definie" -eq 0 ]; then
    IMAGE_REF="exemple.invalid/gunfight:test"
    export IMAGE_REF
    image_ref_temporaire=1
  fi
  if sortie="$(docker compose -f docker-compose.yml -f docker-compose.prod.yml config -q 2>&1)"; then
    ok "socle + prod valides"
  else
    echec "socle + prod"
    printf '%s\n' "$sortie" | details
  fi
  if [ "$image_ref_temporaire" -eq 1 ]; then
    unset IMAGE_REF
  fi

  if [ "$env_temporaire" -eq 1 ]; then
    rm -f .env
  fi
fi

# --- Bilan ------------------------------------------------------------------
printf '\n'
if [ "$echecs" -eq 0 ]; then
  echo "Toutes les vérifications statiques sont passées."
  exit 0
fi
echo "$echecs vérification(s) en échec : corrige-les avant d'ouvrir la pull request." >&2
exit 1
