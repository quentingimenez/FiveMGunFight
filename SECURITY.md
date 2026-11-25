# Sécurité du dépôt et du serveur

## Secrets à ne jamais versionner

| Fichier | Contenu | État |
|---|---|---|
| `.env` | configuration de développement, `IMAGE_REF` ; les secrets de production sont dans `secrets/` | ignoré par Git |
| `secrets/` | licence, mots de passe MariaDB, clé Steam, montés dans `/run/secrets` | ignoré par Git |
| `server-data/secrets.cfg` | copie générée au démarrage depuis `/run/secrets` (prod) ou `.env` (dev) | ignoré par Git |
| `server-data/cache/` | cache de FXServer, peut contenir de l'état local | ignoré par Git |
| `backups/` | archives de production (base, txdata, maps) | ignoré par Git |
| `restauration/` | extractions locales de sauvegardes | ignoré par Git |

Le modèle `.env.example` ne contient que des valeurs `change_moi`. Les tests
automatiques (`tests/test_depot.py`, `tests/test_ops.py`) échouent si un fichier
secret est suivi par Git, si un mot de passe réel apparaît dans le modèle, ou si
un script d'exploitation contient un secret en clair.

Les archives `*.age` restent des données sensibles : une clé d'identité age
compromise permet de les déchiffrer. Conserve `AGE_IDENTITY` hors du dépôt.

## Versions supportées

- **Serveur** : l'image publiée sur GHCR, déployée par digest. Seul le digest en
  production est supporté ; les tags sont des raccourcis, pas des versions.
- **MariaDB** : 11.4 (digest épinglé dans `docker-compose.yml`). Les montées
  majeures sont manuelles et testées en préproduction.
- **FXServer** : version contenue dans l'image, épinglée par
  [`.fxserver-version`](.fxserver-version) (URL et SHA256). La CI passe
  obligatoirement ces deux valeurs au build ; le mode `FX_CHANNEL` du
  `Dockerfile` ne sert plus qu'aux constructions locales. Voir
  [`docs/adr/0002-fxserver-epingle.md`](docs/adr/0002-fxserver-epingle.md).

Une faille n'est corrigée que sur la dernière image publiée et le dernier
commit de `main`. Il n'y a pas de branche de maintenance pour les anciens tags.

## Signalement

Une faille ou une fuite se signale **en privé** au mainteneur (`@WardenPro`),
pas dans une issue publique. Ne publie pas l'exploit ni le secret dans un ticket.
Indique la version ou le digest concerné, les étapes de reproduction et l'impact
estimé. Un accusé de réception est envoyé dès que possible ; aucun délai de
correction public n'est garanti.

En cas de fuite de secret, applique d'abord
[`docs/runbooks/rotation-secrets.md`](docs/runbooks/rotation-secrets.md) :
révoque, remplace, puis communique.

## Rotation des secrets

Les procédures détaillées (licence, MariaDB, txAdmin, Steam, GHCR, age, rclone)
sont dans [`docs/runbooks/rotation-secrets.md`](docs/runbooks/rotation-secrets.md).

Règles générales :

1. révoquer l'ancien secret côté fournisseur **avant** de configurer le nouveau ;
2. ne jamais saisir un secret en argument de commande visible (`ps`, historique) ;
3. redémarrer le composant concerné et vérifier la santé ;
4. mettre à jour le secret CI (`CFX_LICENSE_KEY`) séparément des secrets du VPS ;
5. si le secret a pu être commité, considérer l'historique Git comme compromis
   et le nettoyer (`git filter-repo`) **après** révocation : une simple
   suppression de fichier ne retire pas l'historique.

## Surface d'exposition

- **30120 TCP/UDP** : port de jeu, ouvert par conception.
- **40120 TCP** : panneau txAdmin. À n'ouvrir que si l'accès distant est
  réellement nécessaire, avec un mot de passe fort et la double authentification ;
  sinon le laisser fermé sur le pare-feu du VPS.
- **MariaDB** : aucun port exposé, accessible seulement depuis le réseau Docker
  interne `backend` via l'hôte `mariadb`.
- **Secrets** : montés en fichiers dans `/run/secrets` (licence, mots de passe
  base, clé Steam) et lus par l'entrypoint ; ils ne figurent plus dans
  l'environnement des conteneurs. `.env` ne porte que la configuration non
  secrète et `IMAGE_REF`.
- **Préproduction** : 30121 TCP/UDP et 40121 sur la boucle locale uniquement,
  mêmes secrets que la production mais volumes et projet Compose distincts.

## Accès au dépôt

Deux collaborateurs disposent du droit d'écriture : `WardenPro` (propriétaire)
et `Zhics`. Toute évolution passe par une pull request.

La protection de branche GitHub de `main` est **préparée mais inactive** : le
dépôt privé est sur un plan gratuit et GitHub refuse la règle (403). La
discipline repose sur `AGENTS.md`, le hook `.githooks/pre-push` et la revue
humaine. Voir [`docs/protection-branche.md`](docs/protection-branche.md) et
[`docs/adr/0001-protection-branche.md`](docs/adr/0001-protection-branche.md).
