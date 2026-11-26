"""Génère le catalogue de tatouages de la NUI depuis les collections GTA V.

Le dossier source contient un fichier JSON par collection (nom du fichier sans
extension = nom de collection). Ces fichiers proviennent des métadonnées
d'overlays de GTA V ; une copie pratique est publiée dans le dépôt public
`root-cause/v-tattoos` (https://github.com/root-cause/v-tattoos).

Exemple :
    python3 scripts/generer_tattoos.py --dossier /tmp/v-tattoos

Le fichier produit est volontairement compact : chaque tatouage est un tableau
[collection, overlay homme, overlay femme, zone, libellé]. La NUI choisit
l'overlay du genre courant et ignore une chaîne vide.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
SORTIE = (
    RACINE
    / "server-data"
    / "resources"
    / "[gunfight]"
    / "gf_lobby"
    / "html"
    / "data"
    / "tattoos.json"
)

ZONES = (
    "ZONE_HEAD",
    "ZONE_TORSO",
    "ZONE_LEFT_ARM",
    "ZONE_RIGHT_ARM",
    "ZONE_LEFT_LEG",
    "ZONE_RIGHT_LEG",
)


def identifiant(valeur: object) -> str | None:
    """Retourne un identifiant natif sur, ou None."""
    if not isinstance(valeur, str):
        return None
    if not 1 <= len(valeur) <= 64:
        return None
    if not all(caractere.isalnum() or caractere == "_" for caractere in valeur):
        return None
    return valeur


def charger(dossier: Path) -> tuple[list[list[str]], list[list[object]]]:
    collections: list[list[str]] = []
    tatouages: list[list[object]] = []
    vus: set[tuple[str, str, str]] = set()

    for chemin in sorted(dossier.glob("*.json")):
        collection = identifiant(chemin.stem)
        if collection is None:
            raise SystemExit(f"nom de collection invalide : {chemin.name}")
        entrees = json.loads(chemin.read_text(encoding="utf-8"))
        if not isinstance(entrees, list):
            raise SystemExit(f"{chemin.name} ne contient pas une liste")

        retenues = 0
        for entree in entrees:
            if not isinstance(entree, dict):
                continue
            homme = identifiant(entree.get("HashNameMale"))
            femme = identifiant(entree.get("HashNameFemale"))
            zone = entree.get("Zone")
            libelle = entree.get("LocalizedName")
            if not (homme or femme):
                continue
            if zone not in ZONES:
                raise SystemExit(f"{chemin.name} : zone inconnue {zone!r}")
            if not isinstance(libelle, str) or not libelle.strip():
                libelle = homme or femme
            cle = (collection, homme or "", femme or "")
            if cle in vus:
                continue
            vus.add(cle)
            tatouages.append([collection, homme or "", femme or "", zone, libelle.strip()])
            retenues += 1
        collections.append([collection, retenues])

    if not tatouages:
        raise SystemExit(f"aucun tatouage trouvé dans {dossier}")

    tatouages.sort(key=lambda item: (ZONES.index(str(item[3])), str(item[4]).casefold(), str(item[0]), str(item[1])))
    return collections, tatouages


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dossier", type=Path, required=True, help="dossier des collections JSON")
    parser.add_argument("--sortie", type=Path, default=SORTIE, help="fichier de sortie")
    arguments = parser.parse_args()

    collections, tatouages = charger(arguments.dossier)
    donnees = {
        "version": 1,
        "zones": list(ZONES),
        "collections": collections,
        "tattoos": tatouages,
    }
    arguments.sortie.parent.mkdir(parents=True, exist_ok=True)
    arguments.sortie.write_text(
        json.dumps(donnees, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        f"{len(tatouages)} tatouages, {len(collections)} collections "
        f"-> {arguments.sortie}"
    )


if __name__ == "__main__":
    main()
