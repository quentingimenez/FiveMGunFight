# Runbook — Mise à jour

**Objectif** : déployer une nouvelle image sans interruption prolongée, avec un
retour arrière immédiat possible.

**Principe** : la production ne construit rien et ne déploie jamais un tag
mutable. On déploie un **digest** `@sha256:…`, validé d'abord en préproduction.

**Prérequis** : CI verte sur le commit, digest publié sur GHCR, sauvegarde
récente, accès au VPS, `scripts/deployer.sh` et `scripts/verifier-sante.sh`.

## 0. Migrer les volumes avant le premier démarrage non-root

Le conteneur tourne désormais avec l'utilisateur `fivem` (uid 10001). Un volume
`gunfight-prod-txdata` ou `gunfight-prod-maps` créé par l'ancienne image root
appartient encore à `root` : FXServer ne pourra pas y écrire. Fais cette
migration **une seule fois**, serveur arrêté, avant le premier `up` de l'image
durcie :

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml stop fxserver
docker run --rm \
  -v gunfight-prod-txdata:/data/txdata \
  -v gunfight-prod-maps:/data/maps \
  --user 0:0 --entrypoint sh \
  debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e \
  -c 'chown -R 10001:10001 /data/txdata /data/maps && ls -ld /data/txdata /data/maps'
```

Vérifie que les deux lignes affichent `10001 10001`. Un volume neuf créé par
l'image durcie hérite déjà du bon propriétaire : la commande est sans effet.
Si tu utilises d'autres noms de volumes, adapte-les ; ne touche jamais aux
volumes d'un autre environnement.

## 1. Identifier le digest

```bash
docker buildx imagetools inspect ghcr.io/<compte>/fivemgunfight:v1.2.3
```

Relève la ligne `Digest: sha256:…` et forme la référence complète :

```bash
export IMAGE='ghcr.io/<compte>/fivemgunfight@sha256:<64 hex>'
```

Un tag seul est refusé par `deployer.sh` : il peut être réécrit et rend le
déploiement impossible à reproduire.

## 2. Valider en préproduction

```bash
export STAGING_IMAGE_REF="$IMAGE"
docker compose -f docker-compose.staging.yml pull
docker compose -f docker-compose.staging.yml up -d --wait
docker compose -f docker-compose.staging.yml logs --tail=200 fxserver
```

La préproduction écoute sur **30121** (jeu) et **127.0.0.1:40121** (txAdmin) ;
elle ne peut pas entrer en collision avec la production (30120/40120). Vérifie
`Started resource gf_…`, une connexion sur `connect 127.0.0.1:30121`, puis :

```bash
docker compose -f docker-compose.staging.yml down
```

Garde `STAGING_IMAGE_REF` définie pour `logs` et `down` : Compose résout tout
le modèle à chaque commande, même sans recréer de conteneur.

## 3. Sauvegarder

```bash
bash scripts/sauvegarder.sh
```

Note le dossier produit. Sans sauvegarde récente, arrête la procédure.

## 4. Répéter à blanc en production

```bash
IMAGE_REF="$IMAGE" bash scripts/deployer.sh --dry-run
```

Le script affiche les commandes, vérifie le format du digest et ne modifie
rien. Contrôle que le digest et l'URL de santé sont les bons.

## 5. Déployer

```bash
IMAGE_REF="$IMAGE" bash scripts/deployer.sh --force
```

Déroulé réel :

- vérification `cosign` si la commande et une clé/identité sont configurées ;
- mémorisation du digest actuel dans `backups/.image-precedente` ;
- `docker compose pull fxserver` puis `up -d --wait --wait-timeout 300` ;
- contrôle HTTP et healthcheck Docker ;
- rollback automatique vers le digest précédent si le contrôle échoue.

## 6. Vérifier

```bash
bash scripts/verifier-sante.sh
docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs --tail=200 fxserver
```

Puis, côté joueur : connexion, une manche, vérification des maps et des comptes
txAdmin. Ne considère pas le déploiement terminé tant que ces contrôles ne sont
pas passés.

## 7. Revenir en arrière

```bash
bash scripts/deployer.sh --force --rollback
```

Ou, si `backups/.image-precedente` est absent, remets l'ancien digest :

```bash
IMAGE_REF='ghcr.io/...@sha256:...' bash scripts/deployer.sh --force
```

Le rollback ne restaure pas les données. Si la nouvelle version a modifié la
base ou les maps, applique [`restauration.md`](restauration.md).

## 8. Vérification finale

- `scripts/verifier-sante.sh` code 0 ;
- `docker compose ... ps` : `fxserver` et `mariadb` `healthy` ;
- les joueurs se connectent, une manche démarre ;
- le digest affiché par `docker inspect` correspond à `$IMAGE` ;
- l'ancien digest reste noté dans `backups/.image-precedente` pour un rollback
  ultérieur ;
- la préproduction est arrêtée et ses volumes peuvent être supprimés.
