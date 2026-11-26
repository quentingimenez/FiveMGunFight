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
def extraire_rpf(fichier: Path, sortie: Path) -> None:
    """Extrait une archive GTA RPF7 non chiffrée (« OPEN »), .rpf imbriqués compris."""

    def lire(buf: bytes, prefixe: Path) -> None:
        if buf[:4] != b"7FPR":
            raise ValueError(f"{prefixe} n'est pas une archive RPF7")
        nombre = int.from_bytes(buf[4:8], "little")
        chiffrement = int.from_bytes(buf[12:16], "little")
        if chiffrement not in (0, 0x4E45504F):
            raise ValueError(f"{prefixe} est chiffrée : extrais-la avec OpenIV ou CodeWalker")
        noms = 16 + nombre * 16

        def nom(decalage: int) -> str:
            fin = buf.index(b"\0", noms + decalage)
            return buf[noms + decalage:fin].decode("latin-1")

        entrees = []
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

        def parcourir(index: int, relatif: Path) -> None:
            _, _, debut, n = entrees[index]
            for k in range(debut, debut + n):
                e = entrees[k]
                chemin = relatif / e[1]
                if e[0] == "dir":
                    parcourir(k, chemin)
                    continue
                genre, _, taille, bloc, brut = e
                pos = bloc * 512
                if genre == "res":
                    if taille == 0xFFFFFF:
                        h = buf[pos:pos + 16]
                        taille = h[7] | (h[14] << 8) | (h[5] << 16) | (h[2] << 24)
                    donnees = buf[pos:pos + taille]
                elif taille == 0:
                    donnees = buf[pos:pos + brut]
                else:
                    donnees = zlib.decompress(buf[pos:pos + taille], -15)
                if e[1].lower().endswith(".rpf"):
                    lire(bytes(donnees), prefixe / chemin)
                    continue
                cible = sortie / prefixe / chemin
                cible.parent.mkdir(parents=True, exist_ok=True)
                cible.write_bytes(donnees)

        parcourir(0, Path())

    lire(fichier.read_bytes(), Path(fichier.stem))


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
            extraire_rpf(source, dossier)

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
                    texte = re.sub(r"<audioNameHash>[^<]*</audioNameHash>", f"<audioNameHash>{args.son}</audioNameHash>", texte)
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
