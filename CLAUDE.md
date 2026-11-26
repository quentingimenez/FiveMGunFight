# Claude Code — FiveMGunFight

Claude Code ne lit que ce fichier : le déroulé obligatoire de toute session est
dans `AGENTS.md`, importé ici en entier.

@AGENTS.md

## Fusion : c'est l'agent qui la fait

Rappel des points d'`AGENTS.md` (§ 2, § 4.7, § 4.8) les plus souvent oubliés :

- L'accord de l'utilisateur pour pousser et ouvrir la PR vaut aussi pour la
  fusion. Ne jamais lui demander de fusionner, ne jamais finir un tour avec une
  PR verte encore ouverte.
- Juste après `gh pr create` : activer Auto-fix, **puis** lancer en
  arrière-plan `bash scripts/fusionner-pr.sh <numéro>`. Auto-fix ne réveille
  la session que sur un échec, un conflit ou un commentaire, jamais quand tout
  passe au vert ; le script, lui, attend les checks (`gh pr checks --watch`),
  fusionne en squash et suit la CI de `main` jusqu'au bout.
- Jamais `gh pr merge` à la main : la fusion sans suivi de `main` est ce qui
  laissait passer un `main` rouge. Puis le retour sur `main` du § 4.9.
- Le message de fin donne le lien de la PR, le sha du commit de fusion et le
  résultat de la CI de `main`. Une
  PR qui ne peut pas être fusionnée est signalée comme bloquée, avec la raison
  (§ 7).
