#!/usr/bin/env bash
# =============================================================================
#  Vérifications du dépôt FiveMGunFight.
#
#  Usage : bash scripts/verifier.sh
#
#  Une seule commande, la même en local et en CI (workflow « Qualité ») :
#  scripts/verifier-docker.sh construit l'image docker/verifier et exécute ce
#  script dedans, où tous les outils sont installés. Lancé directement hors de
#  l'image, un outil absent est une erreur : plus aucun contrôle n'est ignoré.
#
#  Tous les contrôles sont exécutés même si l'un échoue, puis le script sort en
#  code 1. La dernière étape lance les tests unittest du dépôt.
#
#  Variables de test :
#    GF_SANS_TESTS=1        saute l'étape unittest (évite une récursion quand
#                           un test lance ce script) ;
#    GF_OUTILS_MASQUES=a,b  simule l'absence des outils a et b.
# =============================================================================
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

echecs=0
titre() { printf '\n== %s\n' "$1"; }
ok() { printf '   ok      %s\n' "$1"; }
echec() { printf '   ECHEC   %s\n' "$1"; echecs=$((echecs + 1)); }
absent() { echec "outil absent : $1 (lance bash scripts/verifier-docker.sh)"; }
details() { sed 's/^/           /'; }

# Recherche d'un outil sur le PATH. GF_OUTILS_MASQUES permet aux tests de
# simuler un outil absent sans le désinstaller (liste séparée par des virgules).
trouver() {
  case ",${GF_OUTILS_MASQUES:-}," in
    *",$1,"*) return 1 ;;
  esac
  command -v "$1" >/dev/null 2>&1
}

# --- 1. Syntaxe Lua ---------------------------------------------------------
titre "Syntaxe Lua (luac -p)"
luac=""
for candidat in luac5.4 luac5.3 luac; do
  if trouver "$candidat"; then
    luac="$candidat"
    break
  fi
done

if [ -z "$luac" ]; then
  absent "luac"
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
  if trouver "$candidat"; then
    python="$candidat"
    break
  fi
done
# Le raccourci "python" du Microsoft Store n'est pas un interpréteur : il ouvre
# la boutique et échoue. Il doit désormais être traité comme une absence.
if [ -z "$python" ]; then
  absent "python"
elif ! "$python" -c 'import sys' >/dev/null 2>&1; then
  absent "python inutilisable (raccourci Microsoft Store ?)"
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
if ! trouver node; then
  absent "node"
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
shellcheck_disponible=0
if trouver shellcheck; then
  shellcheck_disponible=1
else
  absent "shellcheck"
fi

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
  if [ "$shellcheck_disponible" -eq 1 ]; then
    # -S error : seuls les vrais problèmes (analyse impossible) bloquent ;
    # les remarques de style restent visibles sans casser la CI.
    if ! sortie="$(shellcheck -S error -x "$fichier" 2>&1)"; then
      echec "$fichier (shellcheck)"
      printf '%s\n' "$sortie" | details
    fi
  fi
done < <(find . \( -name '*.sh' -o -path './.githooks/*' \) -type f -not -path './.git/*' -not -path './server-data/cache/*' -print0)
if [ "$echecs" -eq "$avant" ]; then
  if [ "$shellcheck_disponible" -eq 1 ]; then
    ok "$total_sh script(s) shell"
  else
    ok "$total_sh script(s) shell (shellcheck non exécuté)"
  fi
fi

# --- 5. Lua (luacheck) ------------------------------------------------------
titre "Lua (luacheck)"
if ! trouver luacheck; then
  absent "luacheck"
else
  if sortie="$(luacheck server-data/resources 2>&1)"; then
    resume="$(printf '%s\n' "$sortie" | grep '^Total:' | tail -n 1)"
    ok "${resume:-luacheck}"
  else
    echec "luacheck"
    printf '%s\n' "$sortie" | details
  fi
fi

# --- 5b. Tests unitaires Lua --------------------------------------------------
# Modules purs (sans native FiveM) testés hors du jeu : tests/lua/*.lua.
titre "Tests unitaires Lua (tests/lua)"
lua=""
for candidat in lua5.4 lua; do
  if trouver "$candidat"; then
    lua="$candidat"
    break
  fi
done

if [ -z "$lua" ]; then
  absent "lua"
else
  for fichier in tests/lua/*.lua; do
    if sortie="$("$lua" "$fichier" 2>&1)"; then
      ok "$fichier : $(printf '%s\n' "$sortie" | tail -n 1)"
    else
      echec "$fichier"
      printf '%s\n' "$sortie" | details
    fi
  done
fi

# --- 6. Workflows GitHub Actions (actionlint) -------------------------------
titre "Workflows GitHub Actions (actionlint)"
if ! trouver actionlint; then
  absent "actionlint"
else
  if sortie="$(actionlint 2>&1)"; then
    ok "workflows valides"
  else
    echec "actionlint"
    printf '%s\n' "$sortie" | details
  fi
fi

# --- 7. Dockerfiles (hadolint) ----------------------------------------------
titre "Dockerfiles (hadolint)"
if ! trouver hadolint; then
  absent "hadolint"
else
  # hadolint découvre .hadolint.yaml dans le répertoire courant.
  if sortie="$(hadolint --config .hadolint.yaml Dockerfile docker/verifier/Dockerfile 2>&1)"; then
    ok "Dockerfiles valides"
  else
    echec "hadolint"
    printf '%s\n' "$sortie" | details
  fi
fi

# --- 8. Secrets dans l'arbre (gitleaks) -------------------------------------
titre "Secrets dans l'arbre (gitleaks)"
if ! trouver gitleaks; then
  absent "gitleaks"
else
  # gitleaks dir lit tout le dossier monté : .env, secrets/ et les autres
  # fichiers ignorés par Git déclenchaient des faux positifs en local alors
  # qu'ils n'entrent jamais dans l'historique. On analyse donc une copie de
  # l'arbre tel que Git le voit, dans un dossier temporaire hors du dépôt.
  if ! secrets_temporaire="$(mktemp -d)"; then
    echec "gitleaks (dossier temporaire)"
  else
    trap 'rm -rf -- "$secrets_temporaire"' EXIT
    bash scripts/arbre-suivi.sh "$secrets_temporaire"
    code_arbre=$?
    if [ "$code_arbre" -eq 0 ]; then
      if sortie="$(gitleaks dir --no-banner --redact --config .gitleaks.toml "$secrets_temporaire" 2>&1)"; then
        ok "aucun secret détecté (fichiers suivis par git)"
      else
        echec "gitleaks"
        printf '%s\n' "$sortie" | details
      fi
    elif [ "$code_arbre" -eq 3 ]; then
      # Dépôt Git illisible : repli sur l'ancien comportement, avec une note
      # visible pour ne pas faire croire que les fichiers ignorés sont scannés.
      printf '   note    dépôt git illisible : analyse de tout le dossier\n'
      if sortie="$(gitleaks dir --no-banner --redact --config .gitleaks.toml . 2>&1)"; then
        ok "aucun secret détecté (analyse de tout le dossier)"
      else
        echec "gitleaks"
        printf '%s\n' "$sortie" | details
      fi
    else
      echec "gitleaks (copie de l'arbre suivi, code $code_arbre)"
    fi
  fi
fi

# --- 9. Style Python des tests (ruff) ---------------------------------------
titre "Style Python des tests (ruff)"
if ! trouver ruff; then
  absent "ruff"
else
  # Sous Docker Desktop, un dossier Windows monté montre tous les fichiers en
  # 0777 : EXE002 (fichier exécutable sans shebang) est alors un faux positif.
  # Sur le runner Linux, les modes viennent de git (0644) : on ignore EXE002.
  if sortie="$(ruff check --extend-ignore EXE002 tests/ 2>&1)"; then
    ok "tests/ conformes"
  else
    echec "ruff"
    printf '%s\n' "$sortie" | details
  fi
fi

# --- 10. docker compose -----------------------------------------------------
titre "docker compose config"
if ! trouver docker; then
  absent "docker"
elif ! docker compose version >/dev/null 2>&1; then
  absent "docker compose v2"
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

# --- 11. Tests du dépôt -----------------------------------------------------
# GF_OUTILS_OBLIGATOIRES=1 : un outil manquant fait échouer la suite au lieu de
# la sauter. GF_SANS_TESTS=1 évite la récursion quand un test lance ce script.
titre "Tests du dépôt (unittest)"
if [ "${GF_SANS_TESTS:-}" = "1" ]; then
  printf '   saute   tests (GF_SANS_TESTS=1)\n'
elif [ -z "$python" ]; then
  absent "python (tests unittest)"
else
  if sortie="$(GF_OUTILS_OBLIGATOIRES=1 "$python" -m unittest discover -s tests -v 2>&1)"; then
    resume="$(printf '%s\n' "$sortie" | sed '/^[[:space:]]*$/d' | tail -n 1)"
    ok "${resume:-tests unittest}"
  else
    echec "unittest"
    printf '%s\n' "$sortie" | details
  fi
fi

# --- Bilan ------------------------------------------------------------------
printf '\n'
if [ "$echecs" -eq 0 ]; then
  echo "Toutes les vérifications sont passées."
  exit 0
fi
echo "$echecs vérification(s) en échec : corrige-les avant d'ouvrir la pull request." >&2
exit 1
