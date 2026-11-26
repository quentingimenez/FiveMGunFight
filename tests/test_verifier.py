"""Tests de la commande unique de vérification et de l'obligation des outils.

`scripts/verifier.sh` doit échouer quand un outil manque, au lieu de
l'ignorer comme avant. `GF_OUTILS_MASQUES` permet de simuler une absence sans
désinstaller quoi que ce soit ; `GF_SANS_TESTS=1` évite la récursion quand le
script lance lui-même cette suite.
"""

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path
from unittest import mock

from outils import bash, exiger

RACINE = Path(__file__).resolve().parents[1]


class OutilsObligatoires(unittest.TestCase):
    """`exiger` échoue sous GF_OUTILS_OBLIGATOIRES, sinon saute le test."""

    def test_outil_absent_echoue_quand_il_est_obligatoire(self) -> None:
        cas = unittest.TestCase()
        with mock.patch.dict(os.environ, {"GF_OUTILS_OBLIGATOIRES": "1"}, clear=True):
            try:
                exiger(cas, "lua", None)
            except unittest.SkipTest:
                self.fail("sauté au lieu d'échouer")
            except AssertionError as erreur:
                self.assertIn("outil obligatoire absent : lua", str(erreur))
            else:
                self.fail("aucune erreur levée")

    def test_outil_absent_saute_le_test_quand_il_est_facultatif(self) -> None:
        cas = unittest.TestCase()
        with mock.patch.dict(os.environ, {}, clear=True):
            try:
                exiger(cas, "lua", None)
            except unittest.SkipTest as saut:
                self.assertIn("lua absent", str(saut))
            except AssertionError as erreur:
                self.fail(f"échec au lieu d'un saut : {erreur}")
            else:
                self.fail("aucun saut levé")

    def test_outil_present_ne_leve_rien(self) -> None:
        exiger(self, "bash", "chemin/factice")


class VerifierStrict(unittest.TestCase):
    """Le script de vérification ne conclut plus au vert avec un outil absent."""

    def test_outils_masques_font_echouer_la_verification(self) -> None:
        executable = bash()
        exiger(self, "bash", executable)
        variables = os.environ.copy()
        variables["GF_SANS_TESTS"] = "1"
        variables["GF_OUTILS_MASQUES"] = "luacheck,ruff"
        resultat = subprocess.run(
            [executable, "scripts/verifier.sh"],
            cwd=str(RACINE),
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
            env=variables,
        )
        sortie = resultat.stdout + resultat.stderr
        self.assertEqual(resultat.returncode, 1, sortie)
        self.assertIn("outil absent : luacheck", sortie)
        self.assertIn("outil absent : ruff", sortie)
        self.assertNotIn("Toutes les vérifications sont passées", sortie)


if __name__ == "__main__":
    unittest.main()
