# Contribuer au projet

Merci de contribuer. Ce dépôt est un serveur FiveM en production : chaque
changement peut casser une partie en cours. Les règles ci-dessous existent pour
qu'une erreur soit détectée **avant** la fusion, pas pendant un match.

## 1. Règle principale

- La branche `main` est **protégée** : personne ne pousse dessus directement,
  tout passe par une **pull request** relue et validée par la CI.
- Une branche par sujet, courte durée de vie, supprimée après fusion.
- La CI doit être **verte** avant la fusion : les vérifications sont bloquantes.

## 2. Avant de commencer

Lis au minimum :

- [`docs/architecture.md`](docs/architecture.md) — comment le serveur est
  construit et ce que fait chaque ressource ;
- [`docs/qualite.md`](docs/qualite.md) — ce que la CI vérifie et comment la
  lancer en local ;
- [`docs/protection-branche.md`](docs/protection-branche.md) — ce qui est
  interdit et ce que la protection couvre vraiment.

Récupère la dernière version de `main`, puis crée ta branche :

```bash
git switch main
git pull
git switch -c feat/vote-de-map
```

## 3. Nommer sa branche

Format : `type/sujet-en-kebab-case`, avec éventuellement le numéro d'issue.

| Type | Usage | Exemple |
|---|---|---|
| `feat` | nouvelle fonctionnalité | `feat/vote-de-map` |
| `fix` | correction de bug | `fix/redzone-respawn-hors-zone` |
| `docs` | documentation seulement | `docs/processus-pr` |
| `ci` | pipelines et outillage | `ci/tests-lua` |
| `chore` | maintenance, dépendances | `chore/maj-fxserver` |

## 4. Rédiger les commits

```text
type(scope): sujet à l'impératif, 72 caractères max

Pourquoi ce changement (le contexte, le bug, la contrainte).
Ce que ça change pour les joueurs ou pour les autres développeurs.

Réf : #12
```

- `type` : `feat`, `fix`, `docs`, `ci`, `chore`, `refactor`, `perf`, `test`.
- `scope` : la ressource concernée (`gf_redzone`, `gf_maps`, `docker`, …).
- Le **corps** explique le pourquoi ; le code explique le comment.
- Un commit = un changement cohérent. Les messages servent à relire l'historique
  des parties cassées, ils doivent rester utiles dans six mois.

## 5. Tester en local

Avant d'ouvrir la pull request, exécute les mêmes contrôles que la CI :

```bash
bash scripts/verifier.sh                      # Lua, JSON, JS, shell, compose
python -m unittest discover -s tests -v      # cohérence du dépôt
```

Si tu touches aux scripts Lua, au `server.cfg` ou au `Dockerfile`, teste
réellement le serveur :

```bash
docker compose build
docker compose up -d
docker compose logs -f fxserver     # attendre « Started resource gf_… »
```

Puis en jeu : `/attack` ou `/redzone`, et une manche de test (`/startround` en
admin). Vérifie la console pour les erreurs rouges.

## 6. Ouvrir la pull request

1. Pousse la branche :

   ```bash
   git push -u origin feat/vote-de-map
   ```

2. Ouvre la pull request vers `main` et remplis le modèle proposé :
   **résumé**, **pourquoi**, **comment tu as testé**, cases de la checklist.
3. Reste disponible pendant la revue : réponds aux commentaires par des
   commits supplémentaires sur la même branche (pas de réécriture d'historique
   après une première revue).

Une pull request doit être **petite** : une fonctionnalité ou une correction.
Au-delà de ~400 lignes modifiées, découpe.

## 7. Revue de code

- **1 approbation** est requise (`CODEOWNERS` : `@WardenPro` ou `@Zhics`).
- L'auteur ne peut pas approuver sa propre pull request.
- Le relecteur vérifie :
  - la logique côté **serveur** (le client ne décide jamais du score ni des tirs
    touchés) ;
  - l'absence de secret, de clé de licence ou de mot de passe ;
  - la cohérence avec les `config.lua` (pas de valeur codée en dur) ;
  - la mise à jour de la documentation si le comportement change.
- Un commentaire bloquant doit être résolu avant la fusion (la résolution des
  conversations est exigée par la protection de branche).

## 8. Fusionner

- La fusion se fait **en squash** : l'historique de `main` reste une suite de
  changements complets et lisibles.
- La branche est supprimée automatiquement après fusion.
- Ne jamais forcer l'envoi (`git push --force`) sur `main`.
- Si `main` casse malgré tout : on **annule** par une pull request de revert
  (`git revert -m 1 <sha>`), puis on analyse tranquillement. On ne « répare »
  pas `main` par un commit direct.

## 9. CI : ce qui est bloquant

| Vérification | Workflow | Bloquante |
|---|---|---|
| Syntaxe Lua, JSON, JS, shell, compose | `.github/workflows/qualite.yml` | oui |
| Cohérence des manifestes, maps, config, docs | `.github/workflows/qualite.yml` | oui |
| Construction de l'image Docker | `.github/workflows/docker.yml` | oui |
| Démarrage réel du serveur (smoke test) | `.github/workflows/docker.yml` | sur `main` (nécessite le secret `CFX_LICENSE_KEY`) |

Une CI rouge se corrige par un nouveau commit sur la branche, jamais par un
contournement. Si tu penses qu'un test est faux, ouvre une pull request qui
corrige le test **et** explique pourquoi.

## 10. Sécurité

- Ne jamais versionner `.env` ni `server-data/secrets.cfg` (déjà ignorés).
- Ne jamais coller une clé de licence dans une issue, une capture ou un commit.
- En cas de fuite, voir [`SECURITY.md`](SECURITY.md) : la clé doit être
  révoquée immédiatement sur <https://portal.cfx.re>.
