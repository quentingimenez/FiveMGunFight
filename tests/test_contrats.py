"""Tests du registre des contrats entre ressources FiveMGunFight.

Couvre les extracteurs purs de `scripts/contrats.py` (exports fournis et
consommés, événements, state bags, dépendances), le calcul de la dette
(cycles de longueur deux et dépendances cachées), le déterminisme de la
documentation générée, et une vérification d'intégration sur le vrai dépôt.

Lancement local :  python -m unittest tests.test_contrats -v
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]


def charger_script(nom: str):
    """Charge un script du dossier `scripts/` comme module importable."""
    chemin = RACINE / "scripts" / f"{nom}.py"
    spec = importlib.util.spec_from_file_location(nom, chemin)
    module = importlib.util.module_from_spec(spec)
    sys.modules[nom] = module
    spec.loader.exec_module(module)
    return module


contrats = charger_script("contrats")


def contrat(
    ressource: str,
    *,
    consomme: list[str] | None = None,
    dures: list[str] | None = None,
    optionnelles: list[str] | None = None,
) -> dict:
    """Fabrique un contrat complet en mémoire, avec des listes vides par défaut."""
    return {
        "ressource": ressource,
        "exports": [],
        "consomme": list(consomme or []),
        "emet": [],
        "ecoute": [],
        "state_bags": {"ecrit": [], "lit": []},
        "dependances": {
            "dures": list(dures or []),
            "optionnelles": list(optionnelles or []),
        },
        "dette": [],
    }


class VerificationDuDepot(unittest.TestCase):
    """Le registre et la documentation du vrai dépôt sont à jour."""

    def test_verifier_ne_signale_aucun_ecart(self) -> None:
        messages = contrats.verifier(RACINE)
        self.assertEqual(
            messages,
            [],
            "Écarts de contrats dans le dépôt :\n" + "\n".join(messages),
        )


class ExtracteursLua(unittest.TestCase):
    """Les extracteurs agissent sur de petites chaînes Lua, sans fichier."""

    def test_export_fourni(self) -> None:
        texte = "exports('Donne', function(src) return src end)"
        self.assertEqual(contrats.extraire_exports(texte), ["Donne"])

    def test_exports_consommes_sous_les_trois_formes(self) -> None:
        texte = "local equipe = exports.gf_core:GetTeam(1)\nlocal cartes = exports.gf_maps.GetActiveMaps('attack')\nexports['gf_ui']:Notify(src, 'salut')\nlocal equipe2 = exports.gf_core:GetTeam(src)"
        self.assertEqual(
            contrats.extraire_consommes(texte, "gf_attack"),
            ["gf_core:GetTeam", "gf_maps:GetActiveMaps", "gf_ui:Notify"],
        )

    def test_export_de_la_propre_ressource_ignore(self) -> None:
        texte = "exports.gf_self:Interne()\nexports['gf_self']:Interne()"
        self.assertEqual(contrats.extraire_consommes(texte, "gf_self"), [])

    def test_evenements_emis_et_ecoutes(self) -> None:
        texte = "TriggerEvent('gf:bus')\nTriggerClientEvent('gf_ui:notify', -1, 'salut')\nRegisterNetEvent('gf:busEchange')\nAddEventHandler('gf_autre:evt', handler)\nTriggerServerEvent(nomDynamique)"
        self.assertEqual(
            contrats.extraire_evenements_emis(texte, "gf_core"),
            ["gf:bus", "gf_ui:notify"],
        )
        self.assertEqual(
            contrats.extraire_evenements_ecoutes(texte, "gf_core"),
            ["gf:busEchange", "gf_autre:evt"],
        )

    def test_prefixe_propre_ignore(self) -> None:
        texte = "TriggerEvent('gf_self:interne')\nAddEventHandler('gf_self:interne', handler)"
        self.assertEqual(contrats.extraire_evenements_emis(texte, "gf_self"), [])
        self.assertEqual(contrats.extraire_evenements_ecoutes(texte, "gf_self"), [])

    def test_state_bags_ecrits_et_lus(self) -> None:
        """Une clé écrite reste aussi une lecture quand le code la relit."""
        texte = "Player(src).state:set('gf_team', 'a', true)\nGlobalState:set('gf_base', 'x', true)\nGlobalState.gf_version = 2\nlocal mode = LocalPlayer.state.gf_mode\nif LocalPlayer.state.gf_alive then return end\nlocal base = GlobalState.gf_base"
        state = contrats.extraire_state_bags(texte)
        self.assertEqual(state["ecrit"], ["gf_base", "gf_team", "gf_version"])
        self.assertEqual(
            state["lit"],
            ["gf_alive", "gf_base", "gf_mode"],
            "gf_base est écrite puis relue : la lecture ne doit pas disparaître",
        )


class DetteSurDonneesMemoire(unittest.TestCase):
    """Cycles et dépendances cachées calculés sans toucher au dépôt."""

    def test_cycle_de_longueur_deux(self) -> None:
        contrats_du_cycle = {
            "gf_a": contrat("gf_a", consomme=["gf_b:Fournit"]),
            "gf_b": contrat("gf_b", consomme=["gf_a:Autre"]),
        }
        self.assertEqual(contrats.cycles_deux(contrats_du_cycle), [("gf_a", "gf_b")])
        dette = contrats.dette_attendue(contrats_du_cycle)
        self.assertIn("cycle:gf_b", dette["gf_a"])
        self.assertIn("cycle:gf_a", dette["gf_b"])

    def test_cycle_par_dependance_dure(self) -> None:
        contrats_du_cycle = {
            "gf_a": contrat("gf_a", dures=["gf_b"]),
            "gf_b": contrat("gf_b", consomme=["gf_a:Autre"]),
        }
        self.assertEqual(contrats.cycles_deux(contrats_du_cycle), [("gf_a", "gf_b")])

    def test_dependance_cachee_selon_les_dependances(self) -> None:
        sans_dependance = contrat("gf_a", consomme=["gf_b:Fournit"])
        self.assertEqual(
            contrats.dependances_cachees(sans_dependance),
            ["dependance-cachee:gf_b"],
        )
        with self.subTest(dependance="dure"):
            avec_dure = contrat(
                "gf_a", consomme=["gf_b:Fournit"], dures=["gf_b"]
            )
            self.assertEqual(contrats.dependances_cachees(avec_dure), [])
        with self.subTest(dependance="optionnelle"):
            avec_optionnelle = contrat(
                "gf_a", consomme=["gf_b:Fournit"], optionnelles=["gf_b"]
            )
            self.assertEqual(contrats.dependances_cachees(avec_optionnelle), [])

    def test_dette_attendue_triee_et_complete(self) -> None:
        contrats_avec_dette = {
            "gf_a": contrat("gf_a", consomme=["gf_b:Fournit"]),
            "gf_b": contrat("gf_b", consomme=["gf_a:Autre"]),
            "gf_c": contrat("gf_c", consomme=["gf_z:Manquant"]),
        }
        self.assertEqual(
            contrats.dette_attendue(contrats_avec_dette),
            {
                "gf_a": ["cycle:gf_b", "dependance-cachee:gf_b"],
                "gf_b": ["cycle:gf_a", "dependance-cachee:gf_a"],
                "gf_c": ["dependance-cachee:gf_z"],
            },
        )


class DocumentationGeneree(unittest.TestCase):
    """Le générateur de documentation est déterministe et sans effet de bord."""

    def test_generation_deterministe_et_newline_final(self) -> None:
        premier = {
            "gf_a": contrat("gf_a", consomme=["gf_b:Fournit"]),
            "gf_b": contrat("gf_b"),
        }
        inverse = {"gf_b": contrat("gf_b"), "gf_a": contrat("gf_a", consomme=["gf_b:Fournit"])}
        texte = contrats.generer_doc(premier)
        self.assertEqual(texte, contrats.generer_doc(premier))
        self.assertEqual(texte, contrats.generer_doc(inverse))
        self.assertTrue(texte.endswith("\n"), "la documentation doit se terminer par un newline")


if __name__ == "__main__":
    unittest.main()
