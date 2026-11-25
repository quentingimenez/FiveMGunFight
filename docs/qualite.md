# Qualité et intégration continue

## Principe

Aucune pull request ne peut être fusionnée si une vérification échoue. La CI ne
se contente pas de « lancer des tests » : les deux workflows sont déclarés comme
**status checks requis** sur la branche `main` (voir
[`protection-branche.md`](protection-branche.md)).

## Ce qui tourne, et quand

| Workflow | Job affiché | Déclencheur | Durée typique |
|---|---|---|---|
| `.github/workflows/qualite.yml` | `Qualité du dépôt` | chaque pull request, chaque envoi sur `main` | 1 à 2 min |
| `.github/workflows/docker.yml` | `Construire et publier l'image` | chaque pull request, chaque envoi sur `main`, tags `v*` | 3 à 8 min |
| `.github/workflows/docker.yml` | `Vérifier le démarrage des ressources` | envoi sur `main` et tags (pas les PR) | jusqu'à 10 min |

Le job de démarrage réel (`smoke`) est volontairement hors des pull requests :
il télécharge l'image, démarre FXServer avec une vraie clé de licence et tourne
plusieurs minutes. Il protège `main` après fusion ; la pull request, elle, est
bloquée par les tests statiques et la construction d'image.

## Les vérifications statiques (`scripts/verifier.sh`)

Le même script sert en local et en CI : une erreur ici est une pull request
rouge.

| Étape | Outil | Ce qu'elle attrape |
|---|---|---|
| Syntaxe Lua | `luac -p` | erreur de syntaxe, `end` manquant, chaîne non fermée — la ressource refuserait de démarrer |
| JSON valide | `python -m json` | virgule en trop dans `maps.json`, fichier tronqué |
| Syntaxe JavaScript | `node --check` | erreur dans `gf_ui/html/app.js` qui casse toute l'interface NUI |
| Scripts shell | `sh -n` / `bash -n` + `shellcheck -S error` | `entrypoint.sh` cassé : le conteneur ne démarre plus du tout |
| Compose | `docker compose config -q` | YAML invalide, référence de volume inexistante, variable mal écrite |

Un outil absent sur ta machine provoque un message « ignore », jamais un faux
succès silencieux. En CI, tous les outils sont installés : rien n'est ignoré.

## Les tests de cohérence (`tests/test_depot.py`)

Écrits avec `unittest` (bibliothèque standard, aucune dépendance à installer).

| Classe | Vérifie |
|---|---|
| `ManifestesFiveM` | chaque dossier de ressource a un `fxmanifest.lua`, avec `fx_version` et le jeu déclaré ; chaque fichier cité (scripts, `ui_page`, `files`) existe réellement |
| `ConfigurationServeur` | les cinq ressources `gf_*` sont démarrées dans `server.cfg` ; `sessionmanager`/`hardcap` n'y reviennent pas ; `.env.example` contient toutes les clés attendues et aucun secret ; `.gitignore` et `.dockerignore` protègent `.env`, `secrets.cfg` et le cache |
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

## Secret de la CI

`CFX_LICENSE_KEY` (Settings → Secrets and variables → Actions) permet au job
`smoke` de démarrer un vrai serveur. Sans ce secret, le job affiche une note
« test ignoré » et ne bloque rien ; les autres jobs, eux, restent bloquants.

```bash
gh secret set CFX_LICENSE_KEY
```

La clé de la CI ne sert qu'aux tests : le serveur de production utilise celle de
`.env`. Ne jamais réutiliser un même secret dans un fichier versionné.

## Consulter et relancer un run

```bash
gh run list                     # derniers runs
gh run view <id> --log-failed   # uniquement les étapes en échec
gh run rerun <id> --failed      # relancer les jobs échoués
gh run watch                    # suivre le run en cours
```

Une CI rouge se corrige par un commit sur la branche. On ne fusionne pas « en
attendant » de corriger : c'est précisément ce que la protection empêche.
