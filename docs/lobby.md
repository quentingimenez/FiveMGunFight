# Lobby Gunfight — architecture et spécification

> Document de conception de la ressource `gf_lobby`. Il décrit l'écran, les
> parcours, le protocole NUI/Lua et les règles serveur. Il sert aussi de contrat
> pour les modules JavaScript et les scripts Lua.

## 1. Objectif

À la connexion, un joueur sans personnage crée son premier personnage, puis
arrive dans un **lobby statique** : il voit son personnage, figé sur une scène,
peut inviter des amis dans son escouade, choisir un mode de jeu et lancer la
partie. Le lobby remplace l'apparition directe dans la map GTA et les commandes
`/attack` / `/redzone` comme interface principale.

Le lobby n'est pas un monde ouvert :

- déplacement, tir, saut, véhicules et menu arme sont neutralisés ;
- la caméra est scriptée et fixe ;
- chaque escouade vit dans son propre routing bucket (les autres joueurs ne
  sont ni visibles ni à portée) ;
- l'interface est une page NUI plein écran, avec curseur.

## 2. Écran

```
┌────────────────────────────────────────────────────────────────────────────┐
│  GUNFIGHT            LOBBY   ARMES 🔒   PERSONNAGE 🔒      3 EN LIGNE  ●   │
│                                                                            │
│  ┌──────────────┐                                      ┌────────────────┐  │
│  │ PROFIL       │                                      │ ESCOUADE 1/4   │  │
│  │  [avatar]    │                                      │ ● Warden  CHEF │  │
│  │  Warden      │              scène 3D                │ ○ Inviter      │  │
│  │  Lobby       │         personnage + escouade        │ ○ Inviter      │  │
│  │  #12         │                                      │ ○ Inviter      │  │
│  └──────────────┘                                      └────────────────┘  │
│                                                                            │
│                Invite tes amis · choisis un mode · lance                   │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ MODES DE JEU                            [ATTAQUE] [REDZONE] [·····]  │  │
│  │ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       ┌───────────┐  │  │
│  │ │ Attaque │ │ Redzone │ │ Gun Game│ │  TDM    │       │  JOUER    │  │  │
│  │ │ 0 joueur│ │ 0 joueur│ │ bientôt │ │ bientôt │       │  →        │  │  │
│  │ └─────────┘ └─────────┘ └─────────┘ └─────────┘       └───────────┘  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

### Barre supérieure

- marque `GUNFIGHT` + mention `LOBBY` ;
- navigation : `LOBBY` actif, `ARMES` et `PERSONNAGE` verrouillés avec libellé
  `BIENTÔT` (emplacements réservés) ;
- état serveur : nombre de joueurs en ligne et pastille de connexion.

### Colonne gauche — profil

Carte compacte : avatar (initiale), nom du personnage, identifiant serveur,
rôle (`CHEF D'ESCOUADE` / `MEMBRE`), état (`DANS LE LOBBY`). Pas de fausses
statistiques : uniquement des données réelles.

### Colonne droite — escouade

- titre + compteur `1/4` ;
- quatre emplacements : membres réels, puis boutons `Inviter` libres ;
- badge `CHEF`, badge `VOUS`, bouton d'exclusion (couronne, chef uniquement) ;
- pied de carte : bouton **Inviter** et **Quitter l'escouade** (si > 1).

### Zone basse — modes

- catalogue : Attaque de zone, Redzone, puis Gun Game et Team Deathmatch
  marqués `BIENTÔT` et désactivés ;
- chaque carte affiche icône, nom, description courte, nombre de joueurs et
  disponibilité ;
- le mode sélectionné est souligné par la couleur d'accent ;
- le chef choisit le mode ; les autres membres voient la sélection mais les
  cartes sont verrouillées avec l'indication « Le chef choisit le mode » ;
- bouton **JOUER** à droite : lance le mode. Pour **Attaque de zone**, il ouvre
  une recherche serveur globale (aucune condition de taille d'escouade) et
  devient **ANNULER** pour le chef qui l'a lancée, avec l'indice
  « Recherche N/20 ». Pour Redzone, il lance l'escouade comme avant. Il est
  désactivé si le joueur n'est pas chef, si le mode est indisponible ou pendant
  un lancement.

### Modales et notifications

- **Inviter** : panneau centré, recherche par nom, liste des joueurs présents
  dans le lobby (hors escouade), bouton `Inviter` par ligne, états vide/chargement ;
- **Invitation reçue** : carte sous la barre supérieure, nom de l'inviteur et du
  chef, boutons `Rejoindre` / `Refuser`, compte à rebours de 30 s ;
- **Toasts** : haut-droite, types info/succès/erreur, empilables, auto-effacés ;
- **Transition** : voile sombre + libellé du mode pendant le lancement ;
- **Création de personnage** : voir §7.

## 3. Parcours

### 3.1 Première connexion

1. `gf_core` connecte le joueur, le place en mode `lobby` (bucket 0), déclenche
   `gf:modeJoined(src, 'lobby')`.
2. `gf_lobby` charge la fiche du personnage depuis `data/characters.json`
   (clé : identifiant `license:…`).
3. Aucun personnage : le serveur envoie l'état avec `me.character = nil`.
4. Le client bascule la caméra en gros plan, applique un aperçu par défaut,
   ouvre la NUI sur l'écran de création.
5. Le joueur choisit nom, genre, carnation et style (4 variantes + aléatoire),
   voit le personnage en 3D. Chaque changement envoie `previewCharacter`.
6. `createCharacter` : validation serveur, sauvegarde JSON, envoi d'un état avec
   le personnage.
7. Le client applique le personnage, recadre la caméra sur l'escouade et affiche
   le lobby. Le joueur est chef de son escouade solo.

### 3.2 Connexion suivante

Le personnage existe : le lobby s'affiche directement, sans écran de création.

### 3.3 Invitation / escouade

1. Le joueur ouvre **Inviter**, la NUI demande `requestPlayers`.
2. Le serveur renvoie uniquement les joueurs du lobby hors de son escouade.
3. `invite` : le serveur crée une invitation de 30 s, prévient la cible et
   confirme à l'expéditeur (`inviteResult`).
4. La cible accepte (`respondInvite`) : le serveur l'ajoute si l'escouade a de
   la place, met à jour le routing bucket et renvoie l'état aux membres.
5. Chaque client replace son propre personnage dans la formation (2 à 4
   personnes), recadre la caméra en douceur et met à jour la NUI.

### 3.4 Lancement

1. Le chef choisit un mode (`selectMode`), diffusé à l'escouade.
2. **Attaque de zone** : `play` ouvre une **file serveur globale** au lieu de
   lancer l'escouade. Le chef peut être seul. Tous les joueurs du lobby ayant un
   personnage sont inscrits automatiquement. Le serveur diffuse `state.queue =
   { mode = 'attack', size = N, min = 20, max = 30, ownerId = <src> }` et
   l'indice « Recherche N/20 ». La NUI reste ouverte pendant l'attente.
   - Un joueur qui quitte le lobby ou déconnecte est retiré de la file ; si la
     file devient vide, la recherche s'arrête.
   - Un joueur qui rejoint le lobby avec un personnage pendant la recherche est
     ajouté automatiquement (`refreshQueue`).
   - **Choix documenté** : une seule recherche serveur active à la fois ; un
     nouveau `play` sur une recherche en cours est un simple rappel d'état, pas
     une seconde file.
   - Le chef annule avec `selectMode {mode='attack', cancel=true}` (le relais
     client `play` ne transmet pas `cancel`). La file est vidée et l'état NUI
     restauré. Le client ne ferme jamais la NUI pendant l'attente.
   - À `size >= Config.Matchmaking.attackMin` (20, configurable), un thread
     serveur fige la file et appelle `exports.gf_core:SetMode(member, 'attack')`
     pour **tous** les membres. `gf_attack.Config.MinPlayers = 20` empêche le
     démarrage à 2 joueurs.
3. **Redzone** : comportement inchangé (`minPlayers = 1`), lancement pour
   l'escouade via `play`.
4. Dans les deux cas, `party.launching = true` est posé côté serveur et diffusé.
   Un échec de `SetMode` restaure `launching = false`, rediffuse l'état et
   affiche un toast ; aucun `close` explicite n'est envoyé avant le spawn.
5. `gf_core` change le bucket, le spawn et ferme la NUI (`modeChanged`).
6. Le lobby CEF reste chargé mais masqué ; il réapparaîtra au retour.

### 3.5 Retour au lobby

`/lobby`, `/attack`, `/redzone`, fin de partie ou redémarrage de ressource :
`gf_core` resynchronise le joueur. `gf_lobby` recrée une escouade solo si
nécessaire, réattribue le bucket, renvoie l'état et rouvre la NUI.

## 4. Architecture technique

Nouvelle ressource autonome :

```
server-data/resources/[gunfight]/gf_lobby/
├── fxmanifest.lua
├── config.lua                 # partagé client/serveur (scène, escouade, modes)
├── appearance.lua             # client : génération/applica. apparence déterministe
├── client.lua                 # caméra, focus, placement, protocole NUI
├── server.lua                 # escouades, invitations, persistance, autorité
├── data/
│   ├── .gitkeep
│   └── characters.json        # généré à l'exécution, jamais versionné
└── html/
    ├── index.html
    ├── css/base.css
    ├── css/modes.css
    ├── css/squad.css
    ├── css/creator.css
    ├── css/customization.css
    ├── js/nui.js              # transport fetch vers les callbacks Lua
    ├── js/app.js              # état global, shell, profil, toasts, routage
    ├── js/modes.js            # barre de modes + bouton Jouer
    ├── js/squad.js            # panneau escouade + invitations
    ├── js/creator.js          # création de personnage
    └── js/customization.js    # onglets verrouillés (placeholders)
```

Ordre de démarrage : `gf_ui`, `gf_core`, `gf_lobby`, `gf_maps`, `gf_attack`,
`gf_redzone`. `gf_lobby` dépend de `gf_core` (manifeste + `server.cfg`).

La NUI est une page unique, sans dépendance externe ni police distante. Toutes
les données serveur sont insérées avec `textContent` ou `Lobby.el`, jamais par
`innerHTML`. Les SVG sont des constantes locales.

## 5. Protocole NUI

Transport : `fetch('https://gf_lobby/<callback>', {method:'POST', body: JSON})`.

### 5.1 UI → Lua (callbacks client)

| Callback | Charge utile | Effet |
|---|---|---|
| `ready` | — | page prête ; le client renvoie l'état en attente |
| `heartbeat` | — | chien de garde NUI (toutes les 2 s) |
| `requestState` | — | redemande l'état au serveur |
| `previewCharacter` | `{gender, seed, skin}` | aperçu local, sans sauvegarde |
| `createCharacter` | `{name, gender, seed, skin}` | création définitive |
| `requestPlayers` | — | liste des joueurs invitables |
| `invite` | `{id}` | invitation |
| `respondInvite` | `{partyId, accept}` | accepter/refuser |
| `leaveParty` | — | quitter l'escouade |
| `kickMember` | `{id}` | exclure (chef) |
| `selectMode` | `{mode}` | choisir le mode (chef) |
| `selectMode` | `{mode, cancel=true}` | annuler la recherche Attaque (chef) |
| `play` | `{mode}` | lancer le mode / ouvrir la file Attaque (chef) |

Tous les callbacks répondent `{ok:true}` (ou `{ok:false, error}`) pour clore le
`fetch`. Le serveur ne fait jamais confiance aux données du client.

### 5.2 Lua → UI (`SendNUIMessage`)

Enveloppe unique : `{type = "...", data = {...}}`.

#### `state`

```lua
{
  serverName = "GUNFIGHT",
  online = 3,
  limits = { partyMax = 4, nameMin = 3, nameMax = 20, skins = 5 },
  me = {
    id = 12,
    name = "Warden",              -- pseudo FiveM
    character = { name = "Vex", gender = "male", seed = 123456, skin = 2 } | nil,
    isLeader = true,
    inLobby = true,
  },
  party = {
    id = 4,
    leaderId = 12,
    leaderName = "Vex",
    maxSize = 4,
    size = 2,
    selectedMode = "attack",
    launching = false,
    members = {
      { id = 12, name = "Warden", displayName = "Vex", slot = 1,
        isLeader = true, isSelf = true, inLobby = true,
        character = { name = "Vex", gender = "male", seed = 123456, skin = 2 } },
      { id = 18, name = "Nova", displayName = "Nova", slot = 2,
        isLeader = false, isSelf = false, inLobby = true,
        character = { name = "Nova", gender = "female", seed = 999, skin = 1 } },
    },
  },
  queue = nil,  -- ou { mode = "attack", size = 22, min = 20, max = 30,
                --      ownerId = 12 } pendant une recherche serveur
  modes = {
    { id = "attack", label = "Attaque de zone", short = "ATTAQUE",
      description = "2 équipes, dernière équipe en vie.", icon = "target",
      players = 0, minPlayers = 1, available = true, placeholder = false },
    { id = "redzone", label = "Redzone", short = "REDZONE",
      description = "Chacun pour soi dans la zone.", icon = "zone",
      players = 0, minPlayers = 1, available = true, placeholder = false },
    { id = "gungame", label = "Gun Game", short = "GUN GAME",
      description = "Chaque élimination change d'arme.", icon = "weapon",
      players = 0, available = false, placeholder = true },
  },
}
```

`slot` est l'ordre dans la formation 3D, recalculé à chaque changement
d'escouade. Une escouade est dissoute quand un membre quitte le lobby : tous les
membres présents partagent le même lobby, donc `slot` est toujours présent.

#### `invite`

```lua
{ partyId = 4, from = {id=18, name="Nova"},
  leader = {id=12, name="Vex"}, expiresIn = 30000 }
```

#### `inviteResult`

```lua
{ ok = true, message = "Invitation envoyée à Nova." }
```

#### `players`

```lua
{ players = { {id=18, name="Nova", partySize=1}, ... } }
```

#### `notice`

```lua
{ message = "L'escouade est complète.", level = "error" } -- info|success|error
```

#### `launching`

```lua
{ mode = "attack", label = "Attaque de zone" }
```

#### `close`

```lua
{}
```

### 5.3 Lua → serveur

| Événement | Données | Contrôles serveur |
|---|---|---|
| `gf_lobby:createCharacter` | nom, genre, seed, skin | lobby, pas déjà créé, nom, limites, cadence |
| `gf_lobby:requestPlayers` | — | lobby, cadence |
| `gf_lobby:invite` | id cible | lobby, membre, cible invitables, place, cadence |
| `gf_lobby:respondInvite` | partyId, accept | invitation existante et non expirée |
| `gf_lobby:leaveParty` | — | membre, lobby |
| `gf_lobby:kickMember` | id cible | chef, cible du groupe |
| `gf_lobby:selectMode` | mode, `cancel?` | chef ; si `cancel`, annule la file dont il est propriétaire |
| `gf_lobby:play` | mode | chef, mode disponible ; Attaque : file serveur sans condition d'escouade ; Redzone : tous les membres dans le lobby |
| `gf_lobby:requestState` | — | réinscription si le joueur est en lobby |

### 5.4 Serveur → client

| Événement | Charge utile |
|---|---|
| `gf_lobby:state` | état complet (§5.2) |
| `gf_lobby:invite` | invitation (§5.2) |
| `gf_lobby:inviteResult` | résultat d'invitation |
| `gf_lobby:players` | liste des joueurs invitables |
| `gf_lobby:notice` | message + niveau |
| `gf_lobby:launching` | mode + libellé |
| `gf_lobby:close` | fermeture du lobby |

### 5.5 Hooks `gf_core` utilisés

- serveur : `gf:modeJoined`, `gf:modeLeft`, `playerDropped`,
  `exports.gf_core:SetMode`, `GetMode`, `GetPlayersInMode`, `IsAdmin` ;
- client : `gf_core:modeChanged`, `gf_core:spawned`,
  `LocalPlayer.state.gf_mode`.

`gf_lobby` masque le HUD `gf_ui` pendant le lobby (`TriggerEvent('gf_ui:hud', nil)`)
et le restaure en sortant.

## 6. Escouade, buckets et synchronisation

### 6.1 Autorité serveur

Le serveur tient :

```lua
Players[src] = { character, partyId, inLobby, lastInvite, lastMode }
Parties[id]  = { id, leader, members = {src...}, selectedMode, launching }
Invites[src] = { partyId, from, expiresAt }
Queue        = { active, mode, owner, members = {[src]=true} }
```

Règles :

- toute action est validée à partir de `src`, jamais d'un identifiant de groupe
  fourni par le client ;
- 4 membres maximum ;
- seul le chef choisit le mode, exclut et lance ;
- n'importe quel membre peut inviter ;
- quitter le lobby (mode, déconnexion) retire le joueur de l'escouade ;
- si le chef part, le premier membre restant devient chef ;
- une invitation expirée est purgée ; accepter une invitation remplace
  l'escouade solo éventuelle ;
- anti-spam : 2 s entre deux invitations, 1 s entre deux changements de mode ;
- une seule file Attaque active : elle est alimentée par `refreshQueue()` à
  chaque entrée/sortie du lobby et à la création de personnage ; le seuil est
  vérifié par un thread serveur toutes les 500 ms.

### 6.2 Routing buckets

| Contexte | Bucket |
|---|---|
| Lobby (escouade `id`) | `1000 + id` |
| Attaque de zone | 1 |
| Redzone | 2 |

Le bucket est appliqué par le serveur à l'entrée dans le lobby, à chaque
changement d'escouade et lors d'une réinscription. Le client ne le définit
jamais. Chaque escouade est donc isolée : la scène 3D ne montre que ses membres,
et les invitations sont le seul moyen de la rejoindre.

### 6.3 Placement et apparence

- Chaque client place **son** personnage à partir de `party.members[].slot`.
  Les autres joueurs ne sont jamais téléportés par un client tiers.
- Formation : ligne centrée, espacement `Config.Stage.spacing`, le chef en
  premier.
- À la réception d'un état, le client :
  1. vérifie le modèle du ped local (`mp_m_freemode_01` / `mp_f_freemode_01`) ;
  2. applique l'apparence de son personnage si elle a changé ;
  3. se téléporte sur son emplacement, fait `SetEntityHeading` et gèle le ped ;
  4. applique l'apparence stockée aux peds des autres membres quand ils existent
     (même seed = même rendu sur tous les clients) ;
  5. met à jour la caméra.
- Le client réapplique le placement après `gf_core:spawned` (le spawn de
  `gf_core` peut se terminer après l'arrivée de l'état).

## 7. Création de personnage

Minimale mais réelle, en attendant l'onglet de personnalisation avancée :

- nom affiché (3 à 20 caractères, accents autorisés, pas de caractère de
  contrôle) ;
- genre (`male` / `female`), modèle freemode correspondant ;
- carnation (5 valeurs) ;
- style : 4 boutons de tenue + bouton aléatoire. Le style est une **seed**
  entière ; l'apparence est générée de façon déterministe à partir de la seed,
  du genre et de la carnation, donc identique sur tous les clients ;
- aperçu 3D immédiat (caméra de création, ped face caméra) ;
- bouton `Entrer dans le lobby` verrouillé tant que le nom est invalide ou la
  requête est en cours.

`appearance.lua` expose :

```lua
GFLobbyAppearance.apply(ped, character) -> boolean
```

L'application :

- attend que le modèle soit chargé (le client s'en charge) ;
- nettoie accessoires, masque, sac, gilet, décalques ;
- choisit les composants (torse, jambes, chaussures, sous-vêtement, haut,
  cheveux) dans les bornes réelles via `GetNumberOfPedDrawableVariations` ;
- applique une tête cohérente (`SetPedHeadBlendData`), les cheveux, la couleur
  des yeux et les sourcils ;
- borne toutes les valeurs pour ne jamais transmettre un index invalide.

Les données sont cosmétiques : le serveur valide les types et les bornes, mais ne
peut pas valider un drawable (pas de ped côté serveur). Un index invalide est
ignoré côté client.

## 8. Caméra et scène

Scène : `Config.Stage` :

```lua
Config.Stage = {
  x = -1037.7, y = -2737.9, z = 20.2, heading = 330.0,
  spacing = 1.45,
  camera = {
    baseDistance = 3.2, distancePerMember = 0.95,
    height = 1.52, lookHeight = 1.12, fov = 42.0,
    creatorDistance = 2.9, creatorOffset = -0.75, creatorFov = 34.0,
  },
}
```

- Repère : `forward` et `right` dérivés du heading ; les personnages font face
  à la caméra.
- `slot i` sur `n` : décalage latéral
  `(i - (n + 1) / 2) * spacing`.
- Caméra groupe :
  `origin + forward * (baseDistance + (n - 1) * distancePerMember) + (0, 0, height)`,
  regard vers `origin + (0, 0, lookHeight)`.
- Caméra création : distance `creatorDistance`, décalage latéral
  `creatorOffset`, FOV `creatorFov` (le personnage apparaît à droite, le
  formulaire à gauche).
- Interpolation : chaque frame, position/regard/FOV glissent vers la cible
  (`SetCamCoord`, `PointCamAtCoord`, `SetCamFov`), pour éviter les coupures lors
  d'une arrivée dans l'escouade.
- Entrée : `RenderScriptCams(true)`, `SetNuiFocus(true, true)`, `DisplayHud(false)`,
  `DisplayRadar(false)`, gel et invincibilité du ped.
- Sortie : rendu caméra désactivé, caméra détruite, focus NUI relâché, HUD et
  radar restaurés. Nettoyage aussi sur `onResourceStop`.

### Chien de garde

Si la NUI ne répond pas (page absente, erreur JS), le client ne doit pas laisser
le joueur prisonnier :

- pas de `ready` sous 15 s, ou plus de `heartbeat` depuis 15 s → le client
  relâche le focus, détruit la caméra, rend le contrôle et affiche un message
  dans le chat ;
- commande `/lobbyui` : réouvre l'interface si le joueur est encore en mode
  lobby ;
- les commandes `/attack`, `/redzone` et `/lobby` de `gf_core` restent un
  secours.

## 9. Persistance

`data/characters.json` :

```json
{
  "version": 1,
  "characters": {
    "license:xxxx": {
      "name": "Vex", "gender": "male", "seed": 123456,
      "skin": 2, "createdAt": 1760000000
    }
  }
}
```

- clé : premier identifiant `license:`, sinon `license2:`, sinon `fivem:` ;
- chargement au démarrage, sauvegarde après création et à l'arrêt de la
  ressource ;
- fichier absent/corrompu : journal d'erreur, démarrage avec un fichier vide
  (les joueurs repassent par la création) ;
- `data/characters.json` est ignoré par Git ;
- commande admin `/resetchar [id]` pour retester la création d'un joueur.

## 10. Contrat JavaScript

`js/nui.js` expose `window.NUI.post(name, data)` : POST JSON vers le callback
FiveM, retourne une promesse, ne lève jamais.

`js/app.js` expose `window.Lobby` **avant** le chargement des modules :

```js
Lobby.state                 // dernier état (ou null)
Lobby.send(name, data)      // -> NUI.post, promesse
Lobby.on(type, handler)     // écoute un message Lua ; plusieurs handlers possibles
Lobby.el(tag, className, text) // élément DOM, textContent
Lobby.icon(name, className) // SVG constant, noms: target, zone, weapon, team,
                            // lock, users, crown, plus, check, play, close,
                            // search, repeat, arrow, male, female, shield,
                            // spark, alert, logout
Lobby.toast(message, level) // level: info|success|error
Lobby.showTransition(title, subtitle)
Lobby.hideTransition()
```

- `state` est mis à jour **avant** la diffusion du message `state` aux modules.
- `app.js` applique `body.screen-creator` ou `body.screen-lobby`, affiche/masque
  `#lobby-chrome` et `#creator-root`, remplit le profil et l'état serveur.
- Chaque module s'enregistre avec `Lobby.on(...)` et ne touche qu'à ses
  conteneurs : `#modes-bar`, `#squad-panel` + `#invite-root`, `#creator-root` +
  `#main-nav`.
- `app.js` envoie `ready` une seule fois après `DOMContentLoaded`, puis un
  `heartbeat` toutes les 2 s. En cas de `close`, il vide l'état, masque l'app et
  arrête les battements.
- `#boot` couvre le chargement initial ; un bouton `Réessayer` envoie
  `requestState` après 8 s sans état.
- `#transition-overlay` est contrôlé par `showTransition` / `hideTransition` ;
  un délai de sécurité le referme après 10 s.

Aucune donnée serveur ne passe par `innerHTML`. Les gestionnaires d'événements
sont ajoutés par `addEventListener`, pas par attribut HTML.

## 11. Contrat Lua client

- `GFLobbyAppearance.apply(ped, character)` : voir §7.
- Le client ne fait jamais confiance à `state.character` pour autre chose que
  l'affichage ; le serveur reste l'autorité.
- Tous les callbacks NUI sont protégés : validation de type, `pcall`, réponse
  systématique, journalisation des erreurs.
- `gf_core:modeChanged` non-lobby → fermeture. `gf_lobby:close` → fermeture.
- `gf_lobby:state` → présentation + mise à jour NUI. Si `character` est nil, la
  NUI affiche la création ; sinon le lobby.
- `onResourceStop` → nettoyage complet.
- `/lobbyui` → réouverture manuelle (secours).

## 12. Tests et exploitation

Statique (CI) :

- `luac -p` sur `config.lua`, `appearance.lua`, `client.lua`, `server.lua` ;
- `node --check` sur les six fichiers JS ;
- tests `tests/test_depot.py` : `gf_lobby` dans la liste des ressources, chaque
  fichier du manifeste existe, ressource citée dans `server.cfg` et `README`,
  `data/characters.json` non suivi ;
- workflow Docker : 13 ressources trouvées, `gf_lobby` démarrée.

Manuel en jeu :

1. premier personnage (homme puis femme), aperçu, validation ;
2. reconnection : le personnage revient, pas de création ;
3. invitation, acceptation, refus, expiration, escouade pleine ;
4. changement de chef, exclusion, départ, retour au lobby ;
5. sélection de mode (chef/membre), lancement, fermeture de la NUI ;
6. file Attaque : lancement par un chef solo, montée à 20 joueurs, annulation,
   départ d'un joueur, arrivée d'un nouveau joueur, seuil atteint ;
7. caméra/formation à 1, 2, 3 et 4 joueurs ;
7. `/lobbyui`, redémarrage de `gf_lobby`, passage Attaque → lobby ;
9. deux escouades : aucun joueur visible d'un groupe à l'autre (hors file
   Attaque, où les joueurs de toutes les escouades sont lancés ensemble).

## 13. Limites de la v1 et extensions

- Escouade **propre au lobby** : elle est dissoute au lancement et lorsqu'un
  membre quitte le lobby. Attaque de zone utilise désormais une file serveur
  globale (20–30 joueurs), mais l'escouade reste le conteneur du lobby.
  Extension : répartition équilibrée en deux équipes de 15 côté `gf_attack`.
- Pas de liste d'amis Cfx.re ni de présence hors ligne : invitations des joueurs
  présents dans le lobby uniquement. Extension : `txAdmin`/base de données,
  amis persistants.
- `ARMES` et `PERSONNAGE` sont des placeholders. Points d'extension :
  - `customization.js` : ajouter un panneau et un callback serveur ;
  - `appearance.lua` : lire les vêtements enregistrés dans le personnage ;
  - `server.lua` : table `characters` étendue, validation de charges utiles.
- Pas de personnalisation avancée du visage (parents, barbe, maquillage). La
  seed donne une identité stable, l'onglet Personnage la remplacera.
- Escouade non prise en compte par les règles d'équipe de `gf_attack` / `gf_redzone`.
- La scène est un point fixe de l'aéroport. Extension : plusieurs scènes,
  choisi par le chef, ou Studio (intérieur).
