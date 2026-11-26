# Documentation

Index des documents du dépôt. Le `README.md` à la racine reste le guide
utilisateur (installation, commandes en jeu, dépannage) ; les documents ici
décrivent le fonctionnement interne et l'exploitation.

## Architecture et développement

| Document | À lire si… |
|---|---|
| [`architecture.md`](architecture.md) | tu veux comprendre comment le serveur est assemblé (Docker, ressources, données) |
| [`lobby.md`](lobby.md) | tu travailles sur le lobby, l'escouade ou la création de personnage |
| [`must-have.md`](must-have.md) | tu veux connaître les fonctionnalités prévues et l'ordre dans lequel les construire |
| [`qualite.md`](qualite.md) | tu modifies du code et tu veux savoir ce que la CI vérifie |
| [`debug-test.md`](debug-test.md) | tu veux les accès (ports, logs, console, admin) et les scénarios de test local |
| [`protection-branche.md`](protection-branche.md) | tu dois configurer ou vérifier les règles de la branche `main` |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | tu ouvres ta première pull request |
| [`../SECURITY.md`](../SECURITY.md) | tu manipules des secrets, ou tu constates une fuite |

## Exploitation

| Document | À lire si… |
|---|---|
| [`runbooks/incident.md`](runbooks/incident.md) | la production est indisponible ou dégradée |
| [`runbooks/restauration.md`](runbooks/restauration.md) | tu dois restaurer une sauvegarde (RPO 24 h, RTO 1 h) |
| [`runbooks/mise-a-jour.md`](runbooks/mise-a-jour.md) | tu déploies une nouvelle image par digest |
| [`runbooks/deploiement-unraid.md`](runbooks/deploiement-unraid.md) | tu déploies ou migres le conteneur Unraid sans figer le badge de build |
| [`runbooks/rotation-secrets.md`](runbooks/rotation-secrets.md) | un secret doit être remplacé ou a fuité |

Outils associés : `scripts/verifier-sante.sh` (santé), `scripts/deployer.sh`
(déploiement et rollback), `scripts/sauvegarder.sh` (sauvegarde),
`scripts/restaurer.sh` (vérification et extraction), et
`docker-compose.staging.yml` (préproduction isolée).

## Décisions

| Document | Sujet |
|---|---|
| [`adr/0001-protection-branche.md`](adr/0001-protection-branche.md) | protection de `main`, option GitHub Pro vs dépôt public |
| [`adr/0002-fxserver-epingle.md`](adr/0002-fxserver-epingle.md) | FXServer épinglé par URL et SHA256 |

## Règles en une ligne

Une branche, une pull request, une revue, une CI verte, puis fusion en squash.
Aucun envoi direct sur `main`. La protection GitHub de `main` reste **à
activer** : le dépôt privé est sur un plan gratuit (voir l'ADR 0001).
