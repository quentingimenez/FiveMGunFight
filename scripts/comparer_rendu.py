#!/usr/bin/env python3
"""Compare une capture du lobby à une image de référence par un indice SSIM.

Usage :
    python scripts/comparer_rendu.py capture.png reference.png --config config.json
    python scripts/comparer_rendu.py capture.png reference.png --config cfg.json --json

La lecture PNG est faite en pur Python (`zlib`, `struct`) : aucun paquet
externe, aucun réseau, aucun sous-processus. Les images sont converties en
niveaux de gris, réduites à une largeur fixe par moyenne de blocs, puis
comparées par un SSIM global à fenêtre uniforme 7x7 (constantes K1 = 0,01,
K2 = 0,03, L = 255, variance d'échantillon). Les rectangles du fichier de
configuration sont exprimés en fractions de l'image ; les fenêtres qui les
chevauchent sont exclues du calcul, ce qui permet de masquer le personnage
animé du lobby.

Le fichier de configuration est un objet JSON :
    {"seuil": 0.90, "largeur": 320, "masques": [[x0, y0, x1, y1], ...],
     "description": "texte libre"}

Codes de sortie : 0 si l'indice atteint le seuil, 1 s'il est inférieur,
2 en cas d'erreur (fichier absent, PNG ou configuration invalide, tailles
incompatibles). Les erreurs vont sur stderr avec un message en français,
sans trace Python.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import zlib
from pathlib import Path
from typing import NamedTuple, Sequence

SIGNATURE_PNG = b"\x89PNG\r\n\x1a\n"
COULEURS_OCTETS = {0: 1, 2: 3, 6: 4}
TAILLE_FENETRE = 7
DEMI_FENETRE = TAILLE_FENETRE // 2
NOMBRE_PIXELS = TAILLE_FENETRE * TAILLE_FENETRE
K1 = 0.01
K2 = 0.03
LUMINANCE_MAX = 255.0
C1 = (K1 * LUMINANCE_MAX) ** 2
C2 = (K2 * LUMINANCE_MAX) ** 2
TOLERANCE_RAPPORT = 0.01

SORTIE_OK = 0
SORTIE_ECHEC = 1
SORTIE_ERREUR = 2


class Image(NamedTuple):
    """Image PNG décodée, ligne par ligne, sans interprétation de l'alpha."""

    largeur: int
    hauteur: int
    pixels: list[list[tuple[int, ...]]]


def _paeth(gauche: int, dessus: int, diagonal: int) -> int:
    """Prédicteur Paeth utilisé par le filtre PNG 4."""
    estimation = gauche + dessus - diagonal
    distance_gauche = abs(estimation - gauche)
    distance_dessus = abs(estimation - dessus)
    distance_diagonale = abs(estimation - diagonal)
    if distance_gauche <= distance_dessus and distance_gauche <= distance_diagonale:
        return gauche
    if distance_dessus <= distance_diagonale:
        return dessus
    return diagonal


def lire_png(chemin: str | Path) -> Image:
    """Décode un PNG non entrelacé, 8 bits, gris/RGB/RGBA, filtres 0 à 4.

    Vérifie la signature, le CRC de chaque bloc, la présence de IHDR en
    premier et de IEND, la validité du flux zlib et la longueur exacte des
    données décompressées. Tout cas non pris en charge lève ValueError avec
    un message en français. L'alpha est lu mais ignoré par la suite.
    """
    try:
        donnees = Path(chemin).read_bytes()
    except OSError as erreur:
        raise ValueError(
            f"fichier PNG introuvable ou illisible : {chemin} ({erreur})"
        ) from None

    if not donnees.startswith(SIGNATURE_PNG):
        raise ValueError("signature PNG invalide")

    position = len(SIGNATURE_PNG)
    entete: tuple[int, int, int] | None = None
    flux = bytearray()
    iend = False
    while position < len(donnees):
        if position + 12 > len(donnees):
            raise ValueError("PNG tronqué : bloc incomplet")
        longueur = struct.unpack_from(">I", donnees, position)[0]
        type_bloc = donnees[position + 4 : position + 8]
        fin = position + 8 + longueur
        if fin + 4 > len(donnees):
            raise ValueError("PNG tronqué : données de bloc incomplètes")
        contenu = donnees[position + 8 : fin]
        crc_lu = struct.unpack_from(">I", donnees, fin)[0]
        if (zlib.crc32(type_bloc + contenu) & 0xFFFFFFFF) != crc_lu:
            nom_bloc = type_bloc.decode("latin-1")
            raise ValueError(f"CRC invalide pour le bloc {nom_bloc}")

        if entete is None:
            if type_bloc != b"IHDR":
                raise ValueError("le premier bloc du PNG doit être IHDR")
            if longueur != 13:
                raise ValueError("bloc IHDR de longueur invalide")
            (
                largeur,
                hauteur,
                profondeur,
                couleur,
                compression,
                filtrage,
                entrelace,
            ) = struct.unpack(">IIBBBBB", contenu)
            if profondeur != 8:
                raise ValueError("seule la profondeur 8 bits est prise en charge")
            if couleur not in COULEURS_OCTETS:
                raise ValueError("type de couleur PNG non pris en charge")
            if compression != 0 or filtrage != 0:
                raise ValueError(
                    "méthode de compression ou de filtrage PNG non prise en charge"
                )
            if entrelace != 0:
                raise ValueError("les PNG entrelacés ne sont pas pris en charge")
            if largeur == 0 or hauteur == 0:
                raise ValueError("dimensions PNG invalides")
            entete = (largeur, hauteur, couleur)
        elif type_bloc == b"IDAT":
            flux.extend(contenu)
        elif type_bloc == b"IEND":
            if longueur != 0:
                raise ValueError("bloc IEND de longueur invalide")
            iend = True
            break
        position = fin + 4

    if entete is None:
        raise ValueError("PNG sans bloc IHDR")
    if not iend:
        raise ValueError("PNG tronqué : bloc IEND absent")
    if not flux:
        raise ValueError("PNG sans données d'image : bloc IDAT absent")

    try:
        brut = zlib.decompress(bytes(flux))
    except zlib.error:
        raise ValueError("données PNG compressées invalides") from None

    largeur, hauteur, couleur = entete
    octets = COULEURS_OCTETS[couleur]
    taille_ligne = largeur * octets
    longueur_attendue = hauteur * (1 + taille_ligne)
    if len(brut) != longueur_attendue:
        raise ValueError(
            "longueur des données PNG invalide : "
            f"{len(brut)} octets au lieu de {longueur_attendue}"
        )

    pixels: list[list[tuple[int, ...]]] = []
    precedente = bytearray(taille_ligne)
    curseur = 0
    for _ in range(hauteur):
        filtre = brut[curseur]
        curseur += 1
        ligne = bytearray(brut[curseur : curseur + taille_ligne])
        curseur += taille_ligne
        if filtre == 0:
            pass
        elif filtre == 1:
            for indice in range(octets, taille_ligne):
                ligne[indice] = (ligne[indice] + ligne[indice - octets]) & 0xFF
        elif filtre == 2:
            for indice in range(taille_ligne):
                ligne[indice] = (ligne[indice] + precedente[indice]) & 0xFF
        elif filtre == 3:
            for indice in range(taille_ligne):
                gauche = ligne[indice - octets] if indice >= octets else 0
                ligne[indice] = (
                    ligne[indice] + ((gauche + precedente[indice]) >> 1)
                ) & 0xFF
        elif filtre == 4:
            for indice in range(taille_ligne):
                gauche = ligne[indice - octets] if indice >= octets else 0
                dessus = precedente[indice]
                diagonal = precedente[indice - octets] if indice >= octets else 0
                ligne[indice] = (
                    ligne[indice] + _paeth(gauche, dessus, diagonal)
                ) & 0xFF
        else:
            raise ValueError(f"filtre PNG inconnu : {filtre}")
        pixels.append(
            [
                tuple(ligne[indice : indice + octets])
                for indice in range(0, taille_ligne, octets)
            ]
        )
        precedente = ligne
    return Image(largeur, hauteur, pixels)


def en_gris(image: Image) -> list[list[float]]:
    """Convertit l'image en niveaux de gris ; l'alpha est ignoré."""
    gris: list[list[float]] = []
    for ligne in image.pixels:
        convertie: list[float] = []
        for pixel in ligne:
            if len(pixel) == 1:
                convertie.append(float(pixel[0]))
            else:
                convertie.append(
                    0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2]
                )
        gris.append(convertie)
    return gris


def _poids_axe(source: int, cible: int) -> list[list[tuple[int, float]]]:
    """Chevauchements fractionnels exacts entre cases source et cible."""
    echelle = source / cible
    axes: list[list[tuple[int, float]]] = []
    for indice in range(cible):
        debut = indice * echelle
        fin = (indice + 1) * echelle
        courant: list[tuple[int, float]] = []
        for origine in range(int(debut), min(source, math.ceil(fin))):
            recouvrement = min(fin, origine + 1) - max(debut, origine)
            if recouvrement > 1e-12:
                courant.append((origine, recouvrement))
        axes.append(courant)
    return axes


def reduire(gris: Sequence[Sequence[float]], largeur: int = 320) -> list[list[float]]:
    """Réduit une image à `largeur` colonnes par moyenne de blocs.

    La hauteur cible est arrondie proportionnellement. Chaque pixel cible
    moyenne les pixels source pondérés par la fraction exacte de leur
    recouvrement, y compris aux bords où les blocs sont partiels.
    """
    if largeur <= 0:
        raise ValueError("largeur de réduction invalide")
    if not gris or not gris[0]:
        raise ValueError("image vide : réduction impossible")
    hauteur = len(gris)
    largeur_source = len(gris[0])
    if any(len(ligne) != largeur_source for ligne in gris):
        raise ValueError("lignes de largeurs incompatibles dans l'image")
    hauteur_cible = max(1, round(hauteur * largeur / largeur_source))
    poids_x = _poids_axe(largeur_source, largeur)
    poids_y = _poids_axe(hauteur, hauteur_cible)

    reduction: list[list[float]] = []
    for positions_y in poids_y:
        ligne_cible: list[float] = []
        for positions_x in poids_x:
            somme = 0.0
            total = 0.0
            for origine_y, poids_y_unitaire in positions_y:
                ligne_source = gris[origine_y]
                for origine_x, poids_x_unitaire in positions_x:
                    poids = poids_x_unitaire * poids_y_unitaire
                    somme += ligne_source[origine_x] * poids
                    total += poids
            ligne_cible.append(somme / total if total > 0 else 0.0)
        reduction.append(ligne_cible)
    return reduction


def _integrale(grille: Sequence[Sequence[float]]) -> list[list[float]]:
    """Construit l'image intégrale : somme du rectangle depuis l'origine."""
    hauteur = len(grille)
    largeur = len(grille[0])
    resultat = [[0.0] * (largeur + 1) for _ in range(hauteur + 1)]
    for y in range(hauteur):
        ligne = resultat[y + 1]
        ligne_precedente = resultat[y]
        source = grille[y]
        somme = 0.0
        for x in range(largeur):
            somme += source[x]
            ligne[x + 1] = ligne_precedente[x + 1] + somme
    return resultat


def _somme(
    integrale: Sequence[Sequence[float]], y0: int, x0: int, y1: int, x1: int
) -> float:
    """Somme d'un rectangle fermé via l'image intégrale."""
    return (
        integrale[y1 + 1][x1 + 1]
        - integrale[y0][x1 + 1]
        - integrale[y1 + 1][x0]
        + integrale[y0][x0]
    )


def _grille_masque(
    hauteur: int, largeur: int, masques: Sequence[Sequence[float]]
) -> list[list[bool]]:
    """Marque les pixels dont le centre tombe dans un rectangle masqué."""
    grille = [[False] * largeur for _ in range(hauteur)]
    for rectangle in masques:
        if len(rectangle) != 4:
            raise ValueError("un masque doit contenir quatre fractions")
        x0, y0, x1, y1 = (float(valeur) for valeur in rectangle)
        if not (0.0 <= x0 < x1 <= 1.0) or not (0.0 <= y0 < y1 <= 1.0):
            raise ValueError("rectangle de masque invalide")
        debut_x = max(0, math.ceil(x0 * largeur - 0.5))
        fin_x = min(largeur - 1, math.floor(x1 * largeur - 0.5))
        debut_y = max(0, math.ceil(y0 * hauteur - 0.5))
        fin_y = min(hauteur - 1, math.floor(y1 * hauteur - 0.5))
        for y in range(debut_y, fin_y + 1):
            ligne = grille[y]
            for x in range(debut_x, fin_x + 1):
                ligne[x] = True
    return grille


def _calculer_ssim(
    reference: Sequence[Sequence[float]],
    capture: Sequence[Sequence[float]],
    masques: Sequence[Sequence[float]] = (),
) -> tuple[float, int]:
    """Calcule l'indice SSIM global et le nombre de fenêtres retenues."""
    if not reference or not capture:
        raise ValueError("images vides : calcul SSIM impossible")
    hauteur = len(reference)
    largeur = len(reference[0])
    if hauteur < TAILLE_FENETRE or largeur < TAILLE_FENETRE:
        raise ValueError("image trop petite pour une fenêtre de 7x7 pixels")
    if any(len(ligne) != largeur for ligne in reference):
        raise ValueError("lignes de largeurs incompatibles dans la référence")
    if len(capture) != hauteur or any(len(ligne) != largeur for ligne in capture):
        raise ValueError("dimensions des images incompatibles pour le SSIM")

    grille_reference = [[float(valeur) for valeur in ligne] for ligne in reference]
    grille_capture = [[float(valeur) for valeur in ligne] for ligne in capture]
    carres_reference = [
        [valeur * valeur for valeur in ligne] for ligne in grille_reference
    ]
    carres_capture = [[valeur * valeur for valeur in ligne] for ligne in grille_capture]
    produits = [
        [gauche * droite for gauche, droite in zip(ligne_ref, ligne_cap)]
        for ligne_ref, ligne_cap in zip(grille_reference, grille_capture)
    ]
    grille_masquee = _grille_masque(hauteur, largeur, masques)

    somme_ref = _integrale(grille_reference)
    somme_cap = _integrale(grille_capture)
    somme_ref2 = _integrale(carres_reference)
    somme_cap2 = _integrale(carres_capture)
    somme_produit = _integrale(produits)
    somme_masque = _integrale(grille_masquee)

    total = 0.0
    fenetres = 0
    for centre_y in range(DEMI_FENETRE, hauteur - DEMI_FENETRE):
        y0 = centre_y - DEMI_FENETRE
        y1 = centre_y + DEMI_FENETRE
        for centre_x in range(DEMI_FENETRE, largeur - DEMI_FENETRE):
            x0 = centre_x - DEMI_FENETRE
            x1 = centre_x + DEMI_FENETRE
            if _somme(somme_masque, y0, x0, y1, x1) > 0:
                continue
            ref = _somme(somme_ref, y0, x0, y1, x1)
            cap = _somme(somme_cap, y0, x0, y1, x1)
            ref2 = _somme(somme_ref2, y0, x0, y1, x1)
            cap2 = _somme(somme_cap2, y0, x0, y1, x1)
            produit = _somme(somme_produit, y0, x0, y1, x1)
            moyenne_ref = ref / NOMBRE_PIXELS
            moyenne_cap = cap / NOMBRE_PIXELS
            variance_ref = (ref2 - ref * moyenne_ref) / (NOMBRE_PIXELS - 1)
            variance_cap = (cap2 - cap * moyenne_cap) / (NOMBRE_PIXELS - 1)
            covariance = (produit - ref * moyenne_cap) / (NOMBRE_PIXELS - 1)
            numerateur = (
                (2.0 * moyenne_ref * moyenne_cap + C1)
                * (2.0 * covariance + C2)
            )
            denominateur = (
                (moyenne_ref**2 + moyenne_cap**2 + C1)
                * (variance_ref + variance_cap + C2)
            )
            if denominateur == 0.0:
                local = 1.0
            else:
                local = numerateur / denominateur
            total += local
            fenetres += 1

    if fenetres == 0:
        raise ValueError(
            "aucune fenêtre 7x7 utilisable : image trop petite ou masque total"
        )
    return total / fenetres, fenetres


def ssim(
    reference: Sequence[Sequence[float]],
    capture: Sequence[Sequence[float]],
    masques: Sequence[Sequence[float]] = (),
) -> float:
    """Indice SSIM global ; `masques` sont des fractions de l'image."""
    indice, _ = _calculer_ssim(reference, capture, masques)
    return indice


def _nombre(valeur: object, nom: str) -> float:
    """Valide un champ numérique fini, en refusant les booléens."""
    if isinstance(valeur, bool) or not isinstance(valeur, (int, float)):
        raise ValueError(f"{nom} doit être un nombre")
    nombre = float(valeur)
    if not math.isfinite(nombre):
        raise ValueError(f"{nom} doit être un nombre fini")
    return nombre


def charger_config(chemin: str | Path) -> dict[str, object]:
    """Lit et valide strictement le fichier JSON de configuration."""
    try:
        texte = Path(chemin).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as erreur:
        raise ValueError(
            f"configuration introuvable ou illisible : {chemin} ({erreur})"
        ) from None
    try:
        contenu = json.loads(texte)
    except json.JSONDecodeError as erreur:
        raise ValueError(f"configuration JSON invalide : {erreur}") from None
    if not isinstance(contenu, dict):
        raise ValueError("la configuration doit être un objet JSON")

    if "seuil" not in contenu:
        raise ValueError("champ seuil absent de la configuration")
    seuil = _nombre(contenu["seuil"], "seuil")
    if not 0.0 <= seuil <= 1.0:
        raise ValueError("le seuil doit être compris entre 0 et 1")

    if "largeur" not in contenu:
        raise ValueError("champ largeur absent de la configuration")
    largeur = contenu["largeur"]
    if isinstance(largeur, bool) or not isinstance(largeur, int):
        raise ValueError("largeur doit être un entier")
    if largeur <= 0:
        raise ValueError("largeur doit être strictement positive")

    rectangles = contenu.get("masques", [])
    if not isinstance(rectangles, list):
        raise ValueError("masques doit être une liste de rectangles")
    masques: list[tuple[float, float, float, float]] = []
    for index, rectangle in enumerate(rectangles):
        if not isinstance(rectangle, (list, tuple)) or len(rectangle) != 4:
            raise ValueError(f"masques[{index}] doit contenir quatre nombres")
        x0, y0, x1, y1 = (
            _nombre(valeur, f"masques[{index}]") for valeur in rectangle
        )
        if not (0.0 <= x0 < x1 <= 1.0) or not (0.0 <= y0 < y1 <= 1.0):
            raise ValueError(f"rectangle de masque invalide à l'index {index}")
        masques.append((x0, y0, x1, y1))

    description = contenu.get("description", "")
    if not isinstance(description, str):
        raise ValueError("description doit être une chaîne de caractères")

    return {
        "seuil": seuil,
        "largeur": largeur,
        "masques": masques,
        "description": description,
    }


def comparer(
    capture: str | Path, reference: str | Path, config: dict[str, object]
) -> dict[str, object]:
    """Compare deux PNG et renvoie indice, seuil, fenêtres et décision."""
    if "largeur" not in config or "seuil" not in config:
        raise ValueError("configuration de comparaison incomplète")
    largeur = config["largeur"]
    if isinstance(largeur, bool) or not isinstance(largeur, int) or largeur <= 0:
        raise ValueError("largeur de réduction invalide dans la configuration")
    seuil = _nombre(config["seuil"], "seuil")
    if not 0.0 <= seuil <= 1.0:
        raise ValueError("le seuil doit être compris entre 0 et 1")
    masques = config.get("masques", ())

    image_capture = lire_png(capture)
    image_reference = lire_png(reference)
    rapport_reference = image_reference.largeur / image_reference.hauteur
    rapport_capture = image_capture.largeur / image_capture.hauteur
    if abs(rapport_capture - rapport_reference) / rapport_reference > TOLERANCE_RAPPORT:
        raise ValueError(
            "rapports de forme incompatibles entre la capture et la référence"
        )

    gris_reference = reduire(en_gris(image_reference), largeur)
    gris_capture = reduire(en_gris(image_capture), largeur)
    if len(gris_reference) != len(gris_capture) or len(gris_reference[0]) != len(
        gris_capture[0]
    ):
        raise ValueError("tailles incompatibles après réduction des images")

    indice, fenetres = _calculer_ssim(gris_reference, gris_capture, masques)
    return {
        "indice": indice,
        "seuil": seuil,
        "fenetres": fenetres,
        "ok": indice >= seuil,
    }


class _Analyseur(argparse.ArgumentParser):
    """Analyseur d'arguments avec des messages d'erreur en français."""

    def error(self, message: str) -> None:
        traductions = (
            ("the following arguments are required:", "arguments requis manquants :"),
            ("unrecognized arguments:", "arguments non reconnus :"),
            ("invalid choice:", "choix invalide :"),
        )
        for anglais, francais in traductions:
            if message.startswith(anglais):
                message = francais + message[len(anglais) :]
                break
        print(f"Erreur : {message}", file=sys.stderr)
        self.print_usage(sys.stderr)
        raise SystemExit(SORTIE_ERREUR)


def main(argv: list[str] | None = None) -> int:
    """Point d'entrée : lit les images, calcule l'indice et affiche le verdict."""
    analyseur = _Analyseur(
        description=(
            "Compare une capture du lobby à une image de référence par un "
            "indice SSIM avec zones masquées."
        ),
        epilog="Codes de sortie : 0 réussi, 1 sous le seuil, 2 erreur.",
    )
    analyseur.add_argument("capture", help="capture PNG du lobby")
    analyseur.add_argument("reference", help="image PNG de référence")
    analyseur.add_argument(
        "--config", required=True, help="fichier JSON de configuration"
    )
    analyseur.add_argument(
        "--json", action="store_true", help="sortie JSON sur stdout au lieu du texte"
    )
    args = analyseur.parse_args(argv)

    try:
        config = charger_config(args.config)
        resultat = comparer(args.capture, args.reference, config)
    except ValueError as erreur:
        print(f"Erreur : {erreur}", file=sys.stderr)
        return SORTIE_ERREUR

    indice = round(float(resultat["indice"]), 4)
    seuil = float(resultat["seuil"])
    fenetres = int(resultat["fenetres"])
    ok = bool(resultat["ok"])

    if args.json:
        json.dump(
            {
                "indice": indice,
                "seuil": seuil,
                "fenetres": fenetres,
                "ok": ok,
            },
            sys.stdout,
            ensure_ascii=False,
        )
        print()
    else:
        print(f"Indice SSIM : {indice:.4f}")
        print(f"Seuil : {seuil:.4f}")
        print(f"Fenêtres comptées : {fenetres}")
        print("Résultat : OK" if ok else "Résultat : ÉCHEC")
    return SORTIE_OK if ok else SORTIE_ECHEC


if __name__ == "__main__":
    sys.exit(main())
