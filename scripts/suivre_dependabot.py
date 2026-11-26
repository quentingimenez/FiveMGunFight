#!/usr/bin/env python3
"""Liste et classe les PR Dependabot ouvertes ; l'outil ne modifie rien.

Il ne commente pas, ne fusionne pas et ne ferme pas les PR : il affiche, pour
chacune, la montée de version et l'action à mener (rebase, diagnostiquer,
attendre, decider ou fusionner). À lancer au début d'une session :

  python scripts/suivre_dependabot.py
  python scripts/suivre_dependabot.py --depuis-json dependabot.json
  python scripts/suivre_dependabot.py --json --aujourdhui 2026-06-15

Les données viennent de `gh pr list` ; la variable GH choisit l'exécutable.
Avec --depuis-json, la même sortie JSON est lue depuis un fichier (tests,
hors-ligne).

Codes de sortie : 0 si la liste est vide ou si toutes les PR sont en attente,
1 si au moins une PR demande une action, 2 si le JSON est illisible, 3 si gh
est absent ou en échec.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime, timezone
from pathlib import Path

CHAMPS_GH = (
    "number,title,url,headRefName,createdAt,mergeable,statusCheckRollup,labels"
)
PAIRE_DE_VERSIONS = re.compile(r"\bfrom\s+(\S+)\s+to\s+(\S+)", re.IGNORECASE)
HEX = re.compile(r"^[0-9a-fA-F]{7,64}$")
CONCLUSIONS_ROUGES = {
    "FAILURE",
    "CANCELLED",
    "TIMED_OUT",
    "ACTION_REQUIRED",
    "STARTUP_FAILURE",
}
CONCLUSIONS_VERTES = {"SUCCESS", "NEUTRAL", "SKIPPED"}
ETATS_ROUGES = {"FAILURE", "ERROR"}
RANGS_MONTEE = {"majeure": 4, "mineure": 3, "correctif": 2, "digest": 1, "inconnue": 0}


def _nettoyer_version(jeton: str) -> str:
    """Retire les ponctuations qu'un titre peut coller à une version."""
    return jeton.strip("`'\"()[]{}.,;:!?")


def _composants(jeton: str) -> list[int] | None:
    """Composants numériques d'une version (préfixe « v » ignoré), sinon None."""
    texte = _nettoyer_version(jeton)
    if texte[:1] in ("v", "V"):
        texte = texte[1:]
    morceaux = texte.split(".")
    if not morceaux or any(not morceau.isdigit() for morceau in morceaux):
        return None
    return [int(morceau) for morceau in morceaux]


def _type_d_une_paire(avant: str, apres: str) -> str:
    """Compare deux versions : majeur, mineur, correctif ou digest."""
    avant = _nettoyer_version(avant)
    apres = _nettoyer_version(apres)
    if HEX.fullmatch(avant) and HEX.fullmatch(apres):
        return "digest"
    composants_avant = _composants(avant)
    composants_apres = _composants(apres)
    if composants_avant is None or composants_apres is None:
        return "inconnue"
    for indice in range(max(len(composants_avant), len(composants_apres))):
        valeur_avant = composants_avant[indice] if indice < len(composants_avant) else 0
        valeur_apres = composants_apres[indice] if indice < len(composants_apres) else 0
        if valeur_avant != valeur_apres:
            if indice == 0:
                return "majeure"
            if indice == 1:
                return "mineure"
            return "correctif"
    return "correctif"


def type_de_montee(titre: str) -> str:
    """Montée annoncée par le titre ; la plus forte si plusieurs paires."""
    montees = [
        _type_d_une_paire(avant, apres)
        for avant, apres in PAIRE_DE_VERSIONS.findall(titre or "")
    ]
    if not montees:
        return "inconnue"
    return max(montees, key=lambda montee: RANGS_MONTEE[montee])


def etat_checks(rollup: list[dict] | None) -> tuple[str, list[str]]:
    """État des checks : vert, rouge, en cours ou aucun, et noms des rouges."""
    if not rollup:
        return "aucun", []
    rouges: list[str] = []
    en_cours = False
    for check in rollup:
        if not isinstance(check, dict):
            en_cours = True
            continue
        est_status = check.get("__typename") == "StatusContext" or (
            "state" in check and "status" not in check
        )
        if est_status:
            etat = str(check.get("state") or "").upper()
            nom = str(check.get("context") or check.get("name") or "?")
            if etat in ETATS_ROUGES:
                rouges.append(nom)
            elif etat != "SUCCESS":
                en_cours = True
        else:
            statut = str(check.get("status") or "").upper()
            conclusion = str(check.get("conclusion") or "").upper()
            nom = str(check.get("name") or check.get("context") or "?")
            if conclusion in CONCLUSIONS_ROUGES:
                rouges.append(nom)
            elif statut != "COMPLETED" or conclusion not in CONCLUSIONS_VERTES:
                en_cours = True
    if rouges:
        return "rouge", rouges
    if en_cours:
        return "en cours", []
    return "vert", []


def age_jours(pr: dict, aujourdhui: date) -> int:
    """Nombre de jours entre createdAt et la date de référence (0 si illisible)."""
    texte = pr.get("createdAt")
    if not texte:
        return 0
    try:
        creation = datetime.fromisoformat(str(texte).replace("Z", "+00:00")).date()
    except ValueError:
        return 0
    return max(0, (aujourdhui - creation).days)


def action(pr: dict, aujourdhui: date) -> tuple[str, str]:
    """Action à mener sur une PR et consigne affichée, par ordre de priorité."""
    montee = type_de_montee(str(pr.get("title") or ""))
    etat, rouges = etat_checks(pr.get("statusCheckRollup"))

    if pr.get("mergeable") == "CONFLICTING":
        code = "rebase"
        phrase = (
            "conflit : commenter « @dependabot rebase » "
            "(avec l'accord de l'utilisateur)"
        )
    elif etat == "rouge":
        code = "diagnostiquer"
        noms = ", ".join(rouges) or "inconnu"
        phrase = (
            f"CI rouge ({noms}) : lire gh run view --log-failed, corriger par "
            "une PR séparée sur main puis « @dependabot rebase », ou refuser "
            "la montée"
        )
    elif etat in ("en cours", "aucun"):
        code = "attendre"
        phrase = "checks en cours"
    elif montee in ("majeure", "inconnue"):
        code = "decider"
        phrase = (
            f"montée {montee} : relire le changelog, tester en local, "
            "décision explicite de l'utilisateur"
        )
    else:
        code = "fusionner"
        phrase = (
            "vert : tester en local, accord de l'utilisateur, puis "
            f"bash scripts/fusionner-pr.sh {pr.get('number')}"
        )

    jours = age_jours(pr, aujourdhui)
    if jours >= 14:
        phrase += f" ; ouverte depuis {jours} jours"
    return code, phrase


def classer(prs: list[dict], aujourdhui: date) -> list[dict]:
    """Classe les PR par numéro croissant, avec l'action et la consigne."""
    resultat: list[dict] = []
    for pr in sorted(prs, key=lambda element: element.get("number") or 0):
        code, consigne = action(pr, aujourdhui)
        etat, rouges = etat_checks(pr.get("statusCheckRollup"))
        resultat.append(
            {
                "numero": pr.get("number"),
                "titre": pr.get("title"),
                "url": pr.get("url"),
                "montee": type_de_montee(str(pr.get("title") or "")),
                "checks": etat,
                "checks_rouges": rouges,
                "age_jours": age_jours(pr, aujourdhui),
                "action": code,
                "consigne": consigne,
            }
        )
    return resultat


def lister_prs() -> list[dict]:
    """Sortie JSON de `gh pr list` ; lève RuntimeError avec un message clair."""
    gh = os.environ.get("GH", "gh")
    commande = [
        gh,
        "pr",
        "list",
        "--author",
        "app/dependabot",
        "--state",
        "open",
        "--limit",
        "100",
        "--json",
        CHAMPS_GH,
    ]
    try:
        resultat = subprocess.run(
            commande,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError as erreur:
        raise RuntimeError(
            f"gh introuvable ou non exécutable ({gh}). Installe GitHub CLI puis "
            f"connecte-toi avec `gh auth login` ({erreur})."
        ) from erreur
    if resultat.returncode != 0:
        detail = (resultat.stderr or "").strip() or f"code {resultat.returncode}"
        raise RuntimeError(
            "gh a échoué (absent ou non authentifié) : "
            f"{detail}\nVérifie avec `gh auth status`."
        )
    try:
        prs = json.loads(resultat.stdout)
    except ValueError as erreur:
        raise RuntimeError(f"Sortie JSON de gh illisible : {erreur}") from erreur
    if not isinstance(prs, list) or any(not isinstance(pr, dict) for pr in prs):
        raise RuntimeError("Sortie JSON de gh invalide : liste d'objets PR attendue.")
    return prs


def _date_reference(texte: str) -> date:
    try:
        return datetime.strptime(texte, "%Y-%m-%d").date()
    except ValueError as erreur:
        raise argparse.ArgumentTypeError("date attendue au format AAAA-MM-JJ") from erreur


def _afficher_texte(resultat: list[dict]) -> None:
    if not resultat:
        print("Aucune PR Dependabot ouverte.")
        return
    print(f"{len(resultat)} PR Dependabot ouverte(s)")
    for pr in resultat:
        print(f"#{pr['numero']} [{pr['action']}] {pr['titre']}")
        print(f"  montée : {pr['montee']}")
        ligne_checks = pr["checks"]
        if pr["checks_rouges"]:
            ligne_checks += f" ({', '.join(pr['checks_rouges'])})"
        print(f"  checks : {ligne_checks}")
        age = "1 jour" if pr["age_jours"] == 1 else f"{pr['age_jours']} jours"
        print(f"  âge : {age}")
        print(f"  consigne : {pr['consigne']}")
        print(f"  url : {pr['url']}")


def main(argv: list[str] | None = None) -> int:
    analyseur = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        epilog=(
            "L'outil ne modifie RIEN : il ne commente pas, ne fusionne pas et "
            "ne ferme pas les PR."
        ),
    )
    analyseur.add_argument(
        "--depuis-json",
        metavar="FICHIER",
        type=Path,
        help="lit la sortie JSON de gh dans FICHIER au lieu d'appeler gh",
    )
    analyseur.add_argument(
        "--json",
        action="store_true",
        help="imprime le résultat classé en JSON au lieu du tableau texte",
    )
    analyseur.add_argument(
        "--aujourdhui",
        metavar="AAAA-MM-JJ",
        type=_date_reference,
        help="date de référence pour l'âge (défaut : aujourd'hui UTC)",
    )
    args = analyseur.parse_args(argv)
    aujourdhui = args.aujourdhui or datetime.now(timezone.utc).date()

    if args.depuis_json:
        try:
            prs = json.loads(args.depuis_json.read_text(encoding="utf-8"))
        except OSError as erreur:
            print(
                f"Fichier JSON illisible : {args.depuis_json} ({erreur})",
                file=sys.stderr,
            )
            return 2
        except ValueError as erreur:
            print(
                f"JSON illisible dans {args.depuis_json} : {erreur}",
                file=sys.stderr,
            )
            return 2
        if not isinstance(prs, list) or any(not isinstance(pr, dict) for pr in prs):
            print(
                f"JSON invalide dans {args.depuis_json} : "
                "liste d'objets PR attendue.",
                file=sys.stderr,
            )
            return 2
    else:
        try:
            prs = lister_prs()
        except RuntimeError as erreur:
            print(str(erreur), file=sys.stderr)
            return 3

    resultat = classer(prs, aujourdhui)
    if args.json:
        print(json.dumps(resultat, ensure_ascii=False, indent=2))
    else:
        _afficher_texte(resultat)
    return 1 if any(pr["action"] != "attendre" for pr in resultat) else 0


if __name__ == "__main__":
    sys.exit(main())
