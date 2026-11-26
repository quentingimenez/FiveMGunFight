# Qualité et intégration continue

## Principe

Aucune pull request ne peut être fusionnée si une vérification échoue. La CI ne
se contente pas de « lancer des tests » : les checks requis sont déclarés comme
**status checks requis** sur la branche `main` (voir
[`protection-branche.md`](protection-branche.md)).

## Ce qui tourne, et quand

| Workflow | Job affiché | Déclencheur | Durée typique |
|---|---|---|---|
| `.github/workflows/qualite.yml` | `Qualité du dépôt` | chaque pull request, chaque envoi sur `main` | 3 à 4 min (image de vérification construite à chaque run) |
| `.github/workflows/qualite.yml` | `Sécurité de l'historique` | chaque pull request, chaque envoi sur `main` | moins d'1 min |
| `.github/workflows/docker.yml` | `Construire et publier l'image` | chaque pull request, `main`, tags `v*`, et chaque lundi à 03:17 UTC | 3 à 8 min |
| `.github/workflows/docker.yml` | `Vérifier le démarrage des ressources` | chaque pull request, `main`, tags `v*`, et chaque lundi à 03:17 UTC | 10 à 25 min |
| `.github/workflows/alerte-main.yml` | `Signaler une CI rouge sur main` | échec de `Qualité` ou de `Docker` sur `main` ; ouvre ou complète l'issue « CI rouge sur main » | quelques secondes |

Le job `Sécurité de l'historique` est un contrôle supplémentaire : il n'est pas
encore listé dans les `contexts` requis de
[`.github/branch-protection.json`](../.github/branch-protection.json). Son échec
est visible, mais ne bloque la fusion qu'une fois la protection mise à jour avec
les droits d'administration.

Le job de démarrage réel (`smoke`) construit désormais l'image **sur chaque
pull request, même sans secret**. Il exécute d'abord un test statique qui ne
demande aucune licence : l'image doit refuser de démarrer avec
`LICENSE_KEY=change_moi`, sortir en code 1 et citer `LICENSE_KEY` dans son
message. C'est le contrôle bloquant qui fonctionne partout. Le démarrage complet
n'a lieu que si le secret `CFX_LICENSE_KEY` est disponible : il lance FXServer
avec une vraie clé et vérifie que les ressources `gf_*` démarrent. Sur `main` et
les tags, l'image publiée sur GHCR est tirée au lieu d'être reconstruite.

Sans secret (PR d'un fork ou de Dependabot, secret non configuré), la
construction et le test statique continuent ; seul le démarrage complet est
sauté, avec une note, sans échec. Les journaux `smoke.log` et
`smoke-static.log` sont publiés en artefact pendant 7 jours, y compris en cas
d'échec, après vérification qu'ils ne contiennent pas la clé de licence.

### Smoke tests de plusieurs PR : pas de file commune

Tous les jobs tournent sur les runners hébergés par GitHub (`ubuntu-24.04`),
gratuits et illimités pour un dépôt public, avec une machine neuve par job.

Le job `smoke` n'a plus de groupe `concurrency` partagé. Un tel groupe
(l'ancien `smoke-licence`) ne garde qu'**un seul** run en attente et annule les
autres (« Canceling since a higher priority waiting request for smoke-licence
exists ») : quand plusieurs PR étaient mises à jour ensemble, le check requis
`Vérifier le démarrage des ressources` était annulé sur certaines, et un envoi
sur `main` pouvait perdre son smoke au profit d'une PR. Le groupe est
désormais `smoke-${{ github.ref }}` : seul un nouvel envoi sur la même PR
annule son smoke obsolète, comme pour le job `image`
(`image-${{ github.ref }}`).

Contrepartie : les smoke de deux références différentes peuvent démarrer en
même temps avec la même clé de licence CI, chacun sur sa machine. Cfx.re ne
l'empêche pas techniquement mais le déconseille ; le smoke ne dure que
quelques minutes et ne reçoit aucun joueur. Si cela pose problème, la parade
est une deuxième clé CI (un compte a droit à trois clés), pas un groupe de
concurrence partagé.

## Les vérifications (`scripts/verifier.sh`, dans l'image)

La même commande sert en local et en CI : une erreur ici est une pull request
rouge. `bash scripts/verifier-docker.sh` construit l'image
[`docker/verifier/Dockerfile`](../docker/verifier/Dockerfile), puis y lance
[`scripts/verifier.sh`](../scripts/verifier.sh). L'image est la référence des
versions : Ubuntu 24.04 épinglé par digest, outils épinglés par version et
SHA256 (Lua 5.4, luacheck, shellcheck, Node.js 20, Python 3, actionlint,
hadolint, gitleaks, ruff, Docker CLI et Compose).

| Étape | Outil | Ce qu'elle attrape |
|---|---|---|
| Syntaxe Lua | `luac -p` | erreur de syntaxe, `end` manquant, chaîne non fermée — la ressource refuserait de démarrer |
| Lua | `luacheck` (`.luacheckrc`) | affectation d'une globale inconnue, variable inutilisée, code mort dans les ressources `gf_*`. W113 est ignoré pour l'instant (natives FiveM), comme documenté dans la configuration |
| JSON valide | Python (`json.load`) | virgule en trop dans `maps.json`, fichier tronqué |
| Syntaxe JavaScript | `node --check` | erreur dans `gf_ui/html/app.js` ou `gf_lobby/html/js/*.js` qui casse toute l'interface NUI |
| Scripts shell | `sh -n` / `bash -n` + `shellcheck -S error` | `entrypoint.sh` cassé : le conteneur ne démarre plus du tout |
| Workflows | `actionlint` | expression `${{ }}` invalide, dépendance de job incohérente, `runs-on` inconnu |
| Dockerfiles | `hadolint` (`.hadolint.yaml`) | mauvaise pratique Docker, instruction qui casse le build ; vérifie le `Dockerfile` racine et `docker/verifier/Dockerfile`. Les ignores DL3008/DL4006 sont justifiés dans la configuration |
| Secrets | `gitleaks dir` (`.gitleaks.toml`) sur une copie des fichiers vus par Git (`scripts/arbre-suivi.sh`) | clé ou jeton accidentellement présent dans un fichier suivi ou non ignoré. `.env`, `secrets/` et les autres fichiers ignorés ne sont jamais lus : ils sont protégés par `.gitignore` et par la classe `DepotGit` |
| Style Python | `ruff check --extend-ignore EXE002 tests/` | import inutilisé, nom non défini, erreur évidente dans les tests. EXE002 est ignoré : un dossier Windows monté sous Docker Desktop est vu en 0777 |
| Tests du dépôt | `python -m unittest discover -s tests -v` | manifestes, configuration, maps, documentation, Compose, chaîne CI ; `GF_OUTILS_OBLIGATOIRES=1` fait échouer un test sauté faute d'outil |
| Compose | `docker compose -f docker-compose.yml -f docker-compose.dev.yml config -q` et idem avec `docker-compose.prod.yml` | YAML invalide, référence de volume inexistante, variable mal écrite, surcouche qui ne se combine plus au socle |

Un outil absent fait **échouer** le script (« outil absent : X ») : plus de
faux succès. Lancé hors de l'image sur un poste incomplet,
`scripts/verifier.sh` échoue ; c'est voulu, la commande de référence est
`bash scripts/verifier-docker.sh`. L'historique Git complet est en plus scanné
par le job `Sécurité de l'historique` (`gitleaks git --log-opts=--all`),
séparément pour que `fetch-depth: 0` ne ralentisse pas le job principal.

Les versions et empreintes des outils sont la référence dans
[`docker/verifier/Dockerfile`](../docker/verifier/Dockerfile), sauf gitleaks
qui reste aussi dans le job `Sécurité de l'historique` ; un test vérifie que
les deux versions sont identiques. Dependabot suit l'image de base
(`directory: /docker/verifier`).

## Les tests de cohérence (`tests/test_depot.py`)

Écrits avec `unittest` (bibliothèque standard, aucune dépendance à installer).

| Classe | Vérifie |
|---|---|
| `ManifestesFiveM` | chaque dossier de ressource a un `fxmanifest.lua`, avec `fx_version` et le jeu déclaré ; chaque fichier cité (scripts, `ui_page`, `files`) existe réellement |
| `ConfigurationServeur` | les six ressources `gf_*` sont démarrées dans `server.cfg` ; `sessionmanager`/`hardcap` n'y reviennent pas ; `.env.example` contient toutes les clés attendues et aucun secret ; `.gitignore` et `.dockerignore` protègent `.env`, `secrets.cfg`, le cache et `gf_lobby/data/characters.json` |
| `InfraDocker` | txAdmin limité à 127.0.0.1, healthcheck FXServer, plafonds mémoire des deux services, nom de projet Compose, `secrets.cfg` en 600, `FROM` Debian épinglé par digest, image MariaDB épinglée par digest, `GF_SEED_MAPS`/`MAPS_DEFAUT` dans l'entrypoint |
| `EnvironnementsCompose` | les trois fichiers Compose existent ; le dev construit l'image et monte `./server-data` ; la prod utilise `${IMAGE_REF}`, le volume `maps` et les volumes `gunfight-prod-*` distincts ; le socle ne déclare ni `build` ni `image` pour `fxserver` |
| `ChaineCI` | toutes les actions sont épinglées par SHA ; chaque job a un timeout, des permissions explicites et tourne sur les runners GitHub `ubuntu-24.04` ; les nouveaux contrôles (luacheck, actionlint, hadolint, gitleaks, ruff) sont présents ; `.fxserver-version` est renseigné avec une URL et un SHA256 valides ; Dependabot suit les actions, les images et `docker-compose` et ignore MariaDB ≥ 11.5 ; `docker.yml` a la concurrence de l'image, le smoke avec un groupe de concurrence par référence, l'artefact de journaux et le test statique sans licence ; le nom du check de démarrage et sa présence dans la protection de branche sont inchangés |
| `MapsEnJeu` | structure de `maps.json` : noms, rayons positifs, polygones d'au moins trois sommets, points de départ présents, identifiants uniques |
| `Documentation` | les documents (`README`, `CONTRIBUTING`, `SECURITY`, `docs/`, dont `docs/lobby.md`, modèle de PR, `CODEOWNERS`) existent et ne sont pas vides ; le README cite chaque ressource ; chaque workflow déclare `on:` et `jobs:` |
| `DepotGit` | aucun fichier secret n'est suivi par Git (`git ls-files`), y compris `gf_lobby/data/characters.json` |

Ces tests n'ont pas de dépendance réseau ni de conteneur : ils tournent en
quelques secondes et peuvent être lancés avant chaque commit.

## Lancer les contrôles en local

Tout lancer d'un coup, comme la CI :

```bash
bash scripts/verifier-docker.sh
```

Prérequis : Docker Desktop démarré. Sous Windows, `bash` est celui de WSL ;
Git Bash marche aussi. La commande construit l'image au premier lancement
(quelques minutes), puis exécute `scripts/verifier.sh` sur le dépôt monté en
`/depot` : contrôles statiques **et** tests Python. Une image déjà construite
peut être réutilisée avec `GF_VERIFIER_IMAGE=<image>`.

Pour isoler un échec, chaque contrôle peut être lancé seul dans l'image de
vérification (sinon, il faut les mêmes outils sur le poste, aux mêmes
versions) :

```bash
luacheck server-data/resources
actionlint
hadolint Dockerfile docker/verifier/Dockerfile
dossier="$(mktemp -d)"
bash scripts/arbre-suivi.sh "$dossier" &&
  gitleaks dir --no-banner --redact --config .gitleaks.toml "$dossier"
rm -rf -- "$dossier"
ruff check --extend-ignore EXE002 tests/
docker compose -f docker-compose.yml -f docker-compose.dev.yml config -q
IMAGE_REF=exemple.invalid/gunfight:test \
  docker compose -f docker-compose.yml -f docker-compose.prod.yml config -q
```

Pour le test statique du smoke, construire l'image avec les valeurs du fichier
épinglé, puis vérifier le refus :

```bash
FX_URL="$(sed -n 's/^FX_URL=//p' .fxserver-version)"
FX_SHA256="$(sed -n 's/^FX_SHA256=//p' .fxserver-version)"
docker build --tag gunfight:local \
  --build-arg "BUILD_SHA=$(git rev-parse --short HEAD)" \
  --build-arg "FX_URL=$FX_URL" --build-arg "FX_SHA256=$FX_SHA256" .
docker run --rm -e LICENSE_KEY=change_moi gunfight:local
echo $?   # doit afficher 1 et citer LICENSE_KEY
```

Sans `BUILD_SHA`, l'image porte la version `dev` et le badge du lobby l'affiche
telle quelle : c'est le repli attendu hors CI, pas un défaut.

Variables utiles :

| Variable | Effet |
|---|---|
| `GF_SANS_TESTS=1` | saute l'étape `unittest` (utilisée par les tests qui lancent `scripts/verifier.sh`) |
| `GF_OUTILS_MASQUES=a,b` | fait croire que ces outils manquent (crochet de test) |
| `GF_VERIFIER_IMAGE=<image>` | utilise une image déjà construite au lieu de la construire |
| `GF_OUTILS_OBLIGATOIRES=1` | transforme en échec un test Python qui serait sauté faute de lua, node ou bash (posé par `scripts/verifier.sh`) |

## Ajouter un test

Règle : **un test doit échouer sur un vrai défaut et passer sur `main`**.

- Défaut statique (syntaxe, format, outil) → ajouter une étape à
  `scripts/verifier.sh`, avec un message d'échec qui dit quoi corriger. Une
  étape qui exige un outil passe par `trouver` et `absent`, et l'outil est
  ajouté à [`docker/verifier/Dockerfile`](../docker/verifier/Dockerfile).
- Invariant du dépôt (manifeste, config, doc, format de données) → ajouter une
  méthode de test dans la classe correspondante de `tests/test_depot.py`.
- Comportement du serveur en jeu → à terme un test d'intégration dédié ; en
  attendant, le test de démarrage Docker est la seule couverture automatique.

Toute nouvelle vérification doit être mentionnée dans ce document.
[`../CONTRIBUTING.md`](../CONTRIBUTING.md) renvoie à la commande locale
(`scripts/verifier-docker.sh`, qui lance `scripts/verifier.sh` dans l'image).

## Dépendances : épinglage et Dependabot

Règle du dépôt : **toute action GitHub est épinglée par un SHA de commit de
40 caractères hexadécimaux, toute image Docker par un digest `sha256:`**. Un tag
(`@v5`, `:11.4`) est déplaçable : il ne garantit pas que la CI ou la production
exécutera le même code demain.

- Les actions des workflows portent un commentaire lisible (`# v5`) à côté du
  SHA, pour savoir quelle version est épinglée.
- Le `FROM` du Dockerfile et l'image MariaDB du socle sont épinglés par digest.
- Les montées de version arrivent par des pull requests, jamais par un tag qui
  glisse silencieusement.

`.github/dependabot.yml` vérifie chaque semaine (lundi 06:00, Europe/Paris) les
trois écosystèmes :

| Écosystème | Portée | Limite |
|---|---|---|
| `github-actions` | toutes les actions des workflows, groupées en une PR | 5 PR ouvertes |
| `docker` | images du Dockerfile et des fichiers Compose, groupées en une PR | 5 PR ouvertes |
| `docker-compose` | services des fichiers Compose (images et versions), groupés en une PR | 5 PR ouvertes |

MariaDB est exclue à partir de **11.5** dans les blocs `docker` et
`docker-compose` : le socle reste sur la branche LTS 11.4, et un changement de
version se décide et se teste à part. Une PR Dependabot passe par la même CI que
les autres ; elle ne se fusionne que verte.

La montée d'Ubuntu de l'image de vérification est exclue : elle reste sur
24.04, le même système que le runner `ubuntu-24.04`, et seul son digest
continue d'être mis à jour. Le suivi d'une PR Dependabot (exécution locale,
accord de l'utilisateur, fusion) est décrit dans
[`../AGENTS.md`](../AGENTS.md) § 10 ; `python scripts/suivre_dependabot.py`
liste et classe les PR ouvertes sans rien modifier.

## Épingler FXServer (`.fxserver-version`)

La CI ne dépend plus d'un artefact « recommended » qui change sous elle : la
version, l'URL et l'empreinte sont dans `.fxserver-version`, à la racine.

```text
FX_VERSION=38435
FX_URL=https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/38435-.../fx.tar.xz
FX_SHA256=1b58507f68086ca3578c187f31e7b4a2259b7192d76b0c80cfc1af682fdf2be9
```

Les jobs `image` et `smoke` lisent ce fichier, refusent une URL vide, un SHA256
qui n'a pas 64 caractères hexadécimaux ou une version non numérique, puis
passent `FX_URL` et `FX_SHA256` au build. Le Dockerfile vérifie l'empreinte avec
`sha256sum -c` : une archive altérée fait échouer la construction.

Procédure de mise à jour :

1. relever la version recommandée et l'URL exacte de l'artefact sur
   <https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/> ;
2. télécharger l'archive dans un dossier temporaire, **jamais dans le dépôt** :

   ```powershell
   curl.exe -fL -o "$env:TEMP\fx.tar.xz" "<URL>"
   (Get-FileHash -Algorithm SHA256 "$env:TEMP\fx.tar.xz").Hash.ToLower()
   (Get-Item "$env:TEMP\fx.tar.xz").Length
   ```

   Sous Linux : `sha256sum fx.tar.xz`. Vérifier aussi que l'archive s'ouvre
   (`tar -tJf fx.tar.xz`) et que sa taille est plausible (environ 71 Mo) ;
3. remplacer les trois valeurs dans `.fxserver-version`, ouvrir une PR et
   laisser la CI reconstruire l'image et relancer le smoke ;
4. supprimer l'archive temporaire. Aucun binaire FXServer n'est versionné.

## Chaîne d'approvisionnement de l'image

- **Trivy** scanne l'image construite sur chaque pull request
  (`severity: CRITICAL,HIGH`, `ignore-unfixed: true`, `exit-code: 1`). Une
  vulnérabilité critique corrigeable bloque donc la fusion.
- Le build publié (push sur `main`, tags, planification) produit une
  **attestation de provenance** (`provenance: mode=max`) et un **SBOM**
  (`sbom: true`), utiles pour vérifier ce qui est réellement publié.
- Sur une pull request, l'image est chargée localement (`load: true`) pour être
  scannée : l'exporteur `docker` de Buildx ne sait pas exporter de liste de
  manifestes avec des attestations dans ce mode. Provenance et SBOM sont donc
  désactivés sur PR, activés sur les publications.
- **Cosign n'est pas encore branché.** La signature keyless exige une identité
  OIDC et des droits d'écriture sur le registre, et ne peut pas être vérifiée
  localement dans cette configuration. C'est l'étape suivante : d'abord la CI
  verte et documentée, puis signature et vérification de l'image publiée.

## Secret de la CI

`CFX_LICENSE_KEY` (Settings → Secrets and variables → Actions) permet au job
`smoke` de démarrer un vrai serveur. C'est une clé **dédiée aux tests**, pas
celle de la production : elle peut être révoquée ou remplacée sans toucher au
serveur en ligne.

```bash
gh secret set CFX_LICENSE_KEY
```

Sans ce secret (PR d'un fork, PR de Dependabot, secret non configuré), le job
construit quand même l'image et exécute le test statique sans licence ; seul le
démarrage complet est sauté, avec une note, et le job reste **vert** si les
autres contrôles passent. La fusion n'est donc pas bloquée par une limite
externe, mais le démarrage réel n'a pas été vérifié. Les autres checks restent
bloquants. La clé de production, elle, reste dans le fichier
`secrets/license_key` du VPS (monté dans `/run/secrets/license_key`) et n'est
jamais versionnée.

Avant publication des journaux, le workflow cherche la valeur du secret dans
`smoke.log` et `smoke-static.log` ; s'il la trouve, l'artefact n'est pas publié
et le job échoue sans afficher la clé.

## Consulter et relancer un run

```bash
gh run list                     # derniers runs
gh run view <id> --log-failed   # uniquement les étapes en échec
gh run rerun <id> --failed      # relancer les jobs échoués
gh run watch                    # suivre le run en cours
```

Une CI rouge se corrige par un commit sur la branche. On ne fusionne pas « en
attendant » de corriger : c'est précisément ce que la protection empêche.
