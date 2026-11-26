"""Contrôles statiques de la ressource gf_menu (menu pause NUI).

Ces tests ne démarrent ni FiveM ni Docker. Ils vérifient que le manifeste
déclare bien la page NUI et ses fichiers, que le client bloque le menu pause
natif, et que la page est autonome (aucune URL externe).

Lancement local :  python -m unittest discover -s tests -v
En CI          :  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
RESSOURCE = RACINE / "server-data" / "resources" / "[gunfight]" / "gf_menu"

MOTIF_FICHIERS = re.compile(r"\bfiles\s*\{([^}]*)\}", re.DOTALL)
MOTIF_CHEMIN = re.compile(r"['\"]([^'\"]+)['\"]")
MOTIF_URL = re.compile(r"https?://", re.IGNORECASE)


class ManifesteMenu(unittest.TestCase):
    def test_manifeste_declare_la_page_et_lua54(self) -> None:
        manifeste = (RESSOURCE / "fxmanifest.lua").read_text(encoding="utf-8")
        self.assertRegex(manifeste, r"ui_page\s+['\"]html/index\.html['\"]")
        self.assertRegex(manifeste, r"lua54\s+['\"]yes['\"]")

    def test_fichiers_declares_existent(self) -> None:
        manifeste = (RESSOURCE / "fxmanifest.lua").read_text(encoding="utf-8")
        blocs = MOTIF_FICHIERS.findall(manifeste)
        self.assertTrue(blocs, "aucun bloc files dans fxmanifest.lua")
        chemins = [chemin for bloc in blocs for chemin in MOTIF_CHEMIN.findall(bloc)]
        self.assertTrue(chemins, "aucun fichier déclaré dans le bloc files")
        for chemin in chemins:
            with self.subTest(fichier=chemin):
                self.assertTrue((RESSOURCE / chemin).is_file(), f"fichier manquant : {chemin}")


class ClientMenu(unittest.TestCase):
    def test_client_bloque_le_frontend_natif(self) -> None:
        client = (RESSOURCE / "client.lua").read_text(encoding="utf-8")
        self.assertIn("DisableFrontendThisFrame()", client)
        self.assertIn("Wait(0)", client)

    def test_wait_0_reste_dans_le_thread_de_blocage(self) -> None:
        client = (RESSOURCE / "client.lua").read_text(encoding="utf-8")
        sans_commentaires = re.sub(r"--[^\n]*", "", client)
        self.assertEqual(1, sans_commentaires.count("Wait(0)"), "Wait(0) doit rester unique en code")
        self.assertLess(sans_commentaires.index("CreateThread("), sans_commentaires.index("Wait(0)"))

    def test_touche_pause_est_celle_du_frontend(self) -> None:
        config = (RESSOURCE / "config.lua").read_text(encoding="utf-8")
        self.assertRegex(config, r"Config\.ToggleControl\s*=\s*200\b")


class PageMenu(unittest.TestCase):
    def test_page_est_autonome(self) -> None:
        for relatif in ("html/index.html", "html/css/menu.css"):
            with self.subTest(fichier=relatif):
                source = (RESSOURCE / relatif).read_text(encoding="utf-8")
                self.assertIsNone(MOTIF_URL.search(source), f"URL externe dans {relatif}")


class DocumentationMenu(unittest.TestCase):
    def test_document_du_menu_present(self) -> None:
        self.assertTrue((RACINE / "docs" / "menu-pause.md").is_file())


if __name__ == "__main__":
    unittest.main()
