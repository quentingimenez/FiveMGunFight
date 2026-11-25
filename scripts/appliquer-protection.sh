#!/usr/bin/env bash
# =============================================================================
#  Protection de la branche main : lecture et application des règles.
#
#  Usage :
#    bash scripts/appliquer-protection.sh --check   # lit l'état (défaut)
#    bash scripts/appliquer-protection.sh --apply   # applique les règles
#
#  Le fichier .github/branch-protection.json n'est jamais modifié : il est
#  envoyé tel quel à l'API GitHub. Le script ne déclenche aucun paiement et
#  n'essaie jamais de contourner la limitation du plan gratuit.
#
#  Prérequis : gh installé et authentifié (gh auth login).
#  Détails et alternatives : docs/protection-branche.md et
#  docs/adr/0001-protection-branche.md.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

readonly REGLES=".github/branch-protection.json"
readonly BRANCHE="${BRANCHE:-main}"

MODE=""
for argument in "$@"; do
  case "$argument" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --help|-h)
      cat <<'EOF'
Protection de la branche main — lecture et application

Usage :
  bash scripts/appliquer-protection.sh --check   # état actuel (défaut)
  bash scripts/appliquer-protection.sh --apply   # applique le JSON versionné

Options :
  --check     Interroge GitHub et explique pourquoi la protection est absente.
              Code de sortie : 0 si active, 1 si absente, 2 si le plan refuse.
  --apply     Envoie .github/branch-protection.json à GitHub (PUT), puis relit
              l'état. Aucun paiement n'est effectué.
  --help      Affiche cette aide.

Prérequis :
  - gh installé et authentifié : gh auth status
  - droits d'administration sur le dépôt
  - un plan GitHub qui autorise la protection de branche

Plan GitHub : la protection des branches d'un dépôt PRIVÉ exige GitHub Pro
(environ 4 $/mois). Rendre le dépôt public active aussi la protection, mais
expose tout le code et la configuration de jeu. Ce script ne choisit pas à ta
place : il se contente d'expliquer le refus. Voir docs/protection-branche.md.

Le script ne modifie jamais .github/branch-protection.json et ne règle aucune
facturation.
EOF
      exit 0
      ;;
    *)
      echo "Option inconnue : $argument (essaie --help)" >&2
      exit 2
      ;;
  esac
done

MODE="${MODE:-check}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh introuvable : installe GitHub CLI (https://cli.github.com)." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "gh n'est pas authentifié : lance « gh auth login » avant ce script." >&2
  exit 1
fi

if [ ! -f "$REGLES" ]; then
  echo "$REGLES introuvable : lance ce script depuis la racine du dépôt." >&2
  exit 1
fi

# Message commun aux refus de plan, pour ne pas dupliquer l'explication.
expliquer_plan() {
  cat >&2 <<'EOF'

Le dépôt est privé sur un plan GitHub gratuit : GitHub refuse la protection de
branche et les rulesets (réponse 403 ou 404 selon l'appel). Deux options :

  - GitHub Pro (environ 4 $/mois) : le dépôt reste privé, la protection
    devient disponible. C'est l'option recommandée, aucun code n'est exposé.
  - dépôt public : la protection devient gratuite, mais tout le code et la
    configuration de jeu deviennent visibles.

Ce script n'achète rien et ne change pas la visibilité du dépôt. Après le
changement de plan, relance « --apply ». Détails : docs/protection-branche.md
et docs/adr/0001-protection-branche.md.
EOF
}

depot="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
echo "Dépôt   : $depot"
echo "Branche : $BRANCHE"
echo "Règles  : $REGLES"
echo

lire_etat() {
  local sortie
  if sortie="$(gh api "repos/$depot/branches/$BRANCHE/protection" 2>&1)"; then
    echo "Protection active (HTTP 200)." >&2
    echo
    printf '%s\n' "$sortie"
    return 0
  fi

  echo "Protection non active ou non lisible." >&2
  case "$sortie" in
    *"Upgrade to GitHub Pro"*|*"Upgrade to GitHub Pro or make this repository public"*|*"HTTP 403"*)
      expliquer_plan
      return 2
      ;;
    *"HTTP 404"*|*"Not Found"*)
      cat >&2 <<'EOF'

GitHub répond 404 : soit aucune protection n'est configurée sur cette branche,
soit la fonctionnalité n'existe pas sur ce plan. Vérifie d'abord le nom de la
branche, puis le plan GitHub (la protection d'un dépôt privé exige GitHub Pro).

Pour l'appliquer : bash scripts/appliquer-protection.sh --apply
EOF
      return 1
      ;;
    *)
      echo "$sortie" >&2
      echo >&2
      echo "Lecture impossible. Vérifie gh auth status et les droits sur le dépôt." >&2
      return 1
      ;;
  esac
}

if [ "$MODE" = "check" ]; then
  lire_etat
  exit $?
fi

# --apply : envoi du JSON existant, sans le réécrire.
if ! sortie="$(gh api -X PUT "repos/$depot/branches/$BRANCHE/protection" \
  -H "Accept: application/vnd.github+json" \
  --input "$REGLES" 2>&1)"; then
  echo "Échec de l'application de la protection :" >&2
  case "$sortie" in
    *"Upgrade to GitHub Pro"*|*"Upgrade to GitHub Pro or make this repository public"*|*"HTTP 403"*)
      expliquer_plan
      exit 2
      ;;
    *"HTTP 404"*|*"Not Found"*)
      echo "Branche '$BRANCHE' introuvable ou protection indisponible sur ce plan." >&2
      expliquer_plan
      exit 2
      ;;
    *)
      echo "$sortie" >&2
      exit 1
      ;;
  esac
fi

echo "Protection appliquée. Relecture de l'état :"
echo
lire_etat
