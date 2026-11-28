"""Tests du vérificateur d'erreurs de script dans le journal FXServer.

`scripts/verifier-journal-serveur.sh` doit distinguer un démarrage propre
(code 0) d'un journal contenant une erreur de script (code 1, lignes fautives
et résumé affichés), et refuser un journal absent ou vide (code 2). Les
journaux de fixture restent petits et lisibles : ils représentent des extraits
réalistes de `docker logs smoke`.

Lancement local :  python -m unittest tests.test_verifier_journal -v
"""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

try:
    from tests.outils import bash as bash_utilisable
    from tests.outils import exiger
except ImportError:
    from outils import bash as bash_utilisable
    from outils import exiger

RACINE = Path(__file__).resolve().parents[1]
SCRIPT = RACINE / "scripts" / "verifier-journal-serveur.sh"
FIXTURES = RACINE / "tests" / "fixtures" / "journaux"


class VerificationJournalServeur(unittest.TestCase):
    """Le script classe correctement journaux propres, fautifs et absents."""

    def lancer(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        """Lance le script avec le bash vérifié en début de test."""
        executable = bash_utilisable()
        return subprocess.run(
            [executable, str(SCRIPT), *arguments],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )

    def test_journal_propre(self) -> None:
        exiger(self, "bash", bash_utilisable())
        resultat = self.lancer(str(FIXTURES / "propre.log"))
        self.assertEqual(resultat.returncode, 0, resultat.stdout + resultat.stderr)
        self.assertIn("Aucune erreur de script", resultat.stdout)

    def test_erreur_de_script(self) -> None:
        exiger(self, "bash", bash_utilisable())
        resultat = self.lancer(str(FIXTURES / "script-error.log"))
        self.assertEqual(resultat.returncode, 1, resultat.stdout + resultat.stderr)
        self.assertIn("SCRIPT ERROR: @gf_lobby/server.lua:12", resultat.stdout)
        self.assertIn("1 erreur(s) de script", resultat.stdout)

    def test_erreur_de_chargement(self) -> None:
        exiger(self, "bash", bash_utilisable())
        resultat = self.lancer(str(FIXTURES / "chargement.log"))
        self.assertEqual(resultat.returncode, 1, resultat.stdout + resultat.stderr)
        self.assertIn(
            "Error loading script server.lua in resource gf_maps", resultat.stdout
        )

    def test_erreur_de_demarrage(self) -> None:
        exiger(self, "bash", bash_utilisable())
        resultat = self.lancer(str(FIXTURES / "demarrage.log"))
        self.assertEqual(resultat.returncode, 1, resultat.stdout + resultat.stderr)
        self.assertIn("Couldn't start resource gf_stats", resultat.stdout)

    def test_sans_argument(self) -> None:
        exiger(self, "bash", bash_utilisable())
        resultat = self.lancer()
        self.assertEqual(resultat.returncode, 2, resultat.stdout + resultat.stderr)

    def test_fichier_absent(self) -> None:
        exiger(self, "bash", bash_utilisable())
        with tempfile.TemporaryDirectory(prefix="journal-absent-") as dossier:
            resultat = self.lancer(str(Path(dossier) / "absent.log"))
        self.assertEqual(resultat.returncode, 2, resultat.stdout + resultat.stderr)

    def test_fichier_vide(self) -> None:
        exiger(self, "bash", bash_utilisable())
        with tempfile.TemporaryDirectory(prefix="journal-vide-") as dossier:
            vide = Path(dossier) / "vide.log"
            vide.write_text("", encoding="utf-8")
            resultat = self.lancer(str(vide))
        self.assertEqual(resultat.returncode, 2, resultat.stdout + resultat.stderr)


if __name__ == "__main__":
    unittest.main()
