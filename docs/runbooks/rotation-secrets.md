# Runbook — Rotation des secrets

**Objectif** : remplacer un secret sans l'exposer, sans casser la production,
et révoquer l'ancien.

**Règle d'or** : un secret se saisit avec `read -s` ou dans un éditeur, jamais
en argument de commande visible dans l'historique ou `ps`. Il ne se colle pas
dans une issue, une PR ou un message.

| Secret | Où il vit | Portée d'une fuite |
|---|---|---|
| Clé de licence Cfx.re | `secrets/license_key` (`/run/secrets/license_key`), secret CI `CFX_LICENSE_KEY` ; `.env` en développement | serveur révoqué, joueurs déconnectés |
| Mot de passe root MariaDB | `secrets/db_root_password` (`/run/secrets/db_root_password`) ; `.env` en développement | accès total à la base |
| Mot de passe utilisateur MariaDB | `secrets/db_password` (`/run/secrets/db_password`) ; `.env` en développement | accès aux données applicatives |
| Compte txAdmin | base txAdmin (volume `txdata`) | panneau d'administration |
| Clé Steam Web API | `secrets/steam_web_api_key` (`/run/secrets/steam_web_api_key`) ; `.env` en développement | quota et identité Steam |
| Token GHCR | `docker login`, jamais dans `.env` | lecture des images privées |
| Clé age / identité | hors dépôt (`AGE_RECIPIENT`, `AGE_IDENTITY`) | déchiffrement des sauvegardes |
| Identifiants rclone | configuration rclone du VPS | accès à la copie hors site |

## 1. Clé de licence Cfx.re

1. Révoque l'ancienne clé sur <https://portal.cfx.re> → *Server Registration Keys*.
2. Crée une nouvelle clé.
3. Remplace le contenu de `secrets/license_key` (éditeur ou `read -s`, jamais un
   argument de commande). En développement seulement, `LICENSE_KEY` dans `.env`.
4. Mets à jour le secret CI : `gh secret set CFX_LICENSE_KEY`.
5. Recrée le serveur :
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate fxserver
   ```

## 2. Mots de passe MariaDB

Génère un mot de passe fort (base64 ne contient ni apostrophe ni antislash,
donc il reste valide dans le SQL ci-dessous) :

```bash
NOUVEAU="$(openssl rand -base64 32)"
printf 'Nouveau mot de passe : %s\n' "$NOUVEAU"   # à recopier dans secrets/db_password
```

Change d'abord le mot de passe **dans la base**, avec l'ancien mot de passe
root encore présent dans `secrets/db_root_password` :

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T mariadb \
  sh -c 'MYSQL_PWD="$(cat /run/secrets/db_root_password)" mariadb -uroot' <<SQL
ALTER USER 'gunfight'@'%' IDENTIFIED BY '${NOUVEAU}';
FLUSH PRIVILEGES;
SQL
```

Puis remplace le contenu de `secrets/db_password` par la même valeur et recrée
les conteneurs :

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate
```

Pour le compte root, la procédure est la même, mais l'hôte varie selon
l'initialisation du volume :

```sql
SELECT User, Host FROM mysql.user WHERE User = 'root';
```

Utilise la ligne retournée (`'root'@'%'` ou `'root'@'localhost'`) dans
`ALTER USER`. Ne change pas `secrets/db_root_password` avant d'avoir modifié le
mot de passe en base : au redémarrage, MariaDB et son healthcheck utiliseraient
l'ancien et l'accès serait perdu. Après la modification en base, mets à jour
`secrets/db_root_password` et recrée **tout** :

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate
```

## 3. Compte txAdmin

1. Connecte-toi à txAdmin (`http://127.0.0.1:40120` via tunnel SSH).
2. Change le mot de passe du compte administrateur et active la double
   authentification.
3. Révoque les sessions ouvertes et les jetons d'API éventuels.
4. Vérifie les journaux d'audit txAdmin après l'opération.

Le compte est stocké dans le volume `gunfight-prod-txdata` : ne supprime pas le
volume pour « réinitialiser » un mot de passe, tu perdrais la configuration.

## 4. Clé Steam Web API

1. Révoque l'ancienne clé sur <https://steamcommunity.com/dev/apikey>.
2. Crée la nouvelle clé.
3. Remplace le contenu de `secrets/steam_web_api_key`.
4. `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate fxserver`.

## 5. Token GHCR

1. Révoque l'ancien token dans GitHub → *Settings → Developer settings → Personal access tokens*.
2. Crée un token limité à `read:packages`.
3. Reconnecte-toi :
   ```bash
   echo "$NOUVEAU_TOKEN" | docker login ghcr.io -u <compte> --password-stdin
   ```
4. Ne mets jamais ce token dans `.env`, dans un script ou dans le dépôt.

## 6. Clés age et rclone

- **age** : génère une nouvelle paire, remplace `AGE_RECIPIENT` pour les
  prochaines sauvegardes. Conserve l'ancienne `AGE_IDENTITY` tant que des
  archives chiffrées avec elle existent : sans elle, elles sont illisibles.
- **rclone** : révoque les identifiants côté fournisseur, crée-en de nouveaux,
  puis `rclone config` sur le VPS. Vérifie avec `rclone lsd "$RCLONE_REMOTE"`.

## 7. Vérification

- `bash scripts/verifier-sante.sh` code 0 ;
- `docker compose ... ps` : conteneurs `healthy` ;
- connexion joueur et démarrage d'une manche ;
- connexion txAdmin avec le nouveau mot de passe, ancienne session refusée ;
- `git status` ne montre aucun secret ; si l'ancien secret a été commité, ne le
  recherche pas avec `git log -S` (la commande exposerait sa valeur) : traite
  l'historique comme compromis et nettoie-le après révocation ;
- l'ancien secret est bien révoqué côté fournisseur.

En cas de fuite avérée : révoque d'abord, fais tourner le secret, puis préviens
`@WardenPro` en privé. Considère l'historique Git comme compromis même après
suppression du commit.
