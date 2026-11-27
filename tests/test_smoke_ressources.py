"""Tests de la vérification des ressources du job smoke.

La liste des ressources gunfight vérifiées par la CI ne doit plus être écrite
à la main dans le workflow : elle est extraite de server-data/server.cfg avec
un outil standard du runner Ubuntu. Ces tests gardent le workflow et la
configuration du serveur cohérents, sans démarrer Docker ni le serveur.

Lancement local :  python -m unittest discover -s tests -v
En CI          :  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
WORKFLOW = RACINE / ".github" / "workflows" / "docker.yml"
CONFIG_SERVEUR = RACINE / "server-data" / "server.cfg"


def lire(chemin: Path) -> str:
    return chemin.read_text(encoding="utf-8")


class SmokeRessources(unittest.TestCase):
    """Le smoke dérive sa liste de ressources de server.cfg."""

    def test_liste_ecrite_a_la_main_absente(self) -> None:
        workflow = lire(WORKFLOW)
        self.assertIsNone(
            re.search(r"for\s+r\s+in\s+gf_", workflow),
            "la boucle ne doit pas énumérer les ressources à la main",
        )
        self.assertNotIn("gf_db gf_journal", workflow)

    def test_extraction_depuis_server_cfg(self) -> None:
        workflow = lire(WORKFLOW)
        self.assertIn("server-data/server.cfg", workflow)
        self.assertTrue(
            re.search(r"\b(?:awk|grep|sed)\b", workflow),
            "l'extraction doit utiliser un outil standard du runner",
        )
        self.assertIn("$1 == \"ensure\"", workflow)

    def test_garde_fou_liste_vide(self) -> None:
        workflow = lire(WORKFLOW)
        extrait = workflow.split("ressources=\"$(awk", 1)
        self.assertEqual(len(extrait), 2, "bloc d'extraction introuvable")
        bloc = extrait[1].split("for r in", 1)[0]
        self.assertIn("[ -z \"$ressources\" ]", bloc)
        self.assertIn("::error::", bloc)
        self.assertIn("exit 1", bloc)

    def test_server_cfg_demarre_des_ressources_gunfight(self) -> None:
        config = lire(CONFIG_SERVEUR)
        self.assertTrue(
            re.search(r"^\s*ensure\s+gf_\S+", config, re.MULTILINE),
            "server.cfg doit contenir au moins une ligne 'ensure gf_'",
        )


if __name__ == "__main__":
    unittest.main()
