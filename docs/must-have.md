# Must Have — fonctionnalités à venir

Cahier des charges des fonctionnalités prévues pour le serveur Gunfight,
classées par **ordre de construction** : chaque bloc s'appuie sur les
précédents. Ce document sert de feuille de route ; chaque ligne deviendra une
ou plusieurs pull requests.

Légende : ✅ en place · 🟡 base prête dans le code · ⬜ à faire

---

## 0. Ce qui existe déjà

| Élément | État | Où |
|---|---|---|
| Menu du lobby (Jouer, Apparence, Caisses, Classement) | 🟡 branche `feat/menu-lobby` | `gf_lobby` |
| Choix de 2 armes parmi les armes possédées, validé côté serveur | 🟡 branche `feat/attaque-vehicules-armes-spectateur` | `gf_core` (`ownedWeapons`, `resolveSelection`) |
| Catalogue d'armes avec accessoires et couleur | 🟡 | `gf_core/config.lua` (`Config.Weapons`) |
| Liste des caisses (affichage seulement) | 🟡 | `gf_lobby/config.lua` (`Config.Crates`) |
| Statistiques kills / morts persistantes | ✅ | `gf_stats` (`gf_stats_players`) |
| Maps cochables (base du vote) | ✅ | `gf_maps` (`GetActiveMaps`) |
| Base de données MariaDB | ✅ utilisée par `gf_stats` | `docker-compose.yml`, `mysql_connection_string` |

---

## 1. Socle : profil joueur en base de données  ⬜ *(prérequis de tout le reste)*

Tout ce qui suit doit être **enregistré par joueur et ne jamais être décidé par
le client**. Avant toute nouvelle fonctionnalité :

- Installer **oxmysql** et créer le schéma (scripts dans `docker/db/init/`).
- Une table `players` (identifiant = licence Rockstar, pseudo, dates).
- Migrer l'apparence et les statistiques de `gf_lobby/data/*.json` vers la base.
- Une ressource dédiée (ex. `gf_profile`) qui charge le profil à la connexion,
  le garde en mémoire et expose des exports (`GetProfile`, `AddCurrency`…).
- Toutes les opérations sur les monnaies / objets passent par le serveur, dans
  des **transactions SQL** (pas de doublon en cas de déconnexion ou de spam).

---

## 2. Monnaies

| Monnaie | Utilité | Comment on l'obtient | État |
|---|---|---|---|
| **Diamants** | ouvrir les caisses | en jouant (kills, victoires, missions) | ⬜ |
| **Rubis** | monnaie rare | **uniquement** : top 3 des kills en Attaque de zone, ou victoire en Redzone | ⬜ |
| **Coins** | boutique | achetés (argent réel) | ⬜ — voir § 10 *Règles Cfx.re* |

- Solde affiché dans la barre du haut du menu du lobby.
- Historique des gains / dépenses en base (utile en cas de litige ou de triche).

### Multiplicateur d'activité  ⬜
- Multiplicateur de diamants qui augmente avec le temps de jeu actif,
  **jusqu'à ×3**.
- À définir : paliers (ex. ×1,5 après 1 h, ×2 après 2 h, ×3 après 4 h ?), remise
  à zéro (par jour ? après une absence ?), et ce qui compte comme « actif »
  (pas d'AFK au lobby).

---

## 3. Inventaire du joueur

| Catégorie | Contenu | État |
|---|---|---|
| **Armes** | armes custom débloquées (accessoires, couleur) ; seules les armes possédées sont jouables | 🟡 vérification déjà en place, inventaire à faire |
| **Véhicules** | véhicules débloqués, utilisés à la place de la Sultan (Redzone, Attaque) | ⬜ |
| **Cosmétiques** | tenues, sacs, etc., portés par-dessus l'apparence | ⬜ |

- Brancher `ownedWeapons(src)` de `gf_core` sur l'inventaire en base.
- Choix du véhicule et des cosmétiques équipés dans le menu du lobby.
- À décider : les joueurs gardent-ils des armes de base gratuites (sinon un
  nouveau joueur n'a rien pour jouer) ?

---

## 4. Caisses  ⬜

- Ouverture contre des **diamants** (le prix dépend de la caisse).
- Tirage **côté serveur uniquement**, avec des probabilités par rareté
  (Commun, Rare, Épique, Légendaire) affichées aux joueurs.
- Animation d'ouverture dans le menu du lobby, objet ajouté à l'inventaire.
- Gestion des doublons (conversion en diamants ? en fragments ?).

---

## 5. Statistiques et classement

| Statistique | État |
|---|---|
| Kills / morts / K/D | 🟡 (fichier JSON, à migrer en base) |
| Nombre de victoires en Attaque de zone | ⬜ |
| Nombre de parties jouées | ⬜ |

- Onglet Classement : trier par K/D, victoires, parties ; profil d'un joueur.

---

## 6. Missions quotidiennes  ⬜

- Plusieurs missions tirées chaque jour, liées au serveur, par exemple :
  « 20 kills en Attaque de zone », « gagner 1 partie », « faire un QUINTUPLÉ ».
- Récompenses : diamants, XP du pass de combat.
- Progression suivie côté serveur à partir des événements existants
  (`gf:playerKilled`, fin de manche, fin de partie).

---

## 7. Pass de combat  ⬜

- Niveaux gagnés avec de l'XP (parties, kills, missions).
- Deux pistes de récompenses : **gratuite** et **premium**.
- Missions propres au pass (hebdomadaires ?).
- Saisons : date de début / fin, remise à zéro des niveaux.
- Nouvel onglet « Pass » dans le menu du lobby.

---

## 8. Social

### Liste d'amis  ⬜
- Ajouter / retirer un ami, voir s'il est en ligne et dans quel mode.

### Groupes  ⬜
- Inviter des amis dans son groupe depuis le menu du lobby.
- Le chef lance la recherche : tout le groupe entre dans la file d'attente.
- **En Attaque de zone, le groupe est placé dans la même équipe**
  (l'équilibrage des équipes doit en tenir compte).

### Échanges entre joueurs  ⬜
- Proposition d'échange (objets ↔ objets), validée par les deux joueurs,
  réalisée **en une seule transaction serveur**.
- Protections : confirmation en deux temps, historique, objets non échangeables
  (récompenses du pass ? objets achetés ?). Voir aussi § 10.

---

## 9. Déjà prévu dans les échanges précédents

- **Vote de map** : en fin de partie, vote entre 9 maps tirées parmi les maps
  cochées dans `/maps` (Redzone et Attaque de zone).
- **Menu de lobby** : groupes et invitations (§ 8) à ajouter au menu existant.

---

## 10. Points de vigilance

### Règles Cfx.re / Tebex sur la monétisation  ⚠️ à vérifier avant de coder la boutique
FiveM encadre strictement la vente contre de l'argent réel (vente obligatoirement
via **Tebex**, restrictions sur ce qui peut être vendu). En particulier, des
**caisses au contenu aléatoire liées à de l'argent réel** (directement, ou via
des Coins convertibles en diamants) peuvent être considérées comme des jeux de
hasard / « loot boxes » et être interdites. De même, un système d'échange
d'objets obtenus contre de l'argent réel peut poser problème.

➡️ Avant de concevoir les Coins et la boutique, relire les conditions
actuelles de Cfx.re (Platform License Agreement, règles de monétisation) et de
Tebex, et garder **les caisses uniquement accessibles avec des diamants gagnés
en jouant**.

### Anti-triche
- Le client affiche, le serveur décide : gains, tirages, échanges, missions.
- Limiter les gains anormaux (kills trop rapprochés, parties abandonnées).
- Journal des transactions pour pouvoir annuler en cas d'abus.

### Données personnelles
- Les identifiants de joueurs restent en base, jamais dans le dépôt Git.
- Prévoir la suppression d'un compte sur demande.

---

## Ordre de construction proposé

1. Profil joueur en base de données (§ 1)
2. Diamants + statistiques complètes (§ 2, § 5)
3. Inventaire d'armes + ouverture des caisses (§ 3, § 4)
4. Missions quotidiennes + multiplicateur (§ 6, § 2)
5. Liste d'amis + groupes (§ 8) — et vote de map (§ 9)
6. Véhicules et cosmétiques (§ 3)
7. Pass de combat (§ 7)
8. Rubis, Coins et boutique — après vérification des règles (§ 2, § 10)
9. Échanges entre joueurs (§ 8)
