# Architecture cible

[`architecture.md`](../architecture.md) décrit **comment le serveur est
assemblé** (Docker, données, démarrage). Ce document fixe **la forme vers
laquelle le code des ressources évolue**, et les règles qui empêchent d'en
sortir. Chaque écart connu est un chantier de
[`chantiers-techniques.md`](../chantiers-techniques.md). La décision est
consignée dans [ADR 0004](../adr/0004-architecture-cible.md).

## Pourquoi

Prises une à une, les ressources sont propres. Les régressions viennent des
**liens entre elles**, que personne ne voit en ouvrant un seul fichier
(relevé du 28 novembre 2026) :

- environ la moitié des appels entre ressources ne sont pas déclarés dans les
  `fxmanifest.lua` : 16 fichiers appellent une autre ressource derrière
  `GetResourceState(...) == 'started'` et un `pcall`, qui la rendent
  silencieuse quand elle manque ;
- le bus `gf:*` compte environ 17 événements, dont 3 documentés ;
  `gf:matchEnded` est émis par gf_attack **et** gf_redzone, `gf:healGranted`
  par gf_admin **et** gf_redzone ;
- le protocole de calques NUI `gf_lobby:menuOverlay` est émis par gf_admin,
  gf_maps, gf_menu et gf_vehicles et n'est écrit nulle part ;
- gf_core connaît les modes : il appelle `exports.gf_attack:CanJoin` et
  expose `UpdateRedzoneWeapons` ;
- gf_inventory lit les fichiers `weapons.meta` de gf_weapons
  (`LoadResourceFile('gf_weapons', …)`) ;
- des cycles au fonctionnement : gf_core ↔ gf_attack, gf_core ↔ gf_admin,
  gf_lobby ↔ gf_attack, gf_inventory ↔ gf_redzone.

## Les couches

Trois couches. Une ressource n'appelle **que sa couche ou une couche
inférieure**. Pour prévenir une couche supérieure, elle émet un événement
dont elle est propriétaire, ou elle offre un point d'enregistrement.

| Couche | Ressources | Rôle |
|---|---|---|
| **Plateforme** | gf_db, gf_ui, gf_core (noyau), gf_weapons (données) | ce dont tout le reste a besoin : schéma, notifications et calques NUI, joueurs, équipes, protection, validation, droits admin, catalogue d'armes |
| **Domaine** | gf_attack, gf_redzone, gf_inventory, gf_killcam, gf_journal, gf_stats, gf_audit | les modes de jeu et ce qui en découle : manches, inventaire, journal, statistiques, audit |
| **Présentation et outils** | gf_lobby, gf_menu, gf_admin, gf_maps, gf_screen, gf_thumbs, gf_vehicles | ce que le joueur et l'admin voient et manipulent |

Exemples de ce que la règle interdit, et de la forme à prendre :

| Aujourd'hui | Cible |
|---|---|
| gf_core appelle `exports.gf_attack:CanJoin()` | gf_attack appelle au démarrage `exports.gf_core:RegisterMode('attack', { canJoin = … })` ; gf_core ne connaît que le contrat d'un mode (C23) |
| gf_core expose `UpdateRedzoneWeapons` | une fonction générique de gf_core (« remplacer l'équipement d'un joueur ») appelée par gf_redzone (C23) |
| gf_inventory lit `weapons.meta` dans gf_weapons | gf_weapons expose ses données d'armes (C24) |
| quatre ressources émettent `gf_lobby:menuOverlay` | gf_ui possède les calques : `PushLayer(nom)` / `PopLayer(nom)`, et gf_lobby s'y abonne comme les autres (C22) |

## Propriétaires

Chaque élément partagé a **un seul propriétaire**, déclaré dans le registre
des contrats (C17) :

| Élément | Propriétaire = | Les autres |
|---|---|---|
| un export | la ressource qui le définit | l'appellent ; la dépendance est dans leur manifeste, ou déclarée optionnelle dans le registre avec ce qui se passe quand elle manque |
| un événement `gf_<ressource>:*` | cette ressource | l'écoutent ; seule elle l'émet |
| un événement du bus `gf:*` | la ressource désignée dans le registre ; les autres émetteurs y sont listés un par un | l'écoutent |
| un state bag, une clé de `GlobalState` | la ressource qui l'écrit | le lisent ; un client ne fait jamais foi (S3) |
| une table SQL | la ressource qui la crée dans `gf_db/migrations/` | passent par ses exports |
| un fichier de données (`maps.json`, `characters.json`, `custom.json`, photos) | la ressource qui le contient | passent par ses exports |
| un calque NUI | gf_ui (pile des calques) | demandent un calque, ne cachent jamais la page d'une autre ressource |

## Forme d'une ressource

Le modèle est `gf_attack/rules.lua` : **cœur fonctionnel, coque
impérative**.

```
gf_<ressource>/
  fxmanifest.lua     dépendances dures déclarées
  config.lua         valeurs nommées, aucune valeur magique (A3)
  <regle>.lua        module pur : pas de natif, temps et hasard en paramètres,
                     renvoie des données ou une liste d'effets (A1) — testé en T1
  server.lua         coque : reçoit, valide (S2), appelle le module, applique
                     les effets, journalise les refus (S9) — testé en T2
  client.lua         coque client : natifs, dessin, NUI — calculs dans un module pur
  html/              page NUI : logique dans des fonctions sans DOM, testées en T1
```

- Une fonction de coque qui dépasse quelques lignes de décision est un
  module pur qui s'ignore.
- Un utilitaire présent dans deux ressources (limiteur de débit, marqueur
  de plantage en KVP) monte dans la plateforme et s'expose (C24).
- Un fichier de plus de 600 lignes environ ne grossit plus (A6). Le cliquet
  du chantier C20 le vérifie ; le découpage se fait dans une PR `refactor`
  du sujet (C16 pour gf_lobby).

## Nommage

- Événements : `gf_<ressource>:camelCase` pour ceux d'une ressource,
  `gf:camelCase` pour le bus partagé ; exports en `PascalCase` ;
  configuration dans un `Config` global de `config.lua`.
- Langue : les **nouveaux** identifiants sont en anglais. Les identifiants
  français existants (`gf:anomalie`, `Pret`, `GardeEtat`,
  `verifierVictoire`) sont renommés seulement quand la ressource est
  refactorée pour une autre raison, jamais dans une PR de renommage seule.
  Les textes vus par le joueur et la documentation restent en français.

## Dette connue et ordre de traitement

Le filet d'abord, les refactors ensuite : un refactor n'est vérifiable que
si le registre, le harnais et le démarrage sans erreur existent.

| Ordre | Chantier | Écart traité |
|---|---|---|
| 1 | C17 Registre des contrats | liens non déclarés, bus `gf:*` sans propriétaire |
| 1 | C18 Harnais Lua partagé | chaque test recopie son faux FiveM |
| 1 | C19 Démarrage sans erreur de script | le smoke ignore les `SCRIPT ERROR` |
| 1 | C20 Documentation tenue par les tests | listes de ressources périmées, fichiers qui grossissent |
| 1 | C21 Mesure du flux | aucun indicateur de régression |
| 2 | C22 Calques NUI possédés par gf_ui | `gf_lobby:menuOverlay` implicite |
| 2 | C24 Utilitaires communs, données d'armes exposées | limiteurs dupliqués, lecture de `weapons.meta` |
| 3 | C23 gf_core sans connaissance des modes | cycles core ↔ attack, core ↔ redzone |
| 3 | C16 Découpage de gf_lobby | `gf_lobby/server.lua` (1 527 lignes), `client.lua` (1 172) |
