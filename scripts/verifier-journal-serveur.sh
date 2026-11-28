#!/usr/bin/env bash
# =============================================================================
#  Vérification des erreurs de script dans un journal FXServer.
#
#  Usage :
#    bash scripts/verifier-journal-serveur.sh <journal>
#
#  Le script cherche les quatre motifs d'erreur de script les plus courants
#  (`SCRIPT ERROR`, `Error loading script`, `Couldn't start resource` et
#  `Failed to load script`) et affiche chaque ligne fautive avec trois lignes
#  de contexte et son numéro de ligne.
#
#  Code de sortie :
#    0 aucune erreur de script dans le journal ;
#    1 au moins une erreur de script (lignes fautives affichées) ;
#    2 argument manquant, fichier absent ou fichier vide.
#
#  Le compteur ne retient que les lignes fautives, jamais les lignes de
#  contexte ajoutées par grep -A3.
# =============================================================================
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "Usage : bash scripts/verifier-journal-serveur.sh <journal>" >&2
  echo "Un chemin de journal est obligatoire." >&2
  exit 2
fi

journal="$1"

if [ ! -f "$journal" ]; then
  echo "Journal introuvable : $journal" >&2
  exit 2
fi

if [ ! -s "$journal" ]; then
  echo "Journal vide : $journal" >&2
  exit 2
fi

motif='SCRIPT ERROR|Error loading script|Couldn.t start resource|Failed to load script'

# grep sort 1 quand il ne trouve rien : sous set -e on neutralise ce code,
# la valeur 0 du compteur est alors bien celle d'un journal propre.
nombre="$(grep -cE "$motif" "$journal" || true)"

if [ "$nombre" -eq 0 ]; then
  echo "Aucune erreur de script dans $journal"
  exit 0
fi

# -n numérote les lignes, -A3 ajoute trois lignes de contexte après chaque
# correspondance, -- garde le chemin safe s'il commence par un tiret.
grep -nE -A3 -- "$motif" "$journal" || true

echo "$nombre erreur(s) de script dans $journal"
exit 1
