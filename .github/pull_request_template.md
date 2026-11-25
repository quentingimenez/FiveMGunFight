<!--
  Modèle de description de pull request. Remplis chaque section ; supprime les
  commentaires. Une pull request vide ou vague sera renvoyée à l'auteur.
-->

## Résumé

<!-- Une ou deux phrases : ce que fait cette pull request. -->

## Pourquoi

<!-- Le bug, la demande, la contrainte, le ticket : #numéro si applicable. -->

## Comment tester

<!--
  Commandes lancées, scénario en jeu, ce que tu as vérifié.
  Exemple : `bash scripts/verifier.sh`, puis /redzone avec 3 joueurs.
-->

## Captures

<!-- Si l'interface ou le rendu en jeu change : avant / après. Sinon, supprime. -->

## Checklist

- [ ] Les contrôles passent en local (`bash scripts/verifier.sh`, `python -m unittest discover -s tests -v`)
- [ ] Testé en jeu si le comportement change (`/attack`, `/redzone`, `/editor`…)
- [ ] Aucun secret ajouté (`.env`, clé de licence, mots de passe, identifiants admin)
- [ ] Documentation mise à jour si le comportement, la configuration ou les fichiers changent
- [ ] Le serveur reste autoritaire : aucune décision de score ou de dégât déplacée côté client
- [ ] Changement cohérent et limité (une fonctionnalité ou une correction)
