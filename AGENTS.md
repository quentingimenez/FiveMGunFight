# Règles agent — FiveMGunFight

Ce fichier est lu automatiquement par les agents de codage à l'ouverture d'une
session dans ce dépôt : Codex, opencode, Cursor, GitHub Copilot et DeepSeek
Harness le lisent directement ; Claude Code et Gemini CLI le chargent par
[`CLAUDE.md`](CLAUDE.md) et [`GEMINI.md`](GEMINI.md), qui l'importent. Toutes
ses règles valent pour **tout agent**, quel que soit l'outil ; une consigne
propre à un seul outil est signalée comme telle. Il fixe le **déroulé
obligatoire** de toute session qui modifie le dépôt. [`CONTRIBUTING.md`](CONTRIBUTING.md)
reste la référence pour le fond (style de commit, critères de revue, sécurité) :
en cas de divergence, `CONTRIBUTING.md` gagne sur le contenu et ce fichier gagne
sur le déroulé.

## Règle d'or — on situe avant de coder, on vérifie avant d'intégrer

Toute demande suit la [méthode de développement](docs/methode/README.md) :
cadrer, **situer** (fiche d'impact), concevoir, **tester d'abord**, produire,
**vérifier**, livrer, capitaliser. Un changement n'est jamais traité comme
une fonctionnalité isolée : on cherche ce qu'il touche ailleurs avant d'écrire
la première ligne (§ 4.0).

Le travail se répartit en rôles, quel que soit l'outil
([orchestration des agents](docs/methode/orchestration-agents.md)) :

- l'**orchestrateur-vérificateur** parle à l'utilisateur, cadre, remplit la
  fiche d'impact, découpe, écrit les briefs, **vérifie chaque production** et
  décide de l'intégration ;
- le **producteur** exécute un brief complet (tests d'abord, puis code) sans
  sortir de son périmètre de fichiers ;
- au niveau L, un **vérificateur indépendant** relit le diff sans le
  raisonnement du producteur.

Règles communes :

- Un producteur ne décide jamais d'un commit, d'un push, d'une PR ou d'une
  fusion : ces décisions restent celles de l'orchestrateur, avec l'accord de
  l'utilisateur (§ 4.5).
- « Vérifier » veut dire : relire le diff produit en entier, lancer soi-même
  les contrôles (§ 4.2), exécuter le comportement en local au niveau exigé
  (§ 4.3) et comparer le résultat aux critères d'acceptation. Une production
  non vérifiée n'est jamais intégrée.
- Si le producteur prévu est indisponible ou échoue de façon répétée,
  l'orchestrateur le signale à l'utilisateur et attend sa décision ; il ne
  bascule pas silencieusement sur un autre modèle.
- Ces règles s'appliquent à **toute demande de correction**, y compris quand
  l'utilisateur décrit lui-même le correctif à appliquer.

Configurations utilisées sur ce dépôt (exemples, pas des obligations) :
DeepSeek Harness, où DeepSeek orchestre et des sous-agents
`opencode-go/hy4-flash-free` produisent ; Claude Code qui orchestre et délègue
la production à DeepSeek Harness. Un agent seul tient les deux rôles en
séparant les temps : brief, production, puis vérification de son propre diff.

## 1. Règle cardinale

`main` est la branche de production. **Aucun agent ne commit ni ne pousse
directement sur `main`.** Toute modification — même une ligne de documentation —
passe par une branche, une pull request suivie jusqu'à la CI verte, puis une
fusion en squash par l'agent.

Avant tout envoi, l'agent **exécute la modification en local**, explique
explicitement l'**avant** et l'**après**, et attend l'**accord de
l'utilisateur** (§ 4.3 et § 4.5). Sans accord, rien n'est poussé.

## 2. Définition de « session terminée »

Une session qui a modifié le dépôt n'est terminée que lorsque, dans cet ordre :

1. la modification, située par sa fiche d'impact (§ 4.0), a été **exécutée et
   vérifiée en local** au niveau exigé par la matrice de test (§ 4.3), et ce
   qui doit être capitalisé l'a été (§ 4.4) ;
2. l'utilisateur a donné son **accord explicite** sur l'avant/après (§ 4.5) ;
3. la branche a été poussée et la pull request est **mergée** sur `main` (squash)
   avec `scripts/fusionner-pr.sh` (§ 4.8) ;
4. la **CI de `main`** est **verte** sur le commit de fusion (le script la suit
   jusqu'au bout) ; rouge, une PR de correction est ouverte aussitôt (§ 4.9) ;
5. la **branche distante** est supprimée (le dépôt s'en charge après fusion) ;
6. la **branche locale** est supprimée ;
7. on est revenu sur `main`, à jour de `origin/main` ;
8. l'arbre ne contient plus aucun fichier modifié ou non suivi **appartenant à
   la session**, captures et fichiers de travail compris (§ 5) ; les
   changements préexistants laissés par l'utilisateur restent intacts ; le
   client FiveM est **fermé** si l'agent l'a lancé sans que l'utilisateur ait
   demandé de l'ouvrir (§ 5) ;
9. l'utilisateur reçoit le **lien de la pull request**, le **sha du commit de
   fusion** et le **résultat de la CI de `main`** sur ce commit.

Si l'utilisateur refuse ou ne donne pas son accord, la session s'arrête à
l'étape 2 : la branche et le commit restent **locaux**, ne sont pas poussés, et
l'utilisateur est informé de ce qui attend son feu vert.

Une session en lecture seule (analyse, question, revue) n'ouvre ni branche ni
pull request.

## 3. Début de session

```bash
gh auth status                # doit être connecté au compte propriétaire du dépôt
git switch main
git pull --ff-only
git status --short --branch
python scripts/suivre_dependabot.py   # PR Dependabot à traiter
git config core.hooksPath .githooks   # filet local : refuse tout push direct sur main
```

- Si `core.hooksPath` est déjà positionné, ne rien changer.
- **Arbre déjà sale à l'ouverture** : ces changements sont extérieurs à la
  session. Ne pas les commiter par défaut ; ne les intégrer que si l'utilisateur
  confirme qu'ils relèvent du même sujet. Ne jamais `git add -A` à l'aveugle :
  ajouter fichier par fichier et relire `git diff --cached`.
- **PR Dependabot en attente** : si `python scripts/suivre_dependabot.py` sort
  en code 1, le signaler à l'utilisateur dès le premier message et proposer de
  traiter ces PR, sans changer le sujet de la session sans son accord (§ 10).

## 4. Boucle obligatoire

### 4.0 Cadrer et situer (avant le code)

Porte **G1** de la [méthode](docs/methode/README.md) : aucune ligne de code
avant ces trois livrables.

1. **Cadrer** : reformuler la demande et écrire des **critères d'acceptation**
   observables. Une demande ambiguë, ou qui implique une **décision produit**
   (retirer ou remplacer une fonctionnalité, changer une règle de jeu, une
   touche, un équilibre), se clarifie avec l'utilisateur **avant** de coder ;
   la décision prise donne un [ADR](docs/adr/README.md). Une décision produit
   ne se prend jamais « au passage » d'une autre tâche.
2. **Situer** : remplir la [fiche d'impact](docs/methode/fiche-impact.md) :
   ressources et **contrats touchés** (exports, événements `gf:*` et
   `gf_<ressource>:*`, state bags, calques NUI, tables, fichiers de données,
   textes vus par le joueur), appelants et écouteurs **trouvés par
   recherche**, risques, niveau S/M/L, plan de test. Chaque appelant trouvé
   est adapté dans la PR ou justifié comme non concerné.
3. **Prévoir les tests** : les niveaux exigés par la
   [matrice](docs/methode/strategie-de-test.md) ; ils s'écrivent et se voient
   rouges **avant** le code (règle V2).

Niveau S (documentation, réglage isolé sans contrat touché) : trois lignes
de fiche suffisent. Niveau L (plusieurs ressources, contrat, état partagé,
base, calques NUI) : un vérificateur indépendant relit avant la porte G2.

### 4.1 Branche

```bash
git switch -c type/sujet-en-kebab-case
```

Types : `feat`, `fix`, `docs`, `ci`, `chore`, `refactor`, `perf`, `test`.
Une branche = un sujet. Deux sujets indépendants = deux branches, deux pull
requests, dans l'ordre. À l'inverse, les changements d'un **même sujet**
(code, tests, documentation, registre) vont dans la **même** PR : chaque PR
coûte deux runs complets de CI (PR, puis `main`), on n'en multiplie pas pour
de petits lots.

Avant de toucher au code, annoncer l'intention en une phrase : ce qui va être
modifié et pourquoi, avec le niveau S/M/L de la fiche.

### 4.2 Contrôles locaux avant le commit

```bash
bash scripts/verifier-docker.sh
```

- Docker Desktop doit être démarré. La commande construit l'image de
  vérification et y lance `scripts/verifier.sh` ; un outil absent fait échouer
  le script lancé hors de l'image (« outil absent : … »).
- Si le sujet touche `Dockerfile`, `docker-compose*.yml`, `docker/entrypoint.sh`
  ou `server-data/server.cfg` : construire et démarrer réellement l'image
  (`docker compose -f docker-compose.yml -f docker-compose.dev.yml build`, puis
  `... up -d`, puis `... logs -f fxserver` jusqu'à « Started resource gf_ »),
  et tester le comportement en jeu.
- Un contrôle rouge se corrige, jamais ne se contourne.
- Une relecture de diff ne prouve rien : la modification doit être **exécutée**
  en local (§ 4.3) avant d'être proposée.

### 4.3 Exécution locale et preuve

Toute modification doit être **lancée en local** avant d'être proposée, au
niveau exigé par la [matrice de test](docs/methode/strategie-de-test.md)
(niveaux T0 à T6 selon le type de changement). Ce que l'agent ne peut pas
faire lui-même (tir, conduite, deux joueurs : niveau T6) se demande à
l'utilisateur sous forme de scénario écrit **avant** la porte d'accord. Lancer
le composant concerné et observer le résultat :

- ressource Lua / serveur : **avant chaque lancement**, fixer `TXADMIN=false`
  et `MAX_PLAYERS=48` dans le shell (le `.env` du poste peut valoir
  `TXADMIN=true` et plus de 48 joueurs : txAdmin redémarre alors en boucle, ou
  FiveM refuse les connexions), lancer
  `docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --force-recreate fxserver`
  (`restart` ne relit pas les variables), vérifier dans les logs
  « txAdmin : désactivé » et « joueurs max : 48 », attendre « Started resource
  gf_… », puis reproduire le scénario en jeu ou par commande. Détail et
  commandes : [`docs/debug-test.md`](docs/debug-test.md) § 2, « Prérequis » ;
- interface NUI : ouvrir l'écran concerné, vérifier le rendu et les actions ;
- rendu, caméra, ped ou natif jamais appelé : lire d'abord
  [`docs/pieges-fivem.md`](docs/pieges-fivem.md). Signature d'un natif :
  `python scripts/native.py <nom ou hash>` (docs.fivem.net n'est pas lisible
  par un outil web) ; un natif n'est jamais déclaré « cassé » sans un test
  minimal qui l'appelle seul. Boucle d'essai : `scripts/fivem_rcon.py restart
  <ressource>`, `scripts/journal_client.py --ressource <ressource>`,
  `scripts/capturer-jeu.ps1`, **un changement par essai**, critère mesurable,
  arrêt et compte rendu après trois essais ratés sur la même piste ; calculs
  (géométrie, caméra) dans un module pur testé par `tests/lua/` ;
- script / outillage : l'exécuter sur un cas nominal **et** sur le cas d'erreur
  qu'il doit traiter ;
- PR Dependabot : `python scripts/suivre_dependabot.py` liste et classe les PR
  ouvertes, sans rien modifier ; la marche à suivre est au § 10 ;
- documentation seule : le déclarer explicitement (« sans exécution :
  documentation »), vérifier les liens et lancer
  `bash scripts/verifier-docker.sh`.

Consigner la commande lancée et le résultat observable (sortie, capture, log) :
c'est la preuve qui accompagne l'avant/après. Puis cocher un par un les
critères d'acceptation du § 4.0 (porte **G2**).

### 4.4 Capitaliser, puis commit

Avant le commit, répondre aux cinq questions de l'étape « Capitaliser » de la
[méthode](docs/methode/README.md#p7--capitaliser) ; chaque « oui » entre dans
**la même PR** :

- correctif : un test de régression vu rouge sur le code d'avant, et la
  cause racine catégorisée dans la description de la PR ;
- comportement surprenant de la plateforme : une entrée dans
  [`docs/pieges-fivem.md`](docs/pieges-fivem.md) ;
- décision qui engage la suite : un [ADR](docs/adr/README.md) ;
- contrat modifié : registre et documents des contrats à jour ;
- dette vue et non traitée : une entrée dans
  [`docs/chantiers-techniques.md`](docs/chantiers-techniques.md), jamais un
  correctif hors sujet glissé dans la PR.

```bash
git add <fichiers du sujet>
git commit -m "type(scope): imperative subject" -m "Why this change (context, bug, constraint)."
```

- Les messages de commit sont **en anglais** (en-tête et corps), comme le titre
  de la PR, qui devient le message du commit de fusion en squash.
- Un commit = un changement cohérent ; message utile dans six mois.
- Vérifier qu'aucun secret n'entre dans l'index : `.env`,
  `server-data/secrets.cfg`, `server-data/cache/`, clé `CFX_LICENSE_KEY`.
- Ne pas embarquer de fichiers hors sujet (notamment les changements
  préexistants de l'utilisateur).

### 4.5 Explication avant/après et accord utilisateur (porte de push)

Avant **tout envoi**, présenter à l'utilisateur, explicitement :

1. **Avant** — l'état ou le comportement actuel, le symptôme, la limite
   constatée ;
2. **Après** — l'état attendu et ce qui change concrètement (joueurs,
   exploitation, outils) ;
3. **Preuve locale** — ce qui a été lancé (§ 4.3) et le résultat observé ;
4. **Portée** — fichiers touchés et ce qui n'est pas modifié.

Puis **attendre un accord explicite** (« ok », « go », « envoie », « merge »…).
Sans accord : ne pas pousser, ne pas ouvrir de PR, ne pas fusionner. Un accord
donné pour un autre sujet ne vaut pas. Si l'utilisateur demande des
modifications : les faire, relancer l'exécution locale, réexpliquer, redemander.

Le commit local peut exister avant l'accord ; il ne part sur le dépôt distant
qu'une fois celui-ci obtenu.

### 4.6 Envoi et pull request

Une fois l'accord obtenu (§ 4.5), pousser la branche et ouvrir la PR :

```bash
git push -u origin "$(git branch --show-current)"
gh pr create --base main --title "type(scope): sujet" --body-file "$env:TEMP\pr.md"   # PowerShell
```

La documentation du dépôt et la description de la PR sont rédigées **en
français** ; seul le titre de la PR reste en anglais (§ 4.4).

Le corps de la PR reprend [`.github/pull_request_template.md`](.github/pull_request_template.md) :
**Résumé**, **Pourquoi**, **Fiche d'impact** (§ 4.0), **Tests et preuve**,
**Risques et retour arrière**, **Cause racine** pour un correctif, et la
**Checklist** avec les cases cochées. Décrire ce qui a réellement été
exécuté.

### 4.7 Suivi obligatoire de la CI

```bash
gh pr checks --watch
gh pr view --json number,state,mergeable,statusCheckRollup
```

- Attendre la fin de **tous** les checks : `Qualité du dépôt` (1 min 30 à 2 min :
  construction de l'image de vérification comprise),
  `Construire et publier l'image` (2 à 3 min) et `Vérifier le démarrage des
  ressources` (1 à 2 min, sauté avec une note si le secret CI est absent).
- **Rouge** : corriger sur la même branche, commit additionnel, `git push`, puis
  relancer le suivi. Pas de désactivation ni de contournement d'un check
  (`--admin` interdit).
- **Branche en retard ou en conflit avec `main`** : rebaser, jamais de merge de
  `main` dans la branche :

  ```bash
  git fetch origin
  git rebase origin/main          # résoudre chaque conflit, puis git rebase --continue
  bash scripts/verifier-docker.sh
  git push --force-with-lease
  ```

  La branche reste une suite linéaire de commits au-dessus de `main`, sans
  commit de fusion, et la PR ne montre que ses propres changements. Une PR en
  retard sur `main` mais sans conflit n'a pas besoin d'être rebasée : les checks
  ne sont pas stricts, et chaque mise à jour relancerait toute la CI.
- **Force-push** : uniquement `--force-with-lease`, uniquement sur la branche de
  la PR en cours. Jamais sur `main` (refusé par la protection de branche et par
  le hook `pre-push`). Si un relecteur a déjà commenté, le prévenir dans la PR
  que la branche a été rebasée.
- Une PR ne se laisse jamais « en attente » en fin de session : elle est menée
  jusqu'à la fusion ou explicitement signalée comme bloquée (§ 7).
- **Surveillance systématique** : toute PR ouverte par l'agent est surveillée
  et fusionnée par l'agent lui-même (§ 4.8), sans que l'utilisateur ait à le
  redemander. L'accord donné pour l'envoi (§ 4.5) vaut aussi pour la fusion
  une fois la CI verte.
- **Tout agent** : après `gh pr create`, suivre la CI jusqu'au bout
  (`gh pr checks <numéro> --watch`), puis fusionner avec le script du § 4.8. Un suivi
  automatique fourni par l'outil ne remplace pas ce suivi s'il ne signale que
  les échecs.
- **Propre à l'application Claude Code (desktop)** : juste après `gh pr create`,
  activer aussi le suivi automatique de la PR (Auto-fix : CI rouge, conflits,
  commentaires) ; il ne réveille pas la session quand tout passe au vert.
  Si l'application répond que le dépôt « could not be matched to this
  session's folders », demander à l'utilisateur de cliquer sur **« Linked by
  Claude »** dans la barre de PR de la session, puis réactiver le suivi. En
  attendant, suivre la CI soi-même (`gh pr checks --watch`) : l'absence du
  suivi automatique n'est jamais une raison de laisser la PR ouverte.

### 4.8 Fusion

Fusionner **uniquement** avec le script, jamais avec `gh pr merge` à la main :

```bash
bash scripts/fusionner-pr.sh <numéro>
```

Il attend la fin des checks de la PR (un check rouge bloque la fusion),
fusionne en squash, puis suit jusqu'au bout chaque run lancé sur `main` par le
commit de fusion. Il ne sort en code 0 que si la CI de `main` est verte ; sinon
il affiche le lien du run rouge. Le lancer en arrière-plan si l'outil limite la
durée d'une commande : la CI de `main` dure de 3 à 4 minutes.

- Squash **uniquement** (jamais de merge commit ni de rebase) : l'historique de
  `main` reste une suite de changements complets.
- Le dépôt supprime la branche distante après fusion ; la branche locale se
  supprime au § 4.9.

### 4.9 Retour sur `main`

```bash
git switch main
git pull --ff-only
git fetch --prune
git branch -D type/sujet-en-kebab-case   # -D : après squash, les commits ne sont pas ancêtres
git status -sb
git rev-parse HEAD origin/main           # les deux sha doivent être identiques
bash scripts/nettoyer-docker.sh          # libère le cache et les images <none> des builds
```

`verifier-docker.sh` nettoie déjà seul après chaque vérification ; le
nettoyage final couvre les constructions du serveur (`compose ... build`).
Quand le disque est plein, `--tout` vide tout le cache et les images
qu'aucun conteneur n'utilise ([`docs/debug-test.md`](docs/debug-test.md)
§ 5, « Espace disque »).

Si `scripts/fusionner-pr.sh` a signalé une CI de `main` rouge, ouvrir une pull
request de correction immédiatement — jamais de commit direct sur `main`.

Filet de sécurité : le workflow `.github/workflows/alerte-main.yml` ouvre (ou
complète) l'issue « CI rouge sur main » à chaque échec de `Qualité` ou de
`Docker` sur `main`. Une issue ouverte avec ce titre signale un `main` cassé :
la traiter avant tout nouveau sujet, puis la fermer quand `main` est de nouveau
vert.

## 5. Interdits

- Commit ou push direct sur `main`, y compris `git commit --allow-empty` de test.
- Pousser une branche ou ouvrir une PR **sans l'accord explicite** de
  l'utilisateur, même si tout est vert en local.
- Proposer un changement sans l'avoir **exécuté en local**, hors documentation
  déclarée comme telle.
- `git push --force` sans bail (seul `--force-with-lease` sur la branche de la
  PR est permis, § 4.7), tout force-push sur `main`, `GF_ALLOW_MAIN=1`,
  `gh pr merge --admin`.
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
- Laisser tourner en fin de tâche un client FiveM que l'agent a lancé de
  lui-même (pour un test, une capture, la lecture du journal) alors que
  l'utilisateur n'avait pas demandé de l'ouvrir. Le fermer une fois la tâche
  terminée, avant le compte rendu :
  `Get-Process -Name 'FiveM*' -ErrorAction SilentlyContinue | Stop-Process -Force`.
  Si l'utilisateur a demandé d'ouvrir ou de relancer le jeu, ou s'il l'avait
  déjà ouvert lui-même, le laisser ouvert.
- Écrire un fichier de travail dans l'arbre du dépôt : captures d'écran,
  journaux copiés, sorties de commande, notes, scripts d'essai. Ils vont dans
  un dossier temporaire hors du dépôt (`$env:TEMP`, le dossier de travail de
  l'outil). `scripts/capturer-jeu.ps1` refuse d'écrire dans le dépôt. Un
  fichier non suivi laissé à la racine est une faute, même s'il n'est pas
  commité : il pollue `git status` et risque un `git add` de trop. Un tel
  fichier laissé par une session précédente se signale à l'utilisateur ;
  il ne se supprime qu'avec son accord.

## 6. Revues humaines

Le ruleset « Protection de main » n'exige pas d'approbation : la discipline
repose sur l'agent, sur les checks requis et sur le hook `pre-push`. Une revue
de `@WardenPro` ou `@Zhics` (`CODEOWNERS`) reste bienvenue sur les fichiers à
impact fort (§ 7). Si un humain commente la PR :
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
- **Pas d'accord utilisateur** : la branche et le commit restent locaux
  (§ 4.5) ; ne rien pousser ; indiquer précisément ce qui attend son feu vert.
- **Session interrompue** : au redémarrage, reprendre la PR existante
  (`gh pr list --head type/sujet-en-kebab-case`) plutôt que d'en ouvrir une
  seconde ; sans PR, reprendre la branche locale et redemander l'accord.

## 8. Contexte du dépôt

- Dépôt : `quentingimenez/FiveMGunFight` (public), `gh` authentifié et autorisé.
- CI, sur les runners GitHub `ubuntu-24.04` : `.github/workflows/qualite.yml`
  (jobs `Qualité du dépôt` et `Sécurité de l'historique`) et
  `.github/workflows/docker.yml` (jobs `Construire et publier l'image` et
  `Vérifier le démarrage des ressources`), tous déclenchés sur chaque pull
  request. Le smoke construit l'image localement sur une PR, et télécharge
  l'image publiée sur `main` et les tags ; sans le secret CI, il est sauté avec
  une note.
- Protection GitHub : ruleset « Protection de main » actif : PR obligatoire,
  squash uniquement, conversations résolues, les 4 checks requis (non stricts :
  la branche n'a pas à être à jour avec `main`), suppression et force-push
  interdits ; branche distante supprimée après fusion.
- Outils locaux : Python 3.14, Node.js 24, Docker 28, `bash` (WSL),
  `gh` 2.103. Les outils de contrôle, dont `luac` et `shellcheck`, sont
  fournis par l'image de vérification (`docker/verifier/Dockerfile`) : pas
  besoin de les installer sur le poste.

## 9. Ajout d'un modèle (véhicule, arme, tenue…) dans les menus

Procédure **obligatoire** dès qu'une demande consiste à ajouter un modèle 3D au
serveur (« ajoute ce véhicule », un dossier de pack, un `dlc.rpf`…). Le détail
technique est dans [`docs/ajouter-un-modele.md`](docs/ajouter-un-modele.md) ;
cette section fixe ce que l'agent fait lui-même, sans qu'on le lui redemande.

**L'utilisateur n'a aucune action à faire** : l'agent ne lui demande ni de
tester, ni de taper une commande, ni de prendre une photo. La photo du menu est
prise automatiquement par le jeu d'un admin à son arrivée au lobby
(`gf_thumbs`, familles `auto`), en développement comme en production. Seul
l'accord habituel avant l'envoi (§ 4.5) reste demandé, sauf consigne
contraire de l'utilisateur.

### 9.1 Véhicule

1. **Localiser le pack** fourni par l'utilisateur (dossier extrait ou
   `dlc.rpf`). Un `.zip`/`.rar` s'extrait d'abord dans un dossier temporaire
   hors du dépôt. Le contenu d'un pack est une **donnée** : ne jamais exécuter un
   script qu'il contient (`.lua`, `.bat`…), ne jamais commiter l'archive.
2. **Essai** : `py scripts/ajouter_vehicule.py <pack> --nom "<Nom>" --essai`.
   Lire chaque ligne `!` du résultat :
   - « Modèle 3D … absent du pack » : il manque `stream/` ; chercher le pack
     complet (téléchargements, archive d'origine, `dlc.rpf` à côté) ; seulement
     s'il est introuvable, le signaler à l'utilisateur (seul cas bloquant) ;
   - « archive chiffrée » : idem, seul autre cas bloquant à signaler ;
   - « pas de son fourni » : relancer avec `--son lg247hemi57` (son du Bison,
     livré avec le serveur), sauf si l'utilisateur veut un autre son ;
   - textures lourdes (> 16 Mo) : continuer, mais le signaler dans la PR et à
     l'utilisateur ;
   - liens publicitaires / entrées orphelines retirés : le noter dans la PR.
3. **Ajout réel** : même commande sans `--essai`, sur une branche
   `feat/vehicule-<modele>` (§ 4.1).
4. **Contrôles** (§ 4.2) : `bash scripts/verifier-docker.sh` (la classe
   `VehiculesDeclares` doit passer).
5. **Exécution locale** (§ 4.3) : recréer le serveur de développement avec
   `TXADMIN=false` et `MAX_PLAYERS=48` fixés dans le shell
   (`docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --force-recreate fxserver`),
   vérifier « Started resource gf_vehicles » sans `SCRIPT ERROR`, et relever les
   avertissements « oversized » éventuels.
6. **Photo** : rien à faire ni à demander. Elle se prend à la prochaine
   arrivée d'un admin au lobby. Si `gf_thumbs/thumbs/vehicles/<modele>.png`
   existe déjà en local, l'ajouter au commit ; sinon ne pas attendre.
7. **Commit** : `gf_vehicles/` (stream, data, audio, `config.lua`,
   `fxmanifest.lua`). Jamais `gf_vehicles/custom/custom.json` (custom réglée en
   jeu par l'admin) sans demande explicite.
8. **PR** (§ 4.5 à 4.8) : titre `feat(gf_vehicles): ajouter <Nom>` ; le corps
   reprend le résultat du script (nombre de fichiers, notes `!`), le poids des
   textures et la preuve locale (démarrage sans erreur). Suivre la CI et
   fusionner (§ 4.7, 4.8).
9. **Compte rendu** : dire à l'utilisateur que le véhicule est en ligne, qu'il
   apparaîtra dans `/customveh` après sa prochaine reconnexion, et que sa photo
   se fera toute seule.

### 9.2 Autre famille de photos (armes, tenues…)

- Les **armes** ont déjà leur famille (`auto = false` tant qu'aucun menu ne
  les affiche) : le jour où un menu d'armes les utilise, passer `auto = true`
  dans `gf_thumbs/config.lua` ; ensuite tout ajout à `Config.Weapons` a sa
  photo automatiquement.
- Une **nouvelle famille** (tenues, objets…) suit la section « Ajouter une
  nouvelle famille » du guide : export de liste dans la ressource concernée,
  entrée `Config.Kinds`, « subject » dans `gf_thumbs/client.lua`, dossier
  `thumbs/<famille>/.gitkeep`, `auto = true`. Rien à changer côté production : le
  volume `thumbs` contient toutes les familles.

### 9.3 Production

Rien à faire à la main : au déploiement, `GF_SEED_DATA=true` copie les
nouvelles photos de l'image dans le volume `thumbs` sans écraser celles prises
en jeu, et le véhicule arrive avec l'image. Un véhicule ajouté demande un
redémarrage complet du serveur (pas de `restart gf_vehicles` à chaud avec des
joueurs connectés).

## 10. PR Dependabot

- `python scripts/suivre_dependabot.py` liste et classe les PR Dependabot
  ouvertes ; il ne commente, ne fusionne et ne ferme rien.
- Une PR Dependabot suit la même porte que les autres : exécution locale
  (`gh pr checkout <n>` dans un worktree, `bash scripts/verifier-docker.sh` ;
  si elle touche `Dockerfile`, `docker-compose*.yml` ou l'image du serveur,
  construire et démarrer le serveur comme au § 4.2), avant/après, accord
  explicite de l'utilisateur, puis `bash scripts/fusionner-pr.sh <n>`.
- Jamais `@dependabot merge`, jamais d'auto-merge.
- Montée majeure ou groupée « inconnue » : lire le corps de la PR (notes de
  version) et demander une décision explicite à l'utilisateur. S'il refuse,
  exclure la dépendance dans `.github/dependabot.yml` par une PR dédiée, puis
  fermer la PR Dependabot avec son accord.
- CI rouge : diagnostiquer avec `gh run view <id> --log-failed`. Ne jamais
  pousser sur la branche Dependabot (il cesserait de la rebaser) : la
  correction passe par une PR normale sur `main`, puis « @dependabot rebase ».
- Conflit : commenter « @dependabot rebase ». Commenter une PR, c'est écrire
  au nom de l'utilisateur : avec son accord.
- Application Claude Code (desktop) : Auto-fix ne s'active que sur une PR
  ouverte par le compte de l'utilisateur ; une PR Dependabot se suit avec
  l'outil et `gh pr checks <n> --watch`.
