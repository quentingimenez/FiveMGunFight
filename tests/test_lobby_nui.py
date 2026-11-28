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


BASE_RESSOURCES = ROOT / "server-data" / "resources"
RESSOURCES = BASE_RESSOURCES / "[gunfight]"

FOCUS_NUI = re.compile(r"SetNuiFocus\s*\(\s*true\b")
PUSH_LAYER = re.compile(r"exports\.gf_ui:PushLayer\s*\(")
POP_LAYER = re.compile(r"exports\.gf_ui:PopLayer\s*\(")
OVERLAY = "gf_lobby:menuOverlay"

# Ressources exclues de la règle, avec leur justification (vérifiée dans leur client.lua) :
EXCEPTIONS_NUI = {
    # gf_ui possède la pile des calques : gf_lobby s'abonne à
    # gf_ui:layersChanged pour masquer/réafficher sa page, plus aucun client
    # ne doit appeler directement menuOverlay.
    "gf_lobby": "s'abonne à gf_ui:layersChanged",
    # N'ouvre que le choix des armes en partie via gf_ui:loadout_open, lancé par
    # gf_attack/server.lua pendant une manche : jamais au lobby.
    "gf_ui": "loadout de partie (gf_ui:loadout_open), jamais au lobby",
}


class NuiFocusLobbyOverlay(unittest.TestCase):
    """Toute NUI ouverte au lobby empile un calque gf_ui et le retire à la fermeture."""

    def test_nui_focus_ouverts_masquent_le_lobby(self) -> None:
        # Aucun client ne doit encore piloter l'overlay du lobby à la main :
        # c'est désormais la pile de gf_ui qui pilote gf_lobby:layersChanged.
        for chemin in sorted(BASE_RESSOURCES.rglob("*.lua")):
            with self.subTest(ressource=str(chemin.relative_to(ROOT))):
                self.assertNotIn(
                    OVERLAY,
                    chemin.read_text(encoding="utf-8"),
                    f"{chemin} utilise encore {OVERLAY} : "
                    "gf_ui possède la pile des calques, utilisez PushLayer/PopLayer",
                )

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
                    PUSH_LAYER,
                    f"{nom} ouvre une NUI avec SetNuiFocus(true) sans "
                    "exports.gf_ui:PushLayer(...) : "
                    "sans calque empilé, le lobby resterait affiché",
                )
                self.assertRegex(
                    source,
                    POP_LAYER,
                    f"{nom} ouvre une NUI avec SetNuiFocus(true) sans "
                    "exports.gf_ui:PopLayer(...) : "
                    "sans retrait de calque, le lobby ne reviendrait jamais",
                )


if __name__ == "__main__":
    unittest.main()
