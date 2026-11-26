#!/usr/bin/env python3
"""Erreurs et messages du journal du client FiveM (Windows).

Lit le dernier CitizenFX_log_*.log, garde ce qui suit le dernier démarrage de
la ressource, regroupe les erreurs identiques et nomme le natif fautif quand
l'erreur ne donne que son hash (« script error in native 00000000786d8bc3 »).

  python scripts/journal_client.py --ressource gf_lobby
  python scripts/journal_client.py --ressource gf_lobby --messages
  python scripts/journal_client.py --fichier chemin/vers/CitizenFX_log.log

Codes de sortie : 0 aucune erreur, 1 au moins une erreur, 2 journal introuvable.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native

# « [     51547] [b3889_GTAProce]             MainThrd/ texte »
PREFIXE = re.compile(r"^\[\s*\d+\]\s+\[[^\]]*\]\s+.*?/ ")
ERREUR = re.compile(r"SCRIPT ERROR|script error|\^1|^> |Error loading|Failed to load")
NATIF = re.compile(r"script error in native ([0-9a-fA-F]+)")


def dossier_journaux() -> Path:
    base = os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local"))
    return Path(base) / "FiveM" / "FiveM.app" / "logs"


def texte(ligne: str) -> str:
    return PREFIXE.sub("", ligne.rstrip("\r\n"), count=1)


def depuis_demarrage(lignes: list[str], ressource: str) -> list[str]:
    """Lignes après le dernier chargement de la ressource (tout, sinon)."""
    marque = f"Creating script environments for {ressource}"
    for index in range(len(lignes) - 1, -1, -1):
        if texte(lignes[index]) == marque:
            return lignes[index + 1:]
    return lignes


def erreurs(lignes: list[str]) -> list[tuple[str, int]]:
    """Erreurs distinctes, dans l'ordre d'apparition, avec leur nombre."""
    comptes: dict[str, int] = {}
    for ligne in lignes:
        message = texte(ligne)
        if ERREUR.search(message):
            comptes[message] = comptes.get(message, 0) + 1
    return list(comptes.items())


def messages(lignes: list[str], ressource: str) -> list[str]:
    prefixe = f"[{ressource}]"
    return [texte(ligne) for ligne in lignes if texte(ligne).startswith(prefixe)]


def annoter(message: str, natifs: list[dict] | None) -> str:
    trouve = NATIF.search(message)
    if not trouve or not natifs:
        return message
    noms = native.chercher(natifs, trouve.group(1))
    if not noms:
        return message
    return message + "\n      = " + "\n      = ".join(
        f"{n['name']} : {native.signature(n)}" for n in noms
    )


def main(argv: list[str] | None = None) -> int:
    analyseur = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    analyseur.add_argument("--ressource", help="ne garder que ce qui suit son dernier démarrage")
    analyseur.add_argument("--messages", action="store_true", help="affiche aussi ses messages [ressource]")
    analyseur.add_argument("--fichier", type=Path, help="journal à lire (défaut : le plus récent)")
    args = analyseur.parse_args(argv)

    fichier = args.fichier
    if fichier is None:
        journaux = sorted(dossier_journaux().glob("CitizenFX_log_*.log"), key=lambda p: p.stat().st_mtime)
        if not journaux:
            print(f"Aucun journal dans {dossier_journaux()}", file=sys.stderr)
            return 2
        fichier = journaux[-1]
    try:
        lignes = fichier.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as erreur:
        print(f"Journal illisible : {fichier} ({erreur})", file=sys.stderr)
        return 2
    if args.ressource:
        lignes = depuis_demarrage(lignes, args.ressource)

    try:
        natifs = native.charger(native.dossier_par_defaut())
    except (OSError, ValueError):
        natifs = None

    print(f"Journal : {fichier} ({len(lignes)} lignes retenues)")
    if args.messages and args.ressource:
        for message in messages(lignes, args.ressource):
            print(f"  {message}")
    trouvees = erreurs(lignes)
    for message, nombre in trouvees:
        suffixe = f"  (x{nombre})" if nombre > 1 else ""
        print(f"  ERREUR {annoter(message + suffixe, natifs)}")
    if not trouvees:
        print("  aucune erreur")
    elif natifs is None and any(NATIF.search(m) for m, _ in trouvees):
        print("  (python scripts/native.py --update pour nommer les natifs)")
    return 1 if trouvees else 0


if __name__ == "__main__":
    sys.exit(main())
