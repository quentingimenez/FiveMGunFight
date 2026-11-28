# Méthode de développement

Ce dossier dit **comment** on travaille sur FiveMGunFight, quel que soit
l'agent (Claude, Codex, DeepSeek, Gemini…) ou l'humain. Il complète :

- [`AGENTS.md`](../../AGENTS.md) : le déroulé Git obligatoire (branche, PR,
  accord, fusion) ;
- [`regles-de-code.md`](../regles-de-code.md) : ce que le code doit respecter ;
- [`chantiers-techniques.md`](../chantiers-techniques.md) : ce qui doit encore
  changer pour que le code existant respecte ces règles.

La méthode répond à un constat mesuré : sur les 60 commits du 26 au
28 novembre 2026 qui précèdent la méthode (jusqu'à `8efec29`), il y a eu 24
correctifs pour 25 fonctionnalités. Les
chaînes de régression (chat retiré, remis, retiré ; file d'Attaque reprise
sept fois ; photos de `gf_thumbs` reprises quatre fois ; pages NUI
superposées quatre fois ; `IsAdmin` qui renvoyait `1`) ont toutes la même
origine : un changement codé comme une fonctionnalité isolée, sans avoir
cherché ce qu'il touchait ailleurs, sans test écrit avant, sans décision
consignée.

| Document | Contenu |
|---|---|
| [`fiche-impact.md`](fiche-impact.md) | le modèle de fiche à remplir **avant** de coder, et comment trouver ce qu'un changement touche |
| [`strategie-de-test.md`](strategie-de-test.md) | les niveaux de vérification T0 à T6 et la matrice « ce qui est exigé pour quel changement » |
| [`architecture-cible.md`](architecture-cible.md) | les couches, les propriétaires, les règles de dépendance, la dette connue |
| [`orchestration-agents.md`](orchestration-agents.md) | les rôles (orchestrateur, producteur, vérificateur), le modèle de brief, la checklist de vérification |

## Le cycle : huit phases, trois portes

Chaque demande traverse les huit phases. Les **portes** sont des points
d'arrêt : on ne passe pas sans le livrable de la porte.

| Phase | Ce qu'on produit | Porte |
|---|---|---|
| **P0 Cadrer** | la demande reformulée en une ou deux phrases ; des **critères d'acceptation** observables (« la file affiche 3 joueurs après le 3ᵉ `/queue` », pas « la file marche ») ; les questions à poser si la demande est ambiguë | |
| **P1 Situer** | la [fiche d'impact](fiche-impact.md) : ressources et contrats touchés, appelants et écouteurs trouvés, risques, plan de test, niveau S/M/L | **G1** — fiche complète avant la première ligne de code |
| **P2 Concevoir** | la forme de la solution : règle de jeu en module pur et coque mince (A1) ; contrat modifié, donc registre mis à jour d'abord ; [ADR](../adr/README.md) si la décision engage la suite | |
| **P3 Tester d'abord** | les tests exigés par la [matrice](strategie-de-test.md#matrice--ce-qui-est-exigé), vus **rouges** pour la bonne raison (V2) | |
| **P4 Produire** | le code, par petits incréments sur un seul sujet ; un producteur délégué reçoit un [brief](orchestration-agents.md#modèle-de-brief-producteur) qui contient la fiche | |
| **P5 Vérifier** | diff relu en entier, `bash scripts/verifier-docker.sh`, sabotage (V3), mutation des lignes changées (V4), exécution locale au niveau exigé, comparaison point par point aux critères de P0 | **G2** — preuve consignée (commande, sortie, capture) |
| **P6 Livrer** | [`AGENTS.md`](../../AGENTS.md) § 4.5 à 4.9 : avant/après, accord, PR, CI, fusion par le script | **G3** — accord explicite de l'utilisateur |
| **P7 Capitaliser** | ce qui évite de refaire l'erreur : voir [« Capitaliser »](#p7--capitaliser) | |

Un agent qui saute P1 ou P3 code « à l'aveugle » : c'est précisément ce que
cette méthode interdit.

## Proportionnalité : niveaux S, M, L

La lourdeur suit le risque, pas la taille du diff.

| Niveau | Quand | Fiche d'impact | En plus |
|---|---|---|---|
| **S** | documentation, configuration isolée, une ressource sans contrat touché (aucun export, événement partagé, state bag, table ni calque NUI) | trois lignes dans la PR : quoi, où, pourquoi aucun contrat n'est touché | — |
| **M** | comportement d'une seule ressource, contrats inchangés | complète | — |
| **L** | plusieurs ressources, un contrat, un état partagé, la base, les calques NUI, une décision produit | complète | ADR si décision ; vérification par un second agent qui n'a pas produit le code (V9) avant G2 |

Dans le doute, on prend le niveau supérieur. Un S qui se révèle toucher un
contrat repasse en L : on s'arrête, on complète la fiche.

## Taille et regroupement des pull requests

Une PR = **un sujet cohérent**, pas un fichier ni un micro-lot. Chaque PR
coûte un run complet de CI sur la PR puis un sur `main` (3 à 4 minutes
chacun, mesurés : [`qualite.md`](../qualite.md)) et une relecture. Donc :

- les petits changements d'un même sujet vont dans la même PR (une
  fonctionnalité, ses tests, sa documentation et le registre des contrats
  ensemble) ;
- deux sujets indépendants restent deux PR ([`AGENTS.md`](../../AGENTS.md)
  § 4.1) ;
- au-delà de 400 lignes environ, découper par commits lisibles dans la même
  PR plutôt que multiplier les PR, sauf si les parties peuvent être livrées
  et vérifiées séparément.

## P7 — Capitaliser

Avant le compte rendu final, l'agent répond à cinq questions. Chaque « oui »
produit un changement **dans la même PR**.

1. **Est-ce un correctif ?** Un test qui aurait détecté le défaut est ajouté
   (vu rouge sur le code d'avant, vert après), et la section « Cause racine »
   du modèle de PR est remplie avec une catégorie ci-dessous.
2. **Un comportement de la plateforme a-t-il surpris ?** (natif, ordre des
   événements, NUI, streaming) : une entrée dans
   [`pieges-fivem.md`](../pieges-fivem.md), avec la mesure qui le prouve.
3. **Une décision a-t-elle été prise** (produit, architecture, outil) qui
   engage la suite ? Un [ADR](../adr/README.md).
4. **Un contrat a-t-il changé ?** Le registre et les documents qui le
   décrivent ([`evenements-serveur.md`](../evenements-serveur.md),
   [`architecture.md`](../architecture.md)) sont à jour.
5. **Une dette a-t-elle été vue sans être traitée ?** Une entrée dans
   [`chantiers-techniques.md`](../chantiers-techniques.md), jamais un
   correctif glissé hors sujet.

### Catégories de cause racine

| Catégorie | Exemple tiré de l'historique | Ce qui l'aurait évitée |
|---|---|---|
| `exigence` : demande ou décision produit floue, non consignée | chat retiré (#89), remis (#94), retiré (#114) | P0 + ADR |
| `effet-de-bord` : appelant ou écouteur d'une autre ressource oublié | indices « /whoami » restés dans trois ressources (#116) | fiche d'impact, recherche des appelants |
| `contrat` : type ou forme d'un échange implicite | `IsPlayerAceAllowed` renvoie `1`, comparé à `true` (#99) | registre des contrats, test T3 |
| `plateforme` : natif, timing, streaming mal compris | assets d'armes jamais libérés (#123), mort annoncée avant la vie à 0 (#70) | test minimal du natif seul, `pieges-fivem.md` |
| `etat` : machine à états décrite cas par cas | équipe vidée pendant la sélection (#90), forfait (#97) | module pur + tests de propriétés (V5) |
| `calques-nui` : page NUI derrière ou devant une autre | éditeur de carte sous le lobby (#117) | propriétaire unique des calques |
| `asset` : modèle ou pack tiers non vérifié en jeu | Bison qui faisait planter les clients (#66) | essai en jeu avant fusion |

`scripts/mesurer_flux.py` (chantier C21) compte les correctifs par
zone et les correctifs qui suivent une fonctionnalité de moins de sept jours :
c'est l'indicateur que cette méthode doit faire baisser.

## Ce que la méthode ne change pas

- Le déroulé Git, la porte d'accord et la fusion par
  `scripts/fusionner-pr.sh` restent ceux d'[`AGENTS.md`](../../AGENTS.md).
- Les règles de code restent celles de
  [`regles-de-code.md`](../regles-de-code.md) ; la méthode dit **quand** les
  appliquer.
- [`CONTRIBUTING.md`](../../CONTRIBUTING.md) reste la référence pour le
  style de commit et les critères de revue.

La décision d'adopter cette méthode est consignée dans
[ADR 0003](../adr/0003-methode-de-developpement.md).
