"""Tests de cohérence du dépôt FiveMGunFight.

Ces tests ne démarrent pas le serveur : le job « Docker » de la CI s'en charge
(construction de l'image puis démarrage réel des ressources). Ils vérifient que
les fichiers du dépôt restent cohérents entre eux, pour qu'une pull request ne
puisse pas casser silencieusement les manifestes, les maps, la configuration ou
la documentation.

Lancement local :  python -m unittest discover -s tests -v
En CI          :  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import json
import math
import re
import shutil
import subprocess
import unittest
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
RESSOURCES = RACINE / "server-data" / "resources"
RESSOURCES_GUNFIGHT = ("gf_core", "gf_ui", "gf_maps", "gf_attack", "gf_redzone")
MAPS_JSON = RESSOURCES / "[gunfight]" / "gf_maps" / "data" / "maps.json"

MOTS_SCRIPTS = (
    "client_script",
    "client_scripts",
    "server_script",
    "server_scripts",
    "shared_script",
    "shared_scripts",
    "ui_page",
    "files",
)


def lire(chemin: Path) -> str:
    return chemin.read_text(encoding="utf-8")


def dossiers_ressources() -> list[Path]:
    return sorted(p for p in RESSOURCES.glob("*/*") if p.is_dir())


def manifestes() -> list[Path]:
    return sorted(RESSOURCES.glob("*/*/fxmanifest.lua"))


def chemins_declares(manifeste: Path) -> set[str]:
    """Chemins de fichiers cités par un fxmanifest (scripts, ui_page, files)."""
    texte = lire(manifeste)
    chemins: set[str] = set()
    for mot in MOTS_SCRIPTS:
        motif = rf"\b{mot}\b\s*(\{{[^}}]*\}}|'[^']*'|\"[^\"]*\")"
        for trouve in re.finditer(motif, texte):
            bloc = trouve.group(1)
            for simple, double in re.findall(r"'([^']+)'|\"([^\"]+)\"", bloc):
                chemin = simple or double
                if chemin:
                    chemins.add(chemin)
    return chemins


def cles_env(chemin: Path) -> dict[str, str]:
    valeurs: dict[str, str] = {}
    for ligne in lire(chemin).splitlines():
        ligne = ligne.strip()
        if not ligne or ligne.startswith("#") or "=" not in ligne:
            continue
        cle, valeur = ligne.split("=", 1)
        valeurs[cle.strip()] = valeur.strip()
    return valeurs


def est_nombre(valeur: object) -> bool:
    return (
        isinstance(valeur, (int, float))
        and not isinstance(valeur, bool)
        and math.isfinite(float(valeur))
    )


class ManifestesFiveM(unittest.TestCase):
    """Les ressources doivent être déclarées correctement pour démarrer."""

    def test_chaque_ressource_a_un_manifeste(self) -> None:
        sans_manifeste = [
            str(d.relative_to(RACINE)) for d in dossiers_ressources()
            if not (d / "fxmanifest.lua").is_file()
        ]
        self.assertEqual([], sans_manifeste, "un dossier de ressource n'a pas de fxmanifest.lua")

    def test_manifeste_declare_version_et_jeu(self) -> None:
        for manifeste in manifestes():
            texte = lire(manifeste)
            with self.subTest(manifeste=str(manifeste.relative_to(RACINE))):
                self.assertRegex(texte, r"fx_version\s+'cerulean'", "fx_version attendu")
                self.assertRegex(texte, r"\bgame\s+'gta5'|\bgames\s*\{", "jeu non déclaré")

    def test_fichiers_declares_existent(self) -> None:
        for manifeste in manifestes():
            for chemin in chemins_declares(manifeste):
                with self.subTest(manifeste=str(manifeste.relative_to(RACINE)), chemin=chemin):
                    self.assertTrue(
                        (manifeste.parent / chemin).is_file(),
                        f"fichier déclaré introuvable : {chemin}",
                    )

    def test_ressources_gunfight_listees_dans_les_manifestes(self) -> None:
        noms = {m.parent.name for m in manifestes()}
        for ressource in RESSOURCES_GUNFIGHT:
            with self.subTest(ressource=ressource):
                self.assertIn(ressource, noms)


class ConfigurationServeur(unittest.TestCase):
    """server.cfg, .env.example et fichiers ignorés restent cohérents."""

    def test_server_cfg_demarre_les_ressources_gunfight(self) -> None:
        texte = lire(RACINE / "server-data" / "server.cfg")
        assurees = re.findall(r"^\s*ensure\s+(\S+)", texte, re.MULTILINE)
        for ressource in RESSOURCES_GUNFIGHT:
            with self.subTest(ressource=ressource):
                self.assertIn(ressource, assurees, "ressource absente de server.cfg")
                self.assertTrue(
                    (RESSOURCES / "[gunfight]" / ressource).is_dir(),
                    "ressource assurée mais absente du dépôt",
                )

    def test_server_cfg_n_assure_pas_de_ressource_supprimee(self) -> None:
        texte = lire(RACINE / "server-data" / "server.cfg")
        assurees = re.findall(r"^\s*ensure\s+(\S+)", texte, re.MULTILINE)
        for disparue in ("sessionmanager", "hardcap"):
            with self.subTest(ressource=disparue):
                self.assertNotIn(
                    disparue, assurees,
                    "ressource supprimée de FXServer : le serveur refuserait de démarrer",
                )

    def test_env_exemple_contient_les_cles_requises(self) -> None:
        valeurs = cles_env(RACINE / ".env.example")
        for cle in (
            "LICENSE_KEY",
            "SERVER_NAME",
            "MAX_PLAYERS",
            "MARIADB_ROOT_PASSWORD",
            "MARIADB_DATABASE",
            "MARIADB_USER",
            "MARIADB_PASSWORD",
        ):
            with self.subTest(cle=cle):
                self.assertIn(cle, valeurs, "clé absente de .env.example")

    def test_env_exemple_ne_contient_aucun_secret(self) -> None:
        valeurs = cles_env(RACINE / ".env.example")
        self.assertEqual("change_moi", valeurs.get("LICENSE_KEY"))
        for cle, valeur in valeurs.items():
            if "PASSWORD" in cle:
                with self.subTest(cle=cle):
                    self.assertTrue(
                        valeur.startswith("change_moi"),
                        "un mot de passe réel semble présent dans .env.example",
                    )

    def test_gitignore_protege_les_secrets(self) -> None:
        lignes = {
            ligne.strip()
            for ligne in lire(RACINE / ".gitignore").splitlines()
            if ligne.strip() and not ligne.startswith("#")
        }
        for motif in (".env", "server-data/secrets.cfg", "server-data/cache/"):
            with self.subTest(motif=motif):
                self.assertIn(motif, lignes)

    def test_dockerignore_exclut_secrets_et_cache(self) -> None:
        lignes = {ligne.strip() for ligne in lire(RACINE / ".dockerignore").splitlines()}
        for motif in (".env", "server-data/secrets.cfg", "server-data/cache/"):
            with self.subTest(motif=motif):
                self.assertIn(motif, lignes)


class MapsEnJeu(unittest.TestCase):
    """Le format de data/maps.json doit rester celui attendu par les modes."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.donnees = json.loads(lire(MAPS_JSON))

    def test_sections_attendues(self) -> None:
        self.assertIsInstance(self.donnees.get("redzone"), list)
        self.assertIsInstance(self.donnees.get("attack"), list)

    def test_redzones_valides(self) -> None:
        for carte in self.donnees["redzone"]:
            with self.subTest(carte=carte.get("id")):
                for cle in ("id", "name", "radius", "center", "spawns"):
                    self.assertIn(cle, carte)
                self.assertTrue(est_nombre(carte["radius"]) and carte["radius"] > 0, "rayon invalide")
                self.assertTrue(all(est_nombre(carte["center"].get(a)) for a in "xyz"))
                self.assertTrue(carte["spawns"], "une redzone sans point d'apparition")
                for apparition in carte["spawns"]:
                    self.assertTrue(all(est_nombre(apparition.get(a)) for a in "xyz"))

    def test_zones_attaque_valides(self) -> None:
        for zone in self.donnees["attack"]:
            with self.subTest(zone=zone.get("id")):
                for cle in ("id", "name", "points", "attackSpawn", "defenseSpawn"):
                    self.assertIn(cle, zone)
                self.assertGreaterEqual(len(zone["points"]), 3, "un polygone a au moins 3 sommets")
                for point in zone["points"]:
                    self.assertTrue(all(est_nombre(point.get(a)) for a in "xyz"))
                for cle in ("attackSpawn", "defenseSpawn"):
                    self.assertTrue(all(est_nombre(zone[cle].get(a)) for a in "xyz"))

    def test_identifiants_uniques(self) -> None:
        identifiants = [c["id"] for c in self.donnees["redzone"] + self.donnees["attack"]]
        self.assertEqual(len(identifiants), len(set(identifiants)), "identifiant de map dupliqué")


class Documentation(unittest.TestCase):
    """La documentation attendue doit exister et rester à jour."""

    DOCUMENTS = (
        "README.md",
        "CONTRIBUTING.md",
        "SECURITY.md",
        "docs/README.md",
        "docs/architecture.md",
        "docs/qualite.md",
        "docs/protection-branche.md",
        ".github/pull_request_template.md",
        ".github/CODEOWNERS",
    )

    def test_documents_presents_et_remplis(self) -> None:
        for document in self.DOCUMENTS:
            with self.subTest(document=document):
                chemin = RACINE / document
                self.assertTrue(chemin.is_file(), "document manquant")
                self.assertGreater(len(lire(chemin).strip()), 200, "document vide ou presque")

    def test_readme_cite_chaque_ressource(self) -> None:
        texte = lire(RACINE / "README.md")
        for ressource in RESSOURCES_GUNFIGHT:
            with self.subTest(ressource=ressource):
                self.assertIn(ressource, texte)

    def test_workflows_declarent_declencheurs_et_jobs(self) -> None:
        workflows = sorted((RACINE / ".github" / "workflows").glob("*.yml"))
        self.assertTrue(workflows, "aucun workflow GitHub Actions")
        for workflow in workflows:
            texte = lire(workflow)
            with self.subTest(workflow=workflow.name):
                self.assertRegex(texte, r"(?m)^on:")
                self.assertRegex(texte, r"(?m)^jobs:")


class DepotGit(unittest.TestCase):
    """Aucun fichier secret ne doit être suivi par Git."""

    def test_fichiers_sensibles_non_suivis(self) -> None:
        if shutil.which("git") is None:
            self.skipTest("git absent")
        try:
            sortie = subprocess.run(
                ["git", "ls-files"],
                cwd=RACINE,
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        except subprocess.CalledProcessError:  # pragma: no cover - copie sans .git
            self.skipTest("dépôt Git illisible")
        suivis = set(sortie.splitlines())
        for interdit in (".env", "server-data/secrets.cfg"):
            with self.subTest(fichier=interdit):
                self.assertNotIn(interdit, suivis, "fichier secret versionné")


if __name__ == "__main__":
    unittest.main()
