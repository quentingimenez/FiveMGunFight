"""Tests de sécurité de l'extracteur RPF7 de scripts/ajouter_vehicule.py.

Toutes les archives utilisées ici sont synthétiques et construites en mémoire :
aucun vrai fichier de Rockstar ni pack tiers n'est lu. Les entrées sont encodées
au format RPF7 non chiffré (entrées de 16 octets, table des noms, blocs de
512 octets). Le module est chargé par chemin, sans sous-processus ni réseau.

Les tests couvrent le cas nominal, les cinq défauts de sécurité (traversée de
chemin, lectures hors bornes, cycles et profondeur, bombes de décompression,
entrée 0 non répertoire), un fuzz déterministe et le comportement de main().
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import random
import struct
import tempfile
import time
import unittest
import unittest.mock
import zlib
from pathlib import Path
from types import ModuleType

RACINE = Path(__file__).resolve().parents[1]
SCRIPT = RACINE / "scripts" / "ajouter_vehicule.py"


def charger_module() -> ModuleType:
    """Charge scripts/ajouter_vehicule.py sans passer par un sous-processus."""
    spec = importlib.util.spec_from_file_location("ajouter_vehicule_rpf", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("module ajouter_vehicule introuvable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


M = charger_module()


def u32(valeur: int) -> bytes:
    return struct.pack("<I", valeur & 0xFFFFFFFF)


class ConstructeurRpf:
    """Construit une archive RPF7 synthétique en mémoire.

    L'entrée 0 est le répertoire racine ; toutes les autres entrées lui sont
    rattachées. ``construire`` assemble l'en-tête, la table des noms et les
    blocs de données alignés sur 512 octets.
    """

    def __init__(self, chiffrement: int = 0) -> None:
        # Chaque entrée est (nom, genre, paramètres) ; l'entrée 0 est la racine.
        self.entrees: list[tuple[str, str, tuple[int, ...]]] = [("", "dir", (1, 0))]
        self.donnees: list[bytes] = []
        self.chiffrement = chiffrement

    def _nom(self, nom: str) -> bytes:
        return nom.encode("latin-1")

    def dir(self, nom: str, premier: int, nombre: int) -> int:
        """Ajoute une entrée répertoire ; renvoie son index."""
        index = len(self.entrees)
        self.entrees.append((nom, "dir", (premier, nombre)))
        return index

    def _ajouter_donnees(self, donnees: bytes) -> int:
        self.donnees.append(donnees)
        return len(self.donnees) - 1

    def fichier_brut(self, nom: str, contenu: bytes, ressource: bool = False) -> int:
        """Ajoute une entrée de données brutes (taille d'entrée nulle)."""
        index_bloc = self._ajouter_donnees(contenu)
        drapeau = 0x800000 if ressource else 0
        index = len(self.entrees)
        self.entrees.append((nom, "bin", (0, index_bloc | drapeau, len(contenu))))
        return index

    def fichier_compresse(self, nom: str, contenu: bytes) -> int:
        """Ajoute une entrée deflate brut (taille d'entrée = taille compressée)."""
        compresse = zlib.compressobj(9, zlib.DEFLATED, -15)
        donnees = compresse.compress(contenu) + compresse.flush()
        index_bloc = self._ajouter_donnees(donnees)
        index = len(self.entrees)
        self.entrees.append((nom, "bin", (len(donnees), index_bloc, 0)))
        return index

    def ressource_taille_speciale(self, nom: str, contenu: bytes) -> int:
        """Ajoute une ressource dont la taille d'entrée vaut 0xFFFFFF."""
        # Les 16 premiers octets portent la taille réelle aux positions
        # h[7] | h[14]<<8 | h[5]<<16 | h[2]<<24 (comportement historique).
        h = bytearray(16)
        taille = 16 + len(contenu)  # la taille écrite inclut les 16 octets d'en-tête
        h[7] = taille & 0xFF
        h[14] = (taille >> 8) & 0xFF
        h[5] = (taille >> 16) & 0xFF
        h[2] = (taille >> 24) & 0xFF
        donnees = bytes(h) + contenu
        index_bloc = self._ajouter_donnees(donnees)
        index = len(self.entrees)
        self.entrees.append((nom, "bin", (0xFFFFFF, index_bloc | 0x800000, 0)))
        return index

    def construire(
        self,
        noms_modifies: dict[int, str] | None = None,
        enfants_racine: tuple[int, int] | None = None,
    ) -> bytes:
        noms_modifies = noms_modifies or {}
        table_noms = bytearray()
        decalages: list[int] = []
        for i, (nom, _, _) in enumerate(self.entrees):
            texte = noms_modifies.get(i, nom)
            decalages.append(len(table_noms))
            table_noms += self._nom(texte) + b"\0"
        taille_table = 16 + 16 * len(self.entrees) + len(table_noms)
        bloc = (taille_table + 511) // 512
        # Chaque donnée occupe un nombre entier de blocs : une archive imbriquée
        # peut être plus grande qu'un bloc et ne doit pas chevaucher la suivante.
        cumuls = [0]
        for donnees in self.donnees:
            cumuls.append(cumuls[-1] + max(1, (len(donnees) + 511) // 512))
        entrees = bytearray()
        for i, (_, genre, params) in enumerate(self.entrees):
            decalage = decalages[i]
            if genre == "dir":
                premier, nombre = params
                if i == 0:
                    premier, nombre = enfants_racine or (1, len(self.entrees) - 1)
                entrees += u32(decalage) + u32(0x7FFFFF00) + u32(premier) + u32(nombre)
            else:
                taille, index_bloc, brut = params
                bas = (decalage & 0xFFFF) | ((taille & 0xFFFF) << 16)
                bloc_relatif = cumuls[index_bloc & 0x7FFFFF] + bloc
                if index_bloc & 0x800000:
                    bloc_relatif |= 0x800000  # bit de ressource
                haut = (bloc_relatif << 8) | ((taille >> 16) & 0xFF)
                entrees += u32(bas) + u32(haut) + u32(brut) + u32(0)
        buf = bytearray((bloc + cumuls[-1] + 1) * 512)
        buf[:4] = b"7FPR"
        buf[4:8] = u32(len(self.entrees))
        buf[8:12] = u32(len(table_noms))
        buf[12:16] = u32(self.chiffrement)
        buf[16:16 + len(entrees)] = entrees
        buf[16 + len(entrees):16 + len(entrees) + len(table_noms)] = table_noms
        for i, donnees in enumerate(self.donnees):
            pos = (bloc + cumuls[i]) * 512
            buf[pos:pos + len(donnees)] = donnees
        return bytes(buf)


def archive_nominale() -> bytes:
    """Archive valide : sous-dossier, fichier compressé, ressource et .rpf imbriqué."""
    c = ConstructeurRpf()
    # Entrées 1..4 : enfants directs de la racine ; entrée 5 : enfant de stream.
    c.dir("stream", 5, 1)
    c.fichier_brut("brut.bin", b"\x01\x02\x03")
    c.ressource_taille_speciale("ressource.ytd", b"texture" * 20)
    imbrique = ConstructeurRpf()
    imbrique.fichier_brut("dedans.meta", b"<meta/>")
    c.fichier_brut("interne.rpf", imbrique.construire(), ressource=False)
    c.fichier_compresse("modele.yft", b"modele" * 100)
    return c.construire(enfants_racine=(1, 4))


def ecrire_archive(dossier: Path, donnees: bytes, nom: str = "dlc.rpf") -> Path:
    chemin = dossier / nom
    chemin.write_bytes(donnees)
    return chemin


def fichiers_sous(racine: Path) -> dict[str, bytes]:
    return {
        str(f.relative_to(racine)).replace("\\", "/"): f.read_bytes()
        for f in racine.rglob("*") if f.is_file()
    }


class CasNominal(unittest.TestCase):
    """Une archive valide produit exactement les mêmes fichiers qu'avant."""

    def test_archive_valide_avec_sous_dossier_ressource_et_imbrication(self) -> None:
        archive = archive_nominale()
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            source = ecrire_archive(parent, archive)
            sortie = parent / "sortie"
            M.extraire_rpf(source, sortie)
            # Comportement historique conservé : les 16 octets d'en-tête de la
            # ressource sont inclus dans le fichier écrit.
            entete = bytearray(16)
            entete[7] = 16 + 20 * len(b"texture")
            self.assertEqual(
                {
                    "dlc/stream/modele.yft": b"modele" * 100,
                    "dlc/brut.bin": b"\x01\x02\x03",
                    "dlc/ressource.ytd": bytes(entete) + b"texture" * 20,
                    "dlc/interne.rpf/dedans.meta": b"<meta/>",
                },
                fichiers_sous(sortie),
            )
            # Aucun fichier écrit hors du dossier de sortie.
            self.assertEqual(["dlc.rpf", "sortie"], sorted(p.name for p in parent.iterdir()))


class BrutSurestime(unittest.TestCase):
    """Un .rpf imbriqué peut déclarer un brut plus grand que les octets restants."""

    def test_rpf_brut_surestime_est_accepte(self) -> None:
        interne = ConstructeurRpf()
        interne.fichier_brut("dedans.meta", b"<meta/>")
        imbrique = interne.construire()
        c = ConstructeurRpf()
        c.fichier_brut("interne.rpf", imbrique)
        archive = bytearray(c.construire())
        # Entrée 1 : champ brut à l'offset 16 + 16*1 + 8.
        p = 16 + 16
        haut = int.from_bytes(archive[p + 4:p + 8], "little")
        pos = ((haut >> 8) & 0xFFFFFF) * 512
        disponible = len(archive) - pos
        self.assertGreater(disponible, len(imbrique))
        archive[p + 8:p + 12] = u32(disponible + 1)

        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            source = ecrire_archive(parent, bytes(archive))
            sortie = parent / "sortie"
            M.extraire_rpf(source, sortie)
            self.assertEqual(
                {"dlc/interne.rpf/dedans.meta": b"<meta/>"}, fichiers_sous(sortie)
            )
            self.assertEqual(
                ["dlc.rpf", "sortie"], sorted(p.name for p in parent.iterdir())
            )
            self.assertEqual(bytes(archive), source.read_bytes())

    def test_fichier_ordinaire_brut_surestime_est_refuse(self) -> None:
        c = ConstructeurRpf()
        c.fichier_brut("ordinaire.meta", b"<meta/>")
        archive = bytearray(c.construire())
        p = 16 + 16
        haut = int.from_bytes(archive[p + 4:p + 8], "little")
        pos = ((haut >> 8) & 0xFFFFFF) * 512
        disponible = len(archive) - pos
        archive[p + 8:p + 12] = u32(disponible + 1)
        donnees = bytes(archive)
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            source = ecrire_archive(parent, donnees)
            sortie = parent / "sortie"
            sortie.mkdir()
            with self.assertRaises(ValueError) as capture:
                M.extraire_rpf(source, sortie)
            self.assertIn("données hors de l'archive", str(capture.exception))
            self.assertEqual(
                ["dlc.rpf", "sortie"], sorted(p.name for p in parent.iterdir())
            )
            self.assertEqual(donnees, source.read_bytes())


class Defauts(unittest.TestCase):
    """Un par défaut de sécurité, avec vérification du périmètre d'écriture."""

    def verifier_rejet(self, donnees: bytes, fragment: str | None = None) -> None:
        """Écrit l'archive, exige ValueError et aucun fichier hors de sortie."""
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            source = ecrire_archive(parent, donnees)
            sortie = parent / "sortie"
            sortie.mkdir()
            with self.assertRaises(ValueError) as capture:
                M.extraire_rpf(source, sortie)
            if fragment:
                self.assertIn(fragment, str(capture.exception))
            # Seuls la source et le dossier de sortie sont autorisés au premier
            # niveau : un répertoire ou un fichier parasite compte comme fuite.
            self.assertEqual(
                ["dlc.rpf", "sortie"], sorted(p.name for p in parent.iterdir())
            )
            # Une écriture « hors sortie » qui écraserait le fichier source ne
            # changerait pas les noms de premier niveau : vérifier ses octets.
            self.assertEqual(
                donnees, source.read_bytes(), "le fichier source a été écrasé"
            )

    def test_defaut_1_traversee_de_chemin(self) -> None:
        for nom, fragment in (
            # Une entrée qui tente d'écraser le fichier source lui-même doit
            # être refusée, et laisser ce fichier intact (vérifié par verifier_rejet).
            ("../dlc.rpf", "invalide"),
            ("../dehors.txt", "invalide"),
            ("..\\dehors.txt", "invalide"),
            ("sous/../../dehors.txt", "invalide"),
            ("C:dehors.txt", "invalide"),
            ("\ncontrole", "contrôlé"),
            ("", "vide"),
            (".", "invalide"),
            ("..", "invalide"),
            ("nom:flux", "invalide"),
            ('nom"quote', "invalide"),
            ("nom?interro", "invalide"),
            ("nom*etoile", "invalide"),
            ("COM1", "réservé"),
        ):
            with self.subTest(nom=nom):
                c = ConstructeurRpf()
                c.fichier_brut(nom, b"x")
                self.verifier_rejet(c.construire(), fragment)

    def test_defaut_1_nom_de_fichier_imbrique_traversant(self) -> None:
        c = ConstructeurRpf()
        c.fichier_brut("../echappe.rpf", b"pas une archive")
        self.verifier_rejet(c.construire(), "invalide")

    def test_defaut_2_lectures_hors_bornes(self) -> None:
        cas: list[tuple[bytes, str]] = [
            (b"", "tronqué"),
            (b"7FPR", "tronqué"),
            (b"X" * 16, "pas une archive RPF7"),
        ]
        c = ConstructeurRpf(chiffrement=123)
        cas.append((c.construire(), "chiffrée"))

        # Nombre d'entrées démesuré.
        buf = bytearray(archive_nominale())
        buf[4:8] = u32(100000)
        cas.append((bytes(buf), "table des entrées"))
        # Table des noms hors de l'archive.
        buf = bytearray(archive_nominale())
        buf[8:12] = u32(100000)
        cas.append((bytes(buf), "table des noms"))
        # Nom sans octet nul final (le find borné dans nom() le détecte).
        buf = bytearray(archive_nominale())
        buf[8:12] = u32(int.from_bytes(buf[8:12], "little") - 1)
        cas.append((bytes(buf), "nom non terminé"))
        # Décalage de nom hors de la table (entrée 1).
        buf = bytearray(archive_nominale())
        buf[16:20] = u32(0xFFFF)
        cas.append((bytes(buf), "décalage de nom"))
        # Bloc de données au-delà de la fin (fichier brut à l'index 2).
        c = ConstructeurRpf()
        c.fichier_brut("gros.bin", b"x" * 10)
        buf = bytearray(c.construire())
        p = 16 + 16  # entrée 1
        buf[p + 4:p + 8] = u32(0x700000 << 8)  # bloc très au-delà de la fin
        cas.append((bytes(buf), "bloc de données"))
        # Ressource 0xFFFFFF avec moins de 16 octets d'en-tête disponibles.
        c = ConstructeurRpf()
        c.ressource_taille_speciale("r.ytd", b"abcdefghijklmnop")
        buf = bytearray(c.construire())
        p = 16 + 16
        buf[p:p + 4] = u32((int.from_bytes(buf[p:p + 4], "little") & 0xFFFF) | 0xFFFF0000)
        buf[p + 4:p + 8] = u32((((len(buf) // 512) | 0x800000) << 8) | 0xFF)
        cas.append((bytes(buf), "en-tête de ressource tronqué"))
        # Intervalles d'enfants hors de la table.
        buf = bytearray(archive_nominale())
        buf[16 + 12:16 + 16] = u32(9999)
        cas.append((bytes(buf), "intervalles d'enfants"))
        # Données compressées invalides (zlib.error -> ValueError).
        c = ConstructeurRpf()
        c.fichier_compresse("x.yft", b"bonne donnee")
        buf = bytearray(c.construire())
        bloc = int.from_bytes(buf[16 + 16 + 4:16 + 16 + 8], "little") >> 8
        buf[bloc * 512] = 0xFF
        buf[bloc * 512 + 1] = 0xFF
        cas.append((bytes(buf), "zlib invalides"))
        # Flux deflate valide mais tronqué de ses deux derniers octets : eof faux.
        c = ConstructeurRpf()
        c.fichier_compresse("tronque.yft", b"contenu" * 50)
        buf = bytearray(c.construire())
        p = 16 + 16
        bas = int.from_bytes(buf[p:p + 4], "little")
        haut = int.from_bytes(buf[p + 4:p + 8], "little")
        taille = (bas >> 16) | ((haut & 0xFF) << 16)
        buf[p:p + 4] = u32((bas & 0xFFFF) | ((taille - 2) << 16))
        cas.append((bytes(buf), "flux zlib tronqué"))

        for donnees, fragment in cas:
            with self.subTest(fragment=fragment):
                self.verifier_rejet(donnees, fragment)

    def test_defaut_2_entree_0_non_repertoire(self) -> None:
        c = ConstructeurRpf()
        c.fichier_brut("fichier.bin", b"x")
        buf = bytearray(c.construire())
        buf[16 + 4:16 + 8] = u32(0)  # entrée 0 devient un fichier
        self.verifier_rejet(bytes(buf), "entrée 0")

    def test_repertoire_partage_est_refuse(self) -> None:
        """Un DAG de répertoires partagés est refusé (visité une seule fois)."""
        c = ConstructeurRpf()
        # Racine : répertoires 1 et 2 ; tous deux pointent sur le répertoire 3.
        c.dir("premier", 3, 1)
        c.dir("second", 3, 1)
        c.dir("partage", 4, 1)
        c.fichier_brut("feuille.bin", b"feuille")
        self.verifier_rejet(c.construire(enfants_racine=(1, 2)), "déjà visité")

    def test_collision_fichier_repertoire_leve_valueerror(self) -> None:
        """Un fichier et un répertoire de même nom : OSError -> ValueError."""
        c = ConstructeurRpf()
        c.dir("a", 2, 1)          # répertoire a contient l'entrée 2 (x)
        c.fichier_brut("x", b"x")
        c.fichier_brut("a", b"collision")
        self.verifier_rejet(c.construire(enfants_racine=(1, 3)), "écriture impossible")

    def test_defaut_3_cycles_et_profondeur(self) -> None:
        # Cycle direct : le répertoire 1 se contient lui-même.
        c = ConstructeurRpf()
        c.dir("boucle", 1, 1)
        self.verifier_rejet(c.construire(), "cycle")

        # Cycle indirect : 1 contient 2, qui contient 1.
        c = ConstructeurRpf()
        c.dir("a", 2, 1)
        c.dir("b", 1, 1)
        self.verifier_rejet(c.construire(), "cycle")

        # Chaîne de .rpf imbriqués plus profonde que PROFONDEUR_MAX.
        with unittest.mock.patch.object(M, "PROFONDEUR_MAX", 2):
            interne = ConstructeurRpf()
            interne.fichier_brut("feuille.bin", b"feuille")
            couche = interne.construire()
            for _ in range(3):
                parent = ConstructeurRpf()
                parent.fichier_brut("couche.rpf", couche)
                couche = parent.construire()
            self.verifier_rejet(couche, "profondeur maximale")

    def test_defaut_4_bombes_et_limites(self) -> None:
        # 1 Mo compressé en ~1 Ko, limite 1 Ko : ValueError, pas de gros alloc.
        c = ConstructeurRpf()
        c.fichier_compresse("bombe.yft", b"A" * (1024 * 1024))
        archive = c.construire()
        with unittest.mock.patch.object(M, "LIMITE_FICHIER", 2048):
            self.verifier_rejet(archive, "bombes")

        # Limite totale : deux petits fichiers, total = 4 octets.
        c = ConstructeurRpf()
        c.fichier_brut("a.bin", b"abcd")
        c.fichier_brut("b.bin", b"abcd")
        archive = c.construire()
        with unittest.mock.patch.object(M, "LIMITE_TOTALE", 4):
            self.verifier_rejet(archive, "total")

    def test_defaut_5_entree_zero_non_repertoire_avec_message_francais(self) -> None:
        c = ConstructeurRpf()
        c.fichier_brut("fichier.bin", b"x")
        buf = bytearray(c.construire())
        buf[16 + 4:16 + 8] = u32(1234)
        self.verifier_rejet(bytes(buf), "l'entrée 0 n'est pas un répertoire")


class FuzzDeterministe(unittest.TestCase):
    """2000 mutations déterministes : succès ou ValueError, jamais autre chose."""

    GRAINE = 0x5EED2025
    NOMBRE = 2000

    def test_fuzz_sans_exception_inattendue_ni_ecriture_hors_sortie(self) -> None:
        original = archive_nominale()
        hasard = random.Random(self.GRAINE)
        debut = time.monotonic()
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            source = ecrire_archive(parent, original, "fuzz.rpf")
            sortie = parent / "sortie"
            sortie.mkdir()
            for index in range(self.NOMBRE):
                donnees = bytearray(original)
                for _ in range(hasard.randint(1, 4)):
                    genre = hasard.randrange(6)
                    if genre == 0 and donnees:
                        donnees[hasard.randrange(len(donnees))] = hasard.randrange(256)
                    elif genre == 1 and len(donnees) > 20:
                        del donnees[hasard.randrange(len(donnees)):]
                    elif genre == 2:
                        pos = hasard.randrange(len(donnees) + 1)
                        donnees[pos:pos] = bytes([hasard.randrange(256)])
                    elif genre == 3:
                        champ = hasard.randrange(4) * 4
                        donnees[champ:champ + 4] = u32(hasard.getrandbits(32))
                    elif genre == 4 and len(donnees) > 32:
                        pos = 16 + hasard.randrange(min(5, len(donnees) // 16 - 1)) * 16
                        donnees[pos:pos + 4] = u32(hasard.getrandbits(32))
                        donnees[pos + 4:pos + 8] = u32(hasard.getrandbits(32))
                    elif donnees:
                        pos = hasard.randrange(len(donnees))
                        donnees[pos] = hasard.choice((0, 0x7F, 0x80, 0xFF))
                source.write_bytes(bytes(donnees))
                try:
                    M.extraire_rpf(source, sortie)
                except ValueError:
                    pass
                except Exception as erreur:  # noqa: BLE001 - tout autre type doit échouer le fuzz
                    self.fail(
                        f"graine {self.GRAINE:#x}, mutation {index} : "
                        f"{type(erreur).__name__} au lieu de ValueError : {erreur}"
                    )
                # Contrôle rapide de premier niveau : source + sortie seulement,
                # sans parcourir récursivement les sorties accumulées.
                self.assertEqual(
                    sorted(p.name for p in parent.iterdir()),
                    ["fuzz.rpf", "sortie"],
                    f"graine {self.GRAINE:#x}, mutation {index} : écriture hors sortie",
                )
                # Le contrôle des noms ne voit pas un écrasement de la source.
                self.assertEqual(
                    bytes(donnees),
                    source.read_bytes(),
                    f"graine {self.GRAINE:#x}, mutation {index} : fichier source écrasé",
                )
        duree = time.monotonic() - debut
        self.assertLess(duree, 30.0, f"fuzz trop lent : {duree:.1f} s")


class ComportementMain(unittest.TestCase):
    """main() affiche un message français et renvoie 1 sur une archive invalide."""

    def test_main_archive_invalide(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source = ecrire_archive(Path(tmp), b"archive invalide", "mauvais.rpf")
            erreurs = io.StringIO()
            sortie = io.StringIO()
            with (
                contextlib.redirect_stderr(erreurs),
                contextlib.redirect_stdout(sortie),
                unittest.mock.patch.object(M.sys, "argv", ["ajouter_vehicule.py", str(source)]),
            ):
                code = M.main()
            self.assertEqual(1, code)
            self.assertIn("Erreur :", erreurs.getvalue())
            self.assertNotIn("Traceback", erreurs.getvalue())
            self.assertNotIn("Traceback", sortie.getvalue())


if __name__ == "__main__":
    unittest.main()
