# Sécurité du dépôt et du serveur

## Secrets à ne jamais versionner

| Fichier | Contenu | État |
|---|---|---|
| `.env` | clé de licence Cfx.re, mots de passe MariaDB, identifiants admin | ignoré par Git |
| `server-data/secrets.cfg` | copie générée au démarrage à partir de `.env` | ignoré par Git |
| `server-data/cache/` | cache de FXServer, peut contenir de l'état local | ignoré par Git |

Le modèle `.env.example` ne contient que des valeurs `change_moi`. Les tests
automatiques (`tests/test_depot.py`) échouent si un fichier secret est suivi par
Git ou si un mot de passe réel apparaît dans le modèle.

## Clé de licence Cfx.re

La clé gratuite est limitée à 48 joueurs et peut être **révoquée à tout moment**
si elle circule publiquement (dépôt, capture d'écran, message, journal de CI).

En cas de fuite suspectée :

1. Révoque la clé sur <https://portal.cfx.re> → *Server Registration Keys*.
2. Crée une nouvelle clé et mets-la à jour dans `.env` local et dans le secret
   GitHub `CFX_LICENSE_KEY` (`gh secret set CFX_LICENSE_KEY`).
3. Redémarre le serveur : `docker compose up -d --force-recreate fxserver`.
4. Vérifie si l'historique Git contient la clé ; si oui, considère-la comme
   compromise même après suppression du commit.

## Signalement

Une faille ou une fuite se signale **en privé** au mainteneur (`@WardenPro`),
pas dans une issue publique. Ne publie pas l'exploit ni le secret dans un ticket.

## Surface d'exposition

- **30120 TCP/UDP** : port de jeu, ouvert par conception.
- **40120 TCP** : panneau txAdmin. À n'ouvrir que si l'accès distant est
  réellement nécessaire, avec un mot de passe fort ; sinon le laisser fermé sur
  le pare-feu du VPS.
- **MariaDB** : aucun port exposé, accessible seulement depuis le réseau Docker
  via l'hôte `mariadb`.

## Accès au dépôt

Deux collaborateurs disposent du droit d'écriture : `WardenPro` (propriétaire)
et `Zhics`. Toute évolution passe par une pull request ; la branche `main` est
protégée (voir `docs/protection-branche.md`).
