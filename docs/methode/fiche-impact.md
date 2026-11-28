# Fiche d'impact

La fiche se remplit en **P1 Situer**, avant la première ligne de code
([méthode](README.md)). Elle oblige à regarder le projet autour du
changement : ce qu'il touche, qui en dépend, comment on saura qu'il marche.
Elle va telle quelle dans la description de la PR (section « Fiche
d'impact » du modèle) ; pour un producteur délégué, elle va dans le brief.

Niveau S : seules les lignes « Demande », « Où » et « Contrats touchés »
(avec la raison du « aucun ») sont exigées.

## Modèle

```markdown
### Fiche d'impact

- **Demande** : <reformulation en une ou deux phrases>
- **Niveau** : S | M | L — <pourquoi>
- **Critères d'acceptation** :
  1. <fait observable, mesurable, avec la commande ou le scénario qui le montre>
  2. …
- **Où** : <ressources et fichiers qui changent>
- **Contrats touchés** (aucun / liste) :
  - exports : <ressource:Export> — appelants trouvés : <fichiers>
  - événements `gf:*` ou `gf_<ressource>:*` : <nom> — émetteurs / écouteurs : <fichiers>
  - state bags, GlobalState : <clé> — écrivains / lecteurs : <fichiers>
  - calques NUI, focus : <ressource> — autres pages ouvertes en même temps : <liste>
  - données : <table, fichier JSON, KVP> — propriétaire : <ressource>
  - commandes, touches, textes vus par le joueur : <liste>
- **Recherches faites** : <commandes lancées, nombre de résultats>
- **Risques** : <ce qui peut casser ailleurs, et comment on le verra>
- **Décision produit ou d'architecture** : aucune / <question posée, réponse, ADR n°>
- **Plan de test** (niveaux de [strategie-de-test.md](strategie-de-test.md)) :
  - T1/T2 : <tests écrits d'abord, ce qu'ils cassent s'ils échouent>
  - T3 : <contrat ou structure vérifiés>
  - T4/T5 : <scénario de démarrage, rcon, NUI, capture>
  - T6 : <playtest humain nécessaire ? oui/non, scénario>
- **Hors sujet repéré** : <dette vue et non traitée → chantier>
```

## Trouver ce qu'un changement touche

Le registre des contrats répond en premier : [`docs/contrats.md`](../contrats.md)
(généré) et les `contrat.json` de chaque ressource disent qui fournit, appelle,
émet ou écoute quoi. Il ne voit pas les appels faits à travers une variable :
pour ceux-là, et pour confirmer, on cherche dans
`server-data/resources/` avec `rg` (ou l'outil de recherche de l'agent) :

| Question | Recherche |
|---|---|
| Qui appelle cet export ? | `rg -n "exports\.gf_core[:.]IsAdmin\|exports\['gf_core'\]" server-data/resources` |
| Qui écoute cet événement ? | `rg -n "'gf:matchEnded'" server-data/resources` (émetteurs : `TriggerEvent`, `TriggerClientEvent`, `TriggerServerEvent` ; écouteurs : `AddEventHandler`, `RegisterNetEvent`) |
| Qui lit ou écrit ce state bag ? | `rg -n "gf_mode" server-data/resources` (`.state.gf_mode`, `state:set('gf_mode'`, `AddStateBagChangeHandler`) |
| Quelles pages NUI peuvent être ouvertes en même temps ? | `rg -n "SetNuiFocus\|menuOverlay" server-data/resources` |
| Qui dépend d'une ressource sans le déclarer ? | `rg -n "GetResourceState\('gf_attack'\)" server-data/resources`, puis comparer aux `dependencies` des `fxmanifest.lua` |
| Qui possède cette table ? | `rg -n "gf_match_events" server-data/resources` et `gf_db/migrations/` |
| Quels textes montrent cette commande au joueur ? | `rg -n "/whoami" server-data/resources docs README.md` |
| Quels tests couvrent ce fichier ? | `rg -ln "gf_lobby/server.lua" tests` |

Chaque résultat est lu, pas seulement compté : un appelant trouvé est soit
adapté dans la même PR, soit justifié comme non concerné dans la fiche.

## Exemple : la suppression du chat (#89), refaite avec la fiche

Ce qui s'est passé : en travaillant sur le panneau admin, le chat a été
supprimé « au passage » (18 fichiers, 5 ressources). L'utilisateur l'a fait
remettre (#94), puis retirer à nouveau (#114) ; des indices de commande
pointaient encore vers le chat (#116).

Avec la fiche :

- **Demande** : panneau admin F10. Le retrait du chat n'en fait pas partie.
- **Décision produit** : « retirer le chat » est une décision produit, donc
  P0 l'arrête. La question est posée à l'utilisateur ; sa réponse
  (« oui, définitivement ») donne un ADR et une PR séparée.
- **Contrats touchés** : la ressource `chat` (`ensure chat` dans
  `server.cfg`), l'événement `chat:addMessage` (émis par gf_core, gf_lobby,
  gf_maps), les suggestions de commandes, la section CHAT du menu pause,
  les textes « tape /… dans le chat » (`rg -n "chat" server-data/resources
  docs README.md`).
- **Risques** : un message serveur n'arrive plus nulle part ; un indice
  envoie le joueur vers un chat absent.
- **Plan de test** : T2 sur les notifications de gf_ui, T4 démarrage sans
  `chat`, T5 capture d'un message serveur reçu.

Résultat attendu : une seule PR, décidée, complète. Au lieu de quatre.
