#!/usr/bin/env python3
"""Ajoute un véhicule (pack FiveM ou dlc.rpf) à la ressource gf_vehicles.

Usage :
    py scripts/ajouter_vehicule.py <dossier_du_pack | dlc.rpf> [--nom "Nom affiché"] [--essai]

Ce que fait le script :
  1. lit le pack (dossier extrait, ou archive GTA dlc.rpf non chiffrée) ;
  2. copie les modèles (.yft/.ytd/.ydr) dans gf_vehicles/stream/ ;
  3. copie les réglages (.meta) dans gf_vehicles/data/<modèle>/ ;
  4. copie le son du moteur s'il est fourni (audioconfig/ + sfx/) ;
  5. reprend les noms affichés du pack (AddTextEntry des .lua, lus comme du
     texte, jamais exécutés) dans data/<modèle>/names.json ;
  6. nettoie les réglages : liens publicitaires dans les noms, entrées de
     carvariations.meta pour des modèles absents du pack ;
  7. déclare les fichiers dans fxmanifest.lua et ajoute le véhicule à
     Config.Vehicles (onglet « Véhicule » de /customveh).

Ensuite : redémarrer le serveur. La photo du menu est prise automatiquement à la
prochaine arrivée d'un admin au lobby. Guide complet : docs/ajouter-un-modele.md.

Le script n'exécute rien du pack : il ne lit et ne copie que des fichiers de
données. --essai affiche ce qui serait fait sans rien écrire.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import tempfile
import zlib
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
RESSOURCE = RACINE / "server-data" / "resources" / "[gunfight]" / "gf_vehicles"
MANIFESTE = RESSOURCE / "fxmanifest.lua"
CONFIG = RESSOURCE / "config.lua"

MODELES = {".yft", ".ytd", ".ydr", ".ydd", ".ybn"}
METAS = {"vehicles.meta", "handling.meta", "carcols.meta", "carvariations.meta", "vehiclelayouts.meta"}
NL = "\n"
# Taille au-delà de laquelle FXServer signale un « oversized asset »
TAILLE_LOURDE = 16 * 1024 * 1024


# ---------------------------------------------------------------- Archive RPF7
# Limites de sécurité de l'extracteur RPF7 (consultées par extraire_rpf, et
# remplaçables par les tests avec unittest.mock.patch).
LIMITE_FICHIER = 512 * 1024 * 1024       # 512 Mo par fichier décompressé
LIMITE_TOTALE = 4 * 1024 * 1024 * 1024   # 4 Go écrits au total
PROFONDEUR_MAX = 8                       # profondeur maximale des .rpf imbriqués

# Composants de nom interdits (traversée, caractères Windows et noms réservés).
_NOMS_RESERVES = {
    "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5",
    "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4",
    "lpt5", "lpt6", "lpt7", "lpt8", "lpt9",
}
_CARACTERES_INTERDITS = set('/\\:<>"|?*')


def extraire_rpf(fichier: Path, sortie: Path) -> None:
    """Extrait une archive GTA RPF7 non chiffrée (« OPEN »), .rpf imbriqués compris.

    Toute archive malformée ou piégée lève une ValueError en français : aucun
    autre type d'exception ne doit s'échapper, et aucune écriture ne sort de
    ``sortie``.
    """
    try:
        racine = sortie.resolve()
    except OSError as erreur:
        raise ValueError(f"dossier de sortie illisible : {erreur}") from None
    total: list[int] = [0]

    def verifier_nom(nom: str, prefixe: Path) -> None:
        if not isinstance(nom, str) or not nom:
            raise ValueError(f"{prefixe} : nom d'entrée vide")
        if nom in (".", "..") or any(c in nom for c in _CARACTERES_INTERDITS):
            raise ValueError(f"{prefixe} : nom d'entrée invalide « {nom} »")
        if any(ord(c) < 32 or ord(c) == 127 for c in nom):
            raise ValueError(f"{prefixe} : nom d'entrée contrôlé « {nom!r} »")
        if nom.rstrip(" .") == "" or nom.split(".")[0].lower() in _NOMS_RESERVES:
            raise ValueError(f"{prefixe} : nom d'entrée réservé « {nom} »")

    def ecrire(cible: Path, donnees: bytes, prefixe: Path) -> None:
        """Vérifie le périmètre et les limites avant chaque écriture."""
        try:
            cible_resolue = cible.resolve()
        except OSError as erreur:
            raise ValueError(f"{prefixe} : chemin de sortie illisible : {erreur}") from None
        try:
            cible_resolue.relative_to(racine)
        except ValueError:
            raise ValueError(f"{prefixe} : écriture hors du dossier de sortie") from None
        if cible_resolue == racine:
            raise ValueError(f"{prefixe} : écriture hors du dossier de sortie")
        if len(donnees) > LIMITE_FICHIER:
            raise ValueError(f"{prefixe} : fichier trop volumineux (limite {LIMITE_FICHIER} octets)")
        total[0] += len(donnees)
        if total[0] > LIMITE_TOTALE:
            raise ValueError(f"{prefixe} : total écrit trop volumineux (limite {LIMITE_TOTALE} octets)")
        try:
            cible.parent.mkdir(parents=True, exist_ok=True)
            cible.write_bytes(donnees)
        except OSError as erreur:
            raise ValueError(f"{prefixe} : écriture impossible : {erreur}") from None

    def lire(buf: bytes, prefixe: Path, profondeur: int) -> None:
        if len(buf) < 16:
            raise ValueError(f"{prefixe} : en-tête RPF7 tronqué")
        if buf[:4] != b"7FPR":
            raise ValueError(f"{prefixe} n'est pas une archive RPF7")
        nombre = int.from_bytes(buf[4:8], "little")
        chiffrement = int.from_bytes(buf[12:16], "little")
        if chiffrement not in (0, 0x4E45504F):
            raise ValueError(f"{prefixe} est chiffrée : extrais-la avec OpenIV ou CodeWalker")
        table_fin = 16 + nombre * 16
        if table_fin > len(buf):
            raise ValueError(f"{prefixe} : table des entrées hors de l'archive")
        longueur_noms = int.from_bytes(buf[8:12], "little")
        noms = table_fin
        fin_noms = noms + longueur_noms
        if fin_noms > len(buf):
            raise ValueError(f"{prefixe} : table des noms hors de l'archive")
        if longueur_noms == 0:
            raise ValueError(f"{prefixe} : table des noms vide")

        def nom(decalage: int) -> str:
            if decalage >= longueur_noms:
                raise ValueError(f"{prefixe} : décalage de nom hors de la table")
            debut = noms + decalage
            fin = buf.find(b"\0", debut, fin_noms)
            if fin < 0:
                raise ValueError(f"{prefixe} : nom non terminé dans la table")
            return buf[debut:fin].decode("latin-1")

        entrees: list[tuple] = []
        for i in range(nombre):
            p = 16 + i * 16
            if int.from_bytes(buf[p + 4:p + 8], "little") == 0x7FFFFF00:
                entrees.append(("dir", nom(int.from_bytes(buf[p:p + 4], "little")),
                                int.from_bytes(buf[p + 8:p + 12], "little"),
                                int.from_bytes(buf[p + 12:p + 16], "little")))
            else:
                bas = int.from_bytes(buf[p:p + 4], "little")
                haut = int.from_bytes(buf[p + 4:p + 8], "little")
                taille = (bas >> 16) | ((haut & 0xFF) << 16)
                decalage = (haut >> 8) & 0xFFFFFF
                entrees.append(("res" if decalage & 0x800000 else "bin", nom(bas & 0xFFFF),
                                taille, decalage & 0x7FFFFF,
                                int.from_bytes(buf[p + 8:p + 12], "little")))

        if not entrees or entrees[0][0] != "dir":
            raise ValueError(f"{prefixe} : l'entrée 0 n'est pas un répertoire")

        # Parcours itératif : (index d'entrée, chemin relatif, index enfant).
        # Un seul ensemble d'index visités évite les cycles (directs ou
        # indirects) et les explositions exponentielles sur les DAG partagés.
        visites: set[int] = set()
        pile: list[tuple[int, Path, int]] = []
        if entrees[0][2] > nombre or entrees[0][3] > nombre - entrees[0][2]:
            raise ValueError(f"{prefixe} : intervalles d'enfants hors de la table")
        visites.add(0)
        pile.append((0, Path(), entrees[0][2]))
        while pile:
            index, relatif, enfant = pile[-1]
            debut, n = entrees[index][2], entrees[index][3]
            if enfant >= debut + n:
                pile.pop()
                continue
            pile[-1] = (index, relatif, enfant + 1)
            k = enfant
            if k < 0 or k >= len(entrees):
                raise ValueError(f"{prefixe} : index d'entrée hors de la table")
            e = entrees[k]
            verifier_nom(e[1], prefixe / relatif)
            chemin = relatif / e[1]
            try:
                cible = (sortie / prefixe / chemin).resolve()
            except OSError as erreur:
                raise ValueError(f"{prefixe} : chemin d'entrée illisible : {erreur}") from None
            try:
                cible.relative_to(racine)
            except ValueError:
                raise ValueError(f"{prefixe} : entrée hors du dossier de sortie") from None

            if e[0] == "dir":
                debut_enfant, nombre_enfants = e[2], e[3]
                if debut_enfant > nombre or nombre_enfants > nombre - debut_enfant:
                    raise ValueError(f"{prefixe} : intervalles d'enfants hors de la table")
                if k in visites:
                    raise ValueError(f"{prefixe} : cycle ou répertoire déjà visité « {chemin} »")
                visites.add(k)
                pile.append((k, chemin, debut_enfant))
                continue

            genre, _, taille, bloc, brut = e
            pos = bloc * 512
            if pos > len(buf):
                raise ValueError(f"{prefixe} : bloc de données hors de l'archive")
            disponible = len(buf) - pos
            if genre == "res":
                if taille == 0xFFFFFF:
                    if disponible < 16:
                        raise ValueError(f"{prefixe} : en-tête de ressource tronqué")
                    h = buf[pos:pos + 16]
                    taille = h[7] | (h[14] << 8) | (h[5] << 16) | (h[2] << 24)
                    if taille > disponible:
                        raise ValueError(f"{prefixe} : ressource hors de l'archive")
                    donnees = buf[pos:pos + taille]
                elif taille > disponible:
                    raise ValueError(f"{prefixe} : ressource hors de l'archive")
                else:
                    donnees = buf[pos:pos + taille]
            elif taille == 0:
                if brut > disponible:
                    # Certains packs réels surestiment la taille d'un .rpf
                    # imbriqué : la lecture récursive vérifie déjà ses bornes.
                    if e[1].lower().endswith(".rpf"):
                        donnees = buf[pos:]
                    else:
                        raise ValueError(f"{prefixe} : données hors de l'archive")
                else:
                    donnees = buf[pos:pos + brut]
            else:
                if taille > disponible:
                    raise ValueError(f"{prefixe} : données compressées hors de l'archive")
                if taille > LIMITE_FICHIER:
                    raise ValueError(f"{prefixe} : fichier trop volumineux (limite {LIMITE_FICHIER} octets)")
                try:
                    obj = zlib.decompressobj(-15)
                    morceaux: list[bytes] = []
                    produit = 0
                    reste = buf[pos:pos + taille]
                    while True:
                        morceau = obj.decompress(reste, max(1, LIMITE_FICHIER - produit + 1))
                        produit += len(morceau)
                        if produit > LIMITE_FICHIER:
                            raise ValueError(f"{prefixe} : bombes de décompression (limite {LIMITE_FICHIER} octets)")
                        if morceau:
                            morceaux.append(morceau)
                        reste = obj.unconsumed_tail
                        if not reste:
                            break
                    if obj.flush():
                        raise ValueError(f"{prefixe} : bombes de décompression (limite {LIMITE_FICHIER} octets)")
                    if not obj.eof:
                        raise ValueError(f"{prefixe} : flux zlib tronqué")
                    donnees = b"".join(morceaux)
                except zlib.error:
                    raise ValueError(f"{prefixe} : données zlib invalides ou tronquées") from None

            if e[1].lower().endswith(".rpf"):
                if profondeur >= PROFONDEUR_MAX:
                    raise ValueError(f"{prefixe} : profondeur maximale des .rpf imbriqués atteinte")
                if len(donnees) > LIMITE_FICHIER:
                    raise ValueError(f"{prefixe} : fichier trop volumineux (limite {LIMITE_FICHIER} octets)")
                lire(donnees, prefixe / chemin, profondeur + 1)
                continue
            ecrire(sortie / prefixe / chemin, donnees, prefixe / relatif)

    lire(fichier.read_bytes(), Path(fichier.stem), 0)


# ---------------------------------------------------------------- Réglages
def balises(texte: str, nom: str) -> list[str]:
    return re.findall(rf"<{nom}>\s*([^<]*?)\s*</{nom}>", texte)


def nettoyer_vehicles_meta(texte: str, modele: str, notes: list[str]) -> str:
    def remplacer(balise: str, valeur: str) -> None:
        nonlocal texte
        motif = re.compile(rf"(<{balise}>)([^<]*)(</{balise}>)")
        def sub(m: re.Match) -> str:
            contenu = m.group(2)
            if re.search(r"https?://|discord|\.gg/|www\.", contenu, re.I):
                notes.append(f"{balise} contenait un lien ({contenu.strip()}), "
                             + (f"remplacé par « {valeur} »" if valeur else "vidé"))
                return m.group(1) + valeur + m.group(3)
            return m.group(0)
        texte = motif.sub(sub, texte)

    remplacer("gameName", modele)
    remplacer("vehicleMakeName", "")
    return texte


def nettoyer_carvariations(texte: str, modeles: set[str], notes: list[str]) -> str:
    """Retire les entrées de modèles qui ne sont pas dans le pack.

    Les entrées sont les <Item> de premier niveau sous <variationData> ; on
    suit la profondeur des balises <Item> (les <Item .../> auto-fermantes ne
    comptent pas) pour ne pas couper une entrée au milieu.
    """
    debut = texte.find("<variationData>")
    if debut == -1:
        return texte
    morceaux, profondeur, depart = [], 0, None
    for m in re.finditer(r"<Item(\s[^>]*)?>|</Item>|</variationData>", texte[debut:]):
        jeton = m.group(0)
        a, b = debut + m.start(), debut + m.end()
        if jeton == "</variationData>":
            break
        if jeton.startswith("</"):
            profondeur -= 1
            if profondeur == 0 and depart is not None:
                bloc = texte[depart:b]
                nom = balises(bloc, "modelName")
                if nom and nom[0].lower() not in modeles:
                    notes.append(f"carvariations.meta : entrée « {nom[0]} » retirée (modèle absent du pack)")
                    debut_ligne = texte.rfind(NL, 0, depart) + 1
                    morceaux.append((debut_ligne, b))
                depart = None
        elif not jeton.endswith("/>"):
            if profondeur == 0:
                depart = a
            profondeur += 1
    for a, b in reversed(morceaux):
        fin = b + 1 if texte[b:b + 1] == NL else b
        texte = texte[:a] + texte[fin:]
    return texte


def noms_du_pack(fichiers: list[Path]) -> dict[str, str]:
    """Noms affichés (pièces, livrées, modèle) déclarés par AddTextEntry dans les .lua du pack.

    Le .lua est lu comme du texte : seules les paires littérales sont reprises.
    """
    noms: dict[str, str] = {}
    motif = re.compile(r"""AddTextEntry\(\s*["']([^"']{1,64})["']\s*,\s*["']([^"']{0,120})["']\s*\)""")
    for f in fichiers:
        if f.suffix.lower() != ".lua":
            continue
        for cle, texte in motif.findall(f.read_text(encoding="utf-8", errors="replace")):
            if re.fullmatch(r"[A-Za-z0-9_]+", cle) and not re.search(r"https?://|discord", texte, re.I):
                noms[cle] = texte
    return noms


# ---------------------------------------------------------------- Déclarations
def ajouter_lignes_files(manifeste: str, chemins: list[str]) -> str:
    debut = manifeste.index("files {")
    fin = manifeste.index("}", debut)
    bloc = manifeste[debut:fin]
    nouvelles = [c for c in chemins if f"'{c}'" not in bloc]
    if not nouvelles:
        return manifeste
    # avant les fichiers html/ pour garder les données groupées
    ancre = manifeste.find("    'html/index.html'", debut, fin)
    insertion = "".join(f"    '{c}',\n" for c in nouvelles)
    pos = ancre if ancre != -1 else fin
    return manifeste[:pos] + insertion + manifeste[pos:]


def ajouter_data_files(manifeste: str, lignes: list[str]) -> str:
    """Ajoute les lignes data_file manquantes juste après la dernière existante."""
    nouvelles = [l for l in lignes if l not in manifeste]
    if not nouvelles:
        return manifeste
    derniere = manifeste.rfind(NL + "data_file ")
    if derniere == -1:
        return manifeste.rstrip(NL) + NL * 2 + NL.join(nouvelles) + NL
    fin = manifeste.index(NL, derniere + 1)
    return manifeste[:fin] + NL + NL.join(nouvelles) + manifeste[fin:]


def ajouter_config(config: str, modele: str, nom: str) -> str:
    if re.search(rf"model\s*=\s*'{re.escape(modele)}'", config):
        return config
    debut = config.index("Config.Vehicles = {")
    fin = config.index("\n}", debut)
    largeur = max(len(m) for m in re.findall(r"model = '([^']+)'", config[debut:fin]) + [modele])
    ligne = f"\n    {{ model = '{modele}',{' ' * (largeur - len(modele) + 1)}label = '{nom.replace(chr(39), ' ')}' }},"
    return config[:fin] + ligne + config[fin:]


# ---------------------------------------------------------------- Programme
def main() -> int:
    # Accents lisibles dans la console Windows
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Ajoute un véhicule à gf_vehicles (voir docs/ajouter-un-modele.md).")
    parser.add_argument("source", type=Path, help="dossier du pack extrait, ou fichier dlc.rpf")
    parser.add_argument("--nom", help="nom affiché dans le menu (défaut : nom du modèle)")
    parser.add_argument("--son", help="son de moteur à utiliser (audioNameHash), ex. lg247hemi57 pour celui du Bison")
    parser.add_argument("--essai", action="store_true", help="affiche ce qui serait fait sans rien écrire")
    args = parser.parse_args()

    source: Path = args.source.resolve()
    if not source.exists():
        print(f"Introuvable : {source}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="gf-vehicule-") as tmp:
        dossier = source
        if source.is_file():
            if source.suffix.lower() != ".rpf":
                print("Donne un dossier extrait ou un fichier .rpf (les .zip/.rar sont à extraire d'abord).", file=sys.stderr)
                return 1
            dossier = Path(tmp)
            try:
                extraire_rpf(source, dossier)
            except ValueError as erreur:
                print(f"Erreur : {erreur}", file=sys.stderr)
                return 1

        fichiers = [f for f in dossier.rglob("*") if f.is_file()]
        metas = {}
        for f in fichiers:
            if f.name.lower() in METAS:
                metas.setdefault(f.name.lower(), f)
        if "vehicles.meta" not in metas:
            print("Pas de vehicles.meta dans le pack : ce n'est pas un véhicule ajouté (add-on).", file=sys.stderr)
            return 1

        vehicles_meta = metas["vehicles.meta"].read_text(encoding="utf-8", errors="replace")
        modeles = [m.lower() for m in balises(vehicles_meta, "modelName")]
        if not modeles:
            print("vehicles.meta ne contient aucun <modelName>.", file=sys.stderr)
            return 1
        modele = modeles[0]
        noms = noms_du_pack(fichiers)
        nom_du_pack = next((noms[g] for g in balises(vehicles_meta, "gameName") if g in noms), None)
        nom = args.nom or nom_du_pack or modele
        if not re.fullmatch(r"[a-z0-9_]+", modele):
            print(f"Nom de modèle inattendu : {modele}", file=sys.stderr)
            return 1

        stream = [f for f in fichiers if f.suffix.lower() in MODELES]
        if not any(f.stem.lower() == modele and f.suffix.lower() == ".yft" for f in stream):
            print(f"Modèle 3D {modele}.yft absent du pack : il faut le dossier stream (ou le dlc.rpf complet).", file=sys.stderr)
            return 1
        rels = [f for f in fichiers if f.name.lower().endswith((".dat151.rel", ".dat54.rel", ".dat10.rel", ".dat16.rel"))]
        awcs = [f for f in fichiers if f.suffix.lower() == ".awc"]

        notes: list[str] = []
        actions: list[str] = []
        manifeste = MANIFESTE.read_text(encoding="utf-8")
        config = CONFIG.read_text(encoding="utf-8")
        declarer: list[str] = []
        data_files: list[str] = []

        # Modèles 3D
        for f in stream:
            cible = RESSOURCE / "stream" / f.name.lower()
            if cible.exists() and cible.stat().st_size != f.stat().st_size:
                notes.append(f"stream/{cible.name} existait déjà (remplacé)")
            if f.suffix.lower() == ".ytd" and f.stat().st_size > TAILLE_LOURDE:
                notes.append(f"{f.name} pèse {f.stat().st_size // (1024 * 1024)} Mo : textures lourdes, risque de chargement lent")
            actions.append(f"stream/{cible.name}")
            if not args.essai:
                cible.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(f, cible)

        # Réglages
        dossier_data = RESSOURCE / "data" / modele
        for nom_meta, f in sorted(metas.items()):
            texte = f.read_text(encoding="utf-8", errors="replace")
            if nom_meta == "vehicles.meta":
                texte = nettoyer_vehicles_meta(texte, modele, notes)
                if args.son:
                    if not re.fullmatch(r"[A-Za-z0-9_]+", args.son):
                        print(f"Son invalide : {args.son}", file=sys.stderr)
                        return 1
                    son_xml = f"<audioNameHash>{args.son}</audioNameHash>"
                    if re.search(r"<audioNameHash\s*/>|<audioNameHash>", texte):
                        # remplace la ligne existante, pleine ou vide (<audioNameHash />)
                        texte = re.sub(r"<audioNameHash>[^<]*</audioNameHash>|<audioNameHash\s*/>", son_xml, texte)
                    else:
                        # pas de ligne de son : on l'ajoute après <handlingId>
                        texte = re.sub(r"(\n([ \t]*)<handlingId>[^<]*</handlingId>)",
                                       lambda m: m.group(1) + NL + m.group(2) + son_xml,
                                       texte, count=1)
                    notes.append(f"son du moteur : « {args.son} »")
            elif nom_meta == "carvariations.meta":
                texte = nettoyer_carvariations(texte, set(modeles), notes)
            chemin = f"data/{modele}/{nom_meta}"
            declarer.append(chemin)
            actions.append(chemin)
            if nom_meta == "vehiclelayouts.meta":
                data_files.append("data_file 'VEHICLE_LAYOUTS_FILE' 'data/**/vehiclelayouts.meta'")
            if not args.essai:
                dossier_data.mkdir(parents=True, exist_ok=True)
                (dossier_data / nom_meta).write_text(texte, encoding="utf-8", newline="\n")

        # Noms affichés (pièces, livrées) : chargés par gf_vehicles/client.lua
        if noms:
            chemin = f"data/{modele}/names.json"
            declarer.append(chemin)
            actions.append(chemin)
            notes.append(f"{len(noms)} nom(s) affiché(s) repris du pack (pièces, livrées)")
            if not args.essai:
                dossier_data.mkdir(parents=True, exist_ok=True)
                (dossier_data / "names.json").write_text(
                    json.dumps(noms, ensure_ascii=False, indent=2, sort_keys=True) + NL, encoding="utf-8", newline=NL)

        # Son du moteur
        for f in rels:
            chemin = f"audioconfig/{f.name.lower()}"
            declarer.append(chemin)
            actions.append(chemin)
            base = chemin[: -len(".rel")]
            base = re.sub(r"\.dat\d+$", ".dat", base)
            if f.name.lower().endswith(".dat151.rel"):
                data_files.append(f"data_file 'AUDIO_GAMEDATA' '{base}'")
            elif f.name.lower().endswith(".dat54.rel"):
                data_files.append(f"data_file 'AUDIO_SOUNDDATA' '{base}'")
            if not args.essai:
                (RESSOURCE / "audioconfig").mkdir(exist_ok=True)
                shutil.copyfile(f, RESSOURCE / chemin)
        for f in awcs:
            pack = f.parent.name.lower() if f.parent.name.lower().startswith("dlc_") else f"dlc_{modele}"
            chemin = f"sfx/{pack}/{f.name.lower()}"
            declarer.append(chemin)
            actions.append(chemin)
            data_files.append(f"data_file 'AUDIO_WAVEPACK' 'sfx/{pack}'")
            if not args.essai:
                (RESSOURCE / "sfx" / pack).mkdir(parents=True, exist_ok=True)
                shutil.copyfile(f, RESSOURCE / chemin)
        if not rels and not args.son:
            son = balises(vehicles_meta, "audioNameHash")
            if not son:
                notes.append("pas de son fourni ni de ligne de son : véhicule muet. Relancer avec --son lg247hemi57")
            if son:
                notes.append(f"pas de son fourni : le véhicule utilise « {son[0]} » (son GTA, ou silencieux s'il "
                             "n'existe pas). Pour un son du serveur : --son lg247hemi57")

        manifeste = ajouter_lignes_files(manifeste, declarer)
        manifeste = ajouter_data_files(manifeste, sorted(set(data_files), key=data_files.index))
        config = ajouter_config(config, modele, nom)
        if not args.essai:
            MANIFESTE.write_text(manifeste, encoding="utf-8", newline="\n")
            CONFIG.write_text(config, encoding="utf-8", newline="\n")

    titre = "ESSAI (rien n'est écrit)" if args.essai else "Véhicule ajouté"
    print(f"{titre} : {nom} (modèle « {modele} »)")
    print(f"  {len(stream)} fichier(s) 3D, {len(metas)} réglage(s), {len(rels) + len(awcs)} fichier(s) de son")
    for n in notes:
        print(f"  ! {n}")
    print("\nÉtapes suivantes :")
    print("  1. redémarrer le serveur (un véhicule ajouté ne se charge pas à chaud) ;")
    print("  2. commit de gf_vehicles, puis pull request ;")
    print("  3. rien d'autre : la photo du menu se prend toute seule à la prochaine")
    print("     arrivée d'un admin au lobby (refaire à la main : /thumbs vehicles " + modele + ").")
    return 0


if __name__ == "__main__":
    sys.exit(main())
