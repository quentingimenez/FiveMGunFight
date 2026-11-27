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
- **réinitialiser le personnage** (`resetchar`).

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
- `customveh` : personnalisation du véhicule de base.

Chaque bouton exécute côté client la commande serveur existante au moyen de
`ExecuteCommand`. La source de la commande est l'administrateur : le serveur
revérifie ses droits avant de l'appliquer. La liste des commandes et leurs effets
sont décrits dans le [README](../README.md#4-commandes-en-jeu).

## Sécurité

- Les droits sont revérifiés côté serveur sur `gf_admin:requestData`
  (`core:IsAdmin(src)`) **et** sur chaque commande exécutée depuis le panneau,
  même si le client affiche déjà `isAdmin === true`.
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

## Limites connues

Le panneau ne propose pas encore : expulsion, téléportation, soin, gel,
annonce ou vue du joueur.

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
