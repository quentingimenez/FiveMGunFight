# Documentation

Index des documents du dépôt. Le `README.md` à la racine reste le guide
utilisateur (installation, commandes en jeu, dépannage) ; les documents ici
décrivent le fonctionnement interne et le processus de développement.

| Document | À lire si… |
|---|---|
| [`architecture.md`](architecture.md) | tu veux comprendre comment le serveur est assemblé (Docker, ressources, données) |
| [`must-have.md`](must-have.md) | tu veux connaître les fonctionnalités prévues et l'ordre dans lequel les construire |
| [`qualite.md`](qualite.md) | tu modifies du code et tu veux savoir ce que la CI vérifie |
| [`protection-branche.md`](protection-branche.md) | tu dois configurer ou vérifier les règles de la branche `main` |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | tu ouvres ta première pull request |
| [`../SECURITY.md`](../SECURITY.md) | tu manipules des secrets, ou tu constates une fuite |

## Règles en une ligne

`main` est protégée : une branche, une pull request, une revue, une CI verte,
puis fusion en squash. Aucun envoi direct sur `main`.
