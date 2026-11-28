"""Tests du nettoyage Docker borné et compatible avec deux générations de buildx.

`scripts/nettoyer-docker.sh` doit borner le cache de construction avec
`--max-used-space` quand buildx le connaît, retomber sur `--keep-storage`
quand il n'existe pas, et échouer proprement si aucune des deux options
n'est disponible. Un faux `docker`, placé en tête de PATH, journalise les
appels et simulate `docker info`, `system df`, `image prune` et
`builder prune --help` (la sortie de l'aide dépend de `GF_DOCKER_AIDE`).

Lancement local :  python -m unittest discover -s tests -v
En CI          :  python3 -m unittest discover -s tests -v
"""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from outils import bash, exiger

RACINE = Path(__file__).resolve().parents[1]
SCRIPT = RACINE / "scripts" / "nettoyer-docker.sh"

MESSAGE_SANS_BORNAGE = (
    "buildx ne permet pas de borner le cache : "
    "lance bash scripts/nettoyer-docker.sh --tout"
)

# Faux `docker` : chaque appel est journalisé dans $FAUX_DOCKER_JOURNAL.
# L'aide de `builder prune` est contrôlée par GF_DOCKER_AIDE, et `info`
# peut échouer avec GF_DOCKER_INFO_ECHEC=1. Pas de `set -e` combiné à
# `[ cond ] && exit 1` (une condition fausse ferait sortir en 1).
FAUX_DOCKER = r"""#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAUX_DOCKER_JOURNAL"
commande="${1:-}"
if [ "$commande" = "info" ]; then
  if [ "${GF_DOCKER_INFO_ECHEC:-0}" = "1" ]; then
    echo "Cannot connect to the Docker daemon" >&2
    exit 1
  fi
  echo "Server Version: 28.0.0"
  exit 0
fi
if [ "$commande" = "builder" ] && [ "${2:-}" = "prune" ] && [ "${3:-}" = "--help" ]; then
  printf '%s\n' "${GF_DOCKER_AIDE:-}"
  exit 0
fi
exit 0
"""


class NettoyerDockerBornage(unittest.TestCase):
    """Le bornage s'adapte aux options réellement offertes par buildx."""

    def setUp(self) -> None:
        executable = bash()
        exiger(self, "bash", executable)
        self.executable = executable
        temporaire = tempfile.TemporaryDirectory(prefix="nettoyer-docker-")
        self.addCleanup(temporaire.cleanup)
        dossier = Path(temporaire.name)
        self.bin = dossier / "bin"
        self.bin.mkdir()
        faux_docker = self.bin / "docker"
        faux_docker.write_text(FAUX_DOCKER, encoding="utf-8", newline="\n")
        faux_docker.chmod(0o755)
        self.journal = dossier / "journal.txt"
        self.journal.write_text("", encoding="utf-8")

    def lancer(
        self,
        *arguments: str,
        aide: str = "",
        cache_max: str | None = None,
        info_echec: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        environnement = os.environ.copy()
        environnement["PATH"] = os.pathsep.join(
            [str(self.bin), environnement.get("PATH", "")]
        )
        environnement["FAUX_DOCKER_JOURNAL"] = str(self.journal)
        environnement["GF_DOCKER_AIDE"] = aide
        environnement["GF_DOCKER_INFO_ECHEC"] = "1" if info_echec else "0"
        if cache_max is not None:
            environnement["GF_CACHE_MAX"] = cache_max
        else:
            environnement.pop("GF_CACHE_MAX", None)
        return subprocess.run(
            [self.executable, str(SCRIPT), *arguments],
            cwd=str(RACINE),
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
            env=environnement,
        )

    def appels_prune_borne(self) -> list[str]:
        """Lignes de `builder prune` hors `--help` (les appels de bornage)."""
        return [
            ligne
            for ligne in self.journal.read_text(encoding="utf-8").splitlines()
            if ligne.startswith("builder prune") and "--help" not in ligne
        ]

    def test_max_used_space_quand_l_aide_le_propose(self) -> None:
        aide = "Usage:  --max-used-space bytes  --keep-storage bytes"
        resultat = self.lancer(aide=aide)
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        prunes = self.appels_prune_borne()
        self.assertEqual(len(prunes), 1, prunes)
        self.assertIn("--max-used-space", prunes[0])
        self.assertIn("4GB", prunes[0])
        self.assertNotIn("--keep-storage", prunes[0])

    def test_keep_storage_en_repli(self) -> None:
        resultat = self.lancer(aide="Usage:  --keep-storage bytes")
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        prunes = self.appels_prune_borne()
        self.assertEqual(len(prunes), 1, prunes)
        self.assertIn("--keep-storage", prunes[0])
        self.assertIn("4GB", prunes[0])
        self.assertNotIn("--max-used-space", prunes[0])

    def test_aucune_option_connue_echoue(self) -> None:
        resultat = self.lancer(aide="Usage:  docker builder prune [OPTIONS]")
        self.assertEqual(resultat.returncode, 1, resultat.stdout + resultat.stderr)
        self.assertIn(MESSAGE_SANS_BORNAGE, resultat.stderr)
        self.assertEqual(
            self.appels_prune_borne(), [], "prune borné malgré une aide muette"
        )

    def test_cache_max_personnalise(self) -> None:
        resultat = self.lancer(
            aide="Usage:  --max-used-space bytes", cache_max="2GB"
        )
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        prunes = self.appels_prune_borne()
        self.assertEqual(len(prunes), 1, prunes)
        self.assertIn("--max-used-space", prunes[0])
        self.assertIn("2GB", prunes[0])
        self.assertNotIn("4GB", prunes[0])

    def test_tout_n_utilise_aucune_option_de_bornage(self) -> None:
        resultat = self.lancer("--tout", aide="Usage:  --max-used-space bytes")
        self.assertEqual(resultat.returncode, 0, resultat.stderr)
        appels = self.journal.read_text(encoding="utf-8").splitlines()
        for ligne in appels:
            self.assertNotIn("--max-used-space", ligne)
            self.assertNotIn("--keep-storage", ligne)
        self.assertTrue(
            any(ligne.startswith("builder prune --all --force") for ligne in appels),
            "aucun prune --all --force",
        )

    def test_docker_injoignable(self) -> None:
        resultat = self.lancer(info_echec=True)
        self.assertEqual(resultat.returncode, 1, resultat.stdout + resultat.stderr)
        self.assertIn("Docker injoignable", resultat.stderr)


if __name__ == "__main__":
    unittest.main()
