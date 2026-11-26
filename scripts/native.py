#!/usr/bin/env python3
"""Signature d'un natif FiveM / GTA V, sans réseau.

docs.fivem.net/natives est une application JavaScript : un outil de lecture
web y reçoit toujours la même page, quel que soit le natif demandé. Ce script
lit à la place les bases publiques de runtime.fivem.net, téléchargées une
fois dans un cache local partagé par tous les worktrees.

Usage :
  python scripts/native.py --update                      # télécharge les bases (réseau)
  python scripts/native.py CreateRuntimeTextureFromImage # nom Lua
  python scripts/native.py CREATE_RUNTIME_TXD            # nom du natif
  python scripts/native.py 00000000786d8bc3              # hash vu dans le journal client
  python scripts/native.py --search runtime_texture      # noms qui contiennent ce fragment

Cache : $GF_NATIVES_DIR, sinon ~/.cache/fivem-natives.
Codes de sortie : 0 trouvé, 1 introuvable, 2 base absente ou illisible.
"""

from __future__ import annotations

import argparse
import json
import os
import string
import sys
import urllib.request
from pathlib import Path

SOURCES = {
    "natives.json": "https://runtime.fivem.net/doc/natives.json",
    "natives_cfx.json": "https://runtime.fivem.net/doc/natives_cfx.json",
}
MAX_RESULTATS = 40


def dossier_par_defaut() -> Path:
    env = os.environ.get("GF_NATIVES_DIR")
    return Path(env) if env else Path.home() / ".cache" / "fivem-natives"


def charger(dossier: Path) -> list[dict]:
    """Tous les natifs des deux bases, chacun avec `hash` et `ns`."""
    natifs: list[dict] = []
    for fichier in SOURCES:
        base = json.loads((dossier / fichier).read_text(encoding="utf-8"))
        for ns, entrees in base.items():
            for valeur_hash, natif in entrees.items():
                # Environ 1 000 natifs GTA n'ont pas de nom connu : FiveM les
                # expose en Lua sous N_0x<hash>.
                nom = natif.get("name") or valeur_hash
                natifs.append({**natif, "name": nom, "hash": valeur_hash, "ns": ns})
    return natifs


def nom_lua(nom: str) -> str:
    """Nom sous lequel le natif est appelé en Lua."""
    nom = nom.lstrip("_")
    if nom.startswith("0x"):
        return "N_" + nom.lower()
    return "".join(mot.capitalize() for mot in nom.split("_") if mot)


def _cle(nom: str) -> str:
    return nom.replace("_", "").lower()


def _hash(requete: str) -> int | None:
    texte = requete.lower()
    if texte.startswith("0x"):
        texte = texte[2:]
    elif len(texte) < 8:
        return None
    if not texte or any(c not in string.hexdigits for c in texte):
        return None
    return int(texte, 16)


def chercher(natifs: list[dict], requete: str) -> list[dict]:
    """Natifs dont le hash ou le nom (Lua ou natif) correspond exactement."""
    valeur = _hash(requete)
    if valeur is not None:
        return [n for n in natifs if int(n["hash"], 16) == valeur]
    cle = _cle(requete)
    return [n for n in natifs if _cle(n["name"]) == cle or _cle(nom_lua(n["name"])) == cle]


def rechercher(natifs: list[dict], fragment: str) -> list[dict]:
    """Natifs dont le nom contient le fragment, triés par nom."""
    cle = _cle(fragment)
    return sorted((n for n in natifs if cle in _cle(n["name"])), key=lambda n: n["name"])


def signature(natif: dict) -> str:
    params = ", ".join(f"{p.get('type', '?')} {p.get('name', '?')}" for p in natif.get("params", []))
    return f"{natif.get('results', 'void')} {nom_lua(natif['name'])}({params})"


def formater(natif: dict) -> str:
    lignes = [
        f"{natif['name']}  [{natif['ns']}, {natif.get('apiset', 'client')}, hash {natif['hash']}]",
        f"  {signature(natif)}",
    ]
    for param in natif.get("params", []):
        if param.get("description"):
            lignes.append(f"    {param['name']} : {param['description']}")
    if natif.get("resultsDescription"):
        lignes.append(f"    retour : {natif['resultsDescription']}")
    if natif.get("description"):
        lignes.append("  " + natif["description"].strip().replace("\n", "\n  "))
    return "\n".join(lignes)


def mettre_a_jour(dossier: Path) -> None:
    dossier.mkdir(parents=True, exist_ok=True)
    for fichier, url in SOURCES.items():
        with urllib.request.urlopen(url, timeout=60) as reponse:
            contenu = reponse.read()
        json.loads(contenu)  # refuse une page d'erreur
        temporaire = dossier / (fichier + ".tmp")
        temporaire.write_bytes(contenu)
        temporaire.replace(dossier / fichier)
        print(f"{fichier} : {len(contenu)} octets -> {dossier}")


def main(argv: list[str] | None = None) -> int:
    analyseur = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    analyseur.add_argument("requete", nargs="?", help="nom Lua, nom du natif ou hash")
    analyseur.add_argument("--search", metavar="FRAGMENT", help="liste les noms qui contiennent FRAGMENT")
    analyseur.add_argument("--update", action="store_true", help="télécharge les bases (réseau requis)")
    analyseur.add_argument("--dossier", type=Path, default=None, help="cache des bases")
    args = analyseur.parse_args(argv)
    dossier = args.dossier or dossier_par_defaut()

    if args.update:
        mettre_a_jour(dossier)
        if not args.requete and not args.search:
            return 0
    if not args.requete and not args.search:
        analyseur.print_usage(sys.stderr)
        return 2

    try:
        natifs = charger(dossier)
    except (OSError, ValueError) as erreur:
        print(
            f"Base des natifs absente ou illisible dans {dossier} ({erreur}).\n"
            "Lance une fois, avec le réseau : python scripts/native.py --update",
            file=sys.stderr,
        )
        return 2

    if args.search:
        trouves = rechercher(natifs, args.search)
        for natif in trouves[:MAX_RESULTATS]:
            print(f"{natif['name']:<50} {signature(natif)}  [{natif.get('apiset', 'client')}]")
        if len(trouves) > MAX_RESULTATS:
            print(f"... {len(trouves) - MAX_RESULTATS} autres : précise le fragment")
        return 0 if trouves else 1

    trouves = chercher(natifs, args.requete)
    if not trouves:
        print(
            f"Aucun natif « {args.requete} ». Essaie : python scripts/native.py --search <fragment>",
            file=sys.stderr,
        )
        return 1
    print("\n\n".join(formater(natif) for natif in trouves))
    return 0


if __name__ == "__main__":
    sys.exit(main())
