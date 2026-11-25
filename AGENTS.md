# Règles agent — FiveMGunFight

Ce fichier est lu automatiquement par les agents de codage (DeepSeek Harness et
autres) à l'ouverture d'une session dans ce dépôt. Il fixe le **déroulé
obligatoire** de toute session qui modifie le dépôt. [`CONTRIBUTING.md`](CONTRIBUTING.md)
reste la référence pour le fond (style de commit, critères de revue, sécurité) :
en cas de divergence, `CONTRIBUTING.md` gagne sur le contenu et ce fichier gagne
sur le déroulé.

## 1. Règle cardinale

`main` est la branche de production. **Aucun agent ne commit ni ne pousse
directement sur `main`.** Toute modification — même une ligne de documentation —
passe par une branche, une pull request suivie jusqu'à la CI verte, puis une
fusion en squash par l'agent.

## 2. Définition de « session terminée »

Une session qui a modifié le dépôt n'est terminée que lorsque, dans cet ordre :

1. la pull request est **mergée** sur `main` (squash) ;
2. la **branche distante** est supprimée (le dépôt s'en charge après fusion) ;
3. la **branche locale** est supprimée ;
4. on est revenu sur `main`, à jour de `origin/main` ;
5. l'arbre ne contient plus aucun fichier modifié ou non suivi **appartenant à
   la session** (les changements préexistants laissés par l'utilisateur restent
   intacts) ;
6. l'utilisateur reçoit le **lien de la pull request** et le **sha du commit de
   fusion**.

Une session en lecture seule (analyse, question, revue) n'ouvre ni branche ni
pull request.

## 3. Début de session

```bash
gh auth status                # doit être connecté au compte propriétaire du dépôt
git switch main
git pull --ff-only
git status --short --branch
git config core.hooksPath .githooks   # filet local : refuse tout push direct sur main
```

- Si `core.hooksPath` est déjà positionné, ne rien changer.
- **Arbre déjà sale à l'ouverture** : ces changements sont extérieurs à la
  session. Ne pas les commiter par défaut ; ne les intégrer que si l'utilisateur
  confirme qu'ils relèvent du même sujet. Ne jamais `git add -A` à l'aveugle :
  ajouter fichier par fichier et relire `git diff --cached`.

## 4. Boucle obligatoire

### 4.1 Branche

```bash
git switch -c type/sujet-en-kebab-case
```

Types : `feat`, `fix`, `docs`, `ci`, `chore`, `refactor`, `perf`, `test`.
Une branche = un sujet. Deux sujets indépendants = deux branches, deux pull
requests, dans l'ordre.

### 4.2 Contrôles locaux avant le commit

```bash
python -m unittest discover -s tests -v
bash scripts/verifier.sh
```

- `luac` et `shellcheck` ne sont pas installés sur le poste de référence : leur
  étape s'affiche « ignoré » ; c'est la CI (Ubuntu) qui tranche.
- Si le sujet touche `Dockerfile`, `docker-compose*.yml`, `docker/entrypoint.sh`
  ou `server-data/server.cfg` : construire et démarrer réellement l'image
  (`docker compose build`, `docker compose up -d`, puis `docker compose logs -f
  fxserver` jusqu'à « Started resource gf_ »), et tester le comportement en jeu.
- Un contrôle rouge se corrige, jamais ne se contourne.

### 4.3 Commit

```bash
git add <fichiers du sujet>
git commit -m "type(scope): sujet à l'impératif" -m "Pourquoi ce changement (contexte, bug, contrainte)."
```

- Un commit = un changement cohérent ; message utile dans six mois.
- Vérifier qu'aucun secret n'entre dans l'index : `.env`,
  `server-data/secrets.cfg`, `server-data/cache/`, clé `CFX_LICENSE_KEY`.
- Ne pas embarquer de fichiers hors sujet (notamment les changements
  préexistants de l'utilisateur).

### 4.4 Envoi et pull request

```bash
git push -u origin "$(git branch --show-current)"
gh pr create --base main --title "type(scope): sujet" --body-file "$env:TEMP\pr.md"   # PowerShell
```

Le corps de la PR reprend [`.github/pull_request_template.md`](.github/pull_request_template.md) :
**Résumé**, **Pourquoi**, **Comment tester**, **Checklist** avec les cases
cochées. Décrire ce qui a réellement été exécuté.

### 4.5 Suivi obligatoire de la CI

```bash
gh pr checks --watch
gh pr view --json number,state,mergeable,statusCheckRollup
```

- Attendre la fin de **tous** les checks : `Qualité du dépôt` (1–2 min) et
  `Construire et publier l'image` (3–8 min).
- **Rouge** : corriger sur la même branche, commit additionnel, `git push`, puis
  relancer le suivi. Pas de réécriture d'historique après le début de la revue,
  pas de force-push, pas de désactivation ni de contournement d'un check
  (`--admin` interdit).
- **Conflit avec `main`** : `git fetch origin`, `git merge origin/main` sur la
  branche, résoudre, push, puis attendre les nouveaux checks. Pas de rebase.
- Une PR ne se laisse jamais « en attente » en fin de session : elle est menée
  jusqu'à la fusion ou explicitement signalée comme bloquée (§ 7).

### 4.6 Fusion

Fusionner **uniquement** quand la CI est verte et la PR fusionnable :

```bash
gh pr merge --squash --delete-branch
```

- Squash **uniquement** (jamais de merge commit ni de rebase) : l'historique de
  `main` reste une suite de changements complets.
- Le dépôt supprime la branche distante après fusion ; `--delete-branch` retire
  aussi la branche locale.

### 4.7 Retour sur `main`

```bash
git switch main
git pull --ff-only
git fetch --prune
git branch -D type/sujet-en-kebab-case   # -D : après squash, les commits ne sont pas ancêtres
git status -sb
git rev-parse HEAD origin/main           # les deux sha doivent être identiques
```

Puis surveiller le run de `main` : le test de démarrage réel ne tourne que
là (`gh run list --branch main --limit 1`). S'il est rouge, ouvrir une pull
request de correction immédiatement — jamais de commit direct sur `main`.

## 5. Interdits

- Commit ou push direct sur `main`, y compris `git commit --allow-empty` de test.
- `git push --force` / `--force-with-lease`, `GF_ALLOW_MAIN=1`, `gh pr merge --admin`.
- Fusionner avec un check rouge, en attente, ou en ignorant une conversation de
  revue non résolue.
- Contourner un contrôle (supprimer un test, désactiver un workflow, modifier la
  CI pour faire passer la PR) sans que ce soit le sujet explicite, revu à part.
- Mélanger plusieurs sujets dans une PR, ou pousser des changements
  préexistants de l'utilisateur.
- Commiter un secret (`.env`, `server-data/secrets.cfg`, cache, clé de licence).
- Laisser une branche locale, une branche distante ou une PR ouverte en fin de
  session sans l'avoir signalé à l'utilisateur.
- « Réparer » `main` par un commit direct : un problème sur `main` se corrige
  par une PR (revert `git revert -m 1 <sha>` sur une branche dédiée si besoin).

## 6. Revues humaines

Le dépôt exige 1 approbation `CODEOWNERS` (`@WardenPro` ou `@Zhics`). Tant que
la protection de branche GitHub n'est pas active (dépôt privé en plan gratuit,
voir [`docs/protection-branche.md`](docs/protection-branche.md)), la discipline
repose sur l'agent et sur le hook `pre-push`. Si un humain commente la PR :
répondre par des commits sur la même branche, puis fusionner une fois les
échanges résolus.

## 7. Blocages et cas particuliers

- **CI en échec pour une cause externe** (panne GitHub, quota, secret
  `CFX_LICENSE_KEY` absent, registre indisponible) : documenter dans la PR,
  avertir l'utilisateur, ne pas fusionner sans feu vert explicite.
- **Fusion refusée** (droits, règle de protection activée) : laisser la PR
  ouverte, donner l'URL et ce qui manque ; ne jamais contourner.
- **Urgence de production** : la boucle reste la même, en priorité. Aucun
  hotfix direct sur `main`.
- **Modification de ce fichier, de `.github/` ou des workflows** : PR dédiée,
  explication dans le corps ; ce sont des fichiers à impact fort (`CODEOWNERS`).
- **Session interrompue** : au redémarrage, reprendre la PR existante
  (`gh pr list --head type/sujet-en-kebab-case`) plutôt que d'en ouvrir une
  seconde.

## 8. Contexte du dépôt

- Dépôt : `WardenPro/FiveMGunFight` (privé), `gh` authentifié et autorisé.
- CI : `.github/workflows/qualite.yml` (job `Qualité du dépôt`) et
  `.github/workflows/docker.yml` (job `Construire et publier l'image`), tous
  deux déclenchés sur chaque pull request. Le job `Vérifier le démarrage des
  ressources` ne tourne que sur `main` et les tags.
- Protection GitHub : inactive à cause du plan gratuit ; options de fusion déjà
  en place (squash autorisé, branche supprimée après fusion). Voir
  `docs/protection-branche.md`.
- Outils locaux : Python 3.14, Node.js 24, Docker 28, `bash` (WSL),
  `gh` 2.103. `luac` et `shellcheck` absents — les contrôles correspondants
  sont ignorés en local et exécutés par la CI.
