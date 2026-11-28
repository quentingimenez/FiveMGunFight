# Documentation

Index des documents du dépôt. Le `README.md` à la racine reste le guide
utilisateur (installation, commandes en jeu, dépannage) ; les documents ici
décrivent le fonctionnement interne et l'exploitation.

## Méthode de développement

À lire **avant** toute modification, par un agent comme par un humain.

| Document | À lire si… |
|---|---|
| [`methode/README.md`](methode/README.md) | tu commences une tâche : les huit phases, les trois portes, les niveaux S/M/L, ce qu'on capitalise |
| [`methode/fiche-impact.md`](methode/fiche-impact.md) | tu dois situer ton changement avant de coder : le modèle de fiche et comment trouver ce qu'il touche |
| [`methode/strategie-de-test.md`](methode/strategie-de-test.md) | tu dois savoir quels tests et quelle preuve ton type de changement exige (niveaux T0 à T6) |
| [`methode/architecture-cible.md`](methode/architecture-cible.md) | tu ajoutes un lien entre ressources, un export, un événement, un calque NUI ou une ressource |
| [`methode/orchestration-agents.md`](methode/orchestration-agents.md) | tu délègues du travail à un autre agent, ou tu vérifies le sien |

## Architecture et développement

| Document | À lire si… |
|---|---|
| [`architecture.md`](architecture.md) | tu veux comprendre comment le serveur est assemblé (Docker, ressources, données) |
| [`evenements-serveur.md`](evenements-serveur.md) | tu ajoutes ou modifies un événement réseau (validation, limite de débit, droits) |
| [`contrats.md`](contrats.md) | tu cherches qui fournit, appelle, émet ou écoute quoi entre les ressources (généré par `python scripts/contrats.py --doc`) |
| [`lobby.md`](lobby.md) | tu travailles sur le lobby, l'escouade ou la création de personnage |
| [`menu-pause.md`](menu-pause.md) | tu travailles sur le menu pause (Échap), sa page NUI ou son protocole |
| [`panneau-admin.md`](panneau-admin.md) | tu travailles sur le panneau admin (F10) ou ses actions |
| [`killcam.md`](killcam.md) | tu travailles sur la killcam |
| [`equilibrage-armes.md`](equilibrage-armes.md) | tu touches aux dégâts ou à l'équilibre des armes |
| [`must-have.md`](must-have.md) | tu veux connaître les fonctionnalités prévues et l'ordre dans lequel les construire |
| [`regles-de-code.md`](regles-de-code.md) | tu écris ou relis du code : les règles à respecter (autorité du serveur, performance, données, tests et preuve) |
| [`chantiers-techniques.md`](chantiers-techniques.md) | tu cherches ce qui doit être revu, corrigé ou ajouté pour que le code existant respecte ces règles |
| [`qualite.md`](qualite.md) | tu modifies du code et tu veux savoir ce que la CI vérifie |
| [`debug-test.md`](debug-test.md) | tu veux les accès (ports, logs, console, admin) et les scénarios de test local |
| [`pieges-fivem.md`](pieges-fivem.md) | tu touches au rendu, à la caméra, au ped ou à un natif, ou tu dois tester en jeu vite (outils d'essai, pièges mesurés) |
| [`ajouter-un-modele.md`](ajouter-un-modele.md) | tu ajoutes un véhicule (ou une autre famille de modèles) et sa photo dans les menus |
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

Quand écrire un ADR, et son modèle : [`adr/README.md`](adr/README.md).

| Document | Sujet |
|---|---|
| [`adr/0001-protection-branche.md`](adr/0001-protection-branche.md) | protection de `main` : dépôt public et ruleset |
| [`adr/0002-fxserver-epingle.md`](adr/0002-fxserver-epingle.md) | FXServer épinglé par URL et SHA256 |
| [`adr/0003-methode-de-developpement.md`](adr/0003-methode-de-developpement.md) | méthode de développement en phases et portes |
| [`adr/0004-architecture-cible.md`](adr/0004-architecture-cible.md) | couches, propriétaires et frontières entre ressources |

## Règles en une ligne

Une branche, une pull request, une CI verte, puis fusion en squash. Aucun
envoi direct sur `main`. La protection GitHub de `main` est **active** : le
ruleset « Protection de main » s'applique au dépôt public. Une revue de
`@WardenPro` ou `@Zhics` reste bienvenue, mais elle n'est pas exigée. Voir
[`protection-branche.md`](protection-branche.md).
