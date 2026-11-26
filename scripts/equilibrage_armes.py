#!/usr/bin/env python3
"""Calcule le temps de mise à mort des armes à partir des weapons.meta du jeu.

Usage :
    python scripts/equilibrage_armes.py DOSSIER_META [--config CHEMIN]
    python scripts/equilibrage_armes.py DOSSIER_META --format json
    python scripts/equilibrage_armes.py DOSSIER_META --distances 10,25,50

DOSSIER_META est la racine des fichiers weapon*.meta extraits du jeu. Ces
fichiers sont lus sur place, en lecture seule : aucune valeur du jeu n'est
recopiée dans le dépôt. Les noms d'armes et leur ordre viennent du bloc
`Config.Weapons` de `gf_core/config.lua` (ou de l'option --config).

Hypothèses de calcul (toutes à confirmer en jeu ; voir les docstrings des
fonctions de calcul et la note du tableau markdown) :

* H1 : l'atténuation avec la distance est linéaire entre
  DamageFallOffRangeMin et DamageFallOffRangeMax, plafonnée à 1 avant et à
  DamageFallOffModifier après ;
* H2 : le dégât d'un tir vaut Damage * NetworkPlayerDamageModifier *
  attenuation * BulletsInBatch, toutes les billes touchant la cible, avec
  NetworkHeadShotPlayerDamageModifier pour un tir à la tête ;
* H3 : il faut retirer 200 points (100 PV + 100 de kevlar), le kevlar
  absorbant les dégâts à 100 %, tête comprise ;
* H4 : le nombre de tirs est le plus petit n tel que n * dégât >= 200 ;
* H5 : le temps est (tirs - 1) * TimeBetweenShots, rechargement ignoré.

Codes de sortie : 0 si le tableau est produit, 2 si les données, la
configuration ou les distances sont invalides. Le tableau va sur stdout, les
avertissements et les erreurs sur stderr. Aucun réseau, aucune base.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SORTIE_OK = 0
SORTIE_ERREUR = 2

POINTS_POUR_TUER = 200
CHAMPS_REQUIS = (
    "Damage",
    "NetworkPlayerDamageModifier",
    "NetworkHeadShotPlayerDamageModifier",
    "DamageFallOffRangeMin",
    "DamageFallOffRangeMax",
    "DamageFallOffModifier",
    "TimeBetweenShots",
    "BulletsInBatch",
    "ClipSize",
)
CHAMPS_ENTIERS = {"ClipSize", "BulletsInBatch"}
CONFIG_DEFAUT = (
    Path(__file__).resolve().parents[1]
    / "server-data"
    / "resources"
    / "[gunfight]"
    / "gf_core"
    / "config.lua"
)

Champs = dict[str, float | int]
Candidat = tuple[str, Champs]
Definitions = dict[str, list[Candidat]]
Ligne = dict[str, object]


class ErreurEquilibrage(Exception):
    """Erreur de données ou de configuration, avec un message en français."""


def _masquer(texte: str) -> tuple[str, str]:
    """Masque les chaînes et les commentaires Lua pour compter les accolades.

    Renvoie deux chaînes de même longueur que `texte` : la première masque les
    chaînes `'...'`/`\"...\"` et les commentaires `-- ...` (recherche du bloc et
    comptage des accolades), la seconde masque seulement les commentaires (pour
    retrouver les `name` sans capturer ceux des commentaires). Les échappements
    `\\'` et `\\"` sont respectés, comme dans `label = 'Fusil d\\'assaut'`.
    """
    accolades: list[str] = []
    noms: list[str] = []
    etat = "code"
    position = 0
    while position < len(texte):
        caractere = texte[position]
        if etat == "commentaire":
            if caractere == "\n":
                etat = "code"
                accolades.append("\n")
                noms.append("\n")
            else:
                accolades.append(" ")
                noms.append(" ")
            position += 1
            continue
        if etat == "code":
            if texte.startswith("--", position):
                etat = "commentaire"
                accolades.append("  ")
                noms.append("  ")
                position += 2
            elif caractere in ("'", '"'):
                etat = "simple" if caractere == "'" else "double"
                accolades.append(" ")
                noms.append(caractere)
                position += 1
            else:
                accolades.append(caractere)
                noms.append(caractere)
                position += 1
            continue
        # Dans une chaîne : masqué pour les accolades, conservé pour les noms.
        if caractere == "\\":
            echappe = texte[position : position + 2]
            accolades.append(" " * len(echappe))
            noms.append(echappe)
            position += len(echappe)
            continue
        accolades.append(" ")
        noms.append(caractere)
        if caractere == ("'" if etat == "simple" else '"'):
            etat = "code"
        position += 1
    return "".join(accolades), "".join(noms)


def armes_du_config(texte: str) -> list[str]:
    """Renvoie les noms WEAPON_... du bloc Config.Weapons, dans leur ordre.

    Le bloc commence à `Config.Weapons = {` et s'arrête à l'accolade fermante
    correspondante, en comptant les accolades imbriquées. Les accolades dans
    les chaînes et les commentaires sont ignorées, et les `name` des autres
    blocs (Config.StarterWeapons, Config.Loadouts, ...) ne sont pas capturés.
    Une absence de bloc lève ErreurEquilibrage.
    """
    masque_accolades, masque_noms = _masquer(texte)
    debut = re.search(r"Config\.Weapons\s*=\s*\{", masque_accolades)
    if debut is None:
        raise ErreurEquilibrage(
            "bloc Config.Weapons introuvable dans la configuration"
        )

    profondeur = 0
    fin = -1
    for position in range(debut.end() - 1, len(masque_accolades)):
        caractere = masque_accolades[position]
        if caractere == "{":
            profondeur += 1
        elif caractere == "}":
            profondeur -= 1
            if profondeur == 0:
                fin = position + 1
                break
    if fin < 0:
        raise ErreurEquilibrage("bloc Config.Weapons mal fermé dans la configuration")

    motif = re.compile(r"name\s*=\s*['\"]\s*(WEAPON_[A-Z0-9_]+)\s*['\"]")
    extrait = masque_noms[debut.start() : fin]
    return [trouve.group(1) for trouve in motif.finditer(extrait)]


def lire_definitions(dossier: str | Path) -> Definitions:
    """Lit récursivement les *.meta et indexe les CWeaponInfo par nom.

    Chaque valeur est une liste de tuples (chemin relatif en séparateurs '/',
    champs), classée par chemin pour être déterministe. Seuls les enfants
    directs de l'Item CWeaponInfo sont lus : les Item imbriqués (composants)
    ne fournissent aucun champ. Un fichier XML illisible ou invalide est
    ignoré avec un avertissement sur stderr ; un dossier absent lève
    ErreurEquilibrage.
    """
    racine = Path(dossier)
    if not racine.is_dir():
        raise ErreurEquilibrage(f"dossier de métadonnées introuvable : {racine}")

    definitions: Definitions = {}
    for chemin in sorted(racine.rglob("*.meta")):
        try:
            arbre = ET.parse(chemin)
        except (ET.ParseError, OSError) as erreur:
            relatif = chemin.relative_to(racine).as_posix()
            print(
                f"Avertissement : fichier ignoré {relatif} ({erreur})",
                file=sys.stderr,
            )
            continue
        relatif = chemin.relative_to(racine).as_posix()
        for item in arbre.getroot().iter("Item"):
            if item.get("type") != "CWeaponInfo":
                continue
            nom = None
            for enfant in item:
                if enfant.tag == "Name" and (enfant.text or "").strip():
                    nom = enfant.text.strip()
                    break
            if not nom:
                continue
            champs: Champs = {}
            for enfant in item:
                if enfant.tag not in CHAMPS_REQUIS:
                    continue
                brut = enfant.get("value")
                if brut is None:
                    continue
                try:
                    valeur = int(brut) if enfant.tag in CHAMPS_ENTIERS else float(brut)
                except ValueError:
                    continue
                champs[enfant.tag] = valeur
            definitions.setdefault(nom, []).append((relatif, champs))
    return definitions


def choisir(nom: str, candidats: list[Candidat]) -> Candidat:
    """Choisit la définition d'une arme et vérifie ses champs requis.

    Une définition sous `update/update.rpf/` est prioritaire sur l'originale.
    Sans définition update, l'unique candidat est retenu. Zéro candidat, deux
    candidats update ou deux candidats originaux sont ambigus et lèvent
    ErreurEquilibrage, de même qu'un champ requis absent après le choix.
    """
    updates = [c for c in candidats if c[0].startswith("update/update.rpf/")]
    if updates:
        if len(updates) > 1:
            chemins = ", ".join(c[0] for c in updates)
            raise ErreurEquilibrage(
                f"arme {nom} ambiguë : plusieurs définitions update : {chemins}"
            )
        retenu = updates[0]
    else:
        if not candidats:
            raise ErreurEquilibrage(f"arme introuvable dans les métadonnées : {nom}")
        if len(candidats) > 1:
            chemins = ", ".join(c[0] for c in candidats)
            raise ErreurEquilibrage(
                f"arme {nom} ambiguë : plusieurs définitions : {chemins}"
            )
        retenu = candidats[0]

    manquants = [champ for champ in CHAMPS_REQUIS if champ not in retenu[1]]
    if manquants:
        raise ErreurEquilibrage(
            f"arme {nom} ({retenu[0]}) : champs manquants : {', '.join(manquants)}"
        )
    return retenu


def attenuation(d: float, mini: float, maxi: float, mod: float) -> float:
    """H1 : atténuation linéaire de 1 à mod entre mini et maxi.

    À VÉRIFIER EN JEU : la courbe réelle de DamageFallOff peut ne pas être
    linéaire ; bornes inclusive et interpolation sont une hypothèse.
    """
    if d <= mini:
        return 1.0
    if d >= maxi:
        return mod
    return 1.0 + (mod - 1.0) * (d - mini) / (maxi - mini)


def degat_tir(champs: Champs, d: float, tete: bool) -> float:
    """H2 : dégât d'un tir à la distance d, corps ou tête.

    À VÉRIFIER EN JEU : on suppose que toutes les billes d'un tir touchent et
    que le multiplicateur tête s'applique après l'atténuation.
    """
    degat = (
        champs["Damage"]
        * champs["NetworkPlayerDamageModifier"]
        * attenuation(
            d,
            champs["DamageFallOffRangeMin"],
            champs["DamageFallOffRangeMax"],
            champs["DamageFallOffModifier"],
        )
        * champs["BulletsInBatch"]
    )
    if tete:
        degat *= champs["NetworkHeadShotPlayerDamageModifier"]
    return float(degat)


def tirs_pour_tuer(points: float, degat: float) -> int:
    """H3 + H4 : plus petit nombre de tirs pour retirer `points`.

    H3 : 200 points à retirer (100 PV + 100 de kevlar), le kevlar absorbant les
    dégâts à 100 %, tête comprise. H4 : le plus petit n tel que n * dégât >=
    points. La tolérance 1e-9 évite qu'un quotient exact (200 / 25 = 8) soit
    arrondi à 9 par erreur flottante.

    À VÉRIFIER EN JEU : le kevlar absorbant réellement la tête et l'absence de
    dégât résiduel aux très courtes distances.
    """
    return math.ceil(points / degat - 1e-9)


def ms_pour_tuer(tirs: int, TimeBetweenShots: float) -> int:
    """H5 : temps en ms entre le premier et le dernier tir.

    À VÉRIFIER EN JEU : le rechargement est ignoré et le délai entre deux tirs
    est supposé constant (TimeBetweenShots).
    """
    return round((tirs - 1) * TimeBetweenShots * 1000)


def tableau(
    armes: list[str], definitions: Definitions, distances: list[int]
) -> list[Ligne]:
    """Construit une ligne par arme dans l'ordre demandé, sans affichage."""
    lignes: list[Ligne] = []
    for nom in armes:
        source, champs = choisir(nom, definitions.get(nom, []))
        degat = float(champs["Damage"])
        cadence = float(champs["TimeBetweenShots"])
        chargeur = int(champs["ClipSize"])
        mesures: list[dict[str, object]] = []
        for distance in distances:
            mesure: dict[str, object] = {"distance": distance}
            for cle, tete in (("corps", False), ("tete", True)):
                tirs = tirs_pour_tuer(
                    POINTS_POUR_TUER, degat_tir(champs, distance, tete)
                )
                mesure[cle] = {
                    "tirs": tirs,
                    "ms": ms_pour_tuer(tirs, cadence),
                    "chargeur_suffit": tirs <= chargeur,
                }
            mesures.append(mesure)
        lignes.append(
            {
                "arme": nom,
                "source": source,
                "degat": degat,
                "cadence_ms": round(cadence * 1000),
                "chargeur": chargeur,
                "billes": int(champs["BulletsInBatch"]),
                "mesures": mesures,
            }
        )
    return lignes


def afficher_markdown(lignes: list[Ligne]) -> None:
    """Affiche un tableau markdown avec une colonne corps et tête par distance."""
    distances = (
        [mesure["distance"] for mesure in lignes[0]["mesures"]] if lignes else []
    )
    entete = ["Arme", "Dégât", "Billes", "Entre deux tirs (ms)", "Chargeur"]
    for distance in distances:
        entete += [f"{distance} m corps", f"{distance} m tête"]
    print("| " + " | ".join(entete) + " |")
    print("| " + " | ".join("---" for _ in entete) + " |")
    for ligne in lignes:
        cellules = [
            str(ligne["arme"]),
            f"{ligne['degat']:g}",
            str(ligne["billes"]),
            str(ligne["cadence_ms"]),
            str(ligne["chargeur"]),
        ]
        for mesure in ligne["mesures"]:
            for cle in ("corps", "tete"):
                resultat = mesure[cle]
                cellule = f"{resultat['tirs']} tirs / {resultat['ms']} ms"
                if not resultat["chargeur_suffit"]:
                    cellule += " *"
                cellules.append(cellule)
        print("| " + " | ".join(cellules) + " |")
    print()
    print(
        "* : le chargeur ne suffit pas pour le nombre de tirs indiqué ; "
        "le temps de rechargement est ignoré du calcul."
    )


def main(argv: list[str] | None = None) -> int:
    """Point d'entrée : lit la config et les .meta, calcule puis affiche."""
    analyseur = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        epilog="Codes de sortie : 0 succès, 2 données ou configuration invalides.",
    )
    analyseur.add_argument(
        "dossier_meta",
        help="dossier des fichiers weapon*.meta extraits du jeu (lecture seule)",
    )
    analyseur.add_argument(
        "--config",
        default=CONFIG_DEFAUT,
        help="fichier config.lua (défaut : celui du dépôt)",
    )
    analyseur.add_argument(
        "--format",
        choices=("markdown", "json"),
        default="markdown",
        help="format de sortie sur stdout (défaut : markdown)",
    )
    analyseur.add_argument(
        "--distances",
        default="10,25,50",
        help="distances en mètres, entiers séparés par des virgules",
    )
    args = analyseur.parse_args(argv)

    try:
        distances = [int(valeur.strip()) for valeur in args.distances.split(",")]
        if any(distance < 0 for distance in distances):
            raise ValueError("distance négative")
    except ValueError:
        analyseur.error("--distances doit être une liste d'entiers positifs")

    try:
        texte_config = Path(args.config).read_text(encoding="utf-8")
        armes = armes_du_config(texte_config)
        dossier = Path(args.dossier_meta)
        if not dossier.is_dir():
            raise ErreurEquilibrage(f"dossier de métadonnées introuvable : {dossier}")
        definitions = lire_definitions(dossier)
        lignes = tableau(armes, definitions, distances)
    except (ErreurEquilibrage, OSError, UnicodeDecodeError) as erreur:
        print(f"Erreur : {erreur}", file=sys.stderr)
        return SORTIE_ERREUR

    if args.format == "json":
        json.dump(lignes, sys.stdout, ensure_ascii=False, indent=2)
        print()
    else:
        afficher_markdown(lignes)
    return SORTIE_OK


if __name__ == "__main__":
    sys.exit(main())
