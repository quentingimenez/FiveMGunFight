<!--
  Modèle de description de pull request (méthode : docs/methode/README.md).
  Remplis chaque section ; supprime les commentaires. Une pull request vide,
  vague ou sans fiche d'impact (niveaux M et L) sera renvoyée à l'auteur.
-->

## Résumé

<!-- Une ou deux phrases : ce que fait cette pull request. -->

## Pourquoi

<!-- Le bug, la demande, la contrainte, le ticket : #numéro si applicable. -->

## Fiche d'impact

<!--
  Remplie AVANT le code : docs/methode/fiche-impact.md.
  Niveau S : Demande, Où et Contrats touchés (avec la raison du « aucun ») suffisent.
-->

- **Niveau** : S | M | L — <pourquoi>
- **Critères d'acceptation** :
  1. …
- **Où** : <ressources et fichiers>
- **Contrats touchés** : aucun | <exports, événements, state bags, calques NUI, données, textes joueur — avec appelants et écouteurs trouvés>
- **Recherches faites** : <commandes, nombre de résultats>
- **Décision produit ou d'architecture** : aucune | <ADR nnnn>

## Tests et preuve

<!--
  Niveaux exigés par la matrice : docs/methode/strategie-de-test.md.
  Pour chaque test ajouté : vu rouge avant le code, puis vert ; ce qui a été saboté.
  Pour l'exécution locale : commande lancée et résultat observé (sortie, log, capture).
-->

- **Niveaux couverts** : T0 · T1 · T2 · T3 · T4 · T5 · T6
- **Tests ajoutés, vus rouges puis verts** : …
- **Sabotage** : <invariant cassé dans le code du produit, test qui a échoué>
- **Exécution locale** : <commande, résultat>
- **Playtest humain (T6)** : non requis | <scénario, résultat>

## Captures

<!-- Si l'interface ou le rendu en jeu change : avant / après. Sinon, supprime. -->

## Risques et retour arrière

<!-- Ce qui peut casser ailleurs, comment on le verrait, comment on revient en arrière (revert, migration descendante, réglage). -->

## Cause racine

<!--
  Correctif uniquement, sinon supprime. Une catégorie de docs/methode/README.md :
  exigence, effet-de-bord, contrat, plateforme, etat, calques-nui, asset.
  Dire pourquoi le défaut n'a pas été vu avant, et quel test l'empêche désormais.
-->

## Checklist

- [ ] Fiche d'impact remplie avant le code ; chaque appelant trouvé est adapté ou justifié
- [ ] Tests exigés par la matrice écrits d'abord, vus rouges, puis verts ; sabotage fait
- [ ] Les contrôles passent en local (`bash scripts/verifier-docker.sh`)
- [ ] Exécuté en local au niveau exigé, preuve ci-dessus ; critères d'acceptation cochés un par un
- [ ] Aucun secret ajouté (`.env`, clé de licence, mots de passe, identifiants admin)
- [ ] Capitalisé : test de régression, piège, ADR, registre des contrats, chantier, selon le cas
- [ ] Documentation mise à jour si le comportement, la configuration ou les fichiers changent
- [ ] Le serveur reste autoritaire : aucune décision de score ou de dégât déplacée côté client
- [ ] Un seul sujet, complet : code, tests et documentation ensemble
