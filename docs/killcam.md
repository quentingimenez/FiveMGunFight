# Killcam (`gf_killcam`)

La killcam fait revoir à la victime les dernières secondes du point de vue de
son tueur. À la mort, le serveur assemble un clip à partir des échantillons
enregistrés pour le tueur, la victime et les joueurs proches, puis l'envoie à la
victime. Le rejeu est entièrement **côté client** (`replay.lua`).

Voir aussi [`architecture.md`](architecture.md) (place de la ressource dans le
dépôt, ordre de démarrage) et
[`evenements-serveur.md`](evenements-serveur.md) (surface réseau client →
serveur et validation des arguments).

## Fonctionnement

### 1. Enregistrement côté client

`record.lua` échantillonne le jeu à intervalles de `Config.SampleMs` (100 ms).
Chaque échantillon est une table de champs numériques ou booléens :

| Champ | Contenu |
|---|---|
| `t` | horodatage ; le client envoie **0**, le serveur l'horodate |
| `x`, `y`, `z`, `h` | position et cap du ped |
| `cx`, `cy`, `cz` | position de la caméra de jeu (`GetGameplayCamCoord`) |
| `rx`, `ry`, `rz` | rotation de la caméra de jeu (`GetGameplayCamRot(2)`) |
| `w` | hash de l'arme |
| `a` | visée |
| `s` | tir |
| `v` | modèle du véhicule, ou 0 |

Les échantillons sont regroupés en lots de 1 à 15, un lot par
`Config.BatchMs` (1000 ms), et envoyés avec
`TriggerServerEvent('gf_killcam:samples', lot)`. Ce sont des **données non
fiables** : le client peut envoyer n'importe quoi, le serveur valide chaque
champ avant de l'accepter.

### 2. Validation, rate-limit et horodatage côté serveur

Le serveur vérifie, pour chaque lot reçu :

- `source` est un joueur connecté et son mode est dans `Config.Modes` (interrogé
  via `gf_core:GetMode`) ;
- le lot contient de 1 à 15 échantillons nettoyés par
  `GFKillcamTrack.clean` : nombres finis, coordonnées bornées à
  −20000..20000, booléens et entiers pour les champs qui l'exigent ;
- un rate-limit d'**un lot par 700 ms et par joueur** ;
- le champ `t` fourni par le client est ignoré : l'horodatage est posé par le
  serveur à la réception.

Les lots acceptés alimentent un tampon de `Config.BufferSeconds` (30 s) par
joueur. Le clip ne contient aucun identifiant personnel (license, IP) : seuls
les identifiants de joueur FiveM et les noms visibles sont transmis.

### 3. Déclenchement et envoi du clip

Sur `gf:playerKilled` (événement serveur interne de `gf_core`), le serveur
assemble le clip à partir des tampons disponibles. Pas de killcam si le tueur
est absent (suicide, déconnexion) ou si son tampon est vide. Le clip a la
structure suivante :

```lua
clip = {
  killer = { id = ..., name = ..., samples = { ... } },
  victim = { id = ..., name = ..., samples = { ... } },
  others  = { { id = ..., name = ..., samples = { ... } }, ... },
  weapon  = ...,     -- hash de l'arme
  duration = ...,    -- durée du clip, en secondes
}
```

Il est envoyé à la **victime uniquement**, en événement latent, avec
`TriggerLatentClientEvent('gf_killcam:play', victime, 250000, clip)`. Les
`others` sont au plus `Config.MaxOthers` joueurs, dans un rayon de
`Config.OthersRadius` (120.0 m). `gf_redzone` retarde la réapparition de la
victime du temps restant du clip (`RemainingMs`) pour que le rejeu se termine
avant le retour en jeu.

### 4. Rejeu côté client

`replay.lua` reçoit `gf_killcam:play` et rejoue le clip sur le client de la
victime : les positions et les caps des peds, ainsi que la position et la
rotation de la caméra, sont interpolés entre les échantillons successifs. Le
rejeu est une restitution de **données**, pas une capture de l'écran du tueur.

## Réglages

Les réglages sont définis dans `config.lua` (partagé entre le client et le
serveur).

| Réglage | Valeur | Effet |
|---|---|---|
| `Config.Enabled` | `true` | Active la ressource ; à `false`, plus aucun enregistrement ni clip n'est envoyé |
| `Config.BufferSeconds` | `30` | Durée du tampon d'échantillons conservé par joueur |
| `Config.ReplaySeconds` | `8` | Durée du clip envoyé à la mort, bornée à 3..30 secondes |
| `Config.SampleMs` | `100` | Intervalle entre deux échantillons côté client |
| `Config.BatchMs` | `1000` | Intervalle entre deux lots `gf_killcam:samples` |
| `Config.MaxOthers` | `6` | Nombre maximum de joueurs supplémentaires dans le clip |
| `Config.OthersRadius` | `120.0` | Rayon (mètres) de recherche des `others` autour du lieu du kill |
| `Config.Modes` | `{ attack = true, redzone = true }` | Modes dans lesquels la killcam est active |

Coût réseau : **environ 0,4 Ko/s par joueur** (échantillons envoyés en lots).

## Limites explicites

- Le rejeu restitue des **données** (positions, caps, caméra) et non l'écran du
  tueur : il n'y a ni capture d'écran ni flux vidéo.
- **Aucun tir ni effet n'est rejoué** : les champs `a` (visée) et `s` (tir)
  font partie des données enregistrées, mais le rejeu ne déclenche aucun tir,
  aucune animation de tir et aucun effet visuel.
- Les valeurs sont **interpolées entre échantillons** : le mouvement est
  reconstruit à partir de 100 ms d'échantillonnage, pas rejoué image par image.
- **Pas de killcam** si le tueur est absent (suicide, déconnexion), si son
  tampon est vide, ou si `Config.Enabled` est à `false`.
- Seuls les modes listés dans `Config.Modes` sont couverts (`attack` et
  `redzone` par défaut) ; les autres modes n'enregistrent pas de lot.

## Dépannage rapide

- Aucune killcam : vérifier `Config.Enabled = true` et que le mode joué est
  bien activé dans `Config.Modes`.
- Le clip n'arrive pas : vérifier que `gf_killcam` est démarrée (`ensure
  gf_killcam` dans `server.cfg`, juste après `gf_core`) et que `gf_core` est
  démarrée avant elle.
- Rejeu saccadé ou court : vérifier `Config.SampleMs`, `Config.BatchMs` et
  `Config.ReplaySeconds` (3..30 s) ; un lot est accepté au plus toutes les
  700 ms par joueur.
- Les événements sont documentés dans
  [`evenements-serveur.md`](evenements-serveur.md) ; la place de la ressource
  dans [`architecture.md`](architecture.md).
