"""gf_lobby NUI: callbacks always answer, and the player never sees a raw error code.

Runs the Lua and Node unit tests of tests/lua and tests/js, and checks that the
character creator turns every error into player-facing text.

Local run:  python -m unittest discover -s tests -v
CI:         python3 -m unittest discover -s tests -v (Lua 5.4 and Node are installed there)
"""

from __future__ import annotations

import re
import shutil
import subprocess
import unittest
from pathlib import Path

from outils import exiger

ROOT = Path(__file__).resolve().parents[1]
LOBBY_JS = ROOT / "server-data" / "resources" / "[gunfight]" / "gf_lobby" / "html" / "js"


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    # check=False: the caller asserts on the return code and shows the output.
    return subprocess.run(
        command,
        check=False,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=120,
    )


class JsUnitTests(unittest.TestCase):
    def test_node_suites_pass(self) -> None:
        node = shutil.which("node")
        exiger(self, "node", node)
        suites = sorted((ROOT / "tests" / "js").glob("*.test.js"))
        self.assertTrue(suites, "no Node suite found")
        result = run([node, "--test", *(str(s.relative_to(ROOT)) for s in suites)])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class CreatorErrorText(unittest.TestCase):
    def test_creator_never_shows_a_raw_error(self) -> None:
        # response.error / result.error hold codes such as callback_unreachable:
        # they must go through errorText() before reaching a toast.
        source = (LOBBY_JS / "creator.js").read_text(encoding="utf-8")
        uses = re.findall(r"[^\n]*\b(?:response|result)\.error\b[^\n]*", source)
        self.assertTrue(uses, "creator.js no longer reads response.error / result.error")
        for line in uses:
            with self.subTest(line=line.strip()):
                self.assertRegex(line, r"errorText\(\s*(?:response|result)\.error\b")


RESSOURCES = ROOT / "server-data" / "resources" / "[gunfight]"

FOCUS_NUI = re.compile(r"SetNuiFocus\s*\(\s*true\b")
OVERLAY_TRUE = re.compile(
    r"TriggerEvent\s*\(\s*['\"]gf_lobby:menuOverlay['\"]\s*,\s*true\s*\)"
)
OVERLAY_FALSE = re.compile(
    r"TriggerEvent\s*\(\s*['\"]gf_lobby:menuOverlay['\"]\s*,\s*false\s*\)"
)

# Ressources exclues de la règle, avec leur justification (vérifiée dans leur client.lua) :
EXCEPTIONS_NUI = {
    # Fournit l'événement menuOverlay : son SetNuiFocus(true) est dans le
    # gestionnaire qui réaffiche la page, pas dans un ouvreur à masquer.
    "gf_lobby": "fournit l'overlay; son focus est le gestionnaire menuOverlay",
    # N'ouvre que le choix des armes en partie via gf_ui:loadout_open, lancé par
    # gf_attack/server.lua pendant une manche : jamais au lobby.
    "gf_ui": "loadout de partie (gf_ui:loadout_open), jamais au lobby",
}


class NuiFocusLobbyOverlay(unittest.TestCase):
    """Toute NUI ouverte au lobby masque puis réaffiche la page du lobby."""

    def test_nui_focus_ouverts_masquent_le_lobby(self) -> None:
        candidats = sorted(RESSOURCES.glob("gf_*/client.lua"))
        self.assertTrue(
            candidats, f"aucun client.lua gf_* trouvé dans {RESSOURCES}"
        )
        controllees = {
            chemin.parent.name
            for chemin in candidats
            if chemin.parent.name not in EXCEPTIONS_NUI
            and FOCUS_NUI.search(chemin.read_text(encoding="utf-8"))
        }
        # Garde-fou : les ouvreurs connus ne doivent pas disparaître du contrôle.
        for attendue in ("gf_admin", "gf_menu", "gf_maps", "gf_vehicles"):
            with self.subTest(ressource=attendue, verification="presente"):
                self.assertIn(
                    attendue,
                    controllees,
                    f"{attendue} n'est plus contrôlée : "
                    "son SetNuiFocus(true) a disparu ou la ressource a été exclue",
                )
        for chemin in candidats:
            nom = chemin.parent.name
            if nom in EXCEPTIONS_NUI:
                continue
            source = chemin.read_text(encoding="utf-8")
            if not FOCUS_NUI.search(source):
                continue
            with self.subTest(ressource=nom):
                self.assertRegex(
                    source,
                    OVERLAY_TRUE,
                    f"{nom} ouvre une NUI avec SetNuiFocus(true) sans "
                    "TriggerEvent('gf_lobby:menuOverlay', true) : "
                    "la page du lobby resterait au-dessus",
                )
                self.assertRegex(
                    source,
                    OVERLAY_FALSE,
                    f"{nom} ouvre une NUI avec SetNuiFocus(true) sans "
                    "TriggerEvent('gf_lobby:menuOverlay', false) : "
                    "la page du lobby ne serait jamais réaffichée",
                )


if __name__ == "__main__":
    unittest.main()
