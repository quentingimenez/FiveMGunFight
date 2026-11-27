"""Tests de la comparaison de rendu par SSIM, avec un encodeur PNG synthétique.

Toutes les fixtures sont générées en mémoire puis écrites dans un dossier
temporaire : aucune image, aucune capture et aucun fichier de travail ne reste
dans le dépôt. Le module testé est chargé par chemin, sans sous-processus,
sans réseau et sans dépendance autre que la bibliothèque standard.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import random
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from types import ModuleType

RACINE = Path(__file__).resolve().parents[1]
SCRIPT = RACINE / "scripts" / "comparer_rendu.py"


def charger_module() -> ModuleType:
    """Charge scripts/comparer_rendu.py sans passer par un sous-processus."""
    spec = importlib.util.spec_from_file_location("comparer_rendu", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("module comparer_rendu introuvable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


M = charger_module()


def _paeth(gauche: int, dessus: int, diagonal: int) -> int:
    """Prédicteur Paeth de l'encodeur de test."""
    estimation = gauche + dessus - diagonal
    distances = (
        abs(estimation - gauche),
        abs(estimation - dessus),
        abs(estimation - diagonal),
    )
    if distances[0] <= distances[1] and distances[0] <= distances[2]:
        return gauche
    if distances[1] <= distances[2]:
        return dessus
    return diagonal


def _filtrer(
    ligne: bytes, precedente: bytes, octets_par_pixel: int, filtre: int
) -> bytes:
    """Applique un filtre PNG forward 0 à 4 à une ligne de pixels."""
    resultat = bytearray(len(ligne))
    for indice, valeur in enumerate(ligne):
        gauche = ligne[indice - octets_par_pixel] if indice >= octets_par_pixel else 0
        dessus = precedente[indice]
        diagonal = (
            precedente[indice - octets_par_pixel] if indice >= octets_par_pixel else 0
        )
        if filtre == 0:
            prediction = 0
        elif filtre == 1:
            prediction = gauche
        elif filtre == 2:
            prediction = dessus
        elif filtre == 3:
            prediction = (gauche + dessus) // 2
        elif filtre == 4:
            prediction = _paeth(gauche, dessus, diagonal)
        else:
            raise ValueError("filtre inconnu dans l'encodeur de test")
        resultat[indice] = (valeur - prediction) & 0xFF
    return bytes(resultat)


def _bloc(
    type_bloc: bytes, donnees: bytes, crc_invalide: bool = False
) -> bytes:
    """Construit un bloc PNG avec CRC calculé, ou volontairement faux."""
    crc = zlib.crc32(type_bloc + donnees) & 0xFFFFFFFF
    if crc_invalide:
        crc ^= 0x1
    return (
        struct.pack(">I", len(donnees))
        + type_bloc
        + donnees
        + struct.pack(">I", crc)
    )


def creer_png(
    pixels: list[list[tuple[int, ...]]],
    type_couleur: int = 2,
    filtres: list[int] | None = None,
    morceaux_idat: int = 1,
    profondeur: int = 8,
    entrelace: int = 0,
    signature: bytes | None = None,
    crc_idat_invalide: bool = False,
    zlib_invalide: bool = False,
    tronquer: int = 0,
) -> bytes:
    """Encode un PNG synthétique, avec filtres par ligne et IDAT découpés."""
    hauteur = len(pixels)
    largeur = len(pixels[0])
    octets_par_pixel = {0: 1, 2: 3, 3: 1, 6: 4}[type_couleur]
    lignes: list[bytes] = []
    precedente = bytes(largeur * octets_par_pixel)
    for y, ligne in enumerate(pixels):
        brut = bytes(
            valeur for pixel in ligne for valeur in pixel[:octets_par_pixel]
        )
        filtre = filtres[y] if filtres is not None else 0
        lignes.append(
            bytes((filtre,))
            + _filtrer(brut, precedente, octets_par_pixel, filtre)
        )
        precedente = brut

    flux = b"donnees-zlib-invalides" if zlib_invalide else zlib.compress(
        b"".join(lignes)
    )
    taille = max(1, len(flux) // morceaux_idat)
    morceaux = [flux[i : i + taille] for i in range(0, len(flux), taille)]
    entete = struct.pack(
        ">IIBBBBB", largeur, hauteur, profondeur, type_couleur, 0, 0, entrelace
    )
    donnees = (
        (b"\x89PNG\r\n\x1a\n" if signature is None else signature)
        + _bloc(b"IHDR", entete)
        + b"".join(
            _bloc(b"IDAT", morceau, crc_invalide=crc_idat_invalide)
            for morceau in morceaux
        )
        + _bloc(b"IEND", b"")
    )
    return donnees[: len(donnees) - tronquer] if tronquer else donnees


def ecrire_png(racine: Path, nom: str, **options: object) -> Path:
    """Écrit une fixture PNG dans le dossier temporaire et renvoie son chemin."""
    chemin = racine / nom
    chemin.write_bytes(creer_png(**options))
    return chemin


def pixels_de_base(type_couleur: int) -> list[list[tuple[int, ...]]]:
    """Pixels synthétiques de 3x2 pour les trois types de couleur lus."""
    base = [
        [(10, 20, 30), (40, 50, 60), (70, 80, 90)],
        [(1, 2, 3), (4, 5, 6), (7, 8, 9)],
    ]
    if type_couleur == 0:
        return [[(pixel[0],) for pixel in ligne] for ligne in base]
    if type_couleur == 2:
        return base
    return [
        [pixel + (200 - 10 * index,) for index, pixel in enumerate(ligne)]
        for ligne in base
    ]


def degrade(taille: int = 32) -> list[list[float]]:
    """Dégradé déterministe, continu en x et y."""
    return [
        [float((7 * x + 3 * y) % 256) for x in range(taille)]
        for y in range(taille)
    ]


def _ssim_naive(
    reference: list[list[float]], capture: list[list[float]]
) -> float:
    """Implémentation directe, sans images intégrales, pour servir de référence."""
    hauteur = len(reference)
    largeur = len(reference[0])
    taille = 7
    demi = taille // 2
    nombre = taille * taille
    c1 = (0.01 * 255) ** 2
    c2 = (0.03 * 255) ** 2
    total = 0.0
    fenetres = 0
    for cy in range(demi, hauteur - demi):
        for cx in range(demi, largeur - demi):
            positions = [
                (y, x)
                for y in range(cy - demi, cy + demi + 1)
                for x in range(cx - demi, cx + demi + 1)
            ]
            valeurs_x = [reference[y][x] for y, x in positions]
            valeurs_y = [capture[y][x] for y, x in positions]
            moyenne_x = sum(valeurs_x) / nombre
            moyenne_y = sum(valeurs_y) / nombre
            variance_x = sum((v - moyenne_x) ** 2 for v in valeurs_x) / (nombre - 1)
            variance_y = sum((v - moyenne_y) ** 2 for v in valeurs_y) / (nombre - 1)
            covariance = sum(
                (gx - moyenne_x) * (cyy - moyenne_y)
                for gx, cyy in zip(valeurs_x, valeurs_y)
            ) / (nombre - 1)
            numerateur = (2 * moyenne_x * moyenne_y + c1) * (
                2 * covariance + c2
            )
            denominateur = (
                moyenne_x**2 + moyenne_y**2 + c1
            ) * (variance_x + variance_y + c2)
            total += numerateur / denominateur
            fenetres += 1
    return total / fenetres


class LecturePNG(unittest.TestCase):
    """Décodage pur Python des PNG valides et refus des cas invalides."""

    def test_couleurs_et_filtres(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            for type_couleur in (0, 2, 6):
                pixels = pixels_de_base(type_couleur)
                for filtre in range(5):
                    with self.subTest(type_couleur=type_couleur, filtre=filtre):
                        chemin = ecrire_png(
                            racine,
                            f"img_{type_couleur}_{filtre}.png",
                            pixels=pixels,
                            type_couleur=type_couleur,
                            filtres=[filtre, filtre],
                        )
                        image = M.lire_png(chemin)
                        self.assertEqual(3, image.largeur)
                        self.assertEqual(2, image.hauteur)
                        self.assertEqual(pixels, image.pixels)

    def test_idats_multiples(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            pixels = pixels_de_base(2) + [[(9, 8, 7), (6, 5, 4), (3, 2, 1)]]
            chemin = ecrire_png(
                Path(dossier),
                "idats.png",
                pixels=pixels,
                filtres=[0, 1, 2, 3],
                morceaux_idat=4,
            )
            self.assertEqual(pixels, M.lire_png(chemin).pixels)

    def test_cas_invalides(self) -> None:
        pixels = pixels_de_base(2)
        cas = {
            "signature": {"signature": b"\x89PNG\r\n\x1a\x00"},
            "crc": {"crc_idat_invalide": True},
            "entrelace": {"entrelace": 1},
            "16 bits": {"profondeur": 16},
            "palette": {"type_couleur": 3},
            "zlib": {"zlib_invalide": True},
            "tronque": {"tronquer": 10},
        }
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            for nom, options in cas.items():
                with self.subTest(cas=nom):
                    chemin = ecrire_png(
                        racine, "invalide.png", pixels=pixels, **options
                    )
                    with self.assertRaises(ValueError):
                        M.lire_png(chemin)
            with self.assertRaises(ValueError):
                M.lire_png(racine / "absent.png")


class Conversion(unittest.TestCase):
    """Luminance et réduction par moyenne de blocs."""

    def test_en_gris(self) -> None:
        image = M.Image(2, 1, [[(10, 20, 30), (200, 100, 0)]])
        gris = M.en_gris(image)
        self.assertAlmostEqual(0.299 * 10 + 0.587 * 20 + 0.114 * 30, gris[0][0])
        self.assertAlmostEqual(0.299 * 200 + 0.587 * 100, gris[0][1])
        self.assertEqual([[42.0]], M.en_gris(M.Image(1, 1, [[(42,)]])))
        self.assertEqual(
            [[0.299 * 10 + 0.587 * 20 + 0.114 * 30]],
            M.en_gris(M.Image(1, 1, [[(10, 20, 30, 0)]])),
        )

    def test_reduction_aligned(self) -> None:
        gris = [
            [0.0, 0.0, 1.0, 1.0],
            [0.0, 0.0, 1.0, 1.0],
            [2.0, 2.0, 3.0, 3.0],
            [2.0, 2.0, 3.0, 3.0],
        ]
        self.assertEqual([[0.0, 1.0], [2.0, 3.0]], M.reduire(gris, 2))

    def test_reduction_fractionnaire(self) -> None:
        gris = [[0.0, 0.0, 0.0], [0.0, 100.0, 0.0], [0.0, 0.0, 0.0]]
        reduction = M.reduire(gris, 2)
        self.assertEqual(2, len(reduction))
        self.assertTrue(all(len(ligne) == 2 for ligne in reduction))
        attendu = 100.0 * 0.25 / 2.25
        for ligne in reduction:
            for valeur in ligne:
                self.assertAlmostEqual(attendu, valeur, places=9)

    def test_dimensions_proportionnelles(self) -> None:
        gris = [[float(x) for x in range(640)] for _ in range(360)]
        reduction = M.reduire(gris, 320)
        self.assertEqual(180, len(reduction))
        self.assertEqual(320, len(reduction[0]))


class IndiceSSIM(unittest.TestCase):
    """Formule locale, fenêtres, variance d'échantillon et masques."""

    def test_identique_et_differents(self) -> None:
        image = degrade()
        self.assertEqual(1.0, M.ssim(image, image))
        generateur = random.Random(1234)
        bruit = [
            [float(generateur.randrange(256)) for _ in range(32)]
            for _ in range(32)
        ]
        self.assertLess(M.ssim(image, bruit), 0.5)
        generateur = random.Random(7)
        leger = [
            [valeur + generateur.randint(-2, 2) for valeur in ligne]
            for ligne in image
        ]
        self.assertGreater(M.ssim(image, leger), 0.9)

    def test_valeur_reference_naive(self) -> None:
        reference = [
            [float((11 * x + 7 * y + (x * y) % 5) % 256) for x in range(16)]
            for y in range(16)
        ]
        capture = [
            [
                reference[y][x] + ((3 * x + 2 * y) % 5) - 2
                for x in range(16)
            ]
            for y in range(16)
        ]
        self.assertAlmostEqual(
            _ssim_naive(reference, capture), M.ssim(reference, capture), delta=1e-9
        )

    def test_masque_interne_et_externe(self) -> None:
        base = [[100.0] * 40 for _ in range(40)]
        interne = [ligne[:] for ligne in base]
        for y in range(12, 24):
            for x in range(12, 24):
                interne[y][x] = 200.0
        self.assertEqual(1.0, M.ssim(base, interne, [(0.15, 0.15, 0.75, 0.75)]))

        externe = [ligne[:] for ligne in base]
        for y in range(12, 24):
            for x in range(20, 32):
                externe[y][x] = 0.0
        self.assertLess(M.ssim(base, externe, [(0.0, 0.0, 0.15, 1.0)]), 1.0)

    def test_aucune_fenetre_utilisable(self) -> None:
        petit = [[0.0] * 6 for _ in range(6)]
        with self.assertRaises(ValueError):
            M.ssim(petit, petit)
        grand = [[10.0] * 32 for _ in range(32)]
        with self.assertRaises(ValueError):
            M.ssim(grand, grand, [(0.0, 0.0, 1.0, 1.0)])


class Configuration(unittest.TestCase):
    """Validation stricte du fichier JSON de configuration."""

    def test_configuration_valide(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            chemin = Path(dossier) / "config.json"
            chemin.write_text(
                json.dumps(
                    {
                        "seuil": 0.9,
                        "largeur": 320,
                        "masques": [[0.1, 0.2, 0.3, 0.4]],
                        "description": "Lobby",
                    }
                ),
                encoding="utf-8",
            )
            config = M.charger_config(chemin)
            self.assertEqual(
                {"seuil", "largeur", "masques", "description"}, set(config)
            )
            self.assertIsInstance(config["seuil"], float)
            self.assertAlmostEqual(0.9, config["seuil"])
            self.assertEqual(320, config["largeur"])
            self.assertEqual([(0.1, 0.2, 0.3, 0.4)], config["masques"])
            self.assertEqual("Lobby", config["description"])

    def test_valeurs_par_defaut(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            chemin = Path(dossier) / "config.json"
            chemin.write_text('{"seuil": 0.8, "largeur": 64}', encoding="utf-8")
            config = M.charger_config(chemin)
            self.assertEqual([], config["masques"])
            self.assertEqual("", config["description"])

    def test_configurations_invalides(self) -> None:
        invalides: list[object] = [
            {"seuil": 1.1, "largeur": 10},
            {"seuil": -0.1, "largeur": 10},
            {"seuil": True, "largeur": 10},
            {"seuil": "0.9", "largeur": 10},
            {"seuil": 0.9, "largeur": 0},
            {"seuil": 0.9, "largeur": True},
            {"seuil": 0.9, "largeur": 3.5},
            {"seuil": 0.9, "largeur": 10, "masques": "non"},
            {"seuil": 0.9, "largeur": 10, "masques": [[0, 0, 1]]},
            {"seuil": 0.9, "largeur": 10, "masques": [[0.4, 0.1, 0.3, 0.9]]},
            {"seuil": 0.9, "largeur": 10, "masques": [[0, 0, 1, 2]]},
            {"seuil": 0.9, "largeur": 10, "description": 3},
        ]
        with tempfile.TemporaryDirectory() as dossier:
            chemin = Path(dossier) / "config.json"
            for contenu in invalides + ["[]", "{", '{"seuil": NaN, "largeur": 10}']:
                with self.subTest(contenu=contenu):
                    texte = contenu if isinstance(contenu, str) else json.dumps(contenu)
                    chemin.write_text(texte, encoding="utf-8")
                    with self.assertRaises(ValueError):
                        M.charger_config(chemin)
            with self.assertRaises(ValueError):
                M.charger_config(Path(dossier) / "absent.json")


class Comparaison(unittest.TestCase):
    """Fonction pure comparer() et contrôle du rapport de forme."""

    def test_comparer_images_identiques(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            pixels = [[(x * 3, y * 5, 100) for x in range(32)] for y in range(32)]
            capture = ecrire_png(racine, "capture.png", pixels=pixels)
            reference = ecrire_png(racine, "reference.png", pixels=pixels)
            resultat = M.comparer(
                capture,
                reference,
                {"seuil": 0.9, "largeur": 32, "masques": (), "description": ""},
            )
            self.assertEqual(
                {"indice", "seuil", "fenetres", "ok"}, set(resultat)
            )
            self.assertEqual(1.0, resultat["indice"])
            self.assertEqual(0.9, resultat["seuil"])
            self.assertGreater(resultat["fenetres"], 0)
            self.assertTrue(resultat["ok"])

    def test_comparer_sous_le_seuil(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            gris_reference = degrade()
            reference = ecrire_png(
                racine,
                "reference.png",
                pixels=[
                    [(int(valeur), int(valeur), int(valeur)) for valeur in ligne]
                    for ligne in gris_reference
                ],
            )
            generateur = random.Random(99)
            bruit = [
                [(generateur.randrange(256),) * 3 for _ in range(32)]
                for _ in range(32)
            ]
            capture = ecrire_png(racine, "capture.png", pixels=bruit)
            resultat = M.comparer(
                capture, reference, {"seuil": 0.9, "largeur": 32}
            )
            self.assertFalse(resultat["ok"])

    def test_rapports_et_hauteurs_incompatibles(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            carre = ecrire_png(
                racine,
                "carre.png",
                pixels=[[(10, 20, 30)] * 32 for _ in range(32)],
            )
            rectangle = ecrire_png(
                racine,
                "rectangle.png",
                pixels=[[(10, 20, 30)] * 64 for _ in range(32)],
            )
            with self.assertRaises(ValueError):
                M.comparer(rectangle, carre, {"seuil": 0.9, "largeur": 32})

            presque_carre = ecrire_png(
                racine,
                "presque.png",
                pixels=[[(10, 20, 30)] * 100 for _ in range(100)],
            )
            reference = ecrire_png(
                racine,
                "reference.png",
                pixels=[[(10, 20, 30)] * 201 for _ in range(100)],
            )
            with self.assertRaises(ValueError):
                M.comparer(
                    presque_carre, reference, {"seuil": 0.9, "largeur": 320}
                )


class LigneDeCommande(unittest.TestCase):
    """Codes de sortie, affichage et JSON via main()."""

    def test_succes_et_affichage(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            pixels = [[(x * 3, y * 5, 100) for x in range(32)] for y in range(32)]
            capture = ecrire_png(racine, "capture.png", pixels=pixels)
            reference = ecrire_png(racine, "reference.png", pixels=pixels)
            config = racine / "config.json"
            config.write_text('{"seuil": 0.9, "largeur": 32}', encoding="utf-8")
            sortie, erreurs = io.StringIO(), io.StringIO()
            with (
                contextlib.redirect_stdout(sortie),
                contextlib.redirect_stderr(erreurs),
            ):
                code = M.main([str(capture), str(reference), "--config", str(config)])
            self.assertEqual(0, code)
            self.assertEqual("", erreurs.getvalue())
            self.assertRegex(sortie.getvalue(), r"Indice SSIM : \d+\.\d{4}")
            self.assertRegex(sortie.getvalue(), r"Seuil : \d+\.\d{4}")
            self.assertIn("1.0000", sortie.getvalue())
            self.assertIn("0.9000", sortie.getvalue())
            self.assertIn("Fenêtres comptées", sortie.getvalue())
            self.assertIn("OK", sortie.getvalue())

    def test_echec_sous_le_seuil(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            capture = ecrire_png(
                racine,
                "capture.png",
                pixels=[[(0, 0, 0)] * 32 for _ in range(32)],
            )
            reference = ecrire_png(
                racine,
                "reference.png",
                pixels=[[(255, 255, 255)] * 32 for _ in range(32)],
            )
            config = racine / "config.json"
            config.write_text('{"seuil": 0.9, "largeur": 32}', encoding="utf-8")
            sortie, erreurs = io.StringIO(), io.StringIO()
            with (
                contextlib.redirect_stdout(sortie),
                contextlib.redirect_stderr(erreurs),
            ):
                code = M.main([str(capture), str(reference), "--config", str(config)])
            self.assertEqual(1, code)
            self.assertIn("ÉCHEC", sortie.getvalue())
            self.assertEqual("", erreurs.getvalue())

    def test_json(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            pixels = [[(x * 3, y * 5, 100) for x in range(32)] for y in range(32)]
            capture = ecrire_png(racine, "capture.png", pixels=pixels)
            reference = ecrire_png(racine, "reference.png", pixels=pixels)
            config = racine / "config.json"
            config.write_text(
                '{"seuil": 0.95, "largeur": 32, "description": "Lobby"}',
                encoding="utf-8",
            )
            sortie = io.StringIO()
            with contextlib.redirect_stdout(sortie):
                code = M.main(
                    [str(capture), str(reference), "--config", str(config), "--json"]
                )
            self.assertEqual(0, code)
            donnees = json.loads(sortie.getvalue())
            self.assertEqual({"indice", "seuil", "fenetres", "ok"}, set(donnees))
            self.assertEqual(round(donnees["indice"], 4), donnees["indice"])
            self.assertAlmostEqual(0.95, donnees["seuil"])
            self.assertIsInstance(donnees["fenetres"], int)
            self.assertIs(donnees["ok"], True)

    def test_erreurs(self) -> None:
        with tempfile.TemporaryDirectory() as dossier:
            racine = Path(dossier)
            pixels = [[(10, 20, 30)] * 32 for _ in range(32)]
            capture = ecrire_png(racine, "capture.png", pixels=pixels)
            reference = ecrire_png(racine, "reference.png", pixels=pixels)
            mauvais_png = racine / "mauvais.png"
            mauvais_png.write_bytes(b"pas un png")
            rectangulaire = ecrire_png(
                racine,
                "rectangulaire.png",
                pixels=[[(10, 20, 30)] * 64 for _ in range(32)],
            )
            config = racine / "config.json"
            config.write_text('{"seuil": 0.9, "largeur": 32}', encoding="utf-8")
            mauvais_config = racine / "mauvais_config.json"
            mauvais_config.write_text('{"seuil": 2, "largeur": 32}', encoding="utf-8")

            scenarios = [
                [str(racine / "absent.png"), str(reference), "--config", str(config)],
                [str(mauvais_png), str(reference), "--config", str(config)],
                [str(rectangulaire), str(reference), "--config", str(config)],
                [str(capture), str(reference), "--config", str(mauvais_config)],
            ]
            for arguments in scenarios:
                with self.subTest(arguments=arguments):
                    erreurs = io.StringIO()
                    with (
                        contextlib.redirect_stdout(io.StringIO()),
                        contextlib.redirect_stderr(erreurs),
                    ):
                        code = M.main(arguments)
                    self.assertEqual(2, code)
                    self.assertIn("Erreur", erreurs.getvalue())
                    self.assertNotIn("Traceback", erreurs.getvalue())


if __name__ == "__main__":
    unittest.main()
