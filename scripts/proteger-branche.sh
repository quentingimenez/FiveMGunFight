#!/usr/bin/env bash
# =============================================================================
#  Applique la protection de la branche main sur GitHub.
#
#  Usage : bash scripts/proteger-branche.sh [branche]
#          (branche par défaut : main)
#
#  Les règles appliquées sont celles de .github/branch-protection.json :
#  pull request obligatoire, une revue, checks CI requis, pas de force-push,
#  pas de suppression, administrateurs inclus.
#
#  Prérequis : GitHub CLI authentifié (gh auth login) et un dépôt dont le plan
#  autorise la protection de branche. Sur un dépôt privé en plan gratuit,
#  GitHub répond "Upgrade to GitHub Pro or make this repository public".
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

branche="${1:-main}"
regles=".github/branch-protection.json"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh introuvable : installe GitHub CLI (https://cli.github.com)." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "gh n'est pas authentifié : lance « gh auth login »." >&2
  exit 1
fi

if [ ! -f "$regles" ]; then
  echo "$regles introuvable : lance ce script depuis le dépôt." >&2
  exit 1
fi

depot="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
echo "Dépôt    : $depot"
echo "Branche  : $branche"
echo "Règles   : $regles"
echo

if ! sortie="$(gh api -X PUT "repos/$depot/branches/$branche/protection" \
  -H "Accept: application/vnd.github+json" \
  --input "$regles" 2>&1)"; then
  echo "Échec de l'application de la protection :" >&2
  echo "$sortie" >&2
  case "$sortie" in
    *"Upgrade to GitHub Pro"*|*"Upgrade to GitHub Pro or make this repository public"*)
      echo >&2
      echo "Le dépôt est privé sur un plan gratuit : GitHub refuse la protection." >&2
      echo "Passe à GitHub Pro (dépôt privé conservé) ou rends le dépôt public," >&2
      echo "puis relance ce script. Détails : docs/protection-branche.md" >&2
      ;;
    *"404"*)
      echo >&2
      echo "La branche '$branche' est introuvable sur le dépôt distant." >&2
      ;;
  esac
  exit 1
fi

echo "Protection appliquée. Vérification :"
echo
gh api "repos/$depot/branches/$branche/protection" \
  --jq '{
    pull_request: (.required_pull_request_reviews != null),
    approbations: .required_pull_request_reviews.required_approving_review_count,
    code_owners: .required_pull_request_reviews.require_code_owner_reviews,
    approbation_apres_push: .required_pull_request_reviews.require_last_push_approval,
    checks_requis: [.required_status_checks.contexts[]],
    branche_a_jour: .required_status_checks.strict,
    conversations_resolues: .required_conversation_resolution.enabled,
    force_push: .allow_force_pushes.enabled,
    suppression: .allow_deletions.enabled,
    admins_soumis: .enforce_admins.enabled
  }'
