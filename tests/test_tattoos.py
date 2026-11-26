"""Tests du catalogue de tatouages vanilla du créateur de personnage.

Le fichier ``html/data/tattoos.json`` est généré par
``scripts/generer_tattoos.py`` à partir des collections publiques de
``root-cause/v-tattoos``. Ces tests vérifient la forme et la cohérence du
catalogue livré, pour qu'une régénération cassée ne passe pas inaperçue.

Lancement local :  python -m unittest discover -s tests -v
En CI          :  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
CATALOGUE = (
    RACINE
    / "server-data"
    / "resources"
    / "[gunfight]"
    / "gf_lobby"
    / "html"
    / "data"
    / "tattoos.json"
)

ZONES = {
    "ZONE_HEAD",
    "ZONE_TORSO",
    "ZONE_LEFT_ARM",
    "ZONE_RIGHT_ARM",
    "ZONE_LEFT_LEG",
    "ZONE_RIGHT_LEG",
}
COLLECTIONS = 24
TATTOOS = 775


class CatalogueTatouagesTest(unittest.TestCase):
    """Vérifie le catalogue compact livré avec la NUI."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.donnees = json.loads(CATALOGUE.read_text(encoding="utf-8"))

    def test_version_et_nombres(self) -> None:
        self.assertEqual(self.donnees["version"], 1)
        self.assertEqual(len(self.donnees["collections"]), COLLECTIONS)
        self.assertEqual(len(self.donnees["tattoos"]), TATTOOS)
        self.assertEqual(
            sum(int(entree[1]) for entree in self.donnees["collections"]),
            TATTOOS,
        )

    def test_zones(self) -> None:
        self.assertEqual(set(self.donnees["zones"]), ZONES)

    def test_entrees(self) -> None:
        collections = {
            nom: int(nombre) for nom, nombre in self.donnees["collections"]
        }
        vus: set[tuple[str, str]] = set()
        par_collection: dict[str, int] = {}
        for entree in self.donnees["tattoos"]:
            self.assertEqual(len(entree), 5, entree)
            collection, homme, femme, zone, libelle = entree
            self.assertIn(collection, collections, entree)
            self.assertIn(zone, ZONES, entree)
            self.assertTrue(homme or femme, entree)
            self.assertTrue(libelle, entree)
            self.assertNotIn((collection, homme or femme), vus, entree)
            vus.add((collection, homme or femme))
            par_collection[collection] = par_collection.get(collection, 0) + 1

        self.assertEqual(par_collection, collections)


if __name__ == "__main__":
    unittest.main()
