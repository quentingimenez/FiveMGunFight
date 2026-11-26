"""Tests de scripts/suivre_vendorise.py : suivi hors ligne de la copie oxmysql.

Ces tests ne font aucun appel réseau : le mode --amont est alimenté par des
réponses gh enregistrées dans un fichier JSON temporaire (--depuis-json).
Ils vérifient l'empreinte de la copie réelle, la version du fxmanifest,
l'indépendance de l'empreinte vis-à-vis des fins de ligne, la détection d'une
modification et les codes de retour des trois scénarios amont.

Lancement : python -m unittest tests.test_vendorise -v
         ou python -m unittest discover -s tests -v
"""

from __future__ import annotations

import importlib.util
import io
import json
import re
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]


def charger_script(nom: str):
    """Charge un script du dossier scripts/ comme module Python (modèle des tests)."""
    chemin = RACINE / "scripts" / f"{nom}.py"
    spec = importlib.util.spec_from_file_location(nom, chemin)
    module = importlib.util.module_from_spec(spec)
    sys.modules[nom] = module
    spec.loader.exec_module(module)
    return module


suivre_vendorise = charger_script("suivre_vendorise")

HEX64 = re.compile(r"^[0-9a-f]{64}$")


def ecrire_json(donnees: object, dossier: Path, nom: str) -> Path:
    """Écrit un JSON temporaire et renvoie son chemin."""
    fichier = dossier / nom
    fichier.write_text(json.dumps(donnees, ensure_ascii=False), encoding="utf-8")
    return fichier


def dossier_lignes(fin: bytes) -> Path:
    """Dossier temporaire avec un fichier racine et un fichier en sous-dossier."""
    dossier = Path(tempfile.mkdtemp(prefix="gf-vendorise-lignes-"))
    (dossier / "lib").mkdir()
    (dossier / "fxmanifest.lua").write_bytes(
        b"version '2.14.3'" + fin + b"name 'oxmysql'" + fin
    )
    (dossier / "lib" / "MySQL.lua").write_bytes(
        b"MySQL = {}" + fin + b"-- sous-dossier" + fin
    )
    return dossier


class EmpreinteEtVersion(unittest.TestCase):
    """Contrôle de la copie oxmysql et de la stabilité de l'empreinte."""

    def test_empreinte_reelle_correspond_au_json(self) -> None:
        donnees = json.loads(
            (
                RACINE
                / "server-data"
                / "resources"
                / "[standalone]"
                / "vendorise.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(len(donnees), 1)
        entree = donnees[0]
        self.assertRegex(entree["empreinte"], HEX64)
        dossier = RACINE / entree["dossier"]
        self.assertEqual(suivre_vendorise.empreinte(dossier), entree["empreinte"])

    def test_version_du_fxmanifest_correspond(self) -> None:
        manifest = (
            RACINE
            / "server-data"
            / "resources"
            / "[standalone]"
            / "oxmysql"
            / "fxmanifest.lua"
        )
        self.assertEqual(suivre_vendorise.version_manifeste(manifest), "2.14.3")

    def test_lf_et_crlf_donnent_la_meme_empreinte(self) -> None:
        lf = dossier_lignes(b"\n")
        crlf = dossier_lignes(b"\r\n")
        self.assertEqual(
            suivre_vendorise.empreinte(lf), suivre_vendorise.empreinte(crlf)
        )

    def test_un_fichier_modifie_change_lempreinte(self) -> None:
        dossier = dossier_lignes(b"\n")
        avant = suivre_vendorise.empreinte(dossier)
        (dossier / "lib" / "MySQL.lua").write_bytes(b"MySQL = { version = 2 }")
        self.assertNotEqual(suivre_vendorise.empreinte(dossier), avant)


class SuiviAmontHorsLigne(unittest.TestCase):
    """Les trois scénarios --amont, sans aucun appel gh."""

    def executer(self, *arguments: str) -> tuple[int, str, str]:
        sortie, erreur = io.StringIO(), io.StringIO()
        with redirect_stdout(sortie), redirect_stderr(erreur):
            code = suivre_vendorise.main(list(arguments))
        return code, sortie.getvalue(), erreur.getvalue()

    def reponses(
        self, dossier: Path, tag: str, avis: list[dict] | None = None
    ) -> Path:
        """Fichier de réponses gh enregistrées pour overextended/oxmysql."""
        return ecrire_json(
            {
                "overextended/oxmysql": {
                    "release": {"tag_name": tag},
                    "advisories": avis or [],
                }
            },
            dossier,
            "amont.json",
        )

    def test_a_jour(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gf-vendorise-amont-") as tmp:
            fichier = self.reponses(Path(tmp), "v2.14.3")
            code, sortie, erreur = self.executer("--amont", "--depuis-json", str(fichier))
        self.assertEqual(code, 0, erreur)
        self.assertIn("à jour", sortie)
        self.assertIn("aucun avis", sortie)

    def test_montee_disponible(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gf-vendorise-amont-") as tmp:
            fichier = self.reponses(Path(tmp), "v2.15.0")
            code, sortie, erreur = self.executer("--amont", "--depuis-json", str(fichier))
        self.assertEqual(code, 1, erreur)
        self.assertIn("montée disponible", sortie)
        self.assertIn("2.15.0", sortie)

    def test_avis_touchant_la_version_installee(self) -> None:
        avis = [
            {
                "ghsa_id": "GHSA-xxxx-yyyy-zzzz",
                "severity": "high",
                "summary": "Injection SQL via la configuration",
                "vulnerabilities": [
                    {
                        "patched_versions": ["2.14.4"],
                        "vulnerable_version_range": "< 2.14.4",
                    }
                ],
            }
        ]
        with tempfile.TemporaryDirectory(prefix="gf-vendorise-amont-") as tmp:
            fichier = self.reponses(Path(tmp), "v2.14.3", avis)
            code, sortie, erreur = self.executer("--amont", "--depuis-json", str(fichier))
        self.assertEqual(code, 1, erreur)
        self.assertIn("GHSA-xxxx-yyyy-zzzz", sortie)
        self.assertIn("high", sortie)
        self.assertIn("2.14.4", sortie)

    def test_plage_a_deux_bornes_hors_version_installee(self) -> None:
        avis = [
            {
                "ghsa_id": "GHSA-deux-bornes",
                "severity": "critical",
                "summary": "Avis hors de la gamme installée",
                "vulnerabilities": [
                    {
                        "patched_versions": ["2.0"],
                        "vulnerable_version_range": ">= 3.0, < 4.0",
                    }
                ],
            }
        ]
        with tempfile.TemporaryDirectory(prefix="gf-vendorise-amont-") as tmp:
            fichier = self.reponses(Path(tmp), "v2.14.3", avis)
            code, sortie, erreur = self.executer("--amont", "--depuis-json", str(fichier))
        self.assertEqual(code, 0, erreur)
        self.assertNotIn("GHSA-deux-bornes", sortie)

    def test_plage_egale_à_une_autre_version(self) -> None:
        avis = [
            {
                "ghsa_id": "GHSA-egale",
                "severity": "medium",
                "summary": "Avis sur une version précise",
                "vulnerabilities": [
                    {
                        "patched_versions": ["2.0"],
                        "vulnerable_version_range": "= 2.14.4",
                    }
                ],
            }
        ]
        with tempfile.TemporaryDirectory(prefix="gf-vendorise-amont-") as tmp:
            fichier = self.reponses(Path(tmp), "v2.14.3", avis)
            code, sortie, erreur = self.executer("--amont", "--depuis-json", str(fichier))
        self.assertEqual(code, 0, erreur)
        self.assertNotIn("GHSA-egale", sortie)

    def test_patched_versions_avec_operateur(self) -> None:
        avis = [
            {
                "ghsa_id": "GHSA-avec-operateur",
                "severity": "high",
                "summary": "Correction avec préfixe d'opérateur",
                "vulnerabilities": [
                    {
                        "patched_versions": [">= 2.14.4"],
                        "vulnerable_version_range": "plage illisible",
                    }
                ],
            }
        ]
        with tempfile.TemporaryDirectory(prefix="gf-vendorise-amont-") as tmp:
            fichier = self.reponses(Path(tmp), "v2.14.3", avis)
            code, sortie, erreur = self.executer("--amont", "--depuis-json", str(fichier))
        self.assertEqual(code, 1, erreur)
        self.assertIn("GHSA-avec-operateur", sortie)
        self.assertIn(">= 2.14.4", sortie)

    def test_cle_de_depot_absente_donne_code_2(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gf-vendorise-amont-") as tmp:
            fichier = ecrire_json({}, Path(tmp), "amont.json")
            code, sortie, erreur = self.executer("--amont", "--depuis-json", str(fichier))
        self.assertEqual(code, 2, erreur)
        self.assertEqual(sortie, "")
        self.assertIn("clé absente", erreur)

    def test_tag_name_absent_donne_code_2(self) -> None:
        with tempfile.TemporaryDirectory(prefix="gf-vendorise-amont-") as tmp:
            fichier = ecrire_json(
                {
                    "overextended/oxmysql": {
                        "release": {},
                        "advisories": [],
                    }
                },
                Path(tmp),
                "amont.json",
            )
            code, sortie, erreur = self.executer("--amont", "--depuis-json", str(fichier))
        self.assertEqual(code, 2, erreur)
        self.assertEqual(sortie, "")
        self.assertIn("tag_name", erreur)


if __name__ == "__main__":
    unittest.main()
