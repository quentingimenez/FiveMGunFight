"""Outils externes requis par les tests du dépôt.

`scripts/verifier.sh` lance la suite avec `GF_OUTILS_OBLIGATOIRES=1` : dans
l'image de vérification, tous les outils sont présents et un outil manquant
doit faire échouer la suite, pas la sauter. Sans cette variable (poste de
développement incomplet), le test est simplement sauté.
"""

from __future__ import annotations

import functools
import os
import shutil
import subprocess
import unittest


def exiger(test_case: unittest.TestCase, nom: str, chemin: str | None) -> None:
    """Exige un outil pour un test : échec si obligatoire, sinon saut."""
    if chemin is not None:
        return
    if os.environ.get("GF_OUTILS_OBLIGATOIRES") == "1":
        test_case.fail(f"outil obligatoire absent : {nom}")
    test_case.skipTest(f"{nom} absent")


def manquant(nom: str) -> None:
    """Signale un outil absent hors d'un TestCase (échec ou saut)."""
    if os.environ.get("GF_OUTILS_OBLIGATOIRES") == "1":
        raise AssertionError(f"outil obligatoire absent : {nom}")
    raise unittest.SkipTest(f"{nom} absent")


@functools.lru_cache(maxsize=1)
def bash() -> str | None:
    """Chemin d'un bash utilisable, ou None s'il est absent ou inutilisable.

    Sous Windows, `shutil.which("bash")` trouve parfois le lanceur WSL alors
    qu'aucune distribution n'est installée : il répond « accès refusé » à
    chaque commande. Un tel lanceur est traité comme absent.
    """
    chemin = shutil.which("bash")
    if chemin is None:
        return None
    try:
        essai = subprocess.run(
            [chemin, "-c", "exit 0"],
            check=False,
            capture_output=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    return chemin if essai.returncode == 0 else None
