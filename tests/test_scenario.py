"""Tests du rejeu de scénarios console (scripts/scenario.py).

Tout est hors ligne : le rcon et le journal sont remplacés par des objets
factices, aucun Docker ni socket n'est utilisé. Les deux scénarios fournis
sont seulement chargés et validés, jamais exécutés.

Lancement local :  python -m unittest tests.test_scenario -v
"""

from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

RACINE = Path(__file__).resolve().parents[1]
SCRIPTS = RACINE / "scripts"
sys.path.insert(0, str(SCRIPTS))


def charger_script(nom: str):
    chemin = SCRIPTS / f"{nom}.py"
    spec = importlib.util.spec_from_file_location(nom, chemin)
    module = importlib.util.module_from_spec(spec)
    sys.modules[nom] = module
    spec.loader.exec_module(module)
    return module


scenario = charger_script("scenario")


class FauxRcon:
    """Répond aux commandes et ajoute des lignes au journal factice."""

    def __init__(self, journal: FauxJournal, lignes: list[str] | None = None) -> None:
        self.journal = journal
        self.lignes = lignes or []
        self.commandes: list[str] = []

    def __call__(self, commande: str) -> str | None:
        self.commandes.append(commande)
        for ligne in self.lignes:
            self.journal.ajouter(ligne)
        return f"ok {commande}\n"


class FauxJournal:
    """Journal en mémoire, initialement vide ou prérempli."""

    def __init__(self, lignes: list[str] | None = None) -> None:
        self.lignes = list(lignes or [])

    def ajouter(self, ligne: str) -> None:
        self.lignes.append(ligne)

    def __call__(self) -> list[str]:
        return list(self.lignes)


class ExecutionScenario(unittest.TestCase):
    def test_scenario_nominal(self) -> None:
        journal = FauxJournal(["ligne ancienne SCRIPT ERROR"])
        rcon = FauxRcon(journal, ["[gf_attack] Lancement forcé : 3 joueur(s) de la file rejoignent la partie."])
        donnees = {
            "nom": "manche",
            "etapes": [
                {"rcon": "startround"},
                {"attendre": "[gf_attack] Lancement forcé :", "delai": 1},
                {"absent": "SCRIPT ERROR"},
            ],
        }
        sortie = io.StringIO()
        with redirect_stdout(sortie):
            code = scenario.executer_scenario(donnees, rcon, journal)
        self.assertEqual(code, 0)
        self.assertEqual(rcon.commandes, ["startround"])
        self.assertEqual(sortie.getvalue().count("ok"), 3)
        # La ligne ancienne ne compte pas : l'étape 'absent' passe malgré elle.
        self.assertIn("absent 'SCRIPT ERROR' : ok", sortie.getvalue())

    def test_attente_jamais_satisfaite(self) -> None:
        journal = FauxJournal()
        rcon = FauxRcon(journal)
        donnees = {
            "nom": "attente vaine",
            "etapes": [{"attendre": "jamais écrit", "delai": 0.1}],
        }
        sortie = io.StringIO()
        with redirect_stdout(sortie):
            code = scenario.executer_scenario(donnees, rcon, journal)
        self.assertEqual(code, 1)
        self.assertIn("délai", sortie.getvalue())

    def test_absent_viole(self) -> None:
        journal = FauxJournal()
        rcon = FauxRcon(journal, ["SCRIPT ERROR: @gf_attack/server.lua:42"])
        donnees = {
            "nom": "erreur de script",
            "etapes": [
                {"rcon": "startround"},
                {"absent": "SCRIPT ERROR"},
            ],
        }
        sortie = io.StringIO()
        with redirect_stdout(sortie):
            code = scenario.executer_scenario(donnees, rcon, journal)
        self.assertEqual(code, 1)
        self.assertIn("absent 'SCRIPT ERROR' : échec", sortie.getvalue())

    def test_attentes_repetables(self) -> None:
        """Aucun état global ne doit faire passer la seconde attente."""
        journal = FauxJournal()
        rcon = FauxRcon(journal)

        def envoyer(commande: str) -> str:
            rcon(commande)
            journal.ajouter("première ligne")
            return "ok"

        donnees = {
            "nom": "attentes répétées",
            "etapes": [
                {"attendre": "première ligne", "delai": 0.2},
                {"attendre": "première ligne", "delai": 0.2},
                {"attendre": "seconde ligne", "delai": 0.2},
            ],
        }

        def sans_seconde() -> list[str]:
            return [ligne for ligne in journal() if ligne != "seconde ligne"]

        sortie = io.StringIO()
        with redirect_stdout(sortie):
            code = scenario.executer_scenario(donnees, envoyer, sans_seconde)
        self.assertEqual(code, 1)

    def test_delai_max_plafonne(self) -> None:
        journal = FauxJournal()
        rcon = FauxRcon(journal)
        donnees = {
            "nom": "plafond",
            "etapes": [{"attendre": "introuvable", "delai": 30}],
        }
        sortie = io.StringIO()
        with redirect_stdout(sortie):
            code = scenario.executer_scenario(donnees, rcon, journal, delai_max=0.1)
        self.assertEqual(code, 1)
        self.assertIn("délai de 0.1 s dépassé", sortie.getvalue())

    def test_journal_illisible_est_un_echec(self) -> None:
        def journal_casse() -> list[str]:
            raise OSError("journal indisponible")

        donnees = {
            "nom": "journal absent",
            "etapes": [{"rcon": "status"}],
        }
        sortie = io.StringIO()
        with redirect_stdout(sortie):
            code = scenario.executer_scenario(donnees, lambda commande: "ok", journal_casse)
        self.assertEqual(code, 1)
        self.assertIn("journal", sortie.getvalue())


class ValidationScenario(unittest.TestCase):
    def test_etape_inconnue(self) -> None:
        donnees = {"nom": "invalide", "etapes": [{"inconnu": 1}]}
        with self.assertRaises(scenario.ScenarioInvalide):
            scenario.valider_scenario(donnees)
        # La lecture du fichier est simulée : aucun fichier n'est écrit.
        with mock.patch.object(Path, "read_text", return_value=json.dumps(donnees)):
            sortie, erreur = io.StringIO(), io.StringIO()
            with redirect_stdout(sortie), redirect_stderr(erreur):
                code = scenario.main(["scenario-invalide.json"])
        self.assertEqual(code, 2)
        self.assertIn("étape inconnue", erreur.getvalue())

    def test_champs_manquants_et_types(self) -> None:
        for donnees in (
            {},
            {"nom": "", "etapes": [{"rcon": "x"}]},
            {"nom": "x", "etapes": []},
            {"nom": "x", "etapes": [{"rcon": 4}]},
            {"nom": "x", "etapes": [{"attendre": "x"}]},
            {"nom": "x", "etapes": [{"attendre": "x", "delai": "bientôt"}]},
            {"nom": "x", "etapes": [{"pause": -1}]},
            {"nom": "x", "etapes": ["rcon"]},
        ):
            with self.subTest(donnees=donnees), self.assertRaises(scenario.ScenarioInvalide):
                scenario.valider_scenario(donnees)


class InterfaceLigneDeCommande(unittest.TestCase):
    def test_json_invalide(self) -> None:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", prefix="scenario-invalide-",
            dir=RACINE, delete=False, encoding="utf-8",
        ) as fichier:
            chemin = Path(fichier.name)
            fichier.write("{ ceci n'est pas du JSON")
        self.addCleanup(chemin.unlink, missing_ok=True)
        sortie, erreur = io.StringIO(), io.StringIO()
        with redirect_stdout(sortie), redirect_stderr(erreur):
            code = scenario.main([str(chemin)])
        self.assertEqual(code, 2)
        self.assertIn("JSON", erreur.getvalue())
        self.assertEqual(sortie.getvalue(), "")

    def test_fichier_absent(self) -> None:
        sortie, erreur = io.StringIO(), io.StringIO()
        with redirect_stdout(sortie), redirect_stderr(erreur):
            code = scenario.main([str(RACINE / "tests" / "gf-scenario-absent.json")])
        self.assertEqual(code, 2)
        self.assertIn("impossible de lire", erreur.getvalue())


class ScenariosFournis(unittest.TestCase):
    def test_manche_attaque(self) -> None:
        donnees = scenario.charger_scenario(SCRIPTS / "scenarios" / "manche-attaque.json")
        self.assertTrue(donnees["nom"].strip())
        etapes = donnees["etapes"]
        self.assertEqual(len(etapes), 3)
        self.assertEqual(etapes[0], {"rcon": "startround"})
        # Le texte attendu doit exister dans le code : un message renommé dans
        # gf_attack casserait le scénario sans que personne ne le voie.
        attendu = etapes[1]["attendre"]
        self.assertTrue(attendu.startswith("[gf_attack] "), attendu)
        source = (
            RACINE / "server-data" / "resources" / "[gunfight]" / "gf_attack" / "server.lua"
        ).read_text(encoding="utf-8")
        self.assertIn(attendu.removeprefix("[gf_attack] "), source, "message absent de gf_attack")
        self.assertEqual(etapes[2], {"absent": "SCRIPT ERROR"})

    def test_redemarrage_attack(self) -> None:
        donnees = scenario.charger_scenario(SCRIPTS / "scenarios" / "redemarrage-attack.json")
        self.assertTrue(donnees["nom"].strip())
        etapes = donnees["etapes"]
        self.assertEqual(len(etapes), 3)
        self.assertEqual(etapes[0], {"rcon": "restart gf_attack"})
        self.assertEqual(etapes[1]["attendre"], "Started resource gf_attack")
        self.assertEqual(etapes[1]["delai"], 60)
        self.assertEqual(etapes[2], {"absent": "SCRIPT ERROR"})

    def test_json_valides(self) -> None:
        for nom in ("manche-attaque.json", "redemarrage-attack.json"):
            with self.subTest(nom=nom):
                chemin = SCRIPTS / "scenarios" / nom
                with chemin.open(encoding="utf-8") as flux:
                    self.assertIsInstance(json.load(flux), dict)


if __name__ == "__main__":
    unittest.main()
