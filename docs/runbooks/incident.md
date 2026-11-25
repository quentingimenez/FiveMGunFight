# Runbook — Incident en production

**Objectif** : qualifier une panne, stabiliser le serveur sans perdre de
données, puis restaurer le service ou revenir à la version précédente.

**Périmètre** : VPS de production, pile Compose `docker-compose.yml` +
`docker-compose.prod.yml`. Les commandes se lancent depuis le dossier de
déploiement (celui qui contient `.env` et `secrets/`).

**Prérequis** : accès SSH au VPS, `docker compose` v2, `scripts/verifier-sante.sh`
et `scripts/deployer.sh` copiés dans le dossier de déploiement.

## 1. Qualifier l'incident

| Symptôme | Première hypothèse | Contrôle |
|---|---|---|
| Personne ne voit le serveur | conteneur arrêté, port fermé, licence | `docker compose ... ps`, `scripts/verifier-sante.sh` |
| Déconnexions en masse | crash FXServer, mémoire, réseau | `docker compose ... logs --tail=200 fxserver` |
| `fxserver` redémarre en boucle | ressource Lua, licence, disque | `docker inspect --format '{{.RestartCount}}' gunfight-fxserver` |
| `mariadb` `unhealthy` | disque plein, volume corrompu | `df -h`, logs MariaDB |
| txAdmin inaccessible | conteneur arrêté, port 40120 fermé | `curl -I http://127.0.0.1:40120` |
| Maps ou comptes perdus | mauvais volume, `down -v` | `docker volume ls`, section 12 du README |

Gravité :

- **P1** : serveur injoignable ou données menacées → agir immédiatement, prévenir
  `@WardenPro`.
- **P2** : dégradation (déconnexions, latence, txAdmin indisponible) → stabiliser
  dans l'heure.
- **P3** : anomalie sans impact joueur → traiter au prochain créneau.

## 2. Constater

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
bash scripts/verifier-sante.sh
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail=200 fxserver
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail=100 mariadb
df -h /
docker system df
```

Ne supprime jamais un volume pour « nettoyer » : `docker compose down -v` efface
la base, txAdmin et les maps. En cas de doute, arrête les conteneurs et copie
les volumes avant toute manipulation.

## 3. Stabiliser

### Redémarrer sans recréer

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml restart fxserver
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f fxserver
```

Attends `Started resource gf_` puis vérifie `scripts/verifier-sante.sh`. Un
`restart` ne change pas l'image et ne touche pas aux volumes.

### Disque plein

```bash
df -h /
docker system df
```

Supprime uniquement les images orphelines (`docker image prune`) et les
sauvegardes trop anciennes. Ne lance pas `docker system prune --volumes` : les
volumes de production seraient supprimés.

### Base de données bloquée

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T mariadb \
  sh -c 'MYSQL_PWD="$(cat /run/secrets/db_root_password)" mariadb -uroot -e "SHOW PROCESSLIST;"'
```

Si MariaDB ne démarre plus, conserve le volume `gunfight-prod-dbdata` et restaure
la dernière sauvegarde dans une pile jetable avant de toucher à la production
(voir [`restauration.md`](restauration.md)).

## 4. Revenir à la version précédente

Le déploiement par digest mémorise l'image précédente dans
`backups/.image-precedente` :

```bash
bash scripts/deployer.sh --force --rollback
```

Sans cette mémoire, remets le digest précédent dans `IMAGE_REF` puis :

```bash
IMAGE_REF='ghcr.io/...@sha256:...' bash scripts/deployer.sh --dry-run
IMAGE_REF='ghcr.io/...@sha256:...' bash scripts/deployer.sh --force
```

Le rollback ne restaure **pas** les données : si la base a été migrée ou
corrompue, applique d'abord la procédure de restauration.

## 5. Escalade

Préviens `@WardenPro` (ou `@Zhics`) avec :

- l'heure de début et les symptômes observés ;
- le digest déployé (`docker inspect --format '{{.Config.Image}}'
  gunfight-fxserver`) et le digest précédent (`cat backups/.image-precedente`) ;
- les 100 dernières lignes des logs `fxserver` et `mariadb` ;
- les actions déjà tentées et leur résultat.

En cas de fuite de secret, applique
[`rotation-secrets.md`](rotation-secrets.md) avant de communiquer.

## 6. Vérification

L'incident est clos quand :

- `bash scripts/verifier-sante.sh` sort avec le code 0 ;
- `docker compose ... ps` montre `fxserver` et `mariadb` `healthy` ;
- `curl -fsS http://127.0.0.1:30120/dynamic.json` répond ;
- un joueur se connecte et une manche démarre ;
- les volumes `gunfight-prod-*` sont toujours présents ;
- aucune erreur rouge nouvelle n'apparaît dans les logs.

Consigne ensuite dans la PR ou le ticket : cause racine, correctif, prévention.
