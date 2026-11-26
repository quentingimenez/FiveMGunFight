# Événements serveur (client → serveur)

Ce document décrit la surface réseau de FiveMGunFight : les événements qu'un
client peut envoyer au serveur, ce que le serveur vérifie avant de les traiter,
et les rate-limits associés. Il est vérifié par
[`tests/test_evenements.py`](../tests/test_evenements.py) : tout
`TriggerServerEvent` d'un script client doit avoir un `RegisterNetEvent` côté
serveur, et tout événement serveur doit figurer dans le tableau ci-dessous.

Rappel de menace : **un client ne contrôle que les arguments de l'événement,
pas `source`**. `source` est fourni par FiveM et désigne le joueur émetteur ;
tout le reste (identifiants d'entité, positions, tueur, arme, map…) est à
considérer comme non fiable. Les événements `baseevents:*` viennent de la
ressource cfx-default `baseevents` : n'importe quel client peut les déclencher,
même s'ils sont normalement émis par son script.

## Tableau des événements

| Événement | Émetteur | Validation | Rate-limit | Admin requis | Notes |
|---|---|---|---|---|---|
| `gf_core:ready` | `gf_core/client.lua` (fin de chargement) | `source` joueur, `Modes[src]` absent, identifiants filtrés (IP retirée) | `Config.ReadyRateLimit` : 1 / 5 s | non | Démarre le lobby. Un appel répété est ignoré. |
| `gf_core:vehicle` | `gf_core/client.lua` (`giveVehicle`) | netId entier > 0, entité existante, type 2 (véhicule), propriétaire réseau = `src`, distance ≤ `Config.VehicleBindDistance` (50 m par défaut) | `Config.VehicleRateLimit` : 5 / 10 s | non | Le client crée le véhicule puis envoie son netId. L'ancien véhicule du joueur est supprimé si le netId change. Refus journalisé au plus 1 fois/min/joueur. |
| `gf_core:vehicleGone` | `gf_core/client.lua` (suppression du véhicule de mode) | `source` joueur ; efface uniquement l'entrée du joueur | `Config.VehicleGoneRateLimit` : 5 / 10 s | non | Ne supprime pas l'entité : le client s'en charge. Empêche un client de nettoyer l'entrée d'un autre joueur. |
| `gf:loadoutChosen` | `gf_ui/client.lua` (menu de choix des armes de l'Attaque de zone) | `source` dans une équipe d'Attaque et phase `select` ; `core:ResolveSelection` ne garde que des identifiants texte distincts d'armes possédées, au plus `Config.SelectionCount`, et complète avec `Config.DefaultSelection` | aucun (ignoré hors phase de choix) | non | Remplace le choix précédent du joueur ; les armes sont données au placement. |
| `gf_attack:useItem` | `gf_attack/client.lua` (touches 3 et 4 : bandage, kevlar) | `item` est une clé de `Config.Items` ; `source` dans une équipe d'Attaque, en vie, phase `place` ou `live` ; il lui reste au moins un exemplaire (compté par le serveur) | une utilisation à la fois : refusé tant que la précédente dure (`Config.Items[item].duration`) | non | Décrémente l'objet puis renvoie `gf_attack:applyItem` : le client joue l'animation et applique +50 PV ou +50 kevlar. Les quantités sont remises à `Config.StartBandages` / `Config.StartKevlars` à chaque manche ; un kill ennemi rapporte `Config.KevlarPerKill` kevlar (max `Config.MaxKevlars`). |
| `gf_maps:save` | `gf_maps/client.lua` (éditeur de maps) | `core:IsAdmin(src)`, `kind` dans `{redzone, attack}`, validation complète de la map, `id` limité à `[%w_]+` | aucun (réservé aux admins) | oui | Écrit `data/maps.json`, puis émet `gf_maps:updated` côté serveur. |
| `gf_maps:setEnabled` | `gf_maps/client.lua` (éditeur de maps) | `core:IsAdmin(src)`, `kind` connu, `id` existant | aucun (réservé aux admins) | oui | Coche/décoche une map ; écrit `data/maps.json`. |
| `gf_maps:delete` | `gf_maps/client.lua` (éditeur de maps) | `core:IsAdmin(src)`, `kind` connu, `id` existant | aucun (réservé aux admins) | oui | Supprime une map ; écrit `data/maps.json`. |
| `gf_vehicles:saveCustom` | `gf_vehicles/client.lua` (menu `/customveh`) | `core:IsAdmin(src)` ; `model` est un modèle de `Config.Vehicles` ; `sanitize` ne garde que les propriétés connues, entiers bornés (peinture, couleurs GTA 0–160, types de jantes, vitres, xénon, style de plaque), couleurs RGB 0–255, mods limités aux types de `Config.ModSlots` + jantes (23), plaque `[A-Z0-9 ]` tronquée à `Config.PlateMaxLength` | aucun (réservé aux admins) | oui | Le véhicule devient le véhicule de base avec cette custom : écrit `custom/custom.json`, publie `GlobalState.gf_vehicle_base` et `GlobalState.gf_vehicle_customs` ; `gf_core` les applique aux véhicules de mode suivants. |
| `gf_thumbs:save` | `gf_thumbs/client.lua` (studio photo `/thumbs`) | `core:IsAdmin(src)` ; famille connue (`Config.Kinds`) ; id `[%w_]+` (1–64) ; data URL `data:image/png;base64,` décodée, signature PNG vérifiée, au plus `Config.MaxImageBytes` | aucun (réservé aux admins) | oui | Écrit `thumbs/<famille>/<id>.png` (volume `thumbs` en production), puis émet `gf_thumbs:updated` à tous (les clients vident leur cache). Envoyé en événement latent. |
| `gf_thumbs:request` | `gf_thumbs/client.lua` (export `Get`, ex. onglet Véhicule de `/customveh`) | `reqId` nombre ; famille connue ; `ids` table, 100 au plus, chacun `[%w_]+` ; lecture seule ; une photo absente est simplement omise | 1 / 250 ms par joueur | non | Répond par `gf_thumbs:data` (événement latent) avec les data URL des photos existantes. |
| `gf_thumbs:lobbyReady` | `gf_thumbs/client.lua` (arrivée au lobby, une fois) | `source` joueur ; ignoré si `Config.AutoCapture` est faux ou déjà reçu pour ce joueur ; `core:IsAdmin(src)` sinon rien | 1 par joueur et par session | non | Sans effet pour un non-admin. Répond `gf_thumbs:autoCapture` à un admin : son jeu photographie les modèles des familles `auto` qui n'ont pas encore de photo, puis les envoie par `gf_thumbs:save`. |
| `gf_lobby:createCharacter` | `gf_lobby` NUI (création de personnage) | `source` dans le lobby, aucun personnage existant, payload normalisé (nom 3–20 caractères, genre, seed entier, carnation historique bornée), cadence 2 s | 1 / 2 s | non | Persiste le personnage par identifiant `license:` quand il est disponible. |
| `gf_lobby:updateAppearance` | `gf_lobby` NUI (onglet Personnage) | `source` dans le lobby avec personnage ; apparence normalisée par `GFLobbyAppearanceSchema` (bornes, 24 tatouages, 4 par zone) ; carnation historique bornée ; ne touche qu'à `appearance` et `skin` | 1 / 1 s | non | Nom, genre et seed restent figés. Persiste et rediffuse l'état à l'escouade. |
| `gf_lobby:requestState` | `gf_lobby` NUI (ouverture/rafraîchissement) | `source` connue ; lecture seule ; ne ferme la NUI que si `gf_core` confirme un autre mode | `Config.RequestCooldownMs` : 500 ms | non | Idempotent : peut rejoindre le lobby si `gf_core` y place déjà le joueur. |
| `gf_lobby:requestPlayers` | `gf_lobby` NUI (modale d'invitation) | `source` dans le lobby et une escouade ; lecture seule ; liste filtrée aux joueurs du lobby avec personnage | `Config.RequestCooldownMs` : 500 ms | non | Aucun effet de bord sur les autres joueurs (pas de resync ni de changement de bucket). |
| `gf_lobby:invite` | `gf_lobby` NUI | `source` dans le lobby avec personnage et escouade ; cible connectée, dans le lobby, avec personnage, hors escouade ; taille max ; cooldown | `Config.Party.inviteCooldown` : 2 s | non | L'invitation est liée à la cible et expire après `Config.Party.inviteTimeout` (30 s). |
| `gf_lobby:respondInvite` | `gf_lobby` NUI | invitation existante pour `source`, non expirée, `partyId` identique ; cible encore dans le lobby avec personnage ; escouade non pleine | aucun | non | Accepter ou refuser ne peut viser que l'invitation reçue par l'émetteur. |
| `gf_lobby:leaveParty` | `gf_lobby` NUI | `source` dans une escouade | aucun | non | Quitte l'escouade et en recrée une solo si le joueur reste dans le lobby. |
| `gf_lobby:kickMember` | `gf_lobby` NUI | `source` chef de l'escouade ; cible membre de cette même escouade ; pas soi-même | aucun | non | La cible exclue reçoit une notification ; son bucket est recréé si elle reste dans le lobby. |
| `gf_lobby:selectMode` | `gf_lobby` NUI | `source` chef d'escouade ; mode existant et disponible ; cooldown | `Config.Party.modeCooldown` : 1 s | non | Diffuse le nouvel état aux membres. |
| `gf_lobby:play` | `gf_lobby` NUI | `source` chef d'escouade ; mode disponible ; tous les membres dans le lobby avec personnage ; `minPlayers` ; cooldown | `Config.Party.modeCooldown` : 1 s | non | Lance via `gf_core:SetMode` ; en cas d'échec partiel, restaure l'état et prévient le chef. |
| `baseevents:onPlayerKilled` | `[cfx-default] baseevents/deathevents.lua` (client) | killerId client ignoré ; tueur dérivé de `lastDamager` (< `Config.KillCreditWindow` = 10 s, même mode), victime réellement morte si `Config.ValidateDeathHealth`, anti-doublon 1,5 s, distance max `Config.MaxKillDistance` | aucun dédié ; anti-doublon 1,5 s et refus journalisé au plus 1/min/joueur | non | Le tueur vient exclusivement de `weaponDamageEvent` côté serveur ; l'arme du client ne sert que si le serveur n'en a pas enregistré. Sans dégât serveur récent, aucun kill n'est crédité. |
| `baseevents:onPlayerDied` | `[cfx-default] baseevents/deathevents.lua` (client) | mêmes règles que `onPlayerKilled`, sans arme fournie | aucun dédié ; anti-doublon 1,5 s | non | Mort sans tueur identifié : `killer = nil`, sauf dégât serveur récent. |
| `baseevents:onPlayerWasted` | `[cfx-default] baseevents/deathevents.lua` (client) | aucune (événement cfx-default, non traité par gf_core) | aucun | non | Enregistré par `baseevents/server.lua` ; aucun handler gf_core ne l'écoute. Tout client peut l'émettre, sans effet sur le jeu. |
| `baseevents:enteringVehicle` | `[cfx-default] baseevents/vehiclechecker.lua` (client) | aucune (événement cfx-default, non traité par gf_core) | aucun | non | Enregistré par `baseevents/server.lua`. Arguments à traiter comme non fiables si une ressource les écoute un jour. |
| `baseevents:enteringAborted` | `[cfx-default] baseevents/vehiclechecker.lua` (client) | aucune (événement cfx-default, non traité par gf_core) | aucun | non | Enregistré par `baseevents/server.lua`. |
| `baseevents:enteredVehicle` | `[cfx-default] baseevents/vehiclechecker.lua` (client) | aucune (événement cfx-default, non traité par gf_core) | aucun | non | Enregistré par `baseevents/server.lua`. |
| `baseevents:leftVehicle` | `[cfx-default] baseevents/vehiclechecker.lua` (client) | aucune (événement cfx-default, non traité par gf_core) | aucun | non | Enregistré par `baseevents/server.lua`. |

## Détail : validation du véhicule de mode

`gf_core:vehicle` reçoit un netId créé côté client (`CreateVehicle` dans
`gf_core/client.lua`) puis le transmet au serveur. `gf_core/server.lua` appelle
le module pur `gf_core/validation.lua` avec les natives en dépendances :

1. `Validation.normaliserNetId` refuse `nil`, `0`, les négatifs, les décimaux,
   les chaînes non numériques, les booléens, les tables, NaN et l'infini.
2. `NetworkGetEntityFromNetworkId` doit renvoyer une entité qui existe.
3. `GetEntityType` doit valoir `2` (véhicule).
4. `NetworkGetEntityOwner` doit être égal à `src` : un joueur ne peut pas
   revendiquer le véhicule d'un autre.
5. `Validation.distance` entre l'entité et le péd du joueur doit être
   inférieure ou égale à `Config.VehicleBindDistance` (50 m par défaut).

Ce n'est qu'après ces contrôles que `Vehicles[src]` est renseigné. Un refus ne
modifie pas l'ancien véhicule ; le message de log est limité par
`Config.RefusLogRateLimit` (1 par minute et par joueur) pour éviter le spam.

Le rate-limit de l'événement (`Config.VehicleRateLimit`, 5 tentatives par
10 secondes) est consommé avant la validation, pour qu'un client qui boucle ne
puisse pas saturer les natives.

**Véhicules créés côté serveur** : il n'y en a aucun aujourd'hui dans le dépôt
(le seul `CreateVehicle` est dans `gf_core/client.lua`). Si un mode en crée un
plus tard, son propriétaire réseau n'est pas le joueur : il ne doit pas passer
par `gf_core:vehicle`, mais être enregistré directement côté serveur dans un
registre séparé, puis supprimé par `deleteVehicle`.

## Détail : créditation des kills

Avant ce durcissement, `baseevents:onPlayerKilled` utilisait le `killerId`
fourni par le client : un client pouvait s'attribuer un kill, en attribuer un à
un autre ou fausser l'anti-teamkill.

Désormais :

1. `weaponDamageEvent` est un événement déclenché par le serveur pour chaque
   dégât. gf_core annule les dégâts interdits (coéquipier, joueur protégé,
   modes différents, lobby, règle `AllowDamage` du mode). **Après tous les
   `CancelEvent()`**, donc uniquement pour un dégât autorisé, il enregistre
   `lastDamager[victime] = { src = tireur, at = GetGameTimer(), weapon = ... }`
   si le tireur n'est pas la victime.
2. `handleDeath` ignore totalement le tueur fourni par le client. Il lit
   `lastDamager[victime]`, efface l'entrée, puis crédite le tireur seulement si
   le dégât a moins de `Config.KillCreditWindow` secondes (10 par défaut) et si
   le tireur est dans le même mode que la victime (`Modes[tireur] == mode`).
3. Si le client fournit une arme, elle sert à l'affichage ; sinon l'arme
   enregistrée par `weaponDamageEvent` est utilisée.
4. La victime doit être réellement morte côté serveur : `GetPlayerPed(victime)`
   existe et `GetEntityHealth(ped) <= 0`. La vérification est contrôlée par
   `Config.ValidateDeathHealth` (activée par défaut). Si des morts légitimes
   sont rejetées sur un serveur donné, passe-la à `false` et surveille les
   logs de refus.
5. `lastDamager` est nettoyé à la déconnexion du joueur (`playerDropped`),
   y compris les entrées où il était le tireur.

Conséquences : un kill sans dégât serveur récent n'est **jamais** crédité. Une
mort par chute, noyade ou autre source sans `weaponDamageEvent` a donc
`killer = nil`, ce qui est le comportement attendu. L'anti-doublon de 1,5 s
évite qu'un client rejoue la même mort.

## Rate-limits

Le module pur `gf_core/rate_limit.lua` implémente une fenêtre glissante par
clé. Le serveur l'utilise avec une table par événement, une clé par joueur, et
`GetGameTimer()` comme horloge :

- `Config.VehicleRateLimit` : 5 / 10 s pour `gf_core:vehicle` ;
- `Config.VehicleGoneRateLimit` : 5 / 10 s pour `gf_core:vehicleGone` ;
- `Config.ReadyRateLimit` : 1 / 5 s pour `gf_core:ready` ;
- `Config.RequestCooldownMs` : 500 ms pour `gf_lobby:requestState` et
  `gf_lobby:requestPlayers` ;
- `Config.RefusLogRateLimit` : 1 / 60 s pour les messages de refus.

Les états sont supprimés dans `playerDropped`, sinon un identifiant de session
réutilisé hériterait du compteur du joueur précédent.

## Ajouter un événement client → serveur

1. Déclarer `RegisterNetEvent('mon:event')` et `AddEventHandler` dans un
   `server_script` de la ressource.
2. Valider `source` (joueur connecté) et chaque argument ; ne jamais faire
   confiance au client pour un identifiant d'entité, une position ou un score.
3. Ajouter un rate-limit si l'événement peut être déclenché souvent.
4. Vérifier les droits avec `core:IsAdmin(src)` s'il modifie la configuration
   ou les maps.
5. Ajouter la ligne dans le tableau ci-dessus.
6. Lancer `python -m unittest discover -s tests -v` : le contrat échouera tant
   que l'événement n'est pas déclaré côté serveur, documenté et, le cas
   échéant, protégé.

## Événements serveur internes (non déclenchables par un client)

Ces événements sont émis par le serveur lui-même (`TriggerEvent`) ou par
FiveM. Ils ne passent pas par `RegisterNetEvent` et ne font pas partie de la
surface client → serveur, mais ils sont documentés pour la cohérence.

| Événement | Émetteur | Validation | Rate-limit | Admin requis | Notes |
|---|---|---|---|---|---|
| `gf:modeJoined` | `gf_core/server.lua` (`setMode`) | interne, jamais reçu du réseau | aucun | non | Écouté par `gf_attack` et `gf_redzone` pour placer le joueur. |
| `gf:modeLeft` | `gf_core/server.lua` (`setMode`, `playerDropped`) | interne, jamais reçu du réseau | aucun | non | Permet aux modes de nettoyer leurs équipes et scores. |
| `gf:playerKilled` | `gf_core/server.lua` (`handleDeath`) | tueur déjà validé ou `nil` | aucun | non | Consommé par les modes pour les scores ; l'arme peut être `nil`. |
| `weaponDamageEvent` | FiveM (serveur) | event serveur natif, non déclenché par un client | aucun | non | Sert de source de vérité pour `lastDamager` après les annulations de dégâts. |
