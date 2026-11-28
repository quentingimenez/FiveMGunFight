#!/usr/bin/env python3
"""Mesure le flux de correctifs d'un dépôt à partir de son historique Git.

L'outil est en lecture seule : il appelle uniquement `git log`, sans write,
sans commit et sans modifier l'arbre de travail. Il compte les commits par
type (titres Conventional Commits), le rapport correctifs/fonctionnalités,
les correctifs par portée et les chaînes « correctif après fonctionnalité »
de la même portée dans une fenêtre de quelques jours.

  python scripts/mesurer_flux.py --depot . --derniers 60
  python scripts/mesurer_flux.py --depot . --depuis 2026-11-26 --json
  python scripts/mesurer_flux.py --depot . --derniers 60 --jours 14

Codes de sortie : 0 si tout va bien, 2 si les arguments sont invalides ou si
le dossier n'est pas un dépôt Git (message clair sur stderr, sans traceback).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
SANS_PORTEE = "(sans portée)"
JOURS_DEFAUT = 7
TYPES_CONNUS = frozenset(
    {
        "build",
        "chore",
        "ci",
        "docs",
        "feat",
        "fix",
        "perf",
        "refactor",
        "revert",
        "style",
        "test",
    }
)
ENTETE = re.compile(
    r"^(?P<type>[A-Za-z][A-Za-z0-9-]*)"
    r"(?:\((?P<portee>[^()]+)\))?"
    r"(?P<rupture>!)?:[ \t]*(?P<sujet>.*)$"
)
NUMERO_PR = re.compile(r"\(#(\d+)\)")
PR_EN_FIN = re.compile(r"\s*\(#\d+\)\s*$")


class ErreurHistorique(RuntimeError):
    """L'historique Git n'a pas pu être lu (git absent ou dépôt invalide)."""


def _instant(texte: object) -> datetime | None:
    """Instant UTC d'une date %cI, ou None si elle est illisible."""
    try:
        valeur = datetime.fromisoformat(str(texte).strip().replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    if valeur.tzinfo is None:
        valeur = valeur.replace(tzinfo=timezone.utc)
    return valeur.astimezone(timezone.utc)


def _date_locale(texte: object) -> date | None:
    """Date telle qu'écrite dans %cI, sans conversion de fuseau."""
    try:
        return datetime.fromisoformat(str(texte).strip().replace("Z", "+00:00")).date()
    except (TypeError, ValueError):
        return None


def analyser_titre(titre: str) -> dict[str, object]:
    """Découpe un titre en type, portée, sujet, rupture et numéro de PR.

    Un titre sans type Conventional Commits reconnu est classé « autre ».
    La fonction est pure : elle ne touche ni à git ni au système de fichiers.
    """
    texte = (titre or "").strip()
    correspondance = ENTETE.fullmatch(texte)
    if correspondance is None:
        type_ = "autre"
        portee: str | None = None
        rupture = False
        sujet = texte
    else:
        brut = correspondance.group("type").lower()
        type_ = brut if brut in TYPES_CONNUS else "autre"
        portee = correspondance.group("portee")
        rupture = bool(correspondance.group("rupture"))
        sujet = correspondance.group("sujet").strip()
    numero = NUMERO_PR.search(texte)
    return {
        "type": type_,
        "portee": portee,
        "sujet": PR_EN_FIN.sub("", sujet).strip(),
        "rupture": rupture,
        "pr": int(numero.group(1)) if numero else None,
    }


def filtrer_fenetre(
    commits: list[dict[str, str]],
    derniers: int | None = None,
    depuis: str | date | None = None,
) -> list[dict[str, str]]:
    """Applique --derniers ou --depuis à une liste déjà triée du plus récent."""
    selection = list(commits)
    if derniers is not None:
        selection = selection[:derniers]
    if depuis is not None:
        date_depuis = date.fromisoformat(depuis) if isinstance(depuis, str) else depuis
        selection = [
            entree
            for entree in selection
            if (jour := _date_locale(entree.get("date"))) is not None
            and jour >= date_depuis
        ]
    return selection


def analyser(commits: list[dict[str, str]], jours: int = JOURS_DEFAUT) -> dict[str, object]:
    """Calcule les compteurs et les chaînes, sans effet de bord."""
    liste = list(commits)
    par_type: Counter[str] = Counter()
    par_portee: Counter[str] = Counter()
    feats: list[dict[str, object]] = []
    fixs: list[dict[str, object]] = []
    for entree in liste:
        titre = analyser_titre(str(entree.get("titre") or ""))
        par_type[str(titre["type"])] += 1
        complet = {**entree, **titre}
        if titre["type"] == "fix":
            par_portee[str(titre["portee"] or SANS_PORTEE)] += 1
            fixs.append(complet)
        elif titre["type"] == "feat":
            feats.append(complet)

    groupes: dict[str, dict[str, object]] = {}
    fix_attaches = 0
    for fix in fixs:
        date_fix = _instant(fix.get("date"))
        if date_fix is None:
            continue
        borne = date_fix - timedelta(days=jours)
        compatibles = []
        for feat in feats:
            if feat["portee"] != fix["portee"]:
                continue
            date_feat = _instant(feat.get("date"))
            if date_feat is not None and borne <= date_feat <= date_fix:
                compatibles.append((date_feat, str(feat["sha"]), feat))
        if not compatibles:
            continue
        _, _, feat = max(compatibles, key=lambda element: (element[0], element[1]))
        fix_attaches += 1
        sha_feat = str(feat["sha"])
        groupe = groupes.setdefault(
            sha_feat,
            {
                "sha": sha_feat[:7],
                "titre": feat["titre"],
                "portee": feat["portee"],
                "_date": _instant(feat.get("date")),
                "fix": [],
            },
        )
        liste_fix = groupe["fix"]
        assert isinstance(liste_fix, list)
        liste_fix.append({"sha": str(fix["sha"])[:7], "titre": fix["titre"]})

    chaines = [
        {
            "sha": groupe["sha"],
            "titre": groupe["titre"],
            "portee": groupe["portee"],
            "fix": groupe["fix"],
        }
        for groupe in sorted(
            groupes.values(),
            key=lambda groupe: (groupe["_date"], groupe["sha"]),
            reverse=True,
        )
    ]
    nombre_feats = par_type["feat"]
    nombre_fixs = len(fixs)
    return {
        "commits_analyses": len(liste),
        "commits_par_type": {cle: par_type[cle] for cle in sorted(par_type)},
        "rapport_fix_feat": nombre_fixs / nombre_feats if nombre_feats else None,
        "fix_par_portee": {cle: par_portee[cle] for cle in sorted(par_portee)},
        "chaines": chaines,
        "fix_apres_feat": fix_attaches,
        "part_fix_apres_feat": fix_attaches / nombre_fixs if nombre_fixs else 0.0,
    }


def lire_historique(depot: Path) -> list[dict[str, str]]:
    """Lit l'historique en lecture seule avec exactement un `git log`."""
    commande = ["git", "log", "--format=%H%x09%cI%x09%s"]
    try:
        resultat = subprocess.run(
            commande,
            cwd=str(depot),
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except OSError as erreur:
        raise ErreurHistorique(
            f"git introuvable ou non exécutable dans {depot} : {erreur}"
        ) from erreur
    if resultat.returncode != 0:
        detail = (resultat.stderr or "").strip() or f"code {resultat.returncode}"
        raise ErreurHistorique(
            f"{depot} n'est pas un dépôt git ou git a échoué : {detail}"
        )
    commits: list[dict[str, str]] = []
    for ligne in resultat.stdout.splitlines():
        if not ligne.strip():
            continue
        # Format %H%x09%cI%x09%s : sha, tabulation, date %cI, tabulation,
        # sujet. Le sujet peut contenir des tabulations : maxsplit=2 le garde
        # entier dans le troisième champ.
        parties = ligne.split("\t", 2)
        if len(parties) != 3 or not parties[0]:
            continue
        sha, date_iso, titre = parties
        commits.append({"sha": sha, "date": date_iso, "titre": titre})
    return commits


def _tableau(entetes: list[str], lignes: list[list[str]]) -> list[str]:
    """Tableau texte aligné, avec une ligne de séparation."""
    largeurs = [len(tete) for tete in entetes]
    for ligne in lignes:
        for indice, cellule in enumerate(ligne):
            largeurs[indice] = max(largeurs[indice], len(str(cellule)))

    def formatter(ligne: list[str]) -> str:
        return "  ".join(
            str(cellule).ljust(largeurs[indice])
            for indice, cellule in enumerate(ligne)
        ).rstrip()

    return [formatter(entetes), "  ".join("-" * largeur for largeur in largeurs)] + [
        formatter(ligne) for ligne in lignes
    ]


def _nombre(valeur: float) -> str:
    return f"{valeur:.2f}".replace(".", ",")


def _pourcentage(valeur: float) -> str:
    return f"{valeur * 100:.1f}".replace(".", ",") + " %"


def afficher_texte(resultat: dict[str, object]) -> None:
    """Rapport lisible en français, sans JSON."""
    fenetre = resultat["fenetre"]
    assert isinstance(fenetre, dict)
    print("Mesure du flux de correctifs")
    print("============================")
    print()
    if fenetre["derniers"] is not None:
        nombre = fenetre["derniers"]
        periode = (
            "1 dernier commit" if nombre == 1 else f"{nombre} derniers commits"
        )
    elif fenetre["depuis"] is not None:
        periode = f"depuis le {fenetre['depuis']}"
    else:
        periode = "historique complet"
    print(f"Fenêtre : {periode} ; chaînes sur {fenetre['jours']} jours")
    print(f"Commits analysés : {resultat['commits_analyses']}")
    print()
    print("Commits par type")
    print("----------------")
    par_type = resultat["commits_par_type"]
    assert isinstance(par_type, dict)
    for ligne in _tableau(
        ["type", "commits"], [[cle, str(valeur)] for cle, valeur in par_type.items()]
    ):
        print(ligne)
    rapport = resultat["rapport_fix_feat"]
    texte_rapport = (
        "indéfini (aucune fonctionnalité)"
        if rapport is None
        else _nombre(float(rapport))
    )
    print()
    print(f"Rapport fix/feat : {texte_rapport}")
    print()
    print("Correctifs par portée")
    print("---------------------")
    par_portee = resultat["fix_par_portee"]
    assert isinstance(par_portee, dict)
    for ligne in _tableau(
        ["portée", "correctifs"],
        [[cle, str(valeur)] for cle, valeur in par_portee.items()],
    ):
        print(ligne)
    print()
    print("Chaînes correctif après fonctionnalité")
    print("--------------------------------------")
    chaines = resultat["chaines"]
    assert isinstance(chaines, list)
    if not chaines:
        print("Aucune chaîne sur la période.")
    for chaine in chaines:
        print(f"{chaine['sha']}  {chaine['titre']}")
        for fix in chaine["fix"]:
            print(f"  - {fix['sha']}  {fix['titre']}")
    print()
    total_fix = sum(int(valeur) for valeur in par_portee.values())
    print(
        f"Correctifs après une fonctionnalité : "
        f"{resultat['fix_apres_feat']} / {total_fix}"
    )
    print(f"Part : {_pourcentage(float(resultat['part_fix_apres_feat']))}")


def afficher_json(resultat: dict[str, object]) -> None:
    """Un seul objet JSON valide sur stdout, sans texte décoratif."""
    print(json.dumps(resultat, ensure_ascii=False, indent=2))


def _entier_positif(texte: str) -> int:
    try:
        valeur = int(texte)
    except ValueError as erreur:
        raise argparse.ArgumentTypeError(f"entier attendu, reçu « {texte} »") from erreur
    if valeur <= 0:
        raise argparse.ArgumentTypeError(f"entier strictement positif attendu : {valeur}")
    return valeur


def _date_iso(texte: str) -> date:
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", texte) is None:
        raise argparse.ArgumentTypeError(f"date ISO invalide « {texte} » : AAAA-MM-JJ")
    try:
        return date.fromisoformat(texte)
    except ValueError as erreur:
        raise argparse.ArgumentTypeError(f"date ISO invalide « {texte} »") from erreur


def _forcer_utf8() -> None:
    """Garantit l'encodage UTF-8 des accents, y compris sous Windows."""
    reconfigurer = getattr(sys.stdout, "reconfigure", None)
    if callable(reconfigurer):
        try:
            reconfigurer(encoding="utf-8")
        except (OSError, ValueError):
            pass


def main(argv: list[str] | None = None) -> int:
    _forcer_utf8()
    analyseur = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        epilog="Lecture seule : aucun écrit n'est effectué dans le dépôt.",
    )
    analyseur.add_argument(
        "--depot",
        type=Path,
        default=RACINE,
        metavar="CHEMIN",
        help="dossier du dépôt à mesurer (défaut : racine du projet)",
    )
    fenetre = analyseur.add_mutually_exclusive_group()
    fenetre.add_argument(
        "--derniers",
        type=_entier_positif,
        metavar="N",
        help="n'examiner que les N commits les plus récents",
    )
    fenetre.add_argument(
        "--depuis",
        type=_date_iso,
        metavar="AAAA-MM-JJ",
        help="n'examiner que les commits de date >= AAAA-MM-JJ",
    )
    analyseur.add_argument(
        "--jours",
        type=_entier_positif,
        default=JOURS_DEFAUT,
        metavar="N",
        help="fenêtre des chaînes correctif après fonctionnalité (défaut : 7)",
    )
    analyseur.add_argument(
        "--json",
        action="store_true",
        help="sortie machine : un seul objet JSON sur stdout",
    )
    args = analyseur.parse_args(argv)

    try:
        commits = lire_historique(args.depot)
    except ErreurHistorique as erreur:
        print(str(erreur), file=sys.stderr)
        return 2

    commits = filtrer_fenetre(commits, args.derniers, args.depuis)
    resultat = analyser(commits, args.jours)
    resultat["fenetre"] = {
        "derniers": args.derniers,
        "depuis": args.depuis.isoformat() if args.depuis else None,
        "jours": args.jours,
    }
    if args.json:
        afficher_json(resultat)
    else:
        afficher_texte(resultat)
    return 0


if __name__ == "__main__":
    sys.exit(main())
