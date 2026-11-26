#!/usr/bin/env python3
"""Ajoute une arme (pack FiveM « add-on weapon ») à la ressource gf_weapons.

Usage :
    py scripts/ajouter_arme.py <dossier_du_pack> [--nom "Nom affiché"] [--id identifiant] [--essai]

Ce que fait le script :
  1. trouve l'arme dans weapons.meta (<Name>WEAPON_…</Name>) ;
  2. copie les modèles (.ydr/.ytd/.yft) dans gf_weapons/stream/ ;
  3. copie les réglages (.meta, accessoires compris) dans gf_weapons/data/<ARME>/ ;
  4. reprend les noms affichés du pack (AddTextEntry des .lua, lus comme du texte,
     jamais exécutés) dans data/<ARME>/names.json ;
  5. déclare les fichiers dans fxmanifest.lua et l'arme dans data/index.json ;
  6. ajoute l'arme au catalogue Config.Weapons de gf_core (catégorie et munitions
     déduites du groupe GTA de l'arme).

L'arme n'est donnée à personne : un admin se la donne avec /armes, puis l'équipe
dans le Casier (menu Échap). Sa photo se prend toute seule à la prochaine arrivée
d'un admin au lobby. Guide : docs/ajouter-un-modele.md.

Les dossiers « Replace » (remplacement d'armes du jeu) sont ignorés.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
GUNFIGHT = RACINE / "server-data" / "resources" / "[gunfight]"
RESSOURCE = GUNFIGHT / "gf_weapons"
MANIFESTE = RESSOURCE / "fxmanifest.lua"
INDEX = RESSOURCE / "data" / "index.json"
CONFIG_CORE = GUNFIGHT / "gf_core" / "config.lua"
NL = "\n"

MODELES = {".ydr", ".ytd", ".yft"}
METAS = {"weapons.meta", "weaponcomponents.meta", "weaponarchetypes.meta",
         "weaponanimations.meta", "pedpersonality.meta"}

# Groupe GTA -> (catégorie du catalogue, munitions de départ)
GROUPES = {
    "GROUP_RIFLE": ("Fusil d'assaut", 300),
    "GROUP_MG": ("Mitrailleuse", 400),
    "GROUP_SMG": ("Mitraillette", 360),
    "GROUP_SHOTGUN": ("Fusil à pompe", 60),
    "GROUP_SNIPER": ("Précision", 60),
    "GROUP_PISTOL": ("Pistolet", 96),
}


def noms_du_pack(fichiers: list[Path]) -> dict[str, str]:
    """Paires littérales AddTextEntry("CLE", "Texte") des .lua du pack (lus comme du texte)."""
    noms: dict[str, str] = {}
    motif = re.compile(r"""AddTextEntry\(\s*["']([^"']{1,64})["']\s*,\s*["']([^"']{0,120})["']\s*\)""")
    for f in fichiers:
        if f.suffix.lower() == ".lua":
            for cle, texte in motif.findall(f.read_text(encoding="utf-8", errors="replace")):
                if re.fullmatch(r"[A-Za-z0-9_]+", cle) and not re.search(r"https?://|discord", texte, re.I):
                    noms[cle] = texte
    return noms


def joli(texte: str) -> str:
    """« GHOST FAIR HONEY BADGER » -> « Ghost Fair Honey Badger » (si tout en majuscules)."""
    return texte.title() if texte.isupper() else texte


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Ajoute une arme à gf_weapons (voir docs/ajouter-un-modele.md).")
    parser.add_argument("source", type=Path, help="dossier du pack (contenant weapons.meta et stream/)")
    parser.add_argument("--nom", help="nom affiché (défaut : nom du pack)")
    parser.add_argument("--id", help="identifiant du catalogue (défaut : nom de l'arme sans WEAPON_, en minuscules)")
    parser.add_argument("--essai", action="store_true", help="affiche ce qui serait fait sans rien écrire")
    args = parser.parse_args()

    source: Path = args.source.resolve()
    if not source.is_dir():
        print(f"Dossier introuvable : {source}", file=sys.stderr)
        return 1
    fichiers = [f for f in source.rglob("*") if f.is_file()
                and not any(p.lower() == "replace" for p in f.relative_to(source).parts)]
    weapons_meta = [f for f in fichiers if f.name.lower() == "weapons.meta"]
    if not weapons_meta:
        print("Pas de weapons.meta dans le pack : ce n'est pas une arme ajoutée (add-on).", file=sys.stderr)
        return 1
    texte_armes = weapons_meta[0].read_text(encoding="utf-8", errors="replace")
    armes = [n for n in re.findall(r"<Name>\s*(WEAPON_[A-Z0-9_]+)\s*</Name>", texte_armes, re.I)]
    if not armes:
        print("weapons.meta ne déclare aucune arme WEAPON_….", file=sys.stderr)
        return 1
    arme = armes[0].upper()
    modele = (re.findall(r"<Model>\s*([^<\s]+)\s*</Model>", texte_armes) or [""])[0].lower()
    groupe = (re.findall(r"<Group>\s*([^<\s]+)\s*</Group>", texte_armes) or [""])[0].upper()
    categorie, munitions = GROUPES.get(groupe, ("Spéciale", 120))
    ident = (args.id or arme[len("WEAPON_"):].lower())
    if not re.fullmatch(r"[a-z0-9_]+", ident):
        print(f"Identifiant invalide : {ident}", file=sys.stderr)
        return 1

    stream = [f for f in fichiers if f.suffix.lower() in MODELES]
    if modele and not any(f.stem.lower() == modele for f in stream):
        print(f"Modèle 3D {modele} absent du pack : il faut le dossier stream.", file=sys.stderr)
        return 1
    metas = [f for f in fichiers if f.name.lower() in METAS]
    noms = noms_du_pack(fichiers)
    nom = args.nom or joli(noms.get(arme, "")) or ident
    notes: list[str] = []

    dossier = RESSOURCE / "data" / arme
    declarer: list[str] = []
    for f in stream:
        if not args.essai:
            (RESSOURCE / "stream").mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f, RESSOURCE / "stream" / f.name.lower())
        if f.suffix.lower() == ".ytd" and f.stat().st_size > 16 * 1024 * 1024:
            notes.append(f"{f.name} pèse {f.stat().st_size // (1024 * 1024)} Mo : textures lourdes")
    racine_meta = weapons_meta[0].parent
    for f in metas:
        try:
            relatif = f.relative_to(racine_meta)
        except ValueError:
            relatif = Path(f.name)
        relatif = Path(*[p.replace(" ", "_") for p in relatif.parts])
        chemin = f"data/{arme}/{relatif.as_posix()}"
        declarer.append(chemin)
        if not args.essai:
            (dossier / relatif).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f, dossier / relatif)
    if noms:
        declarer.append(f"data/{arme}/names.json")
        notes.append(f"{len(noms)} nom(s) affiché(s) repris du pack")
        if not args.essai:
            dossier.mkdir(parents=True, exist_ok=True)
            (dossier / "names.json").write_text(json.dumps(noms, ensure_ascii=False, indent=2, sort_keys=True) + NL,
                                                encoding="utf-8", newline=NL)

    # Manifeste : fichiers déclarés
    manifeste = MANIFESTE.read_text(encoding="utf-8")
    debut = manifeste.index("files {")
    fin = manifeste.index("}", debut)
    nouvelles = [c for c in sorted(declarer) if f"'{c}'" not in manifeste[debut:fin]]
    manifeste = manifeste[:fin] + "".join(f"    '{c}',{NL}" for c in nouvelles) + manifeste[fin:]

    # Index des armes ajoutées (lu par gf_weapons/client.lua pour les noms)
    index = json.loads(INDEX.read_text(encoding="utf-8")) if INDEX.exists() else []
    if arme not in index:
        index.append(arme)

    # Catalogue gf_core
    config = CONFIG_CORE.read_text(encoding="utf-8")
    if re.search(rf"name\s*=\s*'{arme}'", config):
        notes.append(f"{arme} déjà dans Config.Weapons (catalogue inchangé)")
    else:
        if re.search(rf"^\s*{ident}\s*=", config, re.M):
            print(f"L'identifiant {ident} existe déjà dans Config.Weapons : choisis-en un autre avec --id.", file=sys.stderr)
            return 1
        d = config.index("Config.Weapons = {")
        f_ = config.index(NL + "}", d)
        nom_lua = nom.replace("\\", "").replace("'", "\\'")
        cat_lua = categorie.replace("'", "\\'")
        ligne = f"{NL}    {ident} = {{ name = '{arme}', label = '{nom_lua}', category = '{cat_lua}', ammo = {munitions} }},"
        config = config[:f_] + ligne + config[f_:]

    if not args.essai:
        MANIFESTE.write_text(manifeste, encoding="utf-8", newline=NL)
        INDEX.write_text(json.dumps(index, indent=2) + NL, encoding="utf-8", newline=NL)
        CONFIG_CORE.write_text(config, encoding="utf-8", newline=NL)

    titre = "ESSAI (rien n'est écrit)" if args.essai else "Arme ajoutée"
    print(f"{titre} : {nom} ({arme}, id « {ident} », {categorie}, {munitions} munitions)")
    print(f"  {len(stream)} fichier(s) 3D, {len(metas)} réglage(s)")
    for n in notes:
        print(f"  ! {n}")
    print(NL + "Étapes suivantes :")
    print("  1. redémarrer le serveur (une arme ajoutée ne se charge pas à chaud) ;")
    print("  2. commit (gf_weapons + gf_core/config.lua), puis pull request ;")
    print("  3. rien d'autre : la photo se prend toute seule à la prochaine arrivée d'un admin au lobby ;")
    print("     un admin se donne l'arme avec /armes, puis l'équipe dans le Casier (Échap).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
