# Menu pause (`gf_menu`)

## Objectif

Remplacer le menu pause natif de GTA V (touche Échap, `INPUT_FRONTEND_PAUSE`)
par une page NUI propre au serveur. Le frontend natif est bloqué à chaque frame
par `DisableFrontendThisFrame()` ; la touche 200 est neutralisée puis capturée
par la ressource. Le joueur garde un seul point d'entrée pour reprendre la
partie, consulter son profil, lire le règlement, ouvrir le chat, rejoindre
Discord et quitter le serveur.

## Écran

La page `html/index.html` se décompose en quatre zones :

- un rail de navigation à gauche, organisé en groupes **PARTIE** (REPRENDRE),
  **ÉQUIPEMENT** (CASIER, CROSSHAIR, BOUTIQUE, CAISSES, PASS DE COMBAT,
  CONTRIBUTEUR — tous marqués « BIENTÔT ») et **SERVEUR** (CHAT, RÉGLEMENT,
  DISCORD, PARAMÈTRES DU JEU « BIENTÔT », QUITTER LE SERVEUR) ;
- une carte de profil à droite : pseudo, ID, K/D, victoires, parties, durée de
  session, date d'adhésion (« membre depuis ») et libellé du mode ;
- un panneau central qui affiche la section choisie (contenu construit par la
  page à partir de l'état reçu) ;
- un bas d'écran qui rappelle les touches et affiche le nombre de joueurs en
  ligne ainsi que le build quand il est fourni.

La page est autonome : elle ne charge aucune bibliothèque ni URL externe.

## Touches

| Touche | Action |
|---|---|
| **Échap** | ouvre le menu ; le referme quand il est déjà ouvert |
| **↑ / ↓** | navigue dans le rail et les éléments de la section courante |
| **Entrée** | valide l'élément sélectionné |
| **Souris** | sélection et clic sur les éléments du rail et des panneaux |

Le menu ne peut pas s'ouvrir pendant que l'interface du lobby est affichée :
`gf_lobby` garde la priorité et son focus. Un changement de mode ou un spawn
(`gf_core:modeChanged`, `gf_core:spawned`) referme le menu et rend la main au
jeu. Un délai de 400 ms (`Config.ReopenDelayMs`) empêche la réouverture
immédiate après une fermeture.

## Protocole NUI

Le client envoie trois types de messages à la page via `SendNUIMessage` :

| Type | Charge utile | Rôle |
|---|---|---|
| `open` | `{}` | la page devient visible et active |
| `close` | néant | la page se masque et rend le focus |
| `state` | état construit côté serveur | profile, statistiques, règlement, fonctionnalités |

La page répond par trois callbacks enregistrés côté client :

| Callback | Effet |
|---|---|
| `ready` | signalement que la page est prête ; mémorise l'état reçu si le menu est déjà ouvert |
| `close` | fermeture demandée depuis la page |
| `quit` | demande de déconnexion transmise au serveur |

Chaque callback délivre **une seule réponse** à la page. Le transport est
`fetch('https://gf_menu/<callback>')`. Si `ready` n'arrive jamais, un garde-fou
`SetTimeout(Config.PageReadyTimeoutMs, ...)` referme le menu pour ne pas piéger
le joueur dans une page vide. Les callbacks dont l'argument n'est pas une
fonction usable sont ignorés sans lever d'erreur.

## Données et sécurité

Toutes les données affichées viennent du serveur via `gf_menu:requestState` :
le client n'envoie ni statistiques, ni identité, ni argent. Le serveur utilise
exclusivement `source` pour retrouver le joueur, sans accepter le moindre
argument : un client ne peut donc pas consulter ou modifier l'état d'un autre
joueur. Les deux événements réseau sont limités :

- `gf_menu:requestState` : 1 appel / 500 ms par joueur, lecture seule, envoie
  `gf_menu:state` au demandeur ;
- `gf_menu:quit` : 1 appel / 1000 ms par joueur, termine par `DropPlayer` avec
  le motif `Config.QuitReason`.

Les libellés, le règlement, la liste des fonctionnalités et l'URL Discord
viennent de `config.lua` côté serveur. Voir
[le contrat d'événements](evenements-serveur.md) et
[les règles de code](regles-de-code.md).

## Dépendances

- `gf_core` : mode courant, changements de mode, apparition, priorité du lobby ;
- `gf_stats` : export `GetPlayerStats(src, callback)` pour les statistiques
  persistantes (kills, morts, parties, victoires, date d'adhésion) ;
- `gf_ui` n'est pas modifiée : le menu pause est une ressource séparée.

L'ordre de démarrage est décrit dans [l'architecture](architecture.md) :
`gf_menu` démarre après `gf_stats`.

## Limites connues

- Les sections CASIER, CROSSHAIR, BOUTIQUE, CAISSES, PASS DE COMBAT,
  CONTRIBUTEUR et PARAMÈTRES DU JEU sont « à venir » : elles s'affichent avec
  un badge et ne proposent aucune action.
- Le menu est indisponible quand l'interface du lobby est ouverte.
- Il n'y a pas de carte : le serveur n'utilise pas les minimaps interactives
  natives, et la page n'en affiche aucune.
- Le chat de la page est un panneau d'information ; il ne remplace pas encore
  le chat natif du jeu.
- `Config.DiscordUrl` est vide par défaut : renseigne l'invitation Discord dans
  `gf_menu/config.lua` (côté serveur) pour que le panneau Discord affiche un
  lien cliquable. Aucune URL n'est codée en dur dans la page.

## Comment tester

1. Suites unitaires : `python3 -m unittest discover -s tests -v` (contrôles
   statiques, lanceurs Lua et Node) puis
   `node --test tests/js/*.test.js`. Les suites Lua se lancent avec
   `lua5.4 tests/lua/menu_state_test.lua` et
   `lua5.4 tests/lua/menu_nui_callbacks.lua` quand l'interpréteur est présent.
2. Rendu : ouvrir `gf_menu/html/index.html` dans un navigateur avec un état
   factice pour vérifier le rail, la carte de profil et les panneaux ; la page
   ne dépend d'aucun service externe.
3. Contrôle du dépôt : `bash scripts/verifier-docker.sh`.
4. En jeu : appuyer sur Échap, vérifier que le menu natif ne s'ouvre pas,
   naviguer au clavier et à la souris, ouvrir le chat et le règlement, puis
   refermer avec Échap. Vérifier aussi que le menu ne s'ouvre pas dans le
   lobby et qu'il se referme sur un changement de mode. Le démarrage du
   serveur et la procédure de test local sont décrits dans
   [`debug-test.md`](debug-test.md).
