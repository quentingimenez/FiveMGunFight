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


class LuaUnitTests(unittest.TestCase):
    def test_lua_suites_pass(self) -> None:
        lua = shutil.which("lua5.4") or shutil.which("lua")
        if lua is None:
            self.skipTest("lua absent (install Lua 5.4; CI provides it)")
        suites = sorted((ROOT / "tests" / "lua").glob("*.lua"))
        self.assertTrue(suites, "no Lua suite found")
        for suite in suites:
            with self.subTest(suite=suite.name):
                result = run([lua, str(suite.relative_to(ROOT))])
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class JsUnitTests(unittest.TestCase):
    def test_node_suites_pass(self) -> None:
        node = shutil.which("node")
        if node is None:
            self.skipTest("node absent (CI provides it)")
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


if __name__ == "__main__":
    unittest.main()
