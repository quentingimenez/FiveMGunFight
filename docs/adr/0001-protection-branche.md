# ADR 0001 — Protection de la branche `main`

**Suite (26/11/2026)** — L'option finalement retenue est le **dépôt public** :
le ruleset « Protection de main » est actif, sans approbation exigée. L'ADR
recommandait GitHub Pro ; cette recommandation n'a pas été suivie.

- **Statut** : accepté le 26/11/2026 (dépôt public, voir « Suite »)
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

**Décision du 26/11/2026 : option 2, dépôt public.** Le ruleset « Protection
de main » est actif : PR obligatoire, fusion en squash, conversations
résolues, les quatre checks de la CI requis, force-push et suppression
interdits, aucune approbation exigée. L'état réel est décrit dans
[`protection-branche.md`](../protection-branche.md) ;
`.github/branch-protection.json` est un ancien modèle qui ne fait pas foi.

Texte d'origine (25/11/2026), conservé pour l'historique :

« Aucune décision n'est prise à ce jour. » L'option recommandée était GitHub Pro :
elle conserve le dépôt privé et active les règles déjà écrites, sans changer le
code. Le passage en public n'est pas recommandé pour un serveur de jeu dont la
configuration et les cartes ont de la valeur.

Le script `scripts/appliquer-protection.sh` permet de lire l'état (`--check`) et
d'appliquer le JSON (`--apply`) dès que le plan le permet. Il ne paie rien, ne
modifie pas le JSON et n'exécute jamais `--apply` tout seul.

## Conséquences

- Depuis le 26/11/2026, la protection est **active** côté GitHub ; avant
  cette date, elle était absente.
- Le hook `pre-push` est un filet local, pas une garantie serveur : il peut être
  contourné (`GF_ALLOW_MAIN=1`, `--no-verify`).
- Après activation, vérifier que les trois contextes CI portent exactement les
  noms attendus, sinon la fusion restera bloquée.

## Références

- `docs/protection-branche.md`
- `.github/branch-protection.json`
- `scripts/appliquer-protection.sh`
