# Protection de la branche `main`

## Objectif

Empêcher tout envoi direct sur `main` et n'autoriser une fusion que si :

1. la modification est arrivée par une **pull request** ;
2. elle a été **relue et approuvée** par l'autre collaborateur ;
3. la **CI est verte** (vérifications statiques, tests de cohérence,
   construction de l'image, démarrage réel du serveur) ;
4. toutes les **conversations de revue sont résolues**.

## Règles appliquées

Le contenu exact est dans [`.github/branch-protection.json`](../.github/branch-protection.json).

| Règle | Effet |
|---|---|
| Pull request obligatoire | `git push origin main` est refusé côté GitHub |
| 1 approbation | l'auteur ne peut pas s'auto-approuver |
| Revue `CODEOWNERS` obligatoire | `@WardenPro` ou `@Zhics` doit approuver |
| Approbation invalidée après un nouvel envoi | une modification après revue doit être relue |
| Status checks requis (stricts) | `Qualité du dépôt`, `Construire et publier l'image` et `Vérifier le démarrage des ressources` doivent passer, sur la pointe de la branche |
| Conversations résolues | aucun commentaire bloquant ne reste ouvert |
| Force-push interdit | pas de réécriture d'historique sur `main` |
| Suppression interdite | `main` ne peut pas être supprimée |
| `enforce_admins: true` | le propriétaire est soumis aux mêmes règles |

Le check **`Vérifier le démarrage des ressources`** est requis même quand le
secret `CFX_LICENSE_KEY` manque (PR de fork ou Dependabot) : le job affiche
alors une note et reste vert, ce qui rend le cas visible sans bloquer la PR.

## Contrainte de plan GitHub

Sur un **dépôt privé en plan gratuit**, GitHub refuse la protection de branche
et les rulesets. L'API répond :

```text
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
```

Constat vérifié sur ce dépôt (25/11/2026) : `PUT /branches/main/protection` et
`POST /rulesets` répondent tous deux `403` avec ce message. L'interface
**Settings → Branches** affiche bien « Add branch ruleset » et « Add classic
branch protection rule », mais l'enregistrement échoue de la même façon.
Ce qui est déjà actif, en revanche : fusion en **squash** uniquement, branche
supprimée après fusion, `CODEOWNERS`, modèle de pull request, hook local
`pre-push` et la CI « Qualité » bloquante dès qu'une protection existe.

Deux solutions, au choix :

- **GitHub Pro** (~4 $/mois, dépôt conservé privé) — recommandé, aucun code
  exposé ;
- **dépôt public** — la protection devient gratuite ; le dépôt ne contient
  aucun secret (vérifié : `.env` et `server-data/secrets.cfg` sont ignorés et
  les tests le contrôlent), mais tout le code et la configuration de jeu
  deviennent visibles.

La procédure ci-dessous s'applique aussitôt après le changement de plan.

## Procédure A — interface web

À faire dans l'ordre. Les noms de cases viennent de l'interface GitHub
(Settings → Branches) en anglais ; ils sont explicites pour éviter les erreurs.

1. Ouvrir **Settings → Branches** du dépôt.
2. **Add branch protection rule** (ou modifier celle qui existe).
3. `Branch name pattern` : `main`.
4. Cocher :
   - `Require a pull request before merging` → `Require approvals` : **1** ;
   - `Dismiss stale pull request approvals when new commits are pushed` ;
   - `Require review from Code Owners` ;
   - `Require conversation resolution before merging` ;
   - `Require status checks to pass before merging` →
     `Require branches to be merged up to date` ;
   - dans la liste des checks, sélectionner **`Qualité du dépôt`**,
     **`Construire et publier l'image`** et
     **`Vérifier le démarrage des ressources`** (ils n'apparaissent qu'après un
     premier run de CI sur une pull request) ;
   - `Do not allow bypassing the above settings` (équivalent de
     `enforce_admins`) ;
   - `Do not allow force pushes` et `Do not allow deletions` restent décochés au
     sens « autoriser » : laisser les cases d'autorisation **sans cocher**.
5. **Create** / **Save changes**.
6. Recommencer éventuellement pour la branche `master` si elle réapparaît.

## Procédure B — ligne de commande

Identique à la procédure A, à partir du fichier de règles versionné :

```bash
bash scripts/proteger-branche.sh
```

Le script vérifie l'authentification `gh`, applique
`.github/branch-protection.json` avec `PUT /repos/{owner}/{repo}/branches/main/protection`,
puis relit la configuration et affiche l'état. Il échoue proprement avec le
message à afficher si le plan ne le permet pas encore.

## Vérifier que la protection est active

```bash
gh api repos/WardenPro/FiveMGunFight/branches/main/protection
```

Attendu : `required_pull_request_reviews` non nul,
`required_status_checks.contexts` contenant les trois noms de jobs,
`allow_force_pushes.enabled: false`, `enforce_admins.enabled: true`.

Test réel, sans risque pour `main` :

```bash
git switch main && git commit --allow-empty -m "test: push direct"
git push                     # doit être refusé
git reset --hard origin/main # annule le commit local
```

Sans protection, ce même envoi passe : c'est le symptôme d'un plan sans droits.

## Filet local (disponible dès maintenant, sans plan payant)

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

Contournement volontaire et exceptionnel (dépannage uniquement) :

```bash
GF_ALLOW_MAIN=1 git push
```

## Ce que la protection ne couvre pas

- **Fork** : une pull request depuis un fork ne peut pas modifier `main` du
  dépôt, mais reste fusionnable selon les mêmes règles.
- **Applications GitHub** et jetons disposant d'un droit de contournement :
  aucun n'est configuré ici ; ne pas en ajouter sans revue.
- **Branches non couvertes** : toute branche autre que `main` (et `master`)
  n'est pas protégée tant que la règle n'est pas étendue.
- **Qualité du contenu** : la revue humaine reste indispensable pour la logique
  de jeu (autorité serveur, anti-triche, équilibrage).

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `HTTP 403 ... Upgrade to GitHub Pro` | dépôt privé en plan gratuit | passer à GitHub Pro ou rendre le dépôt public, puis relancer |
| Les checks n'apparaissent pas dans la liste | aucun run de CI sur une pull request n'existe encore | ouvrir une pull request, attendre le premier run, puis éditer la règle |
| Une pull request reste « blocked » | un check requis est en échec ou jamais lancé | corriger et relancer ; vérifier les noms exacts des jobs dans `.github/workflows/` |
| Fusion impossible malgré tout vert | branche en retard sur `main` (checks stricts) | mettre à jour la branche (`git merge origin/main` puis envoi) |
| Urgence en production | `enforce_admins: true` bloque aussi le propriétaire | modifier temporairement la règle dans l'interface, corriger, puis remettre la règle immédiatement après |
