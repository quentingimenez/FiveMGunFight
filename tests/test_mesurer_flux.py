#!/usr/bin/env python3
"""Tests du mesureur de flux : fonctions pures, dépôt Git temporaire et CLI."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from scripts import mesurer_flux
from scripts.mesurer_flux import analyser, analyser_titre, filtrer_fenetre
from tests.outils import exiger

RACINE = Path(__file__).resolve().parents[1]
SCRIPT = RACINE / "scripts" / "mesurer_flux.py"


def dossier_temporaire() -> tempfile.TemporaryDirectory[str]:
    """Dossier temporaire hors du dépôt, supprimé en fin de test."""
    return tempfile.TemporaryDirectory(prefix="gf-flux-")


def commit(sha: str, date: str, titre: str) -> dict[str, str]:
    """Fabrique un commit en mémoire, sans toucher à git."""
    return {"sha": sha, "date": date, "titre": titre}


class AnalyseDesTitres(unittest.TestCase):
    """Le titre Conventional Commits est découpé sans effet de bord."""

    def test_type_simple(self) -> None:
        titre = analyser_titre("feat: add a new weapon")
        self.assertEqual("feat", titre["type"])
        self.assertIsNone(titre["portee"])
        self.assertEqual("add a new weapon", titre["sujet"])
        self.assertFalse(titre["rupture"])
        self.assertIsNone(titre["pr"])

    def test_portee_et_numero_de_pr(self) -> None:
        titre = analyser_titre("fix(gf_core): correct the admin check (#123)")
        self.assertEqual("fix", titre["type"])
        self.assertEqual("gf_core", titre["portee"])
        self.assertEqual("correct the admin check", titre["sujet"])
        self.assertEqual(123, titre["pr"])

    def test_marqueur_de_rupture(self) -> None:
        titre = analyser_titre("feat(api)!: change the contract (#42)")
        self.assertTrue(titre["rupture"])
        self.assertEqual("api", titre["portee"])
        self.assertEqual(42, titre["pr"])
        self.assertEqual("change the contract", titre["sujet"])

    def test_titre_sans_type_compté_autre(self) -> None:
        titre = analyser_titre("merge the hotfix branch")
        self.assertEqual("autre", titre["type"])
        self.assertIsNone(titre["portee"])
        self.assertEqual("merge the hotfix branch", titre["sujet"])

    def test_type_inconnu_compté_autre(self) -> None:
        self.assertEqual("autre", analyser_titre("wip: something")["type"])


class AnalyseEnMemoire(unittest.TestCase):
    """Les compteurs et les chaînes sont calculés sans lire git."""

    def test_chaines_compteurs_et_rapport(self) -> None:
        commits = [
            commit("b" * 40, "2026-01-04T12:00:00+00:00", "fix(gf_a): correct the action"),
            commit("a" * 40, "2026-01-02T12:00:00+00:00", "feat(gf_a): add the action"),
        ]
        resultat = analyser(commits)
        self.assertEqual(2, resultat["commits_analyses"])
        self.assertEqual({"fix": 1, "feat": 1}, resultat["commits_par_type"])
        self.assertEqual(1.0, resultat["rapport_fix_feat"])
        self.assertEqual({"gf_a": 1}, resultat["fix_par_portee"])
        self.assertEqual(1, resultat["fix_apres_feat"])
        self.assertEqual(1.0, resultat["part_fix_apres_feat"])
        self.assertEqual(1, len(resultat["chaines"]))
        self.assertEqual("a" * 7, resultat["chaines"][0]["sha"])
        self.assertEqual("feat(gf_a): add the action", resultat["chaines"][0]["titre"])
        self.assertEqual(["b" * 7], [f["sha"] for f in resultat["chaines"][0]["fix"]])

    def test_sans_fonctionnalite_pas_de_division_par_zero(self) -> None:
        resultat = analyser([commit("c" * 40, "2026-01-04T12:00:00+00:00", "fix: bug")])
        self.assertIsNone(resultat["rapport_fix_feat"])
        self.assertEqual(0, resultat["fix_apres_feat"])
        self.assertEqual(0.0, resultat["part_fix_apres_feat"])

    def test_fix_trop_ancien_hors_de_la_fenetre_de_jours(self) -> None:
        commits = [
            commit("d" * 40, "2026-01-22T12:00:00+00:00", "fix(gf_a): old bug"),
            commit("a" * 40, "2026-01-02T12:00:00+00:00", "feat(gf_a): add the action"),
        ]
        self.assertEqual(0, len(analyser(commits, jours=7)["chaines"]))
        self.assertEqual(1, len(analyser(commits, jours=21)["chaines"]))

    def test_fenetre_derniers_et_depuis(self) -> None:
        commits = [
            commit("3" * 40, "2026-01-03T12:00:00+00:00", "fix(gf_a): three"),
            commit("2" * 40, "2026-01-02T12:00:00+00:00", "feat(gf_a): two"),
            commit("1" * 40, "2026-01-01T12:00:00+00:00", "feat(gf_a): one"),
        ]
        self.assertEqual(["3" * 40, "2" * 40], [c["sha"] for c in filtrer_fenetre(commits, 2)])
        self.assertEqual(
            ["3" * 40, "2" * 40],
            [c["sha"] for c in filtrer_fenetre(commits, depuis="2026-01-02")],
        )


class LectureDeLHistorique(unittest.TestCase):
    """La commande git et le découpage en trois champs sont contractuels."""

    def test_format_git_et_champs_tabulés(self) -> None:
        sortie = (
            f"{'a' * 40}\t2026-01-02T12:00:00+00:00\tfeat(gf_a): add\tthe action\n"
            "\n"
            "ligne sans tabulations\n"
            f"{'b' * 40}\t2026-01-04T12:00:00+00:00\tfix(gf_a): correct it\n"
        )
        processed = subprocess.CompletedProcess(
            args=[], returncode=0, stdout=sortie, stderr=""
        )
        with mock.patch.object(
            mesurer_flux.subprocess, "run", return_value=processed
        ) as appele:
            commits = mesurer_flux.lire_historique(Path("/depot-factice"))

        self.assertEqual(
            ["git", "log", "--format=%H%x09%cI%x09%s"], appele.call_args.args[0]
        )
        self.assertEqual(2, len(commits))
        self.assertEqual("a" * 40, commits[0]["sha"])
        self.assertEqual("2026-01-02T12:00:00+00:00", commits[0]["date"])
        self.assertEqual("feat(gf_a): add\tthe action", commits[0]["titre"])
        self.assertEqual("fix(gf_a): correct it", commits[1]["titre"])


class ScriptSurDepotTemporaire(unittest.TestCase):
    """Le script est exécuté avec sys.executable sur un vrai dépôt isolé."""

    def setUp(self) -> None:
        exiger(self, "git", shutil.which("git"))

    def git(self, depot: Path, *arguments: str, dates: dict[str, str] | None = None):
        environnement = os.environ.copy()
        # Aucune configuration globale ou système ne doit influencer les commits.
        environnement["GIT_CONFIG_GLOBAL"] = str(depot / "sans-config-globale")
        environnement["GIT_CONFIG_SYSTEM"] = str(depot / "sans-config-systeme")
        environnement["GIT_CONFIG_NOSYSTEM"] = "1"
        if dates:
            environnement.update(dates)
        resultat = subprocess.run(
            ["git", "-C", str(depot), *arguments],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=environnement,
        )
        self.assertEqual(0, resultat.returncode, resultat.stderr)
        return resultat

    def creer_exemple(self, racine: Path) -> tuple[Path, dict[str, str]]:
        depot = racine / "depot"
        depot.mkdir()
        self.git(depot, "init", "-q")
        self.git(depot, "config", "user.name", "Test Flux")
        self.git(depot, "config", "user.email", "test@flux.invalid")
        self.git(depot, "config", "commit.gpgsign", "false")
        self.assertEqual(
            "Test Flux", self.git(depot, "config", "--local", "user.name").stdout.strip()
        )
        shas: dict[str, str] = {}
        etapes = (
            ("feat1", "feat(gf_a): add the first action", "2026-01-01T12:00:00+0000"),
            ("feat2", "feat(gf_a): add the second action (#11)", "2026-01-02T12:00:00+0000"),
            ("fix2j", "fix(gf_a): correct the first action", "2026-01-04T12:00:00+0000"),
            ("fixb", "fix(gf_b): correct another scope (#12)", "2026-01-05T12:00:00+0000"),
            ("fix20j", "fix(gf_a): correct an old action", "2026-01-22T12:00:00+0000"),
        )
        for numero, (cle, titre, date) in enumerate(etapes, start=1):
            (depot / "journal.txt").write_text(f"{numero}\n", encoding="utf-8")
            self.git(depot, "add", "journal.txt")
            self.git(
                depot,
                "commit",
                "-q",
                "-m",
                titre,
                dates={"GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date},
            )
            shas[cle] = self.git(depot, "rev-parse", "HEAD").stdout.strip()
        return depot, shas

    def lancer_script(self, depot: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--depot", str(depot), *arguments],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=str(RACINE),
            timeout=60,
        )

    def test_rapport_json_sur_le_depot_temporaire(self) -> None:
        with dossier_temporaire() as temporaire:
            depot, shas = self.creer_exemple(Path(temporaire))
            resultat = self.lancer_script(depot, "--json")
            self.assertEqual(0, resultat.returncode, resultat.stderr)
            sortie = resultat.stdout.strip()
            self.assertTrue(sortie.startswith("{") and sortie.endswith("}"))
            donnees = json.loads(sortie)
            self.assertEqual(5, donnees["commits_analyses"])
            self.assertEqual({"feat": 2, "fix": 3}, donnees["commits_par_type"])
            self.assertEqual(1.5, donnees["rapport_fix_feat"])
            self.assertEqual({"gf_a": 2, "gf_b": 1}, donnees["fix_par_portee"])
            self.assertEqual(1, len(donnees["chaines"]))
            chaine = donnees["chaines"][0]
            self.assertEqual(shas["feat2"][:7], chaine["sha"])
            self.assertIn("add the second action", chaine["titre"])
            self.assertEqual([shas["fix2j"][:7]], [f["sha"] for f in chaine["fix"]])
            self.assertEqual(1, donnees["fix_apres_feat"])
            self.assertAlmostEqual(1 / 3, donnees["part_fix_apres_feat"])

            texte = self.lancer_script(depot)
            self.assertEqual(0, texte.returncode, texte.stderr)
            self.assertIn("Commits par type", texte.stdout)
            self.assertIn("Correctifs par portée", texte.stdout)
            self.assertIn("5", texte.stdout)

    def test_fenetres_derniers_et_depuis(self) -> None:
        with dossier_temporaire() as temporaire:
            depot, _ = self.creer_exemple(Path(temporaire))
            derniers = json.loads(self.lancer_script(depot, "--json", "--derniers", "2").stdout)
            self.assertEqual(2, derniers["commits_analyses"])
            self.assertEqual({"fix": 2}, derniers["commits_par_type"])
            self.assertEqual(0, len(derniers["chaines"]))
            depuis = json.loads(
                self.lancer_script(depot, "--json", "--depuis", "2026-01-04").stdout
            )
            self.assertEqual(3, depuis["commits_analyses"])
            self.assertEqual({"fix": 3}, depuis["commits_par_type"])

    def test_hors_depot_donne_code_2(self) -> None:
        with dossier_temporaire() as temporaire:
            dossier = Path(temporaire) / "pas-un-depot"
            dossier.mkdir()
            resultat = self.lancer_script(dossier)
            self.assertEqual(2, resultat.returncode)
            self.assertIn("dépôt git", resultat.stderr)
            self.assertNotIn("Traceback", resultat.stderr)

    def test_arguments_invalides_donnent_code_2(self) -> None:
        cas = (
            ("--derniers", "0"),
            ("--derniers", "-1"),
            ("--jours", "0"),
            ("--depuis", "01/01/2026"),
            ("--depuis", "2026-02-30"),
            ("--derniers", "2", "--depuis", "2026-01-01"),
        )
        for arguments in cas:
            with self.subTest(arguments=arguments):
                resultat = subprocess.run(
                    [sys.executable, str(SCRIPT), *arguments],
                    check=False,
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    cwd=str(RACINE),
                    timeout=60,
                )
                self.assertEqual(2, resultat.returncode)
                self.assertNotIn("Traceback", resultat.stderr)


if __name__ == "__main__":
    unittest.main()
