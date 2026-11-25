# ADR 0001 — Protection de la branche `main`

- **Statut** : proposé, décision en attente
- **Date** : 2026-11-25
- **Décideurs** : `@WardenPro`, `@Zhics`

## Contexte

`main` est la branche de production. Les règles souhaitées sont déjà versionnées
dans `.github/branch-protection.json` : pull request obligatoire, une
approbation `CODEOWNERS`, trois checks CI obligatoires, résolution des
conversations, interdiction du force-push et de la suppression.

GitHub refuse cependant l'application de ces règles sur un dépôt **privé** avec
un plan gratuit (réponse 403, voir `docs/protection-branche.md`). La protection
est donc **inactive** aujourd'hui : la discipline repose sur `AGENTS.md`, le
hook `.githooks/pre-push` et la revue humaine.

## Options

1. **GitHub Pro** (environ 4 $/mois) : le dépôt reste privé, la protection
   devient disponible. Aucun code ni secret n'est exposé.
2. **Dépôt public** : la protection devient gratuite, mais le code, les cartes,
   la configuration de jeu et l'historique deviennent visibles. Les secrets
   restent hors du dépôt (`secrets/`, variables CI), mais la surface
   d'exposition augmente.
3. **Statut quo** : aucune protection GitHub ; seuls le hook local et la revue
   humaine empêchent un envoi direct.

## Décision

**Aucune décision n'est prise à ce jour.** L'option recommandée est GitHub Pro :
elle conserve le dépôt privé et active les règles déjà écrites, sans changer le
code. Le passage en public n'est pas recommandé pour un serveur de jeu dont la
configuration et les cartes ont de la valeur.

Le script `scripts/appliquer-protection.sh` permet de lire l'état (`--check`) et
d'appliquer le JSON (`--apply`) dès que le plan le permet. Il ne paie rien, ne
modifie pas le JSON et n'exécute jamais `--apply` tout seul.

## Conséquences

- Tant que la décision n'est pas prise, la protection reste **absente** : ne pas
  l'affirmer dans la documentation.
- Le hook `pre-push` est un filet local, pas une garantie serveur : il peut être
  contourné (`GF_ALLOW_MAIN=1`, `--no-verify`).
- Après activation, vérifier que les trois contextes CI portent exactement les
  noms attendus, sinon la fusion restera bloquée.

## Références

- `docs/protection-branche.md`
- `.github/branch-protection.json`
- `scripts/appliquer-protection.sh`
