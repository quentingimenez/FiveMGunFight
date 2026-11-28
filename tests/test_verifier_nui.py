"""Tests du pilote NUI (scripts/verifier_nui.py).

Le contexte est remplacé par un objet en mémoire : aucun rcon, aucun Docker,
aucune capture, aucun client FiveM et aucune attente réelle. Le script est
chargé par chemin, comme dans tests/test_scenario.py.

Lancement local :  python -m unittest tests.test_verifier_nui -v
"""

from __future__ import annotations

import importlib.util
import io
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


verifier = charger_script("verifier_nui")

PAGES_DEFAUT = ["gf_admin", "gf_maps", "gf_vehicles", "gf_menu"]
LIGNE_PRET = "[gf_testbridge] prêt (développement)"
LIGNE_CLIENT = "[gf_testbridge] client prêt id=1"


class ContexteFaux:
    """Contexte injectable, sans effet de bord hors du test."""

    def __init__(self, *, similarity: float = 0.5, client_actif: bool = True) -> None:
        self.journal: list[str] = []
        self.commandes: list[str] = []
        self.captures: list[str] = []
        self.fermetures_client = 0
        self.lancements_client = 0
        self.dormi: list[float] = []
        self.erreurs: list[str] = []
        self.similarity = similarity
        self._client_actif = client_actif
        self._ouvertes: set[str] = set()
        self.rapports: dict[str, callable] = {}
        self.echec_capture = False
        self.echec_comparaison = False
        self.lignes_bridge = [LIGNE_PRET, LIGNE_CLIENT]
        self.lignes_dormi: list[list[str]] = []

    def envoyer_rcon(self, commande: str) -> str | None:
        self.commandes.append(commande)
        parties = commande.split()
        if parties[0] == "ensure" and len(parties) > 1:
            self.journal.extend(self.lignes_bridge)
        if parties[:2] == ["gf_bridge", "open"] and len(parties) == 3:
            page = parties[2]
            self._ouvertes.add(page)
            cle = ("open", page)
            if cle in self.rapports:
                self.journal.append(self.rapports[cle]())
            else:
                self.journal.append(
                    f"[gf_testbridge] page={page} action=open etat=ouvert"
                )
        if parties[:2] == ["gf_bridge", "close"] and len(parties) == 3:
            page = parties[2]
            self._ouvertes.discard(page)
            cle = ("close", page)
            if cle in self.rapports:
                self.journal.append(self.rapports[cle]())
            else:
                self.journal.append(
                    f"[gf_testbridge] page={page} action=close etat=ferme calques=0"
                )
        return f"ok {commande}\n"

    def lire_journal(self) -> list[str]:
        return list(self.journal)

    def capturer(self, destination) -> int:
        self.captures.append(str(destination))
        return 1 if self.echec_capture else 0

    def comparer(self, premiere, seconde) -> float:
        return self.similarity

    def client_actif(self) -> bool:
        return self._client_actif

    def lancer_client(self) -> None:
        self.lancements_client += 1
        self._client_actif = True

    def fermer_client(self) -> None:
        self.fermetures_client += 1
        self._client_actif = False

    def erreurs_client(self) -> list[str]:
        return list(self.erreurs)

    def dormir(self, secondes: float) -> None:
        self.dormi.append(secondes)
        self.journal.extend(self.lignes_dormi.pop(0) if self.lignes_dormi else [])

    def activer_rapport(self, page: str, action: str, rapport: str) -> None:
        self.rapports[(action, page)] = lambda: rapport


def options(**modifications):
    valeurs = {
        "sans_client": False,
        "garder_client": False,
        "seuil": 0.98,
        "delai": 0.2,
        "verbeux": False,
        "racine": RACINE,
    }
    valeurs.update(modifications)
    return valeurs


class ExecutionNui(unittest.TestCase):
    def lancer(self, contexte, dossier, pages=None, **modifications):
        sortie = io.StringIO()
        with redirect_stdout(sortie), redirect_stderr(sortie):
            code = verifier.executer(
                contexte,
                pages if pages is not None else PAGES_DEFAUT,
                options(**modifications),
                dossier,
            )
        return code, sortie.getvalue()

    def test_succes_quatre_pages(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        code, sortie = self.lancer(contexte, Path(avec.name))
        self.assertEqual(code, 0, sortie)
        self.assertEqual(
            contexte.commandes[:2], ["stop gf_testbridge", "ensure gf_testbridge"]
        )
        self.assertEqual(len(contexte.captures), 8)
        self.assertEqual(contexte.fermetures_client, 0)
        for page in PAGES_DEFAUT:
            self.assertIn(f"gf_bridge open {page}", contexte.commandes)
            self.assertIn(f"gf_bridge close {page}", contexte.commandes)
            self.assertIn(page, sortie)
        self.assertIn("SSIM", sortie)
        self.assertIn(avec.name, sortie)

    def test_client_lance_puis_ferme(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux(client_actif=False)
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 0, sortie)
        self.assertEqual(contexte.lancements_client, 1)
        self.assertEqual(contexte.fermetures_client, 1)

    def test_garder_client(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux(client_actif=False)
        code, sortie = self.lancer(
            contexte, Path(avec.name), pages=["gf_admin"], garder_client=True
        )
        self.assertEqual(code, 0, sortie)
        self.assertEqual(contexte.fermetures_client, 0)

    def test_refus_ouverture(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        contexte.activer_rapport(
            "gf_admin",
            "open",
            "[gf_testbridge] page=gf_admin action=open etat=refus detail=admin requis",
        )
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 1)
        self.assertIn("refus", sortie)
        self.assertIn("admin requis", sortie)

    def test_echec_ouverture(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        contexte.activer_rapport(
            "gf_admin",
            "open",
            "[gf_testbridge] page=gf_admin action=open etat=echec detail=NUI absent",
        )
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 1)
        self.assertIn("echec", sortie)
        self.assertIn("NUI absent", sortie)

    def test_echec_fermeture(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        contexte.activer_rapport(
            "gf_admin",
            "close",
            "[gf_testbridge] page=gf_admin action=close etat=echec detail=calques Bloques",
        )
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 1)
        self.assertIn("calques Bloques", sortie)

    def test_similarite_superieure_au_seuil(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux(similarity=0.99)
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 1)
        self.assertIn("n'a pas modifié le rendu", sortie)
        self.assertIn("0.9900", sortie)

    def test_bridge_desactive(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        contexte.lignes_bridge = ["[gf_testbridge] désactivé"]
        code, sortie = self.lancer(contexte, Path(avec.name))
        self.assertEqual(code, 2)
        self.assertIn("désactivé", sortie)
        self.assertIn("stop gf_testbridge", contexte.commandes)

    def test_client_absent_sans_client(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux(client_actif=False)
        code, sortie = self.lancer(
            contexte, Path(avec.name), pages=["gf_admin"], sans_client=True
        )
        self.assertEqual(code, 2)
        self.assertIn("client", sortie)
        self.assertEqual(contexte.lancements_client, 0)
        self.assertIn("stop gf_testbridge", contexte.commandes)

    def test_timeout_rapport(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        contexte.lignes_bridge = [LIGNE_PRET]
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 2)
        self.assertIn("Délai", sortie)
        self.assertIn("connecté", sortie)

    def test_sortie_dans_depot_refusee(self) -> None:
        contexte = ContexteFaux()
        code, sortie = self.lancer(contexte, RACINE / "captures")
        self.assertEqual(code, 2)
        self.assertIn("dépôt", sortie)
        self.assertEqual(contexte.commandes, [])

    def test_erreur_client(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        contexte.erreurs = ["SCRIPT ERROR: @gf_menu/client.lua:12"]
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 1)
        self.assertIn("SCRIPT ERROR", sortie)

    def test_erreur_serveur_nouvelle_ligne(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        contexte.journal.insert(0, "SCRIPT ERROR: ancienne ligne")
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 0, sortie)

    def test_page_invalide(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        code, sortie = self.lancer(
            contexte, Path(avec.name), pages=["gf_inconnue", "mauvaise-page!"]
        )
        self.assertEqual(code, 2)
        self.assertIn("invalide", sortie)

    def test_finally_ferme_pages_et_bridge(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        contexte.activer_rapport(
            "gf_admin",
            "close",
            "[gf_testbridge] page=gf_admin action=close etat=refus detail= occupation",
        )
        code, _sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 1)
        fermetures = [
            c for c in contexte.commandes if c.startswith("gf_bridge close")
        ]
        self.assertEqual(fermetures.count("gf_bridge close gf_admin"), 2)
        self.assertEqual(contexte.commandes[-1], "stop gf_testbridge")

    def test_capture_en_echec(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        contexte.echec_capture = True
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 1)
        self.assertIn("capture", sortie.lower())

    def test_rcon_injoignable(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)

        class ContexteRconCasse(ContexteFaux):
            def envoyer_rcon(self, commande):
                self.commandes.append(commande)

        contexte = ContexteRconCasse()
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 2)
        self.assertIn("rcon", sortie)

    def test_espacement_captures(self) -> None:
        avec = tempfile.TemporaryDirectory()
        self.addCleanup(avec.cleanup)
        contexte = ContexteFaux()
        code, sortie = self.lancer(contexte, Path(avec.name), pages=["gf_admin"])
        self.assertEqual(code, 0, sortie)
        self.assertIn(2.0, contexte.dormi)
        self.assertIn(3.5, contexte.dormi)


class InterfaceLigneDeCommande(unittest.TestCase):
    def test_option_sans_client_transmise(self) -> None:
        """--sans-client est accepté par le CLI ; executer décide du prérequis."""
        with tempfile.TemporaryDirectory() as dossier, mock.patch.object(
            verifier, "ContexteReel"
        ), mock.patch.object(verifier, "executer", return_value=0) as executer_mock:
            code = verifier.main(["--sans-client", "--sortie", dossier])
        self.assertEqual(code, 0)
        self.assertTrue(executer_mock.call_args.args[2]["sans_client"])

    def test_pages_invalides_refusees(self) -> None:
        sortie, erreur = io.StringIO(), io.StringIO()
        with redirect_stdout(sortie), redirect_stderr(erreur):
            code = verifier.main(
                ["--pages", "gf_admin mauvaise-page!", "--sortie", "C:\\temp\\gf-nui-test"]
            )
        self.assertEqual(code, 2)
        self.assertIn("invalide", erreur.getvalue())


if __name__ == "__main__":
    unittest.main()
