# Claude Code — FiveMGunFight

Claude Code ne lit que ce fichier : le déroulé obligatoire de toute session est
dans `AGENTS.md`, importé ici en entier.

@AGENTS.md

## Fusion : c'est l'agent qui la fait

Rappel des points d'`AGENTS.md` (§ 2, § 4.7, § 4.8) les plus souvent oubliés :

- L'accord de l'utilisateur pour pousser et ouvrir la PR vaut aussi pour la
  fusion. Ne jamais lui demander de fusionner, ne jamais finir un tour avec une
  PR verte encore ouverte.
- Juste après `gh pr create` : activer Auto-fix, **puis** suivre soi-même la CI
  jusqu'au bout avec `gh pr checks <numéro> --watch` (en arrière-plan). Auto-fix
  ne réveille la session que sur un échec, un conflit ou un commentaire, jamais
  quand tout passe au vert.
- Dès que tous les checks sont verts et la PR fusionnable :
  `gh pr merge <numéro> --squash`, puis le retour sur `main` du § 4.9.
- Le message de fin donne le lien de la PR et le sha du commit de fusion. Une
  PR qui ne peut pas être fusionnée est signalée comme bloquée, avec la raison
  (§ 7).
