# Protection de la branche `main`

## Objectif

Empêcher tout envoi direct sur `main` et n'autoriser une fusion que si :

1. la modification est arrivée par une **pull request** ;
2. la **CI est verte** (vérifications statiques, tests de cohérence,
   construction de l'image, démarrage réel du serveur) ;
3. toutes les **conversations de revue sont résolues**.

Aucune approbation n'est exigée ; une revue reste bienvenue.

## Règles appliquées

Le ruleset actif « Protection de main » fait foi ; il s'applique à la branche
par défaut du dépôt public. Le fichier
[`.github/branch-protection.json`](../.github/branch-protection.json) est un
**ancien modèle** (une approbation, trois checks) et ne décrit plus l'état
réel : ne pas s'y fier.

| Règle | Effet |
|---|---|
| Pull request obligatoire | `git push origin main` est refusé côté GitHub |
| Fusion en squash uniquement | seules les fusions squash sont autorisées par le dépôt |
| 0 approbation requise | le ruleset ne demande aucune approbation |
| Revue `CODEOWNERS` non requise | `@WardenPro` ou `@Zhics` sont bienvenus, sans obligation |
| Conversations résolues | aucun commentaire bloquant ne reste ouvert |
| 4 checks requis, non stricts | les quatre jobs de CI doivent passer, sans exiger que la branche soit à jour avec `main` |
| Force-push interdit | pas de réécriture d'historique sur `main` |
| Suppression interdite | `main` ne peut pas être supprimée |
| `bypass_actors` vide | aucun acteur ni application ne contourne le ruleset |

Les quatre checks sont `Qualité du dépôt`, `Sécurité de l'historique`,
`Construire et publier l'image` et `Vérifier le démarrage des ressources`. La
branche n'a pas à être à jour avec `main` (sinon chaque fusion relancerait la CI
de toutes les PR ouvertes) ; l'envoi sur `main` rejoue la CI après fusion.

Le check **`Vérifier le démarrage des ressources`** est requis même quand le
secret `CFX_LICENSE_KEY` manque. Sur une PR de fork ou de Dependabot, qui n'a
jamais accès aux secrets, le job affiche une note et reste vert (le test
statique sans licence tourne quand même). Partout ailleurs (push sur `main`,
PR interne, planification), un secret absent **fait échouer** le job : le
démarrage réel ne peut pas être sauté en silence.

## Historique

Le 25/11/2026, l'API GitHub refusait (403) la protection de branche et les
rulesets sur le dépôt privé en plan gratuit. Le dépôt est ensuite devenu public
et le ruleset « Protection de main » a été créé.

## Procédure A — interface web

À faire dans l'ordre. Les noms de cases viennent de l'interface GitHub
(Settings → Rules → Rulesets) en anglais ; ils sont explicites pour éviter les
erreurs.

1. Ouvrir **Settings → Rules → Rulesets** du dépôt.
2. **New ruleset → New branch ruleset**, ou modifier « Protection de main ».
3. `Enforcement status` : `Active` ; `Target branches` : la branche par défaut.
4. Cocher :
   - `Require a pull request before merging` → `Required approvals` : **0** ;
   - `Require review from Code Owners` : **décoché** ;
   - `Require conversation resolution before merging` ;
   - `Require status checks to pass`, **sans** cocher
     `Require branches to be up to date before merging` ;
   - dans la liste des checks, sélectionner **`Qualité du dépôt`**,
     **`Sécurité de l'historique`**, **`Construire et publier l'image`** et
     **`Vérifier le démarrage des ressources`** (ils n'apparaissent qu'après un
     premier run de CI sur une pull request) ;
   - `Block force pushes` et `Restrict deletions` : activés.
5. Dans **Settings → General → Pull requests**, n'autoriser que la fusion en
   **squash** (décocher merge commit et rebase).
6. Vérifier que la liste `Bypass list` reste **vide**.
7. **Create** / **Save changes**.

## Procédure B — ligne de commande

Le ruleset actif se consulte avec l'API des rulesets :

```bash
gh api repos/quentingimenez/FiveMGunFight/rulesets
```

`scripts/appliquer-protection.sh` et le fichier
`.github/branch-protection.json` décrivent l'**ancien modèle** (une
approbation, trois checks) et ne doivent pas servir à recréer le ruleset actif.
Le script reste disponible et `scripts/proteger-branche.sh` reste son ancien
nom, mais ce n'est plus la procédure d'application actuelle.

## Vérifier que la protection est active

```bash
gh api repos/quentingimenez/FiveMGunFight/rulesets
gh api repos/quentingimenez/FiveMGunFight/rulesets/<id>
```

Attendu : un ruleset nommé « Protection de main », `enforcement: active`,
`bypass_actors` vide, les quatre checks requis et la fusion en squash.

La preuve est la lecture du ruleset par l'API (commandes ci-dessus) : on ne
teste jamais un envoi direct sur `main`.

## Filet local

Le dépôt fournit un hook `pre-push` qui refuse les envois directs vers `main`
depuis ta machine. Il ne remplace pas la protection serveur (on peut le
contourner), mais il bloque l'erreur la plus fréquente au moment où elle se
produit.

Installation, une fois par clone :

```bash
git config core.hooksPath .githooks
```

Désinstallation :

```bash
git config --unset core.hooksPath
```

Le hook peut être contourné (`GF_ALLOW_MAIN=1`, `--no-verify`) ; c'est un
filet local, jamais une garantie serveur. Ne pas contourner la protection
pour pousser directement sur `main`.

## Ce que la protection ne couvre pas

- **Fork** : une pull request depuis un fork ne peut pas modifier `main` du
  dépôt, mais reste fusionnable selon les mêmes règles.
- **Applications GitHub** et jetons disposant d'un droit de contournement :
  aucun n'est configuré ici ; ne pas en ajouter sans revue.
- **Branches non couvertes** : toute branche autre que la branche par défaut
  n'est pas protégée tant que le ruleset n'est pas étendu.
- **Qualité du contenu** : la revue humaine reste indispensable pour la logique
  de jeu (autorité serveur, anti-triche, équilibrage).

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Les checks n'apparaissent pas dans la liste | aucun run de CI sur une pull request n'existe encore | ouvrir une pull request, attendre le premier run, puis éditer la règle |
| Une pull request reste « blocked » | un check requis est en échec ou jamais lancé | corriger et relancer ; vérifier les noms exacts des jobs dans `.github/workflows/` |
| Urgence en production | le ruleset n'a aucun contournement | ouvrir une pull request prioritaire et suivre la boucle habituelle ; ne jamais pousser directement sur `main` |
