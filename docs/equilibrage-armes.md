# Équilibrage des armes

## À quoi sert ce tableau

Ce document accompagne le chantier C6 décrit dans
[chantiers-techniques.md](chantiers-techniques.md). Il s'appuie sur la règle A3
(pas de valeur magique) et sur la règle V8 (un chiffre vient d'une mesure ou
d'une source primaire) de [regles-de-code.md](regles-de-code.md) : toute valeur
d'équilibrage publiée doit pouvoir être rattachée à son origine.

Le tableau donne, pour les 11 armes de `Config.Weapons`
(`server-data/resources/[gunfight]/gf_core/config.lua`), le nombre de tirs et
les millisecondes nécessaires pour tuer, au corps et à la tête, à 10, 25 et 50
mètres, contre une cible de 100 PV et 100 de kevlar. Il sert de base à une
éventuelle décision de réglage (`SetWeaponDamageModifier`) : aucune valeur de
réglage n'est décidée ici. Le tableau est généré par
`scripts/equilibrage_armes.py`, dont la sortie est collée dans la section
« Tableau » plus bas.

## Source des données

Les données brutes proviennent des fichiers `weapon*.meta` du jeu, pour le
build 1.0.3889.0 en édition Legacy. Une même arme peut y être définie
plusieurs fois : la version située sous `update\update.rpf\` remplace
l'originale. Le script la choisit donc en priorité ; deux versions `update`
pour une même arme constituent une ambiguïté refusée, et non un choix arbitraire.

Ces fichiers appartiennent à Rockstar. Ils ne sont jamais commités dans le
dépôt et n'y sont jamais recopiés. Seules les valeurs numériques calculées à
partir de ces fichiers peuvent être publiées dans ce document.

## Comment extraire les fichiers

Avec CodeWalker (ou sa bibliothèque `CodeWalker.Core`, ou un explorateur RPF),
parcourir les archives RPF du jeu et copier tous les fichiers `weapon*.meta`
dans un dossier **hors du dépôt**, en conservant leur chemin d'archive. La
lecture des archives se fait en lecture seule : les fichiers du jeu ne sont pas
modifiés.

L'arborescence attendue dans le dossier de travail ressemble à ceci :

```text
<DOSSIER_META>\
├── update\update.rpf\common\data\ai\weapons.meta
└── x64w.rpf\dlcpacks\mpbusiness\dlc.rpf\common\data\ai\weaponheavypistol.meta
```

Le dossier reste hors du dépôt : aucun `weapon*.meta`, aucun fichier dérivé,
n'est ajouté à l'arbre de travail.

## Régénérer le tableau

Depuis la racine du dépôt :

```text
python scripts/equilibrage_armes.py <DOSSIER_META>
```

Le chemin par défaut de `--config` est
`server-data/resources/[gunfight]/gf_core/config.lua`. Les options acceptées
sont `--config CHEMIN`, `--format markdown|json` et `--distances 10,25,50`
(valeur par défaut). Aucune autre option n'est prévue.

Exemple concret avec un dossier situé hors du dépôt :

```text
python scripts/equilibrage_armes.py C:\Temp\meta
```

Le script sort en code 2 avec un message en français lorsqu'une arme de
`Config.Weapons` est introuvable, lorsqu'une arme est ambiguë (plusieurs
versions `update`), ou lorsqu'un champ nécessaire au calcul manque.

## Hypothèses de calcul

Les cinq hypothèses ci-dessous sont recopiées telles quelles. Chacune doit être
vérifiée en jeu avant d'être tenue pour certaine : elles traduisent des
conventions de calcul et des simplifications, pas des mesures.

**H1 — Atténuation.** `attenuation(d, mini, maxi, mod) = 1.0` si
`d <= mini` ; `mod` si `d >= maxi` ; sinon
`1 + (mod - 1) * (d - mini) / (maxi - mini)`.
**À VÉRIFIER EN JEU.** Une interpolation linéaire entre les deux bornes est
supposée ; le jeu pourrait appliquer une autre courbe d'atténuation.

**H2 — Dégât d'un tir.** `Damage * NetworkPlayerDamageModifier *
attenuation(...) * BulletsInBatch` (toutes les billes touchent), multiplié par
`NetworkHeadShotPlayerDamageModifier` si tête.
**À VÉRIFIER EN JEU.** La multiplication de ces modificateurs et le fait que
toutes les billes touchent sont des hypothèses sur le traitement réel des
dégâts réseau et du tir en jeu.
Mesure en jeu : GTA ajoute aussi un bonus de tir à la tête sur un joueur
proche (champs `HeadShotDamageModifierPlayer` et
`MaxHeadShotDistancePlayer`, absents de ce modèle) : une G36 faisait 396 à la
tête à 10 m, 29 de loin. Le serveur coupe ce bonus
(`SetPedSuffersCriticalHits(ped, false)` sur tous les joueurs,
`gf_core/client.lua`) ; les colonnes « tête » restent à confirmer en jeu.

**H3 — Points à retirer.** 200 = 100 PV + 100 de kevlar ; le kevlar absorbe les
dégâts à 100 %, tête comprise.
**À VÉRIFIER EN JEU.** Le comportement réel du kevlar, en particulier sur les
tirs à la tête, dépend de la configuration du serveur et du build chargé.

**H4 — Tirs pour tuer.** Le plus petit entier `n` tel que `n * degat >= points`,
calculé sans erreur d'arrondi flottante : `math.ceil(points / degat - 1e-9)`
(200 / 25 donne exactement 8, pas 9).
**À VÉRIFIER EN JEU.** La règle d'égalité et la correction d'arrondi sont une
convention de calcul ; seul le compte des tirs en jeu peut la confirmer.

**H5 — Millisecondes pour tuer.** `round((tirs - 1) * TimeBetweenShots * 1000)`
; le rechargement est ignoré ; `chargeur_suffit = tirs <= ClipSize` est indiqué
(astérisque quand le chargeur ne suffit pas).
**À VÉRIFIER EN JEU.** La cadence effective et l'absence de rechargement sont
des simplifications : la mesure en jeu reste nécessaire.

## Avertissement sur le build

Le serveur ne fixe pas `sv_enforceGameBuild` (chantier C5) : FiveM peut charger
un build différent de celui installé sur le poste. Les valeurs calculées ici
doivent donc être réextraites pour le build réellement utilisé par le serveur.
Le détail de ce verrou figure dans le
[chantier C5 de chantiers-techniques.md](chantiers-techniques.md). Aucun autre
identifiant de build que 1.0.3889.0 n'est avancé ici.

## Tableau

Build 1.0.3889.0 Legacy, cible à 100 PV et 100 de kevlar. La colonne « Dégât »
donne la valeur `Damage` brute du fichier, avant `NetworkPlayerDamageModifier`
(1,39 pour le fusil de précision, 1 pour les autres armes du tableau). Une tête
qui ne réduit pas le nombre de tirs correspond à
`NetworkHeadShotPlayerDamageModifier = 1` (fusil de précision, pistolet .50).

<!-- TABLEAU : généré par scripts/equilibrage_armes.py -->

| Arme | Dégât | Billes | Entre deux tirs (ms) | Chargeur | 10 m corps | 10 m tête | 25 m corps | 25 m tête | 50 m corps | 50 m tête |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WEAPON_CARBINERIFLE | 32 | 1 | 135 | 30 | 7 tirs / 810 ms | 4 tirs / 405 ms | 7 tirs / 810 ms | 4 tirs / 405 ms | 7 tirs / 810 ms | 4 tirs / 405 ms |
| WEAPON_ASSAULTRIFLE | 30 | 1 | 158 | 30 | 7 tirs / 948 ms | 4 tirs / 474 ms | 7 tirs / 948 ms | 4 tirs / 474 ms | 7 tirs / 948 ms | 5 tirs / 632 ms |
| WEAPON_SPECIALCARBINE | 32 | 1 | 135 | 30 | 7 tirs / 810 ms | 4 tirs / 405 ms | 7 tirs / 810 ms | 4 tirs / 405 ms | 7 tirs / 810 ms | 4 tirs / 405 ms |
| WEAPON_BULLPUPRIFLE | 32 | 1 | 120 | 30 | 7 tirs / 720 ms | 4 tirs / 360 ms | 7 tirs / 720 ms | 4 tirs / 360 ms | 7 tirs / 720 ms | 4 tirs / 360 ms |
| WEAPON_SMG | 22 | 1 | 118 | 30 | 10 tirs / 1062 ms | 4 tirs / 354 ms | 10 tirs / 1062 ms | 4 tirs / 354 ms | 10 tirs / 1062 ms | 4 tirs / 354 ms |
| WEAPON_COMBATPDW | 28 | 1 | 135 | 30 | 8 tirs / 945 ms | 3 tirs / 270 ms | 8 tirs / 945 ms | 3 tirs / 270 ms | 9 tirs / 1080 ms | 4 tirs / 405 ms |
| WEAPON_PUMPSHOTGUN | 29 | 8 | 800 | 8 | 1 tirs / 0 ms | 1 tirs / 0 ms | 2 tirs / 800 ms | 2 tirs / 800 ms | 3 tirs / 1600 ms | 3 tirs / 1600 ms |
| WEAPON_MARKSMANRIFLE | 65 | 1 | 300 | 8 | 3 tirs / 600 ms | 3 tirs / 600 ms | 3 tirs / 600 ms | 3 tirs / 600 ms | 3 tirs / 600 ms | 3 tirs / 600 ms |
| WEAPON_PISTOL | 26 | 1 | 370 | 12 | 8 tirs / 2590 ms | 4 tirs / 1110 ms | 8 tirs / 2590 ms | 4 tirs / 1110 ms | 9 tirs / 2960 ms | 5 tirs / 1480 ms |
| WEAPON_PISTOL50 | 51 | 1 | 520 | 9 | 4 tirs / 1560 ms | 4 tirs / 1560 ms | 4 tirs / 1560 ms | 4 tirs / 1560 ms | 4 tirs / 1560 ms | 4 tirs / 1560 ms |
| WEAPON_HEAVYPISTOL | 40 | 1 | 420 | 18 | 5 tirs / 1680 ms | 3 tirs / 840 ms | 5 tirs / 1680 ms | 3 tirs / 840 ms | 6 tirs / 2100 ms | 3 tirs / 840 ms |

* : le chargeur ne suffit pas pour le nombre de tirs indiqué ; le temps de rechargement est ignoré du calcul.


## Preuve attendue

La règle V8 et la section « Ce qui prouve un résultat » de
[regles-de-code.md](regles-de-code.md) fixent la preuve : le nombre de tirs
mesuré en jeu sur une cible à distance fixe doit être celui du tableau.

La mesure consiste à placer une cible à 10, 25 et 50 mètres, à compter les tirs
jusqu'à sa mort, puis à comparer le résultat à la cellule corps ou tête
correspondante du tableau. L'écart constaté remet en cause les hypothèses
ci-dessus et la valeur calculée, jamais l'inverse.

## Limites et prochaine étape

Le calcul ignore le rechargement, suppose que toutes les billes touchent, ne
modélise ni le mouvement ni la portée réelle, et considère un kevlar à 100 %.
Ces limites sont celles des hypothèses H1 à H5 et doivent rester visibles à la
lecture du tableau.

Une fois la preuve en jeu obtenue, le chantier C2 fournit les taux de choix et
la part des kills de chaque arme. Ce n'est qu'ensuite que des réglages
éventuels peuvent être décidés, avec leur source, conformément aux règles A3 et
V8.
