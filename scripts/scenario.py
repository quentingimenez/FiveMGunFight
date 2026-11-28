#!/usr/bin/env python3
"""Rejoue un scénario console : commandes rcon et lignes de journal attendues.

Un scénario est un fichier JSON ``{"nom": "...", "etapes": [...]}`` où chaque
étape est l'une de ces quatre formes :

* ``{"rcon": "commande"}`` : envoie la commande à la console par le protocole
  de ``scripts/fivem_rcon.py`` ;
* ``{"attendre": "texte", "delai": secondes}`` : attend le texte dans le journal ;
* ``{"absent": "texte"}`` : échoue si le texte est apparu depuis le début ;
* ``{"pause": secondes}`` : attend un nombre de secondes.

Le journal n'est lu qu'à partir du nombre de lignes présentes au lancement du
scénario : les lignes anciennes ne comptent pas. Celui-ci s'arrête à la
première étape en échec.

Codes de sortie : 0 scénario réussi, 1 étape en échec, 2 scénario invalide ou
mot de passe rcon absent.

  python scripts/scenario.py scripts/scenarios/manche-attaque.json

Le cœur ``executer_scenario`` est injectable (rcon et journal) et se teste sans
réseau ni Docker.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable

RACINE = Path(__file__).resolve().parents[1]
SCRIPTS = RACINE / "scripts"
FICHIER_RCON = SCRIPTS / "fivem_rcon.py"
COMMANDE_JOURNAL = [
    "docker",
    "compose",
    "-f",
    "docker-compose.yml",
    "-f",
    "docker-compose.dev.yml",
    "logs",
    "--no-color",
    "fxserver",
]
INTERVALLE_JOURNAL = 0.5


def _charger_fivem_rcon():
    """Importe le protocole rcon du dépôt, sans le dupliquer."""
    if "fivem_rcon" in sys.modules:
        return sys.modules["fivem_rcon"]
    if str(SCRIPTS) not in sys.path:
        sys.path.insert(0, str(SCRIPTS))
    spec = importlib.util.spec_from_file_location("fivem_rcon", FICHIER_RCON)
    module = importlib.util.module_from_spec(spec)
    sys.modules["fivem_rcon"] = module
    spec.loader.exec_module(module)
    return module


fivem_rcon = _charger_fivem_rcon()


class ScenarioInvalide(Exception):
    """Scénario JSON illisible ou structure incorrecte."""


def charger_scenario(chemin: Path) -> dict:
    """Lit un fichier JSON et renvoie un scénario validé."""
    try:
        donnees = json.loads(chemin.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ScenarioInvalide(f"impossible de lire {chemin} : {exc}") from exc
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ScenarioInvalide(f"JSON illisible dans {chemin} : {exc}") from exc
    valider_scenario(donnees)
    return donnees


def valider_scenario(donnees: object) -> None:
    """Vérifie la structure du scénario, lève ScenarioInvalide sinon."""
    if not isinstance(donnees, dict):
        raise ScenarioInvalide("le scénario doit être un objet JSON")
    if not isinstance(donnees.get("nom"), str) or not donnees["nom"].strip():
        raise ScenarioInvalide("le champ 'nom' doit être une chaîne non vide")
    etapes = donnees.get("etapes")
    if not isinstance(etapes, list) or not etapes:
        raise ScenarioInvalide("le champ 'etapes' doit être une liste non vide")
    for index, etape in enumerate(etapes):
        if not isinstance(etape, dict):
            raise ScenarioInvalide(f"étape {index + 1} : objet attendu")
        cles = set(etape)
        if cles == {"rcon"}:
            if not isinstance(etape["rcon"], str) or not etape["rcon"].strip():
                raise ScenarioInvalide(f"étape {index + 1} : 'rcon' doit être une chaîne non vide")
        elif cles == {"attendre", "delai"}:
            if not isinstance(etape["attendre"], str) or not etape["attendre"]:
                raise ScenarioInvalide(f"étape {index + 1} : 'attendre' doit être une chaîne non vide")
            if not _est_un_delai(etape["delai"]):
                raise ScenarioInvalide(f"étape {index + 1} : 'delai' doit être un nombre positif")
        elif cles == {"absent"}:
            if not isinstance(etape["absent"], str) or not etape["absent"]:
                raise ScenarioInvalide(f"étape {index + 1} : 'absent' doit être une chaîne non vide")
        elif cles == {"pause"}:
            if not _est_un_delai(etape["pause"]):
                raise ScenarioInvalide(f"étape {index + 1} : 'pause' doit être un nombre positif ou nul")
        else:
            raise ScenarioInvalide(f"étape {index + 1} : étape inconnue ou champs incorrects : {sorted(cles)}")


def _est_un_delai(valeur: object) -> bool:
    return isinstance(valeur, (int, float)) and not isinstance(valeur, bool) and valeur >= 0


def _lire_journal_commandes() -> list[str]:
    """Lit le journal fxserver et renvoie ses lignes (texte, utf-8 tolérant)."""
    resultat = subprocess.run(
        COMMANDE_JOURNAL,
        capture_output=True,
        check=False,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    sortie = (resultat.stdout or "") + (resultat.stderr or "")
    return sortie.splitlines()


def executer_scenario(
    scenario: dict,
    envoyer_rcon: Callable[[str], str | None],
    lire_journal: Callable[[], list[str]],
    delai_max: float | None = None,
) -> int:
    """Joue les étapes, affiche un résultat par étape et renvoie le code final.

    ``envoyer_rcon`` renvoie la réponse rcon décodée, ou None en cas d'erreur
    réseau. ``lire_journal`` renvoie les lignes courantes du journal. Le
    décompte des lignes se fait au premier appel, avant toute étape.
    """
    valider_scenario(scenario)
    print(f"Scénario : {scenario['nom']}")

    nombre_initial = 0
    try:
        nombre_initial = len(lire_journal())
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        print(f"échec lecture journal initiale : {exc}")
        return 1

    for index, etape in enumerate(scenario["etapes"], start=1):
        titre = f"étape {index}/{len(scenario['etapes'])}"
        if "rcon" in etape:
            try:
                reponse = envoyer_rcon(etape["rcon"])
            except Exception as exc:  # un callable injecté peut lever n'importe quoi
                print(f"{titre} rcon {etape['rcon']!r} : échec — {exc}")
                return 1
            if reponse is None:
                print(f"{titre} rcon {etape['rcon']!r} : échec — aucune réponse")
                return 1
            if fivem_rcon.refus(reponse):
                print(f"{titre} rcon {etape['rcon']!r} : échec — {reponse.strip()}")
                return 1
            print(f"{titre} rcon {etape['rcon']!r} : ok")
        elif "attendre" in etape:
            delai = etape["delai"]
            if delai_max is not None:
                delai = min(delai, delai_max)
            texte = etape["attendre"]
            echeance = time.monotonic() + delai
            trouve = False
            while True:
                try:
                    lignes = lire_journal()[nombre_initial:]
                except (OSError, subprocess.SubprocessError, ValueError) as exc:
                    print(f"{titre} attendre {texte!r} : échec — journal illisible : {exc}")
                    return 1
                if any(texte in ligne for ligne in lignes):
                    trouve = True
                    break
                if time.monotonic() >= echeance:
                    break
                time.sleep(min(INTERVALLE_JOURNAL, max(0.0, echeance - time.monotonic())))
            if not trouve:
                print(f"{titre} attendre {texte!r} : échec — délai de {delai:g} s dépassé")
                return 1
            print(f"{titre} attendre {texte!r} : ok")
        elif "absent" in etape:
            texte = etape["absent"]
            try:
                lignes = lire_journal()[nombre_initial:]
            except (OSError, subprocess.SubprocessError, ValueError) as exc:
                print(f"{titre} absent {texte!r} : échec — journal illisible : {exc}")
                return 1
            if any(texte in ligne for ligne in lignes):
                print(f"{titre} absent {texte!r} : échec — texte présent dans le journal")
                return 1
            print(f"{titre} absent {texte!r} : ok")
        else:  # pause
            duree = etape["pause"]
            time.sleep(duree)
            print(f"{titre} pause {duree:g} s : ok")
    return 0


def _envoyer_rcon_reel(hote: str, port: int, mot_de_passe: str, delai: float) -> Callable[[str], str | None]:
    """Fabrique le callable rcon à partir du protocole de fivem_rcon.py."""

    def envoyer_rcon(commande: str) -> str | None:
        try:
            datagramme = fivem_rcon.paquet(mot_de_passe, commande)
            reponses = fivem_rcon.envoyer(hote, port, datagramme, delai)
        except (OSError, ValueError) as exc:
            print(f"erreur rcon : {exc}", file=sys.stderr)
            return None
        return "".join(fivem_rcon.decoder(reponse) for reponse in reponses) or None

    return envoyer_rcon


def main(argv: list[str] | None = None) -> int:
    analyseur = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    analyseur.add_argument("scenario", type=Path, help="fichier JSON du scénario")
    analyseur.add_argument("--journal-cmd", default=None, help="commande de lecture du journal")
    analyseur.add_argument("--delai-max", type=float, default=None, help="plafond des délais d'attente (s)")
    analyseur.add_argument("--hote", default="127.0.0.1")
    analyseur.add_argument("--port", type=int, default=30120)
    analyseur.add_argument("--delai-rcon", type=float, default=5.0)
    args = analyseur.parse_args(argv)

    if args.delai_max is not None and not _est_un_delai(args.delai_max):
        print("--delai-max doit être un nombre positif", file=sys.stderr)
        return 2
    try:
        scenario = charger_scenario(args.scenario)
    except ScenarioInvalide as exc:
        print(str(exc), file=sys.stderr)
        return 2

    mot_de_passe = fivem_rcon.lire_mot_de_passe(
        fivem_rcon.FICHIER_MOT_DE_PASSE, dict(os.environ)
    )
    if not mot_de_passe:
        print(
            f"Mot de passe rcon introuvable ({fivem_rcon.FICHIER_MOT_DE_PASSE}).\n"
            "rcon n'est actif qu'avec la surcouche docker-compose.dev.yml et TXADMIN=false.",
            file=sys.stderr,
        )
        return 2

    commandes = args.journal_cmd
    if commandes is None:
        lire_journal = _lire_journal_commandes
    else:

        def lire_journal() -> list[str]:
            resultat = subprocess.run(
                commandes,
                shell=True,
                capture_output=True,
                check=False,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            return ((resultat.stdout or "") + (resultat.stderr or "")).splitlines()

    return executer_scenario(
        scenario,
        _envoyer_rcon_reel(args.hote, args.port, mot_de_passe, args.delai_rcon),
        lire_journal,
        delai_max=args.delai_max,
    )


if __name__ == "__main__":
    sys.exit(main())
