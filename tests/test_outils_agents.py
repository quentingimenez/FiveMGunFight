"""Tests des outils de développement pour agents (scripts/native.py,
scripts/fivem_rcon.py, scripts/journal_client.py).

Ces outils raccourcissent la boucle d'essai en jeu : signature d'un natif sans
réseau, redémarrage d'une ressource sans relancer le conteneur, erreurs du
journal client annotées avec le nom du natif fautif.

Lancement local :  python -m unittest discover -s tests -v
"""

from __future__ import annotations

import importlib.util
import io
import json
import re
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import date
from pathlib import Path

from outils import bash as bash_utilisable
from outils import exiger

RACINE = Path(__file__).resolve().parents[1]


def charger_script(nom: str):
    chemin = RACINE / "scripts" / f"{nom}.py"
    spec = importlib.util.spec_from_file_location(nom, chemin)
    module = importlib.util.module_from_spec(spec)
    sys.modules[nom] = module
    spec.loader.exec_module(module)
    return module


native = charger_script("native")
fivem_rcon = charger_script("fivem_rcon")
journal_client = charger_script("journal_client")
suivre_dependabot = charger_script("suivre_dependabot")

# Extrait réel des bases runtime.fivem.net (doc/natives.json, natives_cfx.json).
BASE_GTA = {
    "ENTITY": {
        "0x428CA6DBD1094446": {
            "name": "FREEZE_ENTITY_POSITION",
            "params": [
                {"name": "entity", "type": "Entity", "description": "The entity."},
                {"name": "toggle", "type": "BOOL", "description": "Freeze or not."},
            ],
            "results": "void",
            "description": "Freezes or unfreezes an entity.",
        }
    },
    "GRAPHICS": {
        "0x29280002282F1928": {
            "name": "DRAW_TEXTURED_POLY",
            "params": [{"name": "x1", "type": "float"}],
            "results": "void",
            "description": "",
        },
        "0xE1C9F04EE5AA3F98": {
            "name": "_0xE1C9F04EE5AA3F98",
            "params": [],
            "results": "void",
        },
        # Natif sans nom connu : la base n'a pas de champ `name`.
        "0x0B40ED49D7D6FF84": {"params": [], "results": "void"},
    },
}
BASE_CFX = {
    "CFX": {
        "0x786D8BC3": {
            "name": "CREATE_RUNTIME_TEXTURE_FROM_IMAGE",
            "params": [
                {"name": "txd", "type": "long", "description": "A handle to the runtime TXD."},
                {"name": "txn", "type": "char*", "description": "The texture name."},
                {"name": "fileName", "type": "char*", "description": "The image file."},
            ],
            "results": "long",
            "description": "Creates a runtime texture.",
            "resultsDescription": "A runtime texture handle.",
            "apiset": "client",
        },
        "0x1F3AC778": {
            "name": "CREATE_RUNTIME_TXD",
            "params": [{"name": "name", "type": "char*", "description": "The TXD name."}],
            "results": "long",
            "apiset": "client",
        },
        "0x65C16D57": {
            "name": "FREEZE_ENTITY_POSITION",
            "params": [{"name": "entity", "type": "Entity"}, {"name": "toggle", "type": "BOOL"}],
            "results": "void",
            "apiset": "server",
        },
    }
}


def base_temporaire() -> Path:
    dossier = Path(tempfile.mkdtemp(prefix="gf-natives-"))
    (dossier / "natives.json").write_text(json.dumps(BASE_GTA), encoding="utf-8")
    (dossier / "natives_cfx.json").write_text(json.dumps(BASE_CFX), encoding="utf-8")
    return dossier


class RechercheDesNatifs(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.dossier = base_temporaire()
        cls.natifs = native.charger(cls.dossier)

    def test_charge_les_deux_bases(self) -> None:
        self.assertEqual(len(self.natifs), 7)
        cfx = [n for n in self.natifs if n["ns"] == "CFX"]
        self.assertEqual(len(cfx), 3)

    def test_nom_lua(self) -> None:
        self.assertEqual(
            native.nom_lua("CREATE_RUNTIME_TEXTURE_FROM_IMAGE"), "CreateRuntimeTextureFromImage"
        )
        self.assertEqual(native.nom_lua("_SET_PED_EYE_COLOR"), "SetPedEyeColor")
        self.assertEqual(native.nom_lua("_0xE1C9F04EE5AA3F98"), "N_0xe1c9f04ee5aa3f98")

    def test_natif_sans_nom_trouve_par_hash_et_nom_lua(self) -> None:
        for requete in ("0x0B40ED49D7D6FF84", "N_0x0b40ed49d7d6ff84"):
            with self.subTest(requete=requete):
                trouves = native.chercher(self.natifs, requete)
                self.assertEqual([n["hash"] for n in trouves], ["0x0B40ED49D7D6FF84"])
        self.assertIn("void N_0x0b40ed49d7d6ff84()", native.formater(trouves[0]))

    def test_trouve_par_nom_lua_ou_natif(self) -> None:
        for requete in (
            "CreateRuntimeTextureFromImage",
            "CREATE_RUNTIME_TEXTURE_FROM_IMAGE",
            "create_runtime_texture_from_image",
        ):
            with self.subTest(requete=requete):
                trouves = native.chercher(self.natifs, requete)
                self.assertEqual([n["name"] for n in trouves], ["CREATE_RUNTIME_TEXTURE_FROM_IMAGE"])

    def test_un_nom_partiel_ne_correspond_pas(self) -> None:
        self.assertEqual(native.chercher(self.natifs, "CreateRuntimeTexture"), [])

    def test_trouve_par_hash_du_journal_client(self) -> None:
        # Le journal client écrit « script error in native 00000000786d8bc3 ».
        for requete in ("00000000786d8bc3", "0x786D8BC3", "786d8bc3"):
            with self.subTest(requete=requete):
                trouves = native.chercher(self.natifs, requete)
                self.assertEqual([n["name"] for n in trouves], ["CREATE_RUNTIME_TEXTURE_FROM_IMAGE"])

    def test_trouve_par_hash_gta_64_bits(self) -> None:
        trouves = native.chercher(self.natifs, "0x29280002282f1928")
        self.assertEqual([n["name"] for n in trouves], ["DRAW_TEXTURED_POLY"])

    def test_variantes_client_et_serveur(self) -> None:
        trouves = native.chercher(self.natifs, "FreezeEntityPosition")
        self.assertEqual(sorted(n["ns"] for n in trouves), ["CFX", "ENTITY"])

    def test_recherche_par_fragment_style_lua(self) -> None:
        noms = [n["name"] for n in native.rechercher(self.natifs, "RuntimeTexture")]
        self.assertEqual(noms, ["CREATE_RUNTIME_TEXTURE_FROM_IMAGE"])

    def test_hash_court_traite_comme_un_nom(self) -> None:
        # Un mot court en lettres a-f (« Fade ») est un nom, pas un hash.
        self.assertIsNone(native._hash("fade"))
        self.assertIsNone(native._hash("0x"))
        self.assertEqual(native._hash("0xbeef"), 0xBEEF)
        self.assertEqual(native._hash("0000beef"), 0xBEEF)

    def test_recherche_par_fragment(self) -> None:
        noms = [n["name"] for n in native.rechercher(self.natifs, "runtime")]
        self.assertEqual(noms, ["CREATE_RUNTIME_TEXTURE_FROM_IMAGE", "CREATE_RUNTIME_TXD"])

    def test_signature_affiche_types_et_noms(self) -> None:
        natif = native.chercher(self.natifs, "CreateRuntimeTextureFromImage")[0]
        texte = native.formater(natif)
        self.assertIn(
            "long CreateRuntimeTextureFromImage(long txd, char* txn, char* fileName)", texte
        )
        self.assertIn("0x786D8BC3", texte)
        self.assertIn("txd : A handle to the runtime TXD.", texte)
        self.assertIn("A runtime texture handle.", texte)

    def test_cli_code_retour(self) -> None:
        sortie = io.StringIO()
        with redirect_stdout(sortie):
            code = native.main(["--dossier", str(self.dossier), "CreateRuntimeTxd"])
        self.assertEqual(code, 0)
        self.assertIn("long CreateRuntimeTxd(char* name)", sortie.getvalue())
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(native.main(["--dossier", str(self.dossier), "PasUnNatif"]), 1)

    def test_cli_sans_base_explique_la_mise_a_jour(self) -> None:
        vide = Path(tempfile.mkdtemp(prefix="gf-natives-vide-"))
        erreur = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(erreur):
            code = native.main(["--dossier", str(vide), "CreateRuntimeTxd"])
        self.assertEqual(code, 2)
        self.assertIn("--update", erreur.getvalue())


class Rcon(unittest.TestCase):
    def test_paquet(self) -> None:
        self.assertEqual(
            fivem_rcon.paquet("abc123", "restart gf_lobby"),
            b"\xff\xff\xff\xffrcon abc123 restart gf_lobby",
        )

    def test_paquet_refuse_un_retour_a_la_ligne(self) -> None:
        with self.assertRaises(ValueError):
            fivem_rcon.paquet("abc", "restart gf_lobby\nquit")
        with self.assertRaises(ValueError):
            fivem_rcon.paquet("a b", "status")
        with self.assertRaises(ValueError):
            fivem_rcon.paquet("", "status")

    def test_decoder_retire_l_en_tete(self) -> None:
        self.assertEqual(
            fivem_rcon.decoder(b"\xff\xff\xff\xffprint Started resource gf_lobby\n"),
            "Started resource gf_lobby\n",
        )
        self.assertEqual(fivem_rcon.decoder(b"brut"), "brut")

    def test_refus_du_serveur_reconnu(self) -> None:
        self.assertTrue(fivem_rcon.refus("Invalid password.\n"))
        self.assertTrue(
            fivem_rcon.refus("The server must set rcon_password to be able to use this command.\n")
        )
        self.assertFalse(fivem_rcon.refus("Started resource gf_lobby\n"))

    def test_mot_de_passe_lu_dans_le_fichier(self) -> None:
        dossier = Path(tempfile.mkdtemp(prefix="gf-rcon-"))
        fichier = dossier / "rcon_password"
        fichier.write_text("deadbeef\n", encoding="utf-8")
        self.assertEqual(fivem_rcon.lire_mot_de_passe(fichier, {}), "deadbeef")
        self.assertEqual(
            fivem_rcon.lire_mot_de_passe(fichier, {"GF_RCON_PASSWORD": "env"}), "env"
        )
        self.assertIsNone(fivem_rcon.lire_mot_de_passe(dossier / "absent", {}))

    def test_cli_sans_mot_de_passe_explique_quoi_faire(self) -> None:
        dossier = Path(tempfile.mkdtemp(prefix="gf-rcon-"))
        erreur = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(erreur):
            code = fivem_rcon.main(["--fichier", str(dossier / "absent"), "restart", "gf_lobby"])
        self.assertEqual(code, 2)
        self.assertIn("TXADMIN=false", erreur.getvalue())


class RconDansLeConteneur(unittest.TestCase):
    """Le mot de passe rcon n'existe qu'en développement, en mode direct."""

    def test_entrypoint_n_active_rcon_qu_en_dev_direct(self) -> None:
        texte = (RACINE / "docker" / "entrypoint.sh").read_text(encoding="utf-8")
        bloc = re.search(r'if \[ "\$\{GF_DEV_RCON:-\}" = "true" \] && \[ "\$TXADMIN" != "true" \]; then(.*?)\nfi', texte, re.DOTALL)
        self.assertIsNotNone(bloc, "rcon doit dépendre de GF_DEV_RCON=true et TXADMIN!=true")
        self.assertIn("rcon_password", bloc.group(1))
        # Aucun rcon_password en dehors de ce bloc.
        hors_bloc = texte.replace(bloc.group(0), "")
        self.assertNotIn('rcon_password \\"', hors_bloc)

    def executer_bloc_rcon(self, txadmin: str, dev_rcon: str) -> Path:
        """Exécute le vrai bloc rcon de l'entrypoint dans un dossier temporaire."""
        bash = bash_utilisable()
        exiger(self, "bash", bash)
        texte = (RACINE / "docker" / "entrypoint.sh").read_text(encoding="utf-8")
        bloc = re.search(r'\nRCON_FICHIER=.*?\nfi\n', texte, re.DOTALL)
        self.assertIsNotNone(bloc, "bloc rcon introuvable dans l'entrypoint")
        dossier = Path(tempfile.mkdtemp(prefix="gf-entrypoint-"))
        (dossier / "secrets.cfg").write_text('sv_maxclients 48\n', encoding="utf-8")
        # Mot de passe d'un démarrage précédent : il doit disparaître.
        (dossier / "cache").mkdir()
        (dossier / "cache" / "rcon_password").write_text("ancien\n", encoding="utf-8")
        # Chemins relatifs et variables dans le script : marche aussi avec le
        # bash de WSL, qui n'hérite ni des chemins ni de l'environnement Windows.
        script = f"set -e\nDATA=.\nTXADMIN={txadmin}\nGF_DEV_RCON={dev_rcon}\n" + bloc.group(0)
        resultat = subprocess.run(
            [bash, "-s"], input=script.replace("\r", ""), cwd=dossier,
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        return dossier

    def test_bloc_rcon_actif_en_dev_direct(self) -> None:
        dossier = self.executer_bloc_rcon(txadmin="false", dev_rcon="true")
        mot_de_passe = (dossier / "cache" / "rcon_password").read_text(encoding="utf-8").strip()
        self.assertRegex(mot_de_passe, r"^[0-9a-f]{48}$")
        secrets = (dossier / "secrets.cfg").read_text(encoding="utf-8")
        self.assertIn(f'set rcon_password "{mot_de_passe}"', secrets)

    def test_bloc_rcon_ferme_en_mode_txadmin_ou_hors_dev(self) -> None:
        for txadmin, dev_rcon in (("true", "true"), ("false", "false"), ("false", "")):
            with self.subTest(TXADMIN=txadmin, GF_DEV_RCON=dev_rcon):
                dossier = self.executer_bloc_rcon(txadmin=txadmin, dev_rcon=dev_rcon)
                self.assertFalse((dossier / "cache" / "rcon_password").exists())
                self.assertNotIn("rcon_password", (dossier / "secrets.cfg").read_text(encoding="utf-8"))

    def test_seule_la_surcouche_dev_active_rcon(self) -> None:
        self.assertIn(
            'GF_DEV_RCON: "true"', (RACINE / "docker-compose.dev.yml").read_text(encoding="utf-8")
        )
        for fichier in ("docker-compose.yml", "docker-compose.prod.yml", "docker-compose.staging.yml"):
            with self.subTest(fichier=fichier):
                self.assertNotIn("GF_DEV_RCON", (RACINE / fichier).read_text(encoding="utf-8"))


JOURNAL = """\
[     37937] [b3889_GTAProce]             MainThrd/ Creating script environments for gf_lobby
[     38000] [b3889_GTAProce]             MainThrd/ script error in native 00000000786d8bc3: invalid handle
[     38001] [b3889_GTAProce]             MainThrd/ [gf_ui] ok
[     51000] [b3889_GTAProce]             MainThrd/ Creating script environments for gf_lobby
[     51547] [b3889_GTAProce]             MainThrd/ script error in native 00000000786d8bc3: invalid handle
[     51548] [b3889_GTAProce]             MainThrd/ [gf_lobby] fond : texture indisponible
[     51549] [b3889_GTAProce]             MainThrd/ script error in native 00000000786d8bc3: invalid handle
[     51550] [b3889_GTAProce]             MainThrd/ SCRIPT ERROR: @gf_lobby/client.lua:12: attempt to index a nil value
[     51551] [b3889_GTAProce]             MainThrd/ > fn (@gf_lobby/client.lua:12)
[     51552] [b3889_GTAProce]             MainThrd/ [gf_ui] ok
"""


class JournalClient(unittest.TestCase):
    def setUp(self) -> None:
        self.lignes = JOURNAL.splitlines()

    def test_texte_retire_l_horodatage(self) -> None:
        self.assertEqual(journal_client.texte(self.lignes[2]), "[gf_ui] ok")

    def test_depuis_le_dernier_demarrage(self) -> None:
        apres = journal_client.depuis_demarrage(self.lignes, "gf_lobby")
        self.assertEqual(len(apres), 6)
        self.assertIn("51547", apres[0])
        # Ressource jamais démarrée : tout le journal.
        self.assertEqual(journal_client.depuis_demarrage(self.lignes, "gf_x"), self.lignes)

    def test_erreurs_regroupees_et_comptees(self) -> None:
        lignes = journal_client.depuis_demarrage(self.lignes, "gf_lobby")
        erreurs = journal_client.erreurs(lignes)
        self.assertEqual(
            erreurs,
            [
                ("script error in native 00000000786d8bc3: invalid handle", 2),
                ("SCRIPT ERROR: @gf_lobby/client.lua:12: attempt to index a nil value", 1),
                ("> fn (@gf_lobby/client.lua:12)", 1),
            ],
        )

    def test_messages_de_la_ressource(self) -> None:
        messages = journal_client.messages(self.lignes, "gf_lobby")
        self.assertEqual(messages, ["[gf_lobby] fond : texture indisponible"])
        # Une autre ressource qui cite [gf_lobby] n'est pas un message de gf_lobby.
        autre = "[  1] [b3889_GTAProce]   MainThrd/ [gf_ui] relaie [gf_lobby]"
        self.assertEqual(journal_client.messages([autre], "gf_lobby"), [])

    def test_erreur_de_natif_annotee(self) -> None:
        natifs = native.charger(base_temporaire())
        texte = journal_client.annoter(
            "script error in native 00000000786d8bc3: invalid handle", natifs
        )
        self.assertIn("CREATE_RUNTIME_TEXTURE_FROM_IMAGE", texte)
        self.assertIn("long txd", texte)
        self.assertEqual(journal_client.annoter("autre erreur", natifs), "autre erreur")
        # Base absente (pas de --update) : l'erreur reste affichée telle quelle.
        brut = "script error in native 00000000786d8bc3: invalid handle"
        self.assertEqual(journal_client.annoter(brut, None), brut)

    def test_cli_journal_illisible(self) -> None:
        dossier = Path(tempfile.mkdtemp(prefix="gf-journal-"))
        erreur = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(erreur):
            code = journal_client.main(["--fichier", str(dossier / "absent.log")])
        self.assertEqual(code, 2)
        self.assertIn("absent.log", erreur.getvalue())

    def test_cli_code_retour_selon_les_erreurs(self) -> None:
        dossier = Path(tempfile.mkdtemp(prefix="gf-journal-"))
        fichier = dossier / "CitizenFX_log_test.log"
        fichier.write_text(JOURNAL, encoding="utf-8")
        sortie = io.StringIO()
        with redirect_stdout(sortie):
            code = journal_client.main(["--fichier", str(fichier), "--ressource", "gf_lobby"])
        self.assertEqual(code, 1)
        self.assertIn("(x2)", sortie.getvalue())
        propre = dossier / "CitizenFX_log_propre.log"
        propre.write_text(self.lignes[3] + "\n" + self.lignes[5] + "\n", encoding="utf-8")
        with redirect_stdout(io.StringIO()):
            self.assertEqual(journal_client.main(["--fichier", str(propre), "--ressource", "gf_lobby"]), 0)


def check_run(nom: str, conclusion: str | None = "SUCCESS", statut: str = "COMPLETED") -> dict:
    """Entrée CheckRun de `statusCheckRollup`, comme la sortie de gh."""
    return {
        "__typename": "CheckRun",
        "name": nom,
        "status": statut,
        "conclusion": conclusion,
    }


def status_context(nom: str, etat: str) -> dict:
    """Entrée StatusContext de `statusCheckRollup` (ancien statut de commit)."""
    return {"__typename": "StatusContext", "context": nom, "state": etat}


# PR réelle #50 : Ubuntu 26.04 de l'image de vérification, « Qualité du dépôt »
# en échec, les trois autres checks verts.
PR_50 = {
    "number": 50,
    "title": (
        "build(deps): bump ubuntu from 24.04 to 26.04 in /docker/verifier "
        "in the verifier group"
    ),
    "url": "https://github.com/quentingimenez/FiveMGunFight/pull/50",
    "headRefName": "dependabot/docker/docker/verifier/ubuntu-24.04",
    "createdAt": "2026-06-01T06:42:11Z",
    "mergeable": "MERGEABLE",
    "statusCheckRollup": [
        check_run("Qualité du dépôt", conclusion="FAILURE"),
        check_run("Sécurité de l'historique"),
        check_run("Construire et publier l'image"),
        check_run("Vérifier le démarrage des ressources"),
    ],
    "labels": [{"name": "dependencies"}, {"name": "docker"}],
}


def pr_dependabot(**changements) -> dict:
    """PR Dependabot minimale, proche de la sortie `gh pr list --json`."""
    pr = {
        "number": 50,
        "title": "build(deps): bump foo from 1.7.12 to 1.7.13",
        "url": "https://github.com/quentingimenez/FiveMGunFight/pull/50",
        "headRefName": "dependabot/docker/foo-1.7.13",
        "createdAt": "2026-06-01T06:42:11Z",
        "mergeable": "MERGEABLE",
        "statusCheckRollup": [check_run("Qualité du dépôt")],
        "labels": [{"name": "dependencies"}],
    }
    pr.update(changements)
    return pr


class SuiviDependabot(unittest.TestCase):
    """Classement des PR Dependabot, hors-ligne (--depuis-json)."""

    AUJOURDHUI = date(2026, 6, 10)

    def test_type_de_montee_numerique(self) -> None:
        for titre, attendu in (
            (
                (
                    "build(deps): bump ubuntu from 24.04 to 26.04 in /docker/verifier "
                    "in the verifier group"
                ),
                "majeure",
            ),
            ("build(deps): bump foo from 1.7.12 to 1.7.13", "correctif"),
            ("build(deps): bump foo from 1.7.12 to 1.8.0", "mineure"),
            ("build(deps): bump node from v4 to v5", "majeure"),
        ):
            with self.subTest(titre=titre):
                self.assertEqual(suivre_dependabot.type_de_montee(titre), attendu)

    def test_type_de_montee_digest_et_inconnue(self) -> None:
        digest = (
            "build(deps): bump alpine from "
            "0123456789abcdef0123456789abcdef01234567 to "
            "89abcdef0123456789abcdef0123456789abcdef"
        )
        self.assertEqual(suivre_dependabot.type_de_montee(digest), "digest")
        groupe = "build(deps): bump the actions group across 1 directory with 7 updates"
        self.assertEqual(suivre_dependabot.type_de_montee(groupe), "inconnue")

    def test_type_de_montee_plusieurs_paires(self) -> None:
        titre = (
            "build(deps): bump a from 1.7.12 to 1.7.13 and "
            "b from 2.1.0 to 3.0.0"
        )
        self.assertEqual(suivre_dependabot.type_de_montee(titre), "majeure")

    def test_etat_checks_vert(self) -> None:
        rollup = [
            check_run("Qualité du dépôt"),
            check_run("Docker", conclusion="NEUTRAL"),
            check_run("Smoke", conclusion="SKIPPED"),
        ]
        self.assertEqual(suivre_dependabot.etat_checks(rollup), ("vert", []))

    def test_etat_checks_rouge_avec_noms(self) -> None:
        rollup = [
            check_run("Qualité du dépôt", conclusion="FAILURE"),
            check_run("Docker"),
            check_run("Smoke", conclusion="TIMED_OUT"),
            status_context("lint", "ERROR"),
        ]
        self.assertEqual(
            suivre_dependabot.etat_checks(rollup),
            ("rouge", ["Qualité du dépôt", "Smoke", "lint"]),
        )

    def test_etat_checks_en_cours(self) -> None:
        rollup = [
            check_run("Qualité du dépôt"),
            check_run("Docker", conclusion=None, statut="IN_PROGRESS"),
            status_context("lint", "PENDING"),
        ]
        self.assertEqual(suivre_dependabot.etat_checks(rollup), ("en cours", []))

    def test_etat_checks_aucun(self) -> None:
        self.assertEqual(suivre_dependabot.etat_checks([]), ("aucun", []))

    def test_etat_checks_status_context(self) -> None:
        for etat, attendu in (
            ("SUCCESS", ("vert", [])),
            ("FAILURE", ("rouge", ["contrat"])),
            ("ERROR", ("rouge", ["contrat"])),
            ("PENDING", ("en cours", [])),
        ):
            with self.subTest(etat=etat):
                self.assertEqual(
                    suivre_dependabot.etat_checks([status_context("contrat", etat)]),
                    attendu,
                )

    def test_action_conflit_prioritaire(self) -> None:
        pr = pr_dependabot(
            title="build(deps): bump ubuntu from 24.04 to 26.04",
            mergeable="CONFLICTING",
            statusCheckRollup=[check_run("Qualité du dépôt", conclusion="FAILURE")],
        )
        code, phrase = suivre_dependabot.action(pr, self.AUJOURDHUI)
        self.assertEqual(code, "rebase")
        self.assertEqual(
            phrase,
            "conflit : commenter « @dependabot rebase » (avec l'accord de l'utilisateur)",
        )

    def test_action_ci_rouge_avant_montee_majeure(self) -> None:
        pr = pr_dependabot(
            title="build(deps): bump ubuntu from 24.04 to 26.04",
            statusCheckRollup=[
                check_run("Qualité du dépôt", conclusion="FAILURE"),
                check_run("Docker", conclusion="FAILURE"),
            ],
        )
        code, phrase = suivre_dependabot.action(pr, self.AUJOURDHUI)
        self.assertEqual(code, "diagnostiquer")
        self.assertIn("CI rouge (Qualité du dépôt, Docker)", phrase)
        self.assertIn("gh run view --log-failed", phrase)
        self.assertIn("PR séparée sur main", phrase)

    def test_action_attend_checks_en_cours_ou_absents(self) -> None:
        for rollup in (
            [check_run("Qualité du dépôt", conclusion=None, statut="QUEUED")],
            [],
        ):
            with self.subTest(rollup=rollup):
                pr = pr_dependabot(statusCheckRollup=rollup)
                code, phrase = suivre_dependabot.action(pr, self.AUJOURDHUI)
                self.assertEqual(code, "attendre")
                self.assertEqual(phrase, "checks en cours")

    def test_action_decider_montee_majeure_ou_inconnue(self) -> None:
        for titre, montee in (
            ("build(deps): bump ubuntu from 24.04 to 26.04", "majeure"),
            ("build(deps): bump the actions group across 1 directory with 7 updates", "inconnue"),
        ):
            with self.subTest(montee=montee):
                pr = pr_dependabot(title=titre)
                code, phrase = suivre_dependabot.action(pr, self.AUJOURDHUI)
                self.assertEqual(code, "decider")
                self.assertIn(f"montée {montee} : relire le changelog", phrase)
                self.assertIn("décision explicite de l'utilisateur", phrase)

    def test_action_fusionner_si_vert_et_mineure(self) -> None:
        pr = pr_dependabot(title="build(deps): bump foo from 1.7.12 to 1.7.13")
        code, phrase = suivre_dependabot.action(pr, self.AUJOURDHUI)
        self.assertEqual(code, "fusionner")
        self.assertIn("vert : tester en local", phrase)
        self.assertIn("bash scripts/fusionner-pr.sh 50", phrase)

    def test_action_mentionne_l_age_a_14_jours(self) -> None:
        pr = pr_dependabot(createdAt="2026-06-01T06:42:11Z")
        code, phrase = suivre_dependabot.action(pr, date(2026, 6, 15))
        self.assertEqual(code, "fusionner")
        self.assertIn(" ; ouverte depuis 14 jours", phrase)
        code, phrase = suivre_dependabot.action(pr, date(2026, 6, 14))
        self.assertEqual(code, "fusionner")
        self.assertNotIn("ouverte depuis", phrase)

    def executer(self, *arguments: str) -> tuple[int, str, str]:
        sortie, erreur = io.StringIO(), io.StringIO()
        with redirect_stdout(sortie), redirect_stderr(erreur):
            code = suivre_dependabot.main(list(arguments))
        return code, sortie.getvalue(), erreur.getvalue()

    def fichier_json(self, contenu) -> Path:
        dossier = base_temporaire()
        fichier = dossier / "dependabot.json"
        fichier.write_text(json.dumps(contenu), encoding="utf-8")
        return fichier

    def test_cli_pr50_reelle(self) -> None:
        fichier = self.fichier_json([PR_50])
        code, sortie, erreur = self.executer(
            "--depuis-json", str(fichier), "--aujourdhui", "2026-06-10"
        )
        self.assertEqual(code, 1, erreur)
        self.assertIn("1 PR Dependabot ouverte(s)", sortie)
        self.assertIn("#50 [diagnostiquer]", sortie)
        self.assertIn("Qualité du dépôt", sortie)
        self.assertIn("montée : majeure", sortie)

    def test_cli_liste_vide(self) -> None:
        fichier = self.fichier_json([])
        code, sortie, erreur = self.executer("--depuis-json", str(fichier))
        self.assertEqual(code, 0, erreur)
        self.assertEqual(sortie, "Aucune PR Dependabot ouverte.\n")

    def test_cli_json_invalide(self) -> None:
        dossier = base_temporaire()
        fichier = dossier / "dependabot.json"
        fichier.write_text("{ ceci n'est pas du JSON", encoding="utf-8")
        code, sortie, erreur = self.executer("--depuis-json", str(fichier))
        self.assertEqual(code, 2)
        self.assertIn("JSON", erreur)
        self.assertEqual(sortie, "")

    def test_cli_json_valide(self) -> None:
        fichier = self.fichier_json([PR_50])
        code, sortie, erreur = self.executer(
            "--depuis-json", str(fichier), "--aujourdhui", "2026-06-10", "--json"
        )
        self.assertEqual(code, 1, erreur)
        donnees = json.loads(sortie)
        self.assertIsInstance(donnees, list)
        self.assertEqual(len(donnees), 1)
        pr = donnees[0]
        self.assertEqual(pr["numero"], 50)
        self.assertEqual(pr["action"], "diagnostiquer")
        self.assertEqual(pr["checks"], "rouge")
        self.assertEqual(pr["checks_rouges"], ["Qualité du dépôt"])
        self.assertEqual(pr["montee"], "majeure")
        self.assertEqual(pr["age_jours"], 9)


if __name__ == "__main__":
    unittest.main()
