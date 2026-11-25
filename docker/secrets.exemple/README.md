# Secrets de production

Ce dossier n'est **qu'un modèle**. Les vrais fichiers vont dans `secrets/` à la
racine du dépôt (ignoré par Git et par l'image) ou dans le dossier pointé par
`SECRETS_DIR` dans `.env`.

```text
secrets/
├── license_key           clé de licence Cfx.re (sv_licenseKey)
├── db_password           mot de passe de l'utilisateur MariaDB gunfight
├── db_root_password      mot de passe root MariaDB
└── steam_web_api_key     clé Steam Web API (peut rester vide)
```

## Création (Linux / VPS)

```bash
install -d -m 700 secrets
printf '%s\n' 'ta-cle-de-licence' > secrets/license_key
printf '%s\n' 'mot-de-passe-gunfight' > secrets/db_password
printf '%s\n' 'mot-de-passe-root' > secrets/db_root_password
printf '%s\n' 'ta-cle-steam' > secrets/steam_web_api_key

chmod 600 secrets/*
chown root:root secrets/*
```

Puis `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d`.

## Règles

- **Un secret par fichier**, une seule ligne, **fin de ligne LF** (pas CRLF :
  un `\r` en fin de valeur casse la clé de licence ; l'entrypoint nettoie les
  `\r`/`\n` par sécurité, mais autant écrire le fichier proprement).
- **Droits 600**, propriétaire root. Compose monte ces fichiers en lecture seule
  sous `/run/secrets/<nom>` dans les conteneurs concernés.
- **Ne jamais versionner** ces fichiers : `secrets/` est dans `.gitignore` et
  `.dockerignore`.
- Le mot de passe de la base doit rester **alphanumérique** : les caractères
  `@ : / ? #` cassent la chaîne `mysql://` construite par l'entrypoint.
- `steam_web_api_key` peut être un fichier vide ; l'entrypoint ne l'ajoute pas à
  `secrets.cfg` s'il est vide.
- Rotation : mettre le conteneur à l'arrêt, remplacer le fichier, relancer.
  MariaDB ne relit le mot de passe root que lors de l'initialisation du volume ;
  après une rotation, le mot de passe root doit être changé aussi en SQL.

## Aucun secret dans l'environnement

En production, `docker inspect gunfight-fxserver` ne doit afficher aucune valeur
de licence, de mot de passe ou de clé Steam : les variables correspondantes sont
neutralisées (`""`) et les valeurs utiles sont lues dans `/run/secrets`. Seul le
développement transmet ces variables (voir l'en-tête de
`docker-compose.dev.yml`).
