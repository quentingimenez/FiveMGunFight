# ADR 0002 — FXServer épinglé par URL et SHA256

- **Statut** : accepté pour la cible ; application encore partielle
- **Date** : 2026-11-25
- **Décideurs** : `@WardenPro`, `@Zhics`

## Contexte

L'image Docker télécharge FXServer au moment du build. Le `Dockerfile` accepte
deux arguments :

- `FX_URL` : lien direct vers une archive `fx.tar.xz` précise ;
- `FX_SHA256` : empreinte SHA256 de cette archive.

Si `FX_URL` est vide, le build interroge le changelog officiel
`https://changelogs-live.fivem.net/api/changelog/versions/linux/server` et prend
l'URL du canal `recommended` (ou `latest`). Si `FX_SHA256` est vide, un
avertissement est affiché et l'archive n'est pas vérifiée : deux builds du même
commit peuvent alors produire des binaires différents.

Les images de base sont déjà épinglées par digest (Debian et MariaDB), et les
actions GitHub par SHA. FXServer restait le maillon non reproductible.

## Décision

Pour toute image publiée en production :

1. télécharger une archive **versionnée** et noter son URL exacte ;
2. calculer son SHA256 ;
3. construire avec `FX_URL` et `FX_SHA256` ;
4. publier l'image, puis déployer par **digest** avec `scripts/deployer.sh`.

Le canal `recommended` sans SHA reste acceptable pour le développement local,
pas pour une image de production.

## Procédure de mise à jour

```bash
# 1. URL de la version voulue (changelog officiel ou annonce Cfx.re)
FX_URL='https://.../fx.tar.xz'
# 2. Empreinte
curl -fsSL "$FX_URL" -o /tmp/fx.tar.xz
sha256sum /tmp/fx.tar.xz
# 3. Build vérifié
docker build \
  --build-arg FX_URL="$FX_URL" \
  --build-arg FX_SHA256='<64 hex>' \
  -t fivemgunfight:essai .
```

Le build échoue si l'empreinte ne correspond pas. Il faut ensuite démarrer
l'image, attendre `Started resource gf_…`, vérifier une connexion, puis publier
et déployer le digest.

## Mise en œuvre

`.fxserver-version` porte `FX_VERSION`, `FX_URL` et `FX_SHA256`. Le job
`Construire et publier l'image` relit ce fichier et **refuse** de construire si
l'un des trois champs manque, si l'URL n'est pas HTTPS ou si l'empreinte n'est
pas un SHA256 de 64 caractères hexadécimaux. Il passe ensuite `FX_URL` et
`FX_SHA256` au build, qui échoue si l'archive ne correspond pas. Le repli
`FX_CHANNEL=recommended` du `Dockerfile` ne sert plus qu'aux builds locaux
volontairement non épinglés.

## Conséquences

- Une montée de version FXServer est explicite, testée et traçable.
- Les mises à jour automatiques du canal sont abandonnées en production.
- Le digest de l'image publiée reste la référence de déploiement ; un tag seul
  n'est jamais déployé.
- En cas d'échec de téléchargement ou d'empreinte, le build s'arrête : pas de
  binaire non vérifié en production.

## Références

- `Dockerfile`
- `docs/runbooks/mise-a-jour.md`
- `scripts/deployer.sh`
