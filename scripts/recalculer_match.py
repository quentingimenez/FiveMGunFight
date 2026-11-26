#!/usr/bin/env python3
"""Recalcule le classement d'un match à partir du journal JSON lines de gf_journal.

Usage :
    python scripts/recalculer_match.py [fichier|-] [--match ID]

Sans fichier ou avec `-`, le journal est lu sur l'entrée standard. Avec
`--match`, seules les lignes de ce match sont considérées ; sinon le dernier
match terminé du journal est pris (dernière ligne `resultats` ou `fin_match` ;
les lignes à `match_id` null sont ignorées). Le script affiche le classement
recalculé, le classement de référence (ligne `resultats`) et les écarts.

Règles de comptage (vérifiées dans le code serveur, à reproduire exactement) :

* `gf:modeKill` est l'événement unique émis par mort comptée, et c'est lui qui
  pilote `gf_stats` : son handler (`gf_stats/server.lua`, `AddEventHandler
  'gf:modeKill'`) incrémente `deaths` pour `data.victim` et `kills` pour
  `data.killer` uniquement si `data.killer` est vrai.
* Dans `gf_attack`, `AttackRules.mort` (`gf_attack/rules.lua`) incrémente
  `deaths` puis émet l'effet `statistiquesKill`, interprété par `executer`
  (`gf_attack/server.lua`) en `TriggerEvent('gf:modeKill', ...)` avec le tueur
  crédité ou `false`. Le tueur n'est crédité que s'il est dans une équipe
  différente de celle de la victime (coéquipier = `false`).
* Dans `gf_redzone`, le handler `gf:playerKilled` (`gf_redzone/server.lua`)
  incrémente `v.deaths` sans condition de phase, puis crédite `kills` seulement
  si `S.phase == 'live'` et si le tueur est dans la zone ; il émet ensuite
  `gf:modeKill` avec le tueur crédité ou `false`.
* Les morts comptent donc même hors phase `live` (les deux modes incrémentent
  `deaths` sans condition de phase), et un `killer = false` ne crédite aucun
  kill. En conséquence, le recalcul compte **deaths = une ligne `kill`**, et
  **kills = une ligne `kill` dont `tueur` est un joueur (objet), pas `false`**.
  Les lignes `mort` (`gf:playerKilled`) servent à enrichir/nommer la victime et
  à vérifier la cohérence, mais une mort sans ligne `kill` n'a pas été comptée
  par le mode (par exemple victime hors équipe en Attaque) : elle ne doit pas
  incrémenter `deaths`. Elle n'ajoute personne au roster.
* Roster : la source initiale est la liste `joueurs` de la ligne `debut_match`
  (cf. `gf:matchStarted` dans `gf_attack/server.lua`, `gf_redzone/server.lua`
  et le handler `gf_journal/server.lua`) : chaque entrée porte un `joueur`
  (avec `id` license) et une `equipe` (A/B en Attaque, absente en Redzone).
  Un joueur présent au coup d'envoi apparaît donc dans la table finale même à
  0 kill / 0 mort et sans autre ligne rattachée au match. Le roster est ensuite
  complété par les lignes `arrivee` et `kill` ; l'équipe conservée est la
  dernière connue (A ou B), les valeurs autres que A/B ne l'écrasent pas. Si
  `debut_match` n'a pas de `joueurs` (journal ancien), on retrouve le
  comportement historique sans erreur.
* Les joueurs sont clés par `joueur.id` de `debut_match` / `donnees.joueur.id`
  / `donnees.victime.id` / `donnees.tueur.id` (identifiant license). Si un
  identifiant manque, la ligne de comptage est ignorée : aucun identifiant
  n'est fabriqué.
* En Attaque, la table finale inclut les joueurs de `etat.equipes` et ceux de
  `etat.partis` (partis pendant le match) — voir `sendMatchResults`
  (`gf_attack/server.lua`) et `terminerManche` (`gf_attack/rules.lua`) : un
  joueur parti reste dans la table avec ses compteurs. En Redzone, `endGame`
  (`gf_redzone/server.lua`) ne classe que les joueurs encore dans `S.players` :
  un joueur avec une ligne `depart` avant la fin est exclu. Noms et équipes
  viennent de `debut_match`, des lignes `arrivee` et `kill` ; la ligne
  `resultats` ne sert qu'à la comparaison finale.
* Tri / comparaison : Attaque = kills décroissants, puis deaths croissants,
  puis nom croissant, comparés strictement dans l'ordre (même comparateur que
  `sendMatchResults`). Redzone = kills décroissants puis deaths croissants
  (même comparateur que `ranking()`), avec un repli déterministe par nom
  croissant pour le tri interne. `ranking()` utilise `table.sort` instable :
  deux joueurs à kills ET deaths égaux forment un groupe dont l'ordre interne
  est libre, et la comparaison redzone l'ignore (multi-ensemble nom/kills/deaths
  par groupe) ; seul l'ordre des groupes (couples kills/deaths) reste strict.

Aucun réseau, aucune base de données. Aucun identifiant de licence n'est
affiché : seuls les noms figurent dans les tableaux.

Codes de sortie : 0 si les tableaux sont identiques (ordre compris), 1 en cas
d'écart, 2 si le journal est illisible ou si le match est introuvable.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, TextIO

SORTIE_IDENTIQUE = 0
SORTIE_ECART = 1
SORTIE_ILLISIBLE = 2

TYPES_FIN = ("resultats", "fin_match")
EQUIPES = ("A", "B")


def charger_lignes(source: str | Path | TextIO) -> list[dict[str, Any]]:
    """Lit un journal JSON lines ; lève ValueError sur une ligne invalide.

    Une ligne vide est ignorée. Chaque ligne non vide doit être un objet JSON
    avec `type` (chaîne) et `donnees` (objet). `match_id` est une chaîne ou null
    (colonne NULLable : lignes avant-match sans match associé).
    """
    if isinstance(source, (str, Path)):
        if source == "-":
            texte = sys.stdin.read()
        else:
            texte = Path(source).read_text(encoding="utf-8")
    else:
        texte = source.read()

    lignes: list[dict[str, Any]] = []
    for numero, brute in enumerate(texte.splitlines(), start=1):
        if not brute.strip():
            continue
        try:
            objet = json.loads(brute)
        except ValueError as erreur:
            raise ValueError(f"JSON illisible ligne {numero} : {erreur}") from erreur
        if not isinstance(objet, dict):
            raise ValueError(f"ligne {numero} : objet JSON attendu")
        identifiant = objet.get("match_id")
        if identifiant is not None and not isinstance(identifiant, str):
            raise ValueError(f"ligne {numero} : match_id doit être une chaîne ou null")
        if not isinstance(objet.get("type"), str):
            raise ValueError(f"ligne {numero} : type est requis")
        if not isinstance(objet.get("donnees"), dict):
            raise ValueError(f"ligne {numero} : donnees doit être un objet")
        lignes.append(objet)
    return lignes


def choisir_match(
    lignes: list[dict[str, Any]], match: str | None
) -> tuple[str, list[dict[str, Any]]]:
    """Sélectionne les lignes d'un match ; lève ValueError s'il est introuvable.

    Les lignes sans `match_id` (null) sont ignorées. Sans identifiant explicite,
    prend la dernière ligne terminale du fichier (`resultats` ou `fin_match`)
    dont le `match_id` est une chaîne : un `fin_match` plus récent gagne donc sur
    un `resultats` ancien.
    """
    if match is not None:
        selection = [ligne for ligne in lignes if ligne["match_id"] == match]
        if not selection:
            raise ValueError(f"match introuvable : {match}")
        return match, selection

    for ligne in reversed(lignes):
        if ligne["type"] in TYPES_FIN and isinstance(ligne["match_id"], str):
            identifiant = ligne["match_id"]
            return identifiant, [
                element for element in lignes if element["match_id"] == identifiant
            ]
    raise ValueError("aucun match terminé (resultats ou fin_match) dans le journal")


def _identifiant(joueur: Any) -> str | None:
    """Identifiant license d'un joueur, ou None s'il est absent."""
    if not isinstance(joueur, dict):
        return None
    identifiant = joueur.get("id")
    return identifiant if isinstance(identifiant, str) and identifiant else None


def _nom(joueur: Any) -> str | None:
    """Nom affichable d'un joueur, ou None s'il est absent."""
    if not isinstance(joueur, dict):
        return None
    nom = joueur.get("nom")
    return nom if isinstance(nom, str) and nom else None


def _tri_attack(joueur: dict[str, Any]) -> tuple[int, int, str]:
    """Comparateur de `sendMatchResults` : kills desc, deaths asc, nom asc."""
    return (-joueur["kills"], joueur["deaths"], joueur["nom"])


def _tri_redzone(joueur: dict[str, Any]) -> tuple[int, int, str]:
    """Comparateur de `ranking()` avec repli déterministe par nom croissant."""
    return (-joueur["kills"], joueur["deaths"], joueur["nom"])


def recalculer(lignes: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], str | None]:
    """Recalcule la table finale et renvoie aussi le mode déclaré par les lignes.

    Le mode est lu dans la ligne (`ligne['mode']`), jamais dans `donnees`.
    """
    joueurs: dict[str, dict[str, Any]] = {}
    presents: set[str] = set()
    mode_declare: str | None = None

    def enregistrer(
        identifiant: str, joueur: Any, equipe: Any = None
    ) -> dict[str, Any]:
        """Crée ou met à jour un joueur du roster (sans fabriquer d'identifiant)."""
        fiche = joueurs.setdefault(
            identifiant,
            {
                "nom": _nom(joueur) or "?",
                "kills": 0,
                "deaths": 0,
                "equipe": None,
            },
        )
        nom = _nom(joueur)
        if nom:
            fiche["nom"] = nom
        if equipe in EQUIPES:
            fiche["equipe"] = equipe
        return fiche

    for ligne in lignes:
        if mode_declare is None and isinstance(ligne.get("mode"), str):
            mode_declare = ligne["mode"]
        type_ligne = ligne["type"]
        donnees = ligne["donnees"]

        if type_ligne == "debut_match":
            # Effectif au coup d'envoi : garde les joueurs à 0 kill / 0 mort
            # qui n'ont aucune autre ligne rattachée au match.
            joueurs_debut = donnees.get("joueurs")
            if isinstance(joueurs_debut, list):
                for entree in joueurs_debut:
                    if not isinstance(entree, dict):
                        continue
                    identifiant = _identifiant(entree.get("joueur"))
                    if identifiant is None:
                        continue
                    enregistrer(
                        identifiant, entree["joueur"], entree.get("equipe")
                    )
                    presents.add(identifiant)

        elif type_ligne in ("arrivee", "depart"):
            joueur = donnees.get("joueur")
            identifiant = _identifiant(joueur)
            if identifiant is None:
                continue
            enregistrer(identifiant, joueur, donnees.get("equipe"))
            if type_ligne == "arrivee":
                presents.add(identifiant)
            elif mode_declare != "attack":
                # En Attaque le joueur parti reste au classement (etat.partis) ;
                # en Redzone il est exclu (endGame ne classe que S.players).
                presents.discard(identifiant)

        elif type_ligne == "kill":
            victime = donnees.get("victime")
            identifiant = _identifiant(victime)
            if identifiant is None:
                continue
            fiche = enregistrer(
                identifiant,
                victime,
                donnees.get("equipe_victime"),
            )
            fiche["deaths"] += 1
            presents.add(identifiant)
            tueur = donnees.get("tueur")
            identifiant_tueur = _identifiant(tueur)
            # `false` (ou tout non-objet) ne crédite aucun kill.
            if identifiant_tueur is not None:
                auteur = enregistrer(
                    identifiant_tueur,
                    tueur,
                    donnees.get("equipe_tueur"),
                )
                auteur["kills"] += 1
                presents.add(identifiant_tueur)

        elif type_ligne == "mort":
            # gf:playerKilled : n'enrichit que les joueurs déjà au roster
            # (arrivee/kill) ; cette ligne ne compte pas et ne crée personne.
            for cle in ("victime", "tueur"):
                joueur = donnees.get(cle)
                identifiant = _identifiant(joueur)
                fiche = joueurs.get(identifiant) if identifiant is not None else None
                if fiche is None:
                    continue
                nom = _nom(joueur)
                if nom:
                    fiche["nom"] = nom
                if donnees.get(f"equipe_{cle}") in EQUIPES:
                    fiche["equipe"] = donnees[f"equipe_{cle}"]

    effectif = set(joueurs) if mode_declare == "attack" else presents
    table: list[dict[str, Any]] = []
    for identifiant in sorted(effectif):
        fiche = joueurs[identifiant]
        ligne_table: dict[str, Any] = {
            "nom": fiche["nom"],
            "kills": fiche["kills"],
            "deaths": fiche["deaths"],
        }
        if mode_declare == "attack":
            # Ne fabrique pas d'équipe : une absence doit apparaître comme telle.
            ligne_table["team"] = fiche["equipe"]
        table.append(ligne_table)

    cle_tri = _tri_attack if mode_declare == "attack" else _tri_redzone
    table.sort(key=cle_tri)
    return table, mode_declare


def _reference(lignes: list[dict[str, Any]]) -> list[dict[str, Any]] | None:
    """Dernière ligne `resultats` : table de référence, dans le format du calcul.

    Les lignes gf_journal utilisent `name`/`team` ; on les ramène aux clés
    `nom`/`equipe` de la table recalculée avant comparaison.
    """
    for ligne in reversed(lignes):
        if ligne["type"] == "resultats":
            rows = ligne["donnees"].get("rows")
            if not isinstance(rows, list):
                return None
            table: list[dict[str, Any]] = []
            for row in rows:
                if not isinstance(row, dict):
                    return None
                entree: dict[str, Any] = {
                    "nom": row.get("name", "?"),
                    "kills": row.get("kills", 0),
                    "deaths": row.get("deaths", 0),
                }
                if "team" in row:
                    entree["team"] = row["team"]
                table.append(entree)
            return table
    return None


def _format_joueur(joueur: dict[str, Any]) -> str:
    """Représentation lisible d'une ligne de table pour les écarts."""
    return (
        f"{joueur.get('nom', '?')} ({joueur.get('kills', 0)} kill(s), "
        f"{joueur.get('deaths', 0)} mort(s))"
    )


def _comparer_strict(
    recalcule: list[dict[str, Any]], reference: list[dict[str, Any]]
) -> list[str]:
    """Comparaison stricte, dans l'ordre (utilisée en Attaque)."""
    ecarts: list[str] = []
    if len(recalcule) != len(reference):
        ecarts.append(
            f"Nombre de joueurs : recalculé {len(recalcule)}, "
            f"référence {len(reference)}"
        )
    for rang in range(max(len(recalcule), len(reference))):
        gauche = recalcule[rang] if rang < len(recalcule) else None
        droite = reference[rang] if rang < len(reference) else None
        if gauche != droite:
            ecarts.append(
                f"Rang {rang + 1} : recalculé {_format_joueur(gauche) if gauche else None}, "
                f"référence {_format_joueur(droite) if droite else None}"
            )
    return ecarts


def _groupes_redzone(
    table: list[dict[str, Any]]
) -> list[tuple[tuple[int, int], list[tuple[str, int, int]]]]:
    """Regroupe les lignes consécutives de même couple (kills, deaths).

    ranking() (`table.sort` instable) ne définit pas l'ordre interne d'un
    groupe de joueurs à kills et deaths égaux : on compare donc chaque groupe
    comme un multi-ensemble de (nom, kills, deaths), sans tenir compte de
    l'ordre des lignes à l'intérieur du groupe. L'ordre des groupes, lui, reste
    strict.
    """
    groupes: list[tuple[tuple[int, int], list[tuple[str, int, int]]]] = []
    for joueur in table:
        couple = (joueur.get("kills", 0), joueur.get("deaths", 0))
        ligne = (
            str(joueur.get("nom", "?")),
            joueur.get("kills", 0),
            joueur.get("deaths", 0),
        )
        if groupes and groupes[-1][0] == couple:
            groupes[-1][1].append(ligne)
        else:
            groupes.append((couple, [ligne]))
    return groupes


def _comparer_redzone(
    recalcule: list[dict[str, Any]], reference: list[dict[str, Any]]
) -> list[str]:
    """Compare les groupes d'égalité Redzone dans l'ordre, sans ordre interne."""
    ecarts: list[str] = []
    groupes_g = _groupes_redzone(recalcule)
    groupes_d = _groupes_redzone(reference)
    if len(groupes_g) != len(groupes_d):
        ecarts.append(
            f"Nombre de groupes d'égalité : recalculé {len(groupes_g)}, "
            f"référence {len(groupes_d)}"
        )
    for rang in range(max(len(groupes_g), len(groupes_d))):
        gauche = groupes_g[rang] if rang < len(groupes_g) else None
        droite = groupes_d[rang] if rang < len(groupes_d) else None
        if gauche is None or droite is None:
            # Un seul des deux côtés a encore un groupe à ce rang.
            present = gauche or droite
            if present is not None:
                table = "référence" if gauche is None else "recalcul"
                ecarts.append(
                    f"Groupe {rang + 1} : présent seulement dans {table} "
                    f"(kills={present[0][0]}, deaths={present[0][1]})"
                )
            continue
        couple_g, lignes_g = gauche
        couple_d, lignes_d = droite
        if couple_g != couple_d:
            ecarts.append(
                f"Groupe {rang + 1} : recalculé kills={couple_g[0]}, "
                f"deaths={couple_g[1]}, référence kills={couple_d[0]}, "
                f"deaths={couple_d[1]}"
            )
            continue
        if sorted(lignes_g) != sorted(lignes_d):
            ecarts.append(
                f"Groupe {rang + 1} (kills={couple_g[0]}, deaths={couple_g[1]}) : "
                f"recalculé {sorted(lignes_g)}, référence {sorted(lignes_d)}"
            )
    return ecarts


def comparer(
    recalcule: list[dict[str, Any]],
    reference: list[dict[str, Any]],
    mode: str | None = None,
) -> list[str]:
    """Renvoie la liste des écarts entre les deux tables.

    En Attaque, la comparaison est stricte et dans l'ordre. En Redzone, les
    joueurs à kills ET deaths égaux forment un groupe dont l'ordre interne est
    libre (ranking() utilise un tri instable) : on compare les groupes dans
    l'ordre et les multi-ensembles de joueurs dans chaque groupe.
    """
    if mode == "redzone":
        return _comparer_redzone(recalcule, reference)
    return _comparer_strict(recalcule, reference)


def _afficher_table(titre: str, table: list[dict[str, Any]]) -> None:
    """Affiche une table sobre : nom, kills, morts (et équipe en Attaque)."""
    print(titre)
    if not table:
        print("  (vide)")
        return
    for rang, joueur in enumerate(table, start=1):
        equipe = f"  équipe={joueur['team']}" if "team" in joueur else ""
        print(
            f"  {rang}. {joueur.get('nom', '?')} : "
            f"{joueur.get('kills', 0)} kill(s), "
            f"{joueur.get('deaths', 0)} mort(s){equipe}"
        )


def main(argv: list[str] | None = None) -> int:
    """Point d'entrée : lit le journal, recalcule, compare et affiche."""
    analyseur = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        epilog="Codes de sortie : 0 identique, 1 écart, 2 données illisibles.",
    )
    analyseur.add_argument(
        "fichier",
        nargs="?",
        default="-",
        help="journal JSON lines (défaut : entrée standard)",
    )
    analyseur.add_argument(
        "--match", metavar="ID", help="identifiant du match à vérifier"
    )
    args = analyseur.parse_args(argv)

    try:
        lignes = charger_lignes(args.fichier)
        identifiant, selection = choisir_match(lignes, args.match)
    except (OSError, ValueError) as erreur:
        print(f"Journal illisible : {erreur}", file=sys.stderr)
        return SORTIE_ILLISIBLE

    try:
        table, mode = recalculer(selection)
    except (KeyError, TypeError) as erreur:
        print(f"Recalcul impossible : {erreur}", file=sys.stderr)
        return SORTIE_ILLISIBLE

    reference = _reference(selection)
    if reference is None:
        print(
            f"Match {identifiant} : aucune ligne resultats exploitable.",
            file=sys.stderr,
        )
        return SORTIE_ILLISIBLE

    print(f"Match {identifiant} (mode {mode or 'inconnu'})")
    _afficher_table("Classement recalculé :", table)
    _afficher_table("Classement de référence :", reference)
    ecarts = comparer(table, reference, mode)
    if ecarts:
        print("Écarts :")
        for ecart in ecarts:
            print(f"  - {ecart}")
        return SORTIE_ECART
    if mode == "redzone":
        print(
            "Écarts : aucun (classements identiques, ordre des groupes "
            "d'égalité compris)."
        )
    else:
        print("Écarts : aucun (classements identiques, ordre compris).")
    return SORTIE_IDENTIQUE


if __name__ == "__main__":
    sys.exit(main())
