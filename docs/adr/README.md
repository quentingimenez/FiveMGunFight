# Décisions d'architecture (ADR)

Un ADR consigne **une décision qui engage la suite** : ce qu'on a choisi,
contre quoi, et pourquoi. Il évite qu'une décision prise dans une PR soit
défaite trois PR plus loin faute d'avoir été écrite (le chat retiré, remis
puis retiré, #89, #94, #114).

## Quand en écrire un

Un ADR est exigé quand la PR :

- **retire ou remplace une fonctionnalité** visible par les joueurs ou les
  admins (chat, mode, commande, touche) ;
- **change une règle de jeu ou un équilibre** au-delà d'un réglage de
  valeur ;
- **change une frontière entre ressources** : nouvelle ressource, export ou
  événement partagé qui change de propriétaire, dépendance nouvelle entre
  couches ([architecture cible](../methode/architecture-cible.md)) ;
- **adopte, remplace ou abandonne un outil, une dépendance ou un format**
  (base de données, bibliothèque, format de fichier, service externe) ;
- **change le processus** (CI, protection de branche, méthode).

En cas de doute, la [fiche d'impact](../methode/fiche-impact.md) le dit :
une ligne « Décision produit ou d'architecture » non vide appelle un ADR.

L'ADR est écrit **dans la PR qui applique la décision**, pas après. Une
décision prise avec l'utilisateur en conversation y est rapportée avec ses
mots.

## Cycle de vie

- **Statuts** : `proposé` → `accepté` → éventuellement `remplacé par
  ADR nnnn` ou `abandonné`. Un ADR accepté ne se réécrit pas : une décision
  nouvelle est un nouvel ADR, et l'ancien reçoit seulement une ligne
  « Remplacé par … ».
- **Numérotation** : quatre chiffres, sans trou, dans l'ordre de fusion.
- Chaque ADR est listé ci-dessous, dans [`docs/README.md`](../README.md) et
  dans le [`README.md`](../../README.md) racine (vérifié par
  `tests/test_ops.py`).

## Modèle

```markdown
# ADR nnnn — <Titre court>

- **Statut** : proposé | accepté le AAAA-MM-JJ | remplacé par ADR nnnn
- **Date** : AAAA-MM-JJ
- **Décideurs** : <comptes>

## Contexte

<Le problème, mesuré si possible ; ce qui oblige à décider maintenant.>

## Options

1. **<Option>** : <avantages, inconvénients>
2. …

## Décision

<L'option retenue, en une phrase, puis ses règles d'application.>

## Conséquences

- <Ce qui devient vrai, ce qui devient interdit, ce qu'il faut faire ensuite.>

## Références

- <PR, documents, mesures>
```

## Index

| ADR | Sujet | Statut |
|---|---|---|
| [0001](0001-protection-branche.md) | protection de `main` : dépôt public et ruleset | accepté |
| [0002](0002-fxserver-epingle.md) | FXServer épinglé par URL et SHA256 | accepté et appliqué |
| [0003](0003-methode-de-developpement.md) | méthode de développement en phases et portes | accepté |
| [0004](0004-architecture-cible.md) | couches, propriétaires et frontières entre ressources | accepté |
