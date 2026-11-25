# Qualité et intégration continue

## Principe

Aucune pull request ne peut être fusionnée si une vérification échoue. La CI ne
se contente pas de « lancer des tests » : les trois checks sont déclarés comme
**status checks requis** sur la branche `main` (voir
[`protection-branche.md`](protection-branche.md)).

## Ce qui tourne, et quand

| Workflow | Job affiché | Déclencheur | Durée typique |
|---|---|---|---|
| `.github/workflows/qualite.yml` | `Qualité du dépôt` | chaque pull request, chaque envoi sur `main` | 1 à 2 min |
| `.github/workflows/docker.yml` | `Construire et publier l'image` | chaque pull request, chaque envoi sur `main`, tags `v*` | 3 à 8 min |
| `.github/workflows/docker.yml` | `Vérifier le démarrage des ressources` | chaque pull request, chaque envoi sur `main`, tags `v*` | 10 à 20 min |

Le job de démarrage réel (`smoke`) tourne désormais **aussi sur les pull
requests**, lorsque le secret y est disponible : il construit l'image
localement, démarre FXServer avec une vraie clé de licence et vérifie que les
ressources `gf_*` démarrent. Sur `main` et les tags, il télécharge l'image
publiée sur GHCR à la place. C'est le seul contrôle qui exécute réellement le
serveur ; il bloque donc la fusion comme les autres.

Le secret doit être un secret **de dépôt** pour être visible sur les pull
requests. Sans secret (PR d'un fork ou de Dependabot, secret non configuré), le
job affiche une note et saute le démarrage, sans échec.

Il est limité par une `concurrency` (`smoke-licence`, sans annulation) : la clé
de licence CI est partagée, deux smoke tests ne doivent pas tourner en même
temps.

## Les vérifications statiques (`scripts/verifier.sh`)

Le même script sert en local et en CI : une erreur ici est une pull request
rouge.

| Étape | Outil | Ce qu'elle attrape |
|---|---|---|
| Syntaxe Lua | `luac -p` | erreur de syntaxe, `end` manquant, chaîne non fermée — la ressource refuserait de démarrer |
| JSON valide | Python (`json.load`) | virgule en trop dans `maps.json`, fichier tronqué |
| Syntaxe JavaScript | `node --check` | erreur dans `gf_ui/html/app.js` qui casse toute l'interface NUI |
| Scripts shell | `sh -n` / `bash -n` + `shellcheck -S error` | `entrypoint.sh` cassé : le conteneur ne démarre plus du tout |
| Compose | `docker compose -f docker-compose.yml -f docker-compose.dev.yml config -q` et idem avec `docker-compose.prod.yml` | YAML invalide, référence de volume inexistante, variable mal écrite, surcouche qui ne se combine plus au socle |

Un outil absent sur ta machine provoque un message « ignore », jamais un faux
succès silencieux. En CI, tous les outils sont installés : rien n'est ignoré.

## Les tests de cohérence (`tests/test_depot.py`)

Écrits avec `unittest` (bibliothèque standard, aucune dépendance à installer).

| Classe | Vérifie |
|---|---|
| `ManifestesFiveM` | chaque dossier de ressource a un `fxmanifest.lua`, avec `fx_version` et le jeu déclaré ; chaque fichier cité (scripts, `ui_page`, `files`) existe réellement |
| `ConfigurationServeur` | les cinq ressources `gf_*` sont démarrées dans `server.cfg` ; `sessionmanager`/`hardcap` n'y reviennent pas ; `.env.example` contient toutes les clés attendues et aucun secret ; `.gitignore` et `.dockerignore` protègent `.env`, `secrets.cfg` et le cache |
| `InfraDocker` | txAdmin limité à 127.0.0.1, healthcheck FXServer, plafonds mémoire des deux services, nom de projet Compose, `secrets.cfg` en 600, `FROM` Debian épinglé par digest, image MariaDB épinglée par digest, `GF_SEED_MAPS`/`MAPS_DEFAUT` dans l'entrypoint |
| `EnvironnementsCompose` | les trois fichiers Compose existent ; le dev construit l'image et monte `./server-data` ; la prod utilise `${IMAGE_REF}`, le volume `maps` et les volumes `gunfight-prod-*` distincts ; le socle ne déclare ni `build` ni `image` pour `fxserver` |
| `ChaineCI` | toutes les actions sont épinglées par SHA ; Dependabot suit les actions et les images et ignore MariaDB ≥ 11.5 ; le check de démarrage figure dans la protection de branche ; `docker.yml` déclenche le smoke sur les pull requests |
| `MapsEnJeu` | structure de `maps.json` : noms, rayons positifs, polygones d'au moins trois sommets, points de départ présents, identifiants uniques |
| `Documentation` | les documents (`README`, `CONTRIBUTING`, `SECURITY`, `docs/`, modèle de PR, `CODEOWNERS`) existent et ne sont pas vides ; le README cite chaque ressource ; chaque workflow déclare `on:` et `jobs:` |
| `DepotGit` | aucun fichier secret n'est suivi par Git (`git ls-files`) |

Ces tests n'ont pas de dépendance réseau ni de conteneur : ils tournent en
quelques secondes et peuvent être lancés avant chaque commit.

## Lancer les contrôles en local

```bash
bash scripts/verifier.sh
python -m unittest discover -s tests -v
```

Prérequis pour ne rien ignorer : Lua 5.4 (`luac`), Node.js, Python 3, Docker
Desktop démarré, `shellcheck` (facultatif).

Sur Windows, `scripts/verifier.sh` fonctionne dans Git Bash ou WSL. Sans Lua
installé, l'étape de syntaxe Lua est ignorée localement — la CI la vérifie.

## Ajouter un test

Règle : **un test doit échouer sur un vrai défaut et passer sur `main`**.

- Défaut statique (syntaxe, format, outil) → ajouter une étape à
  `scripts/verifier.sh`, avec un message d'échec qui dit quoi corriger.
- Invariant du dépôt (manifeste, config, doc, format de données) → ajouter une
  méthode de test dans la classe correspondante de `tests/test_depot.py`.
- Comportement du serveur en jeu → à terme un test d'intégration dédié ; en
  attendant, le test de démarrage Docker est la seule couverture automatique.

Toute nouvelle vérification doit être mentionnée dans ce document et dans
[`../CONTRIBUTING.md`](../CONTRIBUTING.md).

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
deux écosystèmes :

| Écosystème | Portée | Limite |
|---|---|---|
| `github-actions` | toutes les actions des workflows, groupées en une PR | 5 PR ouvertes |
| `docker` | images du Dockerfile et des fichiers Compose, groupées en une PR | 5 PR ouvertes |

MariaDB est exclue à partir de **11.5** : le socle reste sur la branche LTS
11.4, et un changement de version se décide et se teste à part. Une PR Dependabot
passe par la même CI que les autres ; elle ne se fusionne que verte.

## Secret de la CI

`CFX_LICENSE_KEY` (Settings → Secrets and variables → Actions) permet au job
`smoke` de démarrer un vrai serveur. C'est une clé **dédiée aux tests**, pas
celle de la production : elle peut être révoquée ou remplacée sans toucher au
serveur en ligne.

```bash
gh secret set CFX_LICENSE_KEY
```

Sans ce secret (PR d'un fork, PR de Dependabot, secret non configuré), le job
affiche une note, saute les étapes de démarrage et reste **vert** : la fusion
n'est donc pas bloquée par une limite externe, mais le démarrage n'a pas été
vérifié. Les deux autres checks restent bloquants. La clé de production, elle,
reste dans le `.env` du VPS et n'est jamais versionnée.

## Consulter et relancer un run

```bash
gh run list                     # derniers runs
gh run view <id> --log-failed   # uniquement les étapes en échec
gh run rerun <id> --failed      # relancer les jobs échoués
gh run watch                    # suivre le run en cours
```

Une CI rouge se corrige par un commit sur la branche. On ne fusionne pas « en
attendant » de corriger : c'est précisément ce que la protection empêche.
