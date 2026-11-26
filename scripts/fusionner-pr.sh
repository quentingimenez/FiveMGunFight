#!/usr/bin/env bash
# =============================================================================
#  Fusion d'une pull request, puis suivi de la CI de main jusqu'au bout.
#
#  Usage : bash scripts/fusionner-pr.sh <numéro de PR>
#
#  1. attend la fin des checks de la PR et refuse de fusionner si l'un échoue ;
#  2. fusionne en squash ;
#  3. suit chaque run lancé sur main par le commit de fusion ;
#  4. sort en erreur, avec le lien du run, si la CI de main est rouge.
#
#  Une fusion n'est terminée que lorsque la CI de main est verte (AGENTS.md
#  § 2 et § 4.8) : ce script est la seule manière prévue de fusionner.
#
#  Variables (surtout pour les tests) :
#    GH            commande gh à utiliser (défaut : gh)
#    INTERVALLE    secondes entre deux relevés (défaut : 15)
#    ESSAIS_RUNS   relevés avant d'abandonner la recherche des runs (défaut : 20)
#    RUNS_ATTENDUS runs lancés sur main par une fusion (défaut : 2, Qualité et
#                  Docker)
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

GH="${GH:-gh}"
INTERVALLE="${INTERVALLE:-15}"
ESSAIS_RUNS="${ESSAIS_RUNS:-20}"
RUNS_ATTENDUS="${RUNS_ATTENDUS:-2}"

aide() {
  cat <<'EOF'
Fusion d'une pull request et suivi de la CI de main

Usage :
  bash scripts/fusionner-pr.sh <numéro de PR>

Étapes :
  1. attend la fin des checks de la PR ; un check rouge bloque la fusion ;
  2. fusionne en squash (gh pr merge --squash) ;
  3. suit jusqu'au bout chaque run lancé sur main par le commit de fusion ;
  4. code 0 seulement si la CI de main est verte, sinon code 1 et lien du run.

Prérequis : gh installé et authentifié (gh auth status).
EOF
}

pr=""
for argument in "$@"; do
  case "$argument" in
    --help|-h) aide; exit 0 ;;
    -*) echo "Option inconnue : $argument (essaie --help)" >&2; exit 2 ;;
    *)
      if [ -n "$pr" ]; then
        echo "Un seul numéro de PR attendu (essaie --help)" >&2
        exit 2
      fi
      pr="$argument"
      ;;
  esac
done

case "$pr" in
  '' | *[!0-9]*)
    echo "Numéro de PR manquant ou invalide : « $pr » (essaie --help)" >&2
    exit 2
    ;;
esac

pause() {
  if [ "$INTERVALLE" -gt 0 ]; then sleep "$INTERVALLE"; fi
}

# --- 1. Checks de la PR -------------------------------------------------------
printf '\n== Checks de la PR #%s\n' "$pr"
if ! "$GH" pr checks "$pr" --watch --fail-fast --interval "$INTERVALLE"; then
  echo "Checks de la PR #$pr en échec ou absents : fusion refusée." >&2
  exit 1
fi

# --- 2. Fusion en squash ------------------------------------------------------
printf '\n== Fusion en squash de la PR #%s\n' "$pr"
"$GH" pr merge "$pr" --squash
etat="$("$GH" pr view "$pr" --json state,mergeCommit --jq '.state + " " + (.mergeCommit.oid // "")')"
statut="${etat%% *}"
sha="${etat#* }"
if [ "$statut" != "MERGED" ] || [ -z "$sha" ] || [ "$sha" = "$etat" ]; then
  echo "La PR #$pr n'est pas fusionnée (état : $etat)." >&2
  exit 1
fi
echo "Commit de fusion : $sha"

# --- 3. Runs de main lancés par le commit de fusion ---------------------------
printf '\n== CI de main sur %s\n' "$sha"
runs=""
for essai in $(seq 1 "$ESSAIS_RUNS"); do
  runs="$("$GH" run list --branch main --commit "$sha" --event push \
    --json databaseId --jq '.[].databaseId')"
  nombre="$(printf '%s\n' "$runs" | grep -c '[0-9]' || true)"
  if [ "$nombre" -ge "$RUNS_ATTENDUS" ]; then
    break
  fi
  if [ "$essai" -lt "$ESSAIS_RUNS" ]; then pause; fi
done

nombre="$(printf '%s\n' "$runs" | grep -c '[0-9]' || true)"
if [ "$nombre" -lt "$RUNS_ATTENDUS" ]; then
  echo "Seulement $nombre run(s) sur main pour $sha, $RUNS_ATTENDUS attendus :" >&2
  echo "la CI de main n'est pas vérifiée. Voir : gh run list --branch main" >&2
  exit 1
fi

# --- 4. Suivi jusqu'au bout ---------------------------------------------------
rouges=0
for run in $runs; do
  if "$GH" run watch "$run" --exit-status --interval "$INTERVALLE"; then
    echo "   ok      run $run"
  else
    lien="$("$GH" run view "$run" --json url --jq .url)"
    echo "   ECHEC   run $run : $lien" >&2
    rouges=$((rouges + 1))
  fi
done

if [ "$rouges" -gt 0 ]; then
  echo "CI de main rouge après la fusion de la PR #$pr : ouvrir une PR de correction." >&2
  exit 1
fi
echo "PR #$pr fusionnée ($sha) et CI de main verte."
