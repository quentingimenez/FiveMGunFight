"""Tests de scripts/arbre-suivi.sh : la copie de l'arbre vu par Git.

gitleaks doit analyser exactement ce que Git versionne (fichiers suivis et
fichiers non suivis non ignorés), jamais `.env` ni les autres fichiers ignorés.
Le dépôt jetable de ces tests est créé hors du dépôt, dans un dossier
temporaire : aucun fichier de travail ne doit apparaître dans l'arbre.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from outils import bash, exiger

RACINE = Path(__file__).resolve().parents[1]
SCRIPT = RACINE / "scripts" / "arbre-suivi.sh"
GITIGNORE = ".env\nsecrets/\n"


def git(depot: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    """Exécute Git dans le dépôt jetable, sans hériter d'un index global."""
    return subprocess.run(
        ["git", *arguments],
        cwd=str(depot),
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
    )


class ArbreSuivi(unittest.TestCase):
    """La copie ne contient que les fichiers vus par Git."""

    def setUp(self) -> None:
        exiger(self, "bash", bash())
        if shutil.which("git") is None:
            self.skipTest("git absent")

        self._depot_temporaire = tempfile.TemporaryDirectory(prefix="arbre-suivi-")
        self.addCleanup(self._depot_temporaire.cleanup)
        self.depot = Path(self._depot_temporaire.name)

        self._destination_temporaire = tempfile.TemporaryDirectory(
            prefix="arbre-suivi-destination-"
        )
        self.addCleanup(self._destination_temporaire.cleanup)
        self.destination = Path(self._destination_temporaire.name)

        git(self.depot, "init", "-q")
        (self.depot / ".gitignore").write_text(GITIGNORE, encoding="utf-8")
        (self.depot / "a.txt").write_text("suivi\n", encoding="utf-8")
        git(self.depot, "add", ".gitignore", "a.txt")
        git(
            self.depot,
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@t",
            "commit",
            "-q",
            "-m",
            "init",
        )

        (self.depot / "b.txt").write_text("non suivi\n", encoding="utf-8")
        (self.depot / ".env").write_text("SECRET=factice\n", encoding="utf-8")
        (self.depot / "secrets").mkdir()
        (self.depot / "secrets" / "x").write_text("secret factice\n", encoding="utf-8")

        (self.depot / "scripts").mkdir()
        shutil.copy2(SCRIPT, self.depot / "scripts" / "arbre-suivi.sh")

    def lancer(
        self, cwd: Path, destination: Path, script: str = "scripts/arbre-suivi.sh"
    ) -> subprocess.CompletedProcess[str]:
        """Lance le script depuis `cwd`, avec un chemin relatif portable."""
        destination_relative = os.path.relpath(destination, cwd).replace(os.sep, "/")
        return subprocess.run(
            [bash(), script, destination_relative],
            cwd=str(cwd),
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
        )

    def test_copie_les_fichiers_vus_par_git(self) -> None:
        resultat = self.lancer(self.depot, self.destination)
        self.assertEqual(resultat.returncode, 0, resultat.stderr)

        for attendu in ("a.txt", "b.txt", ".gitignore", "scripts/arbre-suivi.sh"):
            with self.subTest(fichier=attendu):
                self.assertTrue(
                    (self.destination / attendu).is_file(),
                    f"{attendu} absent de la copie",
                )

        for interdit in (".env", "secrets/x"):
            with self.subTest(fichier=interdit):
                self.assertFalse(
                    (self.destination / interdit).exists(),
                    f"{interdit} ignoré par Git mais copié",
                )

    def test_destination_non_vide_refusee(self) -> None:
        marqueur = self.destination / "deja-la.txt"
        marqueur.write_text("présent\n", encoding="utf-8")

        resultat = self.lancer(self.depot, self.destination)
        self.assertEqual(resultat.returncode, 2, resultat.stderr)
        self.assertIn("non vide", resultat.stderr)
        self.assertTrue(marqueur.is_file(), "la destination a été modifiée")

    def test_destination_absente_refusee(self) -> None:
        resultat = self.lancer(self.depot, self.depot / "destination-absente")
        self.assertEqual(resultat.returncode, 2, resultat.stderr)
        self.assertFalse((self.depot / "destination-absente").exists())

    def test_hors_depot_git_refuse(self) -> None:
        with tempfile.TemporaryDirectory(prefix="arbre-suivi-sans-git-") as brut:
            sans_git = Path(brut)
            (sans_git / "scripts").mkdir()
            shutil.copy2(SCRIPT, sans_git / "scripts" / "arbre-suivi.sh")
            destination = sans_git / "destination"
            destination.mkdir()

            resultat = self.lancer(sans_git, destination)
            self.assertEqual(resultat.returncode, 3, resultat.stderr)
            self.assertIn("Git", resultat.stderr)

    def test_fichier_suivi_supprime_ignore(self) -> None:
        disparu = self.depot / "c.txt"
        disparu.write_text("ajouté puis supprimé\n", encoding="utf-8")
        git(self.depot, "add", "c.txt")
        disparu.unlink()

        resultat = self.lancer(self.depot, self.destination)
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        self.assertFalse((self.destination / "c.txt").exists())


if __name__ == "__main__":
    unittest.main()
