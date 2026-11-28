# Orchestration des agents

Comment répartir le travail quand plusieurs agents (ou un agent et ses
sous-agents) interviennent sur une même demande. Les règles valent quel que
soit l'outil ; les configurations nommées en fin de document ne sont que
des exemples.

## Les rôles

| Rôle | Fait | Ne fait jamais |
|---|---|---|
| **Orchestrateur-vérificateur** | parle à l'utilisateur ; mène P0 à P3 (cadrage, fiche d'impact, conception, tests attendus) ; découpe ; écrit les briefs ; vérifie chaque production (P5) ; décide de l'intégration ; mène P6 et P7 | intégrer une production non vérifiée ; déléguer une décision de commit, de push, de PR ou de fusion ; accepter un « tout est vert » sans le relancer (V9) |
| **Producteur** | exécute un brief : écrit les tests demandés, les voit rouges, écrit le code, lance les contrôles qu'il peut lancer, rend un rapport | sortir du périmètre de fichiers du brief ; toucher Git en écriture ; télécharger ou installer quoi que ce soit ; « corriger » un test pour le faire passer |
| **Vérificateur indépendant** (niveau L) | relit le diff et la fiche **sans** le raisonnement du producteur ; cherche l'appelant oublié, le cas limite, le test qui ne peut pas échouer | produire le correctif lui-même |

Le producteur ne voit pas la conversation et ne peut pas poser de question :
tout ce dont il a besoin est dans le brief.

## Découper

- Un lot de production = un ensemble de **fichiers distincts** : deux
  producteurs ne touchent jamais le même fichier en même temps.
- Les lots qui changent un contrat passent **avant** ceux qui l'utilisent :
  d'abord le registre et le fournisseur, puis les consommateurs.
- Les tests d'un lot sont dans le même lot que son code, écrits d'abord.
- Un lot se vérifie seul : si on ne peut pas dire « ce lot est juste » sans
  les autres, le découpage est mauvais.

## Modèle de brief producteur

```markdown
RÔLE : producteur. Tu exécutes ce brief seul, sans poser de question.

OBJECTIF : <une phrase>

CONTEXTE : <ce que fait la partie du projet concernée, en 3 à 6 lignes ;
la fiche d'impact complète ci-dessous>

FICHE D'IMPACT : <copiée de P1>

FICHIERS AUTORISÉS (chemins absolus) :
- créer : …
- modifier : …
Tout autre fichier est hors périmètre.

À FAIRE, DANS L'ORDRE :
1. écrire les tests <noms, emplacements, ce qu'ils vérifient> ;
2. les lancer, montrer qu'ils échouent et pourquoi ;
3. écrire le code ;
4. relancer, montrer qu'ils passent ;
5. saboter l'invariant <lequel> dans le code produit, montrer l'échec, annuler.

CONTRAINTES : règles <S…, A…> de docs/regles-de-code.md ; modèle à suivre :
<fichier existant> ; INTERDIT : git en écriture, télécharger ou installer,
modifier un test existant pour le faire passer, toucher un fichier hors liste.

CRITÈRE D'ACCEPTATION : <commande> sort en code 0 et affiche <…>.

RAPPORT ATTENDU : fichiers modifiés ; sortie des tests rouges puis verts ;
résultat du sabotage ; ce qui n'a pas pu être vérifié et pourquoi.
```

## Checklist du vérificateur (porte G2)

Elle se fait **hors** du producteur, sur la vraie machine.

1. `git status --short` : seuls les fichiers autorisés ont changé ; aucun
   fichier de travail dans l'arbre.
2. `git diff` lu **en entier**, pas le résumé du producteur.
3. La fiche d'impact est respectée : chaque appelant listé est adapté ou
   justifié ; aucun contrat changé sans mise à jour du registre et des docs.
4. Les tests : ils testent le comportement ; le sabotage décrit a été
   refait par le vérificateur sur au moins un test ; aucun test existant
   affaibli.
5. `bash scripts/verifier-docker.sh` relancé par le vérificateur.
6. L'exécution locale du niveau exigé par la
   [matrice](strategie-de-test.md#matrice--ce-qui-est-exigé) refaite et
   consignée (commande, sortie, capture).
7. Chaque critère d'acceptation de P0 coché avec sa preuve, un par un.
8. Les règles de [`regles-de-code.md`](../regles-de-code.md) § 11 relues sur
   les lignes changées.

Une production qui échoue à un point retourne au producteur avec le point
précis, ou est corrigée par l'orchestrateur s'il s'agit d'une retouche ;
elle n'est jamais intégrée « en attendant ».

## Signes de code « à l'aveugle »

L'orchestrateur arrête la production dès qu'il en voit un :

- pas de fiche d'impact, ou une fiche dont « Recherches faites » est vide ;
- aucun test vu rouge avant le code ;
- un export, un événement ou un state bag modifié sans liste de ses
  appelants ;
- un chiffre (délai, distance, dégât) sans source ni mesure (V8) ;
- un `pcall` ou un `GetResourceState` ajouté pour faire taire une erreur
  (A7) ;
- un « corrigé » sans reproduction préalable du défaut ;
- une PR qui touche des fichiers sans rapport avec la demande.

## S'arrêter et demander

L'agent s'arrête et revient vers l'utilisateur quand :

- la demande implique une **décision produit** non prise (retirer une
  fonctionnalité, changer une règle de jeu, un équilibre, une touche) ;
- après **trois essais ratés sur la même piste**
  ([`pieges-fivem.md`](../pieges-fivem.md)) : compte rendu de ce qui a été
  mesuré, pas un quatrième essai ;
- un niveau T6 est exigé : il fournit le scénario de playtest ;
- le producteur est indisponible ou échoue de façon répétée : il le dit,
  sans basculer en silence sur un autre modèle.

## Configurations d'exemple

Les rôles sont neutres ; voici comment ils ont été tenus sur ce dépôt.

| Configuration | Orchestrateur-vérificateur | Producteur |
|---|---|---|
| DeepSeek Harness | DeepSeek (agent principal) | sous-agents `opencode-go/hy4-flash-free` |
| Claude Code avec DeepSeek Harness | Claude | DeepSeek Harness et ses sous-agents hy4-flash-free, appelés sur brief |
| Un seul agent | l'agent lui-même, qui tient les deux rôles en séparant les temps : brief écrit, production, puis vérification en relisant son propre diff comme celui d'un autre | |

Quelle que soit la configuration, l'orchestrateur reste responsable de ce
qui est intégré.
