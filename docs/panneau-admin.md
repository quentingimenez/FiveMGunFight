# Panneau d'administration (`gf_admin`)

## Objectif

Offrir aux administrateurs un panneau à boutons pour consulter la liste des
joueurs, piloter les parties et accéder aux outils du serveur. Le client ne
décide jamais de ce qui compte : le serveur revérifie les droits sur chaque
action. Le détail du contrat réseau est dans
[les événements serveur](evenements-serveur.md) et l'ordre de démarrage dans
[l'architecture](architecture.md).

## Ouverture

Le panneau s'ouvre de deux façons :

- par la touche **F10** ;
- par le menu Échap (voir [le menu pause](menu-pause.md)), groupe **ADMIN** >
  bouton **PANNEAU ADMIN**. Le callback NUI `openAdmin` est enregistré côté
  `gf_menu` : il répond `{ ok = false }` si la page n'est pas prête, sinon il
  ferme le menu, déclenche l'événement **client local** `gf_admin:open` et répond
  `{ ok = true }`.

L'entrée **ADMIN** du menu n'est visible que si l'état serveur indique
`isAdmin === true`. Cet état client ne sert qu'à l'affichage : il n'ouvre aucun
accès par lui-même. Le panneau n'est pas accessible aux non-admins.

## Onglets

Le panneau propose trois onglets : **JOUEURS**, **PARTIES** et **OUTILS**.

### JOUEURS

La liste des joueurs affiche, pour chacun : **id**, **nom**, **mode**, **équipe**
et **ping**. Les actions disponibles sur un joueur sont :

- donner une arme au **Casier** (commande `give`) ;
- changer son **mode** (`setmode`) ou son **équipe** (`setteam`) ;
- **réinitialiser le personnage** (`resetchar`) ;
- **expulser** le joueur (`kick <id> [raison...]`) : la raison est nettoyée, avec
  « aucune raison » par défaut ; impossible de s'expulser soi-même ;
- **téléporter l'admin près du joueur** (`goto <id>`) ou **amener le joueur près
  de l'admin** (`bring <id>`) : +1,5 m sur l'axe x. Ces deux commandes sont
  **en jeu seulement**, exigent d'être dans le **même mode** (routing bucket)
  que la cible — sinon le serveur répond « … est dans un autre mode : utilise
  d'abord setmode. » — et refusent de cibler l'admin lui-même. Dans le cas de
  `bring`, la cible est notifiée ;
- **soigner** le joueur (`heal <id>`) : santé maximale si la cible n'est pas
  morte (le serveur émet `gf:healGranted` avant `gf_admin:heal`) ;
- **geler / dégeler** le joueur (`freeze <id>`) : la commande bascule l'état et
  la cible est notifiée ; le gel est oublié à la déconnexion.

### PARTIES

Commandes de partie :

- `startround` : lancer une manche ;
- `endmatch` : arrêter le match ;
- `nextzone` : passer à la zone d'attaque suivante ;
- `endgame` : terminer la partie Redzone ;
- `nextmap` : passer à la map suivante.

### OUTILS

- `editor` : éditeur de maps en jeu ;
- `maps` : liste des maps ;
- `customveh` : personnalisation du véhicule de base ;
- `announce <texte...>` : annonce à tous les joueurs (titre **ANNONCE**,
  8 secondes). Le texte est nettoyé et doit faire entre 1 et 120 caractères ;
  l'auteur et le texte sont journalisés côté serveur.

Chaque bouton exécute côté client la commande serveur existante au moyen de
`ExecuteCommand`. La source de la commande est l'administrateur : le serveur
revérifie ses droits avant de l'appliquer. Les actions ci-dessus sont enregistrées
côté serveur avec `RegisterCommand` et réservées aux admins : même si le client
affiche `isAdmin === true`, c'est bien le serveur qui décide de l'accès. La liste
des commandes et leurs effets sont décrits dans le
[README](../README.md#4-commandes-en-jeu).

### Vue du joueur

La commande `spectate <id>` permet à un administrateur de regarder un joueur,
et `spectate` seule arrête la vue en cours. Elle est réservée aux
administrateurs et utilisable **en jeu seulement**. Depuis le panneau, l'action
`spectate` ferme le panneau (`GFAdminCommands.opensUi('spectate')`) pour rendre
la main au jeu.

Pendant la vue, l'administrateur suit la cible dans son monde (routing bucket)
et retrouve son monde d'origine à l'arrêt. Il est invisible et intouchable près
de la cible, qui n'est pas prévenue. La vue s'arrête automatiquement si la cible
quitte le serveur, avec le message « Le joueur a quitté le serveur : vue
arrêtée. ». Rejouer la même commande ou taper `spectate` seule arrête la vue.
Changer de cible arrête silencieusement la vue précédente puis démarre la
nouvelle.

Au démarrage, une ligne d'action `spectate` avec la cible est journalisée ; elle
ne contient aucun identifiant (license, IP). Aucune ligne n'est ajoutée à
l'arrêt.

La vue utilise la caméra de spectateur du jeu, et non l'écran exact du joueur :
un menu de triche affiché seulement chez lui reste invisible. Pour voir l'écran
réel du joueur, utilisez la commande `screen` décrite ci-dessous.

### Écran en direct

La commande `screen <id>` permet à un administrateur de voir l'écran réel du
joueur désigné, et `screen` seule arrête l'écran en cours. Elle est réservée aux
administrateurs et utilisable **en jeu seulement**, comme `spectate`.

L'image est transmise au travers de la NUI de `gf_screen` à raison de 2 à 5
images par seconde (`Config.Fps` vaut 3 par défaut, borné entre 1 et 5). La vue
s'arrête automatiquement après `Config.MaxSeconds` (600 secondes). Il n'y a
qu'une seule vue par cible : changer de cible arrête la vue précédente avant de
démarrer la nouvelle. **La cible n'est pas prévenue** et son image n'est ni
enregistrée ni diffusée à d'autres joueurs. Le débit généré chez le joueur
regardé est d'environ 60 à 100 Ko/s.

Deux limites sont à connaître : la capture d'écran ne voit pas les triches qui
ne s'affichent que chez le joueur (overlays, menus ESP…), qui restent donc
invisibles ; il s'agit d'une capture périodique d'images, et non d'un flux vidéo
continu. Le contrat réseau de `gf_screen` est décrit dans
[les événements serveur](evenements-serveur.md).

## Sécurité

- Les droits sont revérifiés côté serveur sur `gf_admin:requestData`
  (`core:IsAdmin(src)`) **et** sur chaque commande exécutée depuis le panneau,
  même si le client affiche déjà `isAdmin === true`. Les commandes d'action
  (`kick`, `goto`, `bring`, `heal`, `freeze`, `announce`, `spectate`, `screen`)
  sont enregistrées avec `RegisterCommand` côté serveur : **aucun nouveau
  message client → serveur** n'est ajouté pour ces commandes. En revanche,
  `gf_screen:frame` est le nouvel événement de la ressource `gf_screen`, envoyé
  par le joueur regardé à l'admin qui le surveille ; il est documenté dans
  [les événements serveur](evenements-serveur.md).
- `gf_admin:requestData` ne prend **aucun argument** : le serveur utilise
  uniquement `source`, vérifie que le joueur est connecté et répond en lecture
  seule.
- Rate-limit : **1 / 500 ms** par joueur sur `gf_admin:requestData`.
- La réponse `gf_admin:data` contient la liste des joueurs (id, nom, mode,
  équipe, ping) et le catalogue d'armes. **Aucune donnée d'identification** —
  licence, IP, Steam, Discord — n'est affichée ni transmise.
- Un refus notifie le joueur puis émet `gf_admin:denied`.
- L'événement d'ouverture `gf_admin:open` est un événement **client local** : il
  ne traverse pas le réseau et ne modifie aucun droit.

## Journal des actions

Chaque action d'administration réussie est enregistrée dans la table MariaDB
`gf_admin_log`, créée par la migration `0005` de `gf_db`. Le journal répond aux
questions qui, quoi, sur qui et quand. `id` est une clé primaire auto-incrémentée
(`BIGINT UNSIGNED`) ; `created_at` est l'horodatage de l'action, avec
`CURRENT_TIMESTAMP` comme valeur par défaut, et un index accélère les
consultations triées par date. `admin_name` (`VARCHAR(64)`, obligatoire) donne
le nom de l'administrateur et `admin_identifier` (`VARCHAR(64)`, nullable) son
identifiant lorsqu'il est connu. `action` (`VARCHAR(32)`, obligatoire) nomme la
commande exécutée. `target_name` (`VARCHAR(64)`, nullable) et
`target_identifier` (`VARCHAR(64)`, nullable) désignent le joueur concerné
quand il y en a un ; pour une map ou un véhicule, le kind, l'id ou le modèle
sont précisés dans `details` (`VARCHAR(255)`, nullable), qui contient les
informations complémentaires de l'action.

Les actions journalisées sont `setmode`, `setteam`, `startround`, `endmatch`,
`nextzone`, `endgame`, `nextmap`, `give`, `admin_give`, `resetchar`, `kick`,
`goto`, `bring`, `heal`, `freeze`, `announce`, `spectate`, `screen`, `map_save`,
`map_enable`, `map_delete` et `vehicle_custom`. L'écriture a lieu **uniquement
après le succès** de l'action : un refus ou un échec n'ajoute aucune ligne. Elle
est asynchrone et ne se fait que si `gf_db` est démarrée et prête
(`exports.gf_db:Pret()` renvoie vrai). Chaque action produit également une courte
ligne dans la console du serveur, **sans identifiant** : aucune licence ni
adresse IP n'y figure.

Le panneau ne dispose pas encore d'un affichage de ce journal : la consultation
se fait par SQL sur la base `gunfight`. Par exemple :

```sql
SELECT created_at, admin_name, action, target_name, details
FROM gf_admin_log
ORDER BY created_at DESC
LIMIT 100;
```

## Limites connues

La vue du joueur utilise la caméra de spectateur du jeu : elle ne capture pas
l'écran exact du joueur.

## Comment tester

1. En tant qu'admin, vérifier que l'entrée **ADMIN** apparaît dans le menu Échap
   et que le bouton **PANNEAU ADMIN** ouvre le panneau. Ouvrir aussi le panneau
   directement avec **F10**.
2. Comme non-admin, vérifier que l'entrée **ADMIN** n'apparaît pas et qu'un faux
   `isAdmin` côté client n'ouvre rien.
3. Vérifier dans les logs du serveur les refus côté serveur (`gf_admin:denied`,
   notification au joueur) et confirmer qu'une commande lancée depuis le panneau
   est bien revérifiée par la source admin.
4. Contrôler la surface réseau avec `python -m unittest discover -s tests -v`
   (contrat d'événements) et le dépôt avec `bash scripts/verifier-docker.sh`.
5. Les commandes de test existantes sont décrites dans le
   [README](../README.md#4-commandes-en-jeu) et la procédure de test local dans
   [`debug-test.md`](debug-test.md).
