# ADR 0004 — Couches, propriétaires et frontières entre ressources

- **Statut** : accepté le 2026-11-28
- **Date** : 2026-11-28
- **Décideurs** : `@WardenPro`

## Contexte

Le serveur compte 18 ressources `gf_*` démarrées. Relevé du 28 novembre
2026 :

- environ la moitié des liens entre ressources ne sont pas déclarés dans
  les manifestes ; 16 fichiers appellent une autre ressource derrière
  `GetResourceState` et `pcall` ;
- le bus `gf:*` (environ 17 événements) n'a pas de propriétaire, et
  plusieurs ressources émettent le même événement ;
- le protocole de calques NUI `gf_lobby:menuOverlay` est utilisé par quatre
  ressources sans être écrit nulle part ; quatre correctifs ont porté sur
  des pages ou effets NUI restés affichés ou mal superposés (#18, #63, #65,
  #117) ;
- gf_core, censé être le socle, connaît les modes de jeu, et des cycles
  existent (gf_core ↔ gf_attack, gf_core ↔ gf_admin, gf_lobby ↔ gf_attack,
  gf_inventory ↔ gf_redzone) ;
- `gf_lobby/server.lua` (1 527 lignes) et `gf_core/server.lua` (913)
  concentrent plusieurs responsabilités.

## Options

1. **Laisser en l'état et documenter** : le registre seul ne supprime ni les
   cycles ni l'ambiguïté des calques.
2. **Fusionner les ressources** en quelques grosses ressources : supprime
   les liens en les cachant, et aggrave la taille des fichiers.
3. **Couches et propriétaires explicites**, appliqués progressivement :
   registre des contrats testé d'abord, puis refactors ciblés.

## Décision

Option 3, décrite dans
[`architecture-cible.md`](../methode/architecture-cible.md) :

- trois couches (plateforme, domaine, présentation et outils) ; une
  ressource n'appelle que sa couche ou une couche inférieure ; vers le haut,
  elle émet un événement qu'elle possède ou offre un point d'enregistrement ;
- un propriétaire unique par export, événement, state bag, table, fichier
  de données et calque NUI, déclaré dans le registre des contrats ;
- cœur fonctionnel et coque impérative pour toute règle (modèle :
  `gf_attack/rules.lua`) ;
- gf_ui possède les calques NUI ;
- les nouveaux identifiants sont en anglais ; l'existant est renommé
  seulement lors d'un refactor de la ressource pour une autre raison.

## Conséquences

- Le registre des contrats (C17) décrit d'abord l'existant, cycles compris,
  listés comme dette. Il devient ensuite le contrôle de toute PR qui touche
  un lien entre ressources.
- Les refactors (C22, C23, C24, C16) suivent dans cet ordre, une fois le
  filet en place (C17 à C20).
- Une PR qui ajoute un appel vers une couche supérieure, ou un export sans
  propriétaire déclaré, est refusée.

## Références

- [`architecture-cible.md`](../methode/architecture-cible.md)
- [`architecture.md`](../architecture.md)
- [`regles-de-code.md`](../regles-de-code.md), règles A1, A2, A6
- [ADR 0003](0003-methode-de-developpement.md)
