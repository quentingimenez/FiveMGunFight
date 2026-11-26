# Ajouter un modèle (véhicule, arme, tenue…) et sa photo dans les menus

Ce guide explique comment ajouter un nouveau modèle 3D au serveur et le faire
apparaître, avec sa photo, dans les menus. Tout est prévu pour survivre aux
mises à jour de la production.

## Vue d'ensemble

| Élément | Où | Qui s'en charge |
|---|---|---|
| Modèles 3D (`.yft`, `.ytd`, pièces) | `gf_vehicles/stream/` | `scripts/ajouter_vehicule.py` |
| Réglages (`vehicles.meta`, `handling.meta`…) | `gf_vehicles/data/<modèle>/` | `scripts/ajouter_vehicule.py` |
| Son du moteur (`.rel`, `.awc`) | `gf_vehicles/audioconfig/`, `gf_vehicles/sfx/` | `scripts/ajouter_vehicule.py` |
| Liste du menu | `Config.Vehicles` dans `gf_vehicles/config.lua` | `scripts/ajouter_vehicule.py` |
| Photo du menu | `gf_thumbs/thumbs/<famille>/<id>.png` | **automatique** : prise par le jeu d'un admin à son arrivée au lobby |
| Véhicule de base et customs | `gf_vehicles/custom/custom.json` | `/customveh` en jeu (admin) |

En production, `gf_thumbs/thumbs` et `gf_vehicles/custom` sont des **volumes**
(`gunfight-prod-thumbs`, `gunfight-prod-vehicles`) : ils ne sont pas effacés par
une mise à jour de l'image. Au démarrage, `GF_SEED_DATA=true` y **ajoute** ce que
l'image apporte de nouveau (`cp -Rn`, rien n'est écrasé). Ils sont sauvegardés
dans `jeu.tar.gz` par `scripts/sauvegarder.sh`.

## Ajouter un véhicule

### 1. Lancer le script

Le pack peut être un **dossier extrait** (contenant `stream/`, les `.meta`…) ou
directement un **`dlc.rpf`** non chiffré. Les `.zip`/`.rar` sont à extraire
d'abord.

```powershell
py scripts/ajouter_vehicule.py "C:\chemin\du\pack" --nom "Nom dans le menu" --essai
```

`--essai` montre ce qui serait fait sans rien écrire. Si tout est correct,
relance sans `--essai`. Options :

| Option | Effet |
|---|---|
| `--nom "…"` | nom affiché dans le menu (défaut : nom du modèle) |
| `--son lg247hemi57` | son de moteur à utiliser quand le pack n'en fournit pas (ici celui du Bison) |
| `--essai` | n'écrit rien, affiche seulement le résultat |

Le script :

- trouve le nom du modèle dans `vehicles.meta` (`<modelName>`) ;
- copie les modèles 3D, les réglages et le son ;
- **nettoie** les réglages : liens publicitaires dans `gameName` /
  `vehicleMakeName`, entrées de `carvariations.meta` pour des modèles absents
  du pack (elles font référence à des kits inexistants) ;
- déclare les fichiers dans `fxmanifest.lua` (`files {}` et `data_file`) et
  ajoute la ligne dans `Config.Vehicles` ;
- signale les textures trop lourdes (au-delà de 16 Mo, FXServer prévient d'un
  risque de chargement lent) et l'absence de son.

Il ne lance rien du pack : il ne lit et ne copie que des fichiers de données.

### 2. Redémarrer le serveur

Un véhicule ajouté ne se charge pas à chaud : `docker compose restart fxserver`
(avec la surcouche dev en local). Vérifier « Started resource gf_vehicles » sans
erreur dans les logs.

### 3. Photo : automatique

**Aucune action** : à la prochaine connexion d'un admin, une fois au lobby
(`Config.AutoCaptureDelay`, 8 s), son jeu prend les photos manquantes des
familles marquées `auto` (véhicules). L'écran affiche « Préparation des photos
des menus… » quelques secondes, puis le lobby revient. Jamais pendant une
partie. Ça marche aussi en production : la photo est écrite dans le volume
`thumbs`.

Pour **refaire** une photo à la main (après un changement de custom, par
exemple) : `/thumbs vehicles <modèle>` (ou `/thumbs vehicles` pour toutes).

Le véhicule est posé dans un studio
(boîte verte au-dessus de l'océan, midi), photographié de trois quarts avant à
partir de son modèle 3D, détouré (fond transparent) et recadré. La photo est
enregistrée dans `gf_thumbs/thumbs/vehicles/<modèle>.png` et s'affiche aussitôt
dans le menu. Elle reprend la custom du véhicule s'il en a une.

### 4. Livrer

Commite dans une branche, puis pull request (voir `CONTRIBUTING.md`) :
`server-data/resources/[gunfight]/gf_vehicles/` (stream, data, config, manifeste).
La photo n'est pas obligatoire dans la PR : chaque serveur la prend tout seul.
Si elle a déjà été prise en local (`gf_thumbs/thumbs/vehicles/<modèle>.png`),
la commiter évite seulement de la reprendre ailleurs.

La CI vérifie (`tests/test_depot.py`, classe `VehiculesDeclares`) que chaque
véhicule de `Config.Vehicles` a son `.yft`/`.ytd`, son `vehicles.meta` avec le
bon `<modelName>`, des réglages déclarés dans `files {}` et aucun lien dans ses
noms. Au déploiement suivant, la photo est ajoutée au volume de production sans
écraser celles prises sur le serveur.

## Photos des menus : comment ça marche

La ressource `gf_thumbs` est commune à tous les menus :

- **studio** (`client.lua`) : pose l'objet, cadre la caméra selon
  `GetModelDimensions`, puis la page NUI invisible capture l'image du jeu
  (technique de `citizenfx/screenshot-basic`), retire le vert, recadre l'objet
  dans la zone de son modèle 3D projeté (aucun texte d'interface ne peut entrer
  dans la photo) et renvoie un PNG transparent ;
- **serveur** (`server.lua`) : vérifie (admin, PNG, taille) puis écrit
  `thumbs/<famille>/<id>.png` ;
- **menus** : `exports.gf_thumbs:Get(famille, ids)` renvoie
  `{ [id] = 'data:image/png;base64,…' }` (à appeler dans un thread ; cache côté
  client, vidé quand une photo est refaite).

Familles existantes (`gf_thumbs/config.lua`, `Config.Kinds`) :

| Famille | Liste fournie par | Pose | Auto |
|---|---|---|---|
| `vehicles` | `exports.gf_vehicles:GetThumbList()` | véhicule de trois quarts avant | oui |
| `weapons` | `exports.gf_core:GetWeaponThumbList()` (catalogue `Config.Weapons`) | arme de profil | non (aucun menu ne les affiche encore) |

Photos automatiques : à l'arrivée au lobby, le client envoie
`gf_thumbs:lobbyReady` ; si c'est un admin, le serveur répond
`gf_thumbs:autoCapture` et son jeu photographie ce qui manque (familles `auto`).
`Config.AutoCapture = false` désactive le mécanisme.

## Ajouter une nouvelle famille (ex. tenues)

1. **Liste** : dans la ressource concernée, un export client qui renvoie
   `{ { id = 'identifiant', label = 'Nom' }, ... }` (identifiant :
   lettres, chiffres, `_`).
2. **Configuration** : une entrée dans `Config.Kinds` de `gf_thumbs/config.lua` :

   ```lua
   outfits = {
       provider = { resource = 'gf_lobby', export = 'GetOutfitThumbList' },
       subject = 'outfit',
       width = 256, height = 384,
       auto = true, -- photos prises toutes seules dès qu'un menu les affiche
   },
   ```

3. **Pose** : un « subject » dans `Subjects` de `gf_thumbs/client.lua`, avec
   `spawn(id, pos)` qui crée l'entité (ex. un ped freemode habillé avec
   `SetPedComponentVariation`) et `view`, la direction de la caméra
   (`vector3(0.0, 1.0, 0.1)` pour une vue de face, `'side'` pour un profil).
4. **Dossier** : `gf_thumbs/thumbs/outfits/.gitkeep` (le serveur ne crée pas de
   dossier tout seul).
5. **Menu** : `exports.gf_thumbs:Get('outfits', ids)` pour récupérer les photos.
6. Rien d'autre : avec `auto = true`, les photos se prennent à la prochaine
   arrivée d'un admin au lobby.

Rien à changer pour la production : le volume `thumbs` contient toutes les
familles.

## Dépannage

| Symptôme | Cause / solution |
|---|---|
| Le véhicule n'apparaît pas, « Modèle inconnu » en console F8 | serveur non redémarré, ou FiveM pas complètement quitté ; vérifie `Started resource gf_vehicles` dans les logs |
| Véhicule invisible quelques secondes | textures trop lourdes (avertissement « oversized » au démarrage) : réduire la `.ytd` (OpenIV, textures en 2K/1K) |
| Véhicule silencieux | le son du pack est absent : relance le script avec `--son lg247hemi57` |
| `Modèle 3D … absent du pack` | le pack ne contient que les `.meta` : il faut le dossier `stream/` ou le `dlc.rpf` complet |
| `archive chiffrée` | le `dlc.rpf` est chiffré : extrais-le avec OpenIV ou CodeWalker, puis donne le dossier au script |
| Photo absente dans le menu | elle se prend à la prochaine arrivée d'un admin au lobby ; sinon `/thumbs vehicles <modèle>` et regarde la console F8 (`[gf_thumbs] …`) |
| Bord vert autour de la photo | véhicule peint en vert vif : prends la photo avec une autre custom |
| `Photo … non enregistrée` | dossier `thumbs/<famille>/` manquant ou volume en lecture seule (`chown -R 10001:10001` sur Unraid) |
