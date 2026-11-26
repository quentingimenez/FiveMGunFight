"""Tests du calcul d'équilibrage des armes à partir de fichiers .meta synthétiques.

Aucune valeur ne vient des fichiers du jeu : la config Lua et toutes les
fixtures XML sont inventées pour les tests. Les seules valeurs empruntées sont
les exemples mathématiques de l'hypothèse H4 (200 / 25, 200 / 26, 200 / 24).

Aucun sous-processus, ni réseau, ni base : le module est chargé par chemin.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

RACINE = Path(__file__).resolve().parents[1]
SCRIPT = RACINE / "scripts" / "equilibrage_armes.py"


def charger_module() -> ModuleType:
    """Charge scripts/equilibrage_armes.py sans passer par un sous-processus."""
    spec = importlib.util.spec_from_file_location("equilibrage_armes", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("module equilibrage_armes introuvable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


M = charger_module()

CONFIG_SYNTHETIQUE = r"""-- Configuration synthétique inventée pour les tests.
Config.Weapons = {
    alpha = { name = 'WEAPON_SYNTHRIFLE', label = 'Fusil d\'assaut' },
    -- name = 'WEAPON_FANTOME_COMMENTAIRE',
    beta = { name = "WEAPON_SYNTHPISTOL", label = 'Pistolet synthétique' },
}
Config.StarterWeapons = { 'WEAPON_FANTOME_STARTER' }
Config.Loadouts = {
    attack = { name = 'WEAPON_FANTOME_LOADOUT', armure = 7 },
}
"""


def champs_numeriques(clip: int = 18) -> dict[str, float | int]:
    """Valeurs numériques inventées pour les tests (jamais valeurs du jeu)."""
    return {
        "Damage": 17.0,
        "NetworkPlayerDamageModifier": 1.4,
        "NetworkHeadShotPlayerDamageModifier": 2.0,
        "DamageFallOffRangeMin": 10.0,
        "DamageFallOffRangeMax": 40.0,
        "DamageFallOffModifier": 0.5,
        "TimeBetweenShots": 0.2,
        "BulletsInBatch": 3,
        "ClipSize": clip,
    }


def attributs(champs: dict[str, float | int]) -> dict[str, str]:
    """Convertit les champs synthétiques en attributs XML de .meta."""
    return {cle: str(valeur) for cle, valeur in champs.items()}


def meta_xml(nom: str, champs: dict[str, str], imbrique: str = "") -> str:
    """Construit un fichier .meta synthétique avec un Item CWeaponInfo."""
    lignes = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<Item type="CWeaponInfo">',
        f"  <Name>{nom}</Name>",
    ]
    for cle, valeur in champs.items():
        lignes.append(f'  <{cle} value="{valeur}" />')
    if imbrique:
        lignes.append(imbrique)
    lignes.append("</Item>")
    return "\n".join(lignes) + "\n"


def ecrire_meta(
    racine: Path,
    relatif: str,
    nom: str,
    champs: dict[str, str],
    imbrique: str = "",
) -> Path:
    """Écrit une fixture dans un sous-dossier du dossier temporaire."""
    chemin = racine / relatif
    chemin.parent.mkdir(parents=True, exist_ok=True)
    chemin.write_text(meta_xml(nom, champs, imbrique), encoding="utf-8")
    return chemin


def ecrire_scenario(
    racine: Path, clip_fusil: int = 18, clip_pistolet: int = 18
) -> Path:
    """Écrit la config et deux armes synthétiques ; renvoie le chemin config."""
    config = racine / "config.lua"
    config.write_text(CONFIG_SYNTHETIQUE, encoding="utf-8")
    ecrire_meta(
        racine,
        "update/update.rpf/data/weapons.meta",
        "WEAPON_SYNTHRIFLE",
        attributs(champs_numeriques(clip_fusil)),
    )
    ecrire_meta(
        racine,
        "data/weapons.meta",
        "WEAPON_SYNTHPISTOL",
        attributs(champs_numeriques(clip_pistolet)),
    )
    return config


class Attenuation(unittest.TestCase):
    """H1 : bornes inclusives et interpolation linéaire."""

    def test_bornes_et_prolongements(self) -> None:
        self.assertEqual(1.0, M.attenuation(10.0, 10.0, 40.0, 0.5))
        self.assertEqual(0.5, M.attenuation(40.0, 10.0, 40.0, 0.5))
        self.assertEqual(0.5, M.attenuation(90.0, 10.0, 40.0, 0.5))
        self.assertEqual(1.0, M.attenuation(2.0, 10.0, 40.0, 0.5))

    def test_interpolation_au_milieu(self) -> None:
        self.assertAlmostEqual(0.75, M.attenuation(25.0, 10.0, 40.0, 0.5))


class DegatTir(unittest.TestCase):
    """H2 : produit complet, tête et billes multiples."""

    def test_produit_complet_corps_et_tete(self) -> None:
        champs = champs_numeriques()
        attendu = 17.0 * 1.4 * 0.75 * 3
        self.assertAlmostEqual(attendu, M.degat_tir(champs, 25.0, False))
        self.assertAlmostEqual(attendu * 2.0, M.degat_tir(champs, 25.0, True))

    def test_billes_multipliees_sans_attenuation(self) -> None:
        self.assertAlmostEqual(
            17.0 * 1.4 * 3, M.degat_tir(champs_numeriques(), 5.0, False)
        )


class TirsEtTemps(unittest.TestCase):
    """H3, H4 et H5 : 200 points, arrondi exact et délai entre tirs."""

    def test_tirs_sans_erreur_d_arrondi(self) -> None:
        self.assertEqual(8, M.tirs_pour_tuer(200, 25))
        self.assertEqual(8, M.tirs_pour_tuer(200, 26))
        self.assertEqual(9, M.tirs_pour_tuer(200, 24))

    def test_temps_sans_rechargement(self) -> None:
        self.assertEqual(1750, M.ms_pour_tuer(8, 0.25))
        self.assertEqual(0, M.ms_pour_tuer(1, 0.25))


class Config(unittest.TestCase):
    """Le bloc Config.Weapons seul fournit les noms, dans son ordre."""

    def test_ordre_et_limites_du_bloc(self) -> None:
        self.assertEqual(
            ["WEAPON_SYNTHRIFLE", "WEAPON_SYNTHPISTOL"],
            M.armes_du_config(CONFIG_SYNTHETIQUE),
        )

    def test_bloc_absent(self) -> None:
        with self.assertRaises(M.ErreurEquilibrage):
            M.armes_du_config("Config.StarterWeapons = { 'WEAPON_X' }\n")


class Definitions(unittest.TestCase):
    """Lecture récursive, chemins relatifs et enfants directs uniquement."""

    def test_recursif_et_chemin_relatif(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            ecrire_meta(
                racine,
                "sous/dossier/armes.meta",
                "WEAPON_SYNTHRIFLE",
                attributs(champs_numeriques()),
            )
            (racine / "casse.meta").write_text("<Item type=", encoding="utf-8")
            erreurs = io.StringIO()
            with contextlib.redirect_stderr(erreurs):
                definitions = M.lire_definitions(racine)
            chemins = [candidat[0] for candidat in definitions["WEAPON_SYNTHRIFLE"]]
            self.assertEqual(["sous/dossier/armes.meta"], chemins)
            self.assertIn("Avertissement", erreurs.getvalue())

    def test_dossier_absent(self) -> None:
        with tempfile.TemporaryDirectory() as dossier, self.assertRaises(M.ErreurEquilibrage):
            M.lire_definitions(Path(dossier) / "absent")

    def test_item_imbrique_ne_fournit_pas_de_champ(self) -> None:
        """Un Damage dans un Item imbriqué ne remplace pas le Damage direct."""
        imbrique = (
            '    <Item type="CComponent">\n'
            '      <Damage value="999" />\n'
            "    </Item>"
        )
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            ecrire_meta(
                racine,
                "a/direct.meta",
                "WEAPON_SYNTHRIFLE",
                attributs(champs_numeriques()),
                imbrique,
            )
            sans_damage = attributs(champs_numeriques())
            del sans_damage["Damage"]
            ecrire_meta(
                racine,
                "b/imbrique.meta",
                "WEAPON_SYNTHPISTOL",
                sans_damage,
                imbrique,
            )
            with contextlib.redirect_stderr(io.StringIO()):
                definitions = M.lire_definitions(racine)
            self.assertEqual(
                17.0, definitions["WEAPON_SYNTHRIFLE"][0][1]["Damage"]
            )
            with self.assertRaises(M.ErreurEquilibrage) as capture:
                M.choisir("WEAPON_SYNTHPISTOL", definitions["WEAPON_SYNTHPISTOL"])
            self.assertIn("Damage", str(capture.exception))


class Choix(unittest.TestCase):
    """Priorité update, ambiguïtés et champs requis."""

    def test_priorite_update(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            ecrire_meta(
                racine,
                "update/update.rpf/d/meta.meta",
                "WEAPON_X",
                attributs(champs_numeriques(clip=5)),
            )
            ecrire_meta(
                racine,
                "d/meta.meta",
                "WEAPON_X",
                attributs(champs_numeriques(clip=9)),
            )
            definitions = M.lire_definitions(racine)
            source, champs = M.choisir("WEAPON_X", definitions["WEAPON_X"])
            self.assertTrue(source.startswith("update/update.rpf/"))
            self.assertEqual(5, champs["ClipSize"])

    def test_ambiguite_deux_update(self) -> None:
        candidats = [
            ("update/update.rpf/a.meta", champs_numeriques()),
            ("update/update.rpf/b.meta", champs_numeriques()),
        ]
        with self.assertRaises(M.ErreurEquilibrage) as capture:
            M.choisir("WEAPON_X", candidats)
        self.assertIn("a.meta", str(capture.exception))
        self.assertIn("b.meta", str(capture.exception))

    def test_arme_introuvable(self) -> None:
        with self.assertRaises(M.ErreurEquilibrage):
            M.choisir("WEAPON_X", [])

    def test_champ_manquant(self) -> None:
        champs = champs_numeriques()
        del champs["ClipSize"]
        with self.assertRaises(M.ErreurEquilibrage) as capture:
            M.choisir("WEAPON_X", [("d/meta.meta", champs)])
        self.assertIn("ClipSize", str(capture.exception))


class TableauEtSortie(unittest.TestCase):
    """Construction du tableau et sorties markdown/json via main()."""

    def test_chargeur_insuffisant_dans_tableau_et_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            config = ecrire_scenario(racine, clip_fusil=2)
            definitions = M.lire_definitions(racine)
            armes = M.armes_du_config(config.read_text(encoding="utf-8"))
            resultats = M.tableau(armes, definitions, [10])
            self.assertFalse(
                resultats[0]["mesures"][0]["corps"]["chargeur_suffit"]
            )
            sortie, erreurs = io.StringIO(), io.StringIO()
            with (
                contextlib.redirect_stdout(sortie),
                contextlib.redirect_stderr(erreurs),
            ):
                code = M.main(
                    [
                        str(racine),
                        "--config",
                        str(config),
                        "--distances",
                        "10",
                    ]
                )
            self.assertEqual(M.SORTIE_OK, code)
            lignes_fusil = [
                ligne
                for ligne in sortie.getvalue().splitlines()
                if ligne.startswith("| WEAPON_SYNTHRIFLE")
            ]
            self.assertTrue(lignes_fusil)
            self.assertIn("3 tirs /", lignes_fusil[0])
            self.assertIn("ms *", lignes_fusil[0])
            lignes_pistolet = [
                ligne
                for ligne in sortie.getvalue().splitlines()
                if ligne.startswith("| WEAPON_SYNTHPISTOL")
            ]
            self.assertTrue(lignes_pistolet)
            self.assertNotIn("ms *", lignes_pistolet[0])

    def test_main_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            config = ecrire_scenario(racine)
            sortie, erreurs = io.StringIO(), io.StringIO()
            with (
                contextlib.redirect_stdout(sortie),
                contextlib.redirect_stderr(erreurs),
            ):
                code = M.main([str(racine), "--config", str(config)])
            self.assertEqual(M.SORTIE_OK, code)
            self.assertEqual("", erreurs.getvalue())
            self.assertIn("WEAPON_SYNTHRIFLE", sortie.getvalue())
            self.assertIn("tirs /", sortie.getvalue())
            lignes_table = sortie.getvalue().splitlines()
            self.assertIn("Entre deux tirs (ms)", lignes_table[0])
            self.assertIn("---", lignes_table[1])

    def test_main_json(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            config = ecrire_scenario(racine)
            sortie = io.StringIO()
            with contextlib.redirect_stdout(sortie):
                code = M.main(
                    [str(racine), "--config", str(config), "--format", "json"]
                )
            self.assertEqual(M.SORTIE_OK, code)
            donnees = json.loads(sortie.getvalue())
            self.assertEqual(
                ["WEAPON_SYNTHRIFLE", "WEAPON_SYNTHPISTOL"],
                [ligne["arme"] for ligne in donnees],
            )
            self.assertEqual(
                {
                    "arme",
                    "source",
                    "degat",
                    "cadence_ms",
                    "chargeur",
                    "billes",
                    "mesures",
                },
                set(donnees[0]),
            )
            self.assertEqual(
                [10, 25, 50], [m["distance"] for m in donnees[0]["mesures"]]
            )
            self.assertEqual(
                {"tirs", "ms", "chargeur_suffit"},
                set(donnees[0]["mesures"][0]["corps"]),
            )

    def test_main_dossier_absent(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            config = racine / "config.lua"
            config.write_text(CONFIG_SYNTHETIQUE, encoding="utf-8")
            erreurs = io.StringIO()
            with contextlib.redirect_stderr(erreurs):
                code = M.main([str(racine / "absent"), "--config", str(config)])
            self.assertEqual(M.SORTIE_ERREUR, code)
            self.assertIn("Erreur :", erreurs.getvalue())
            self.assertIn("introuvable", erreurs.getvalue())

    def test_distances_invalides(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            config = ecrire_scenario(racine)
            for valeur in ("10,x", "10,-5"):
                with (
                    self.subTest(valeur=valeur),
                    contextlib.redirect_stderr(io.StringIO()),
                    self.assertRaises(SystemExit) as capture,
                ):
                    M.main(
                        [
                            str(racine),
                            "--config",
                            str(config),
                            "--distances",
                            valeur,
                        ]
                    )
                self.assertEqual(2, capture.exception.code)


if __name__ == "__main__":
    unittest.main()
