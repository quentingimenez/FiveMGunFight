# ADR 0003 — Méthode de développement en phases et portes

- **Statut** : accepté le 2026-11-28
- **Date** : 2026-11-28
- **Décideurs** : `@WardenPro`

## Contexte

Les agents de codage livrent du code correct pris isolément, mais chaque
demande est traitée comme une fonctionnalité indépendante du reste du
projet. Mesure sur les 60 commits du 26 au 28 novembre 2026 : 25
fonctionnalités et 24 correctifs. Les chaînes de régression relevées (chat,
file d'Attaque, `gf_thumbs`, calques NUI, `IsAdmin`) viennent de décisions
non consignées, d'appelants oubliés dans d'autres ressources, de contrats
implicites et de tests écrits après l'incident.

[`AGENTS.md`](../../AGENTS.md) encadrait déjà l'après-code (branche,
vérification, accord, PR, fusion) et
[`regles-de-code.md`](../regles-de-code.md) le contenu du code. Rien
n'obligeait à situer un changement dans le projet avant de l'écrire, ni ne
disait quel niveau de test chaque type de changement exige.

## Options

1. **Renforcer la revue seule** : plus de points dans la checklist de revue.
   Le défaut est constaté après coup, quand le code est écrit ; les
   régressions de l'historique avaient passé la revue.
2. **Méthode en phases avec portes, outillée** : un livrable obligatoire
   avant de coder (fiche d'impact), une matrice de tests par type de
   changement, des rôles d'agents neutres, un filet de tests sur les liens
   entre ressources.
3. **Geler les fonctionnalités** le temps de rembourser la dette : arrête la
   production sans changer la façon de produire.

## Décision

Option 2. La méthode est décrite dans [`docs/methode/`](../methode/README.md)
et s'applique à tout agent et à tout humain :

- huit phases (cadrer, situer, concevoir, tester d'abord, produire,
  vérifier, livrer, capitaliser) et trois portes : G1 fiche d'impact avant
  le code, G2 preuve consignée, G3 accord de l'utilisateur ;
- une lourdeur proportionnée au risque (niveaux S, M, L) ;
- des niveaux de vérification T0 à T6 et une matrice de ce qui est exigé ;
- des rôles neutres (orchestrateur-vérificateur, producteur, vérificateur
  indépendant) : le couple DeepSeek / Hy4 Flash devient une configuration
  parmi d'autres ;
- peu de PR, chacune sur un sujet cohérent : chaque PR coûte deux runs de CI
  (PR puis `main`) ;
- un filet outillé (chantiers C17 à C21) avant les refactors d'architecture
  (C22 à C24, C16).

## Conséquences

- [`AGENTS.md`](../../AGENTS.md) gagne une étape « Cadrer et situer » avant
  le code et une étape « Capitaliser » avant le compte rendu ; le modèle de
  PR gagne les sections Niveau, Fiche d'impact, Risques et Cause racine.
- Une PR sans fiche d'impact (niveaux M et L) est renvoyée.
- Un correctif sans test de régression doit dire pourquoi et donner la
  mesure qui le remplace.
- L'efficacité se mesure : la part de correctifs qui suivent une
  fonctionnalité de moins de sept jours doit baisser (C21).

## Références

- [`docs/methode/`](../methode/README.md)
- [`regles-de-code.md`](../regles-de-code.md) § 8 et § 11
- [`chantiers-techniques.md`](../chantiers-techniques.md), C17 à C24
- [ADR 0004](0004-architecture-cible.md)
