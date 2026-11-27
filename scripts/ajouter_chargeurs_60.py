#!/usr/bin/env python3
"""Ajoute un chargeur 60 aux armes personnalisées ayant un chargeur initial plus petit.

Le composant reprend le modèle et les propriétés du chargeur initial. Les
fusils à pompe, les snipers et les capacités initiales >= 60 sont conservés.
Lancer depuis le dépôt : py scripts/ajouter_chargeurs_60.py [--essai]
"""
from __future__ import annotations

import argparse
import copy
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCE = ROOT / 'server-data/resources/[gunfight]/gf_weapons'


def xml(path: Path) -> ET.Element:
    # Certains packs ont une déclaration d'encodage GTA non conforme à XML.
    text = path.read_text(encoding='utf-8').replace('UTF - 8', 'UTF-8')
    return ET.fromstring(text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--essai', action='store_true')
    args = parser.parse_args()
    weapons = sorted((RESOURCE / 'data').glob('WEAPON_*'))
    components: dict[str, ET.Element] = {}
    for weapon in weapons:
        for path in weapon.rglob('weaponcomponents.meta'):
            for item in xml(path).iter('Item'):
                if item.get('type') == 'CWeaponComponentClipInfo' and item.findtext('Name'):
                    name = item.findtext('Name', '').lower()
                    if name in components and ET.tostring(components[name]) != ET.tostring(item):
                        raise ValueError(f'Composant ambigu : {name}')
                    components[name] = item

    manifest_path = RESOURCE / 'fxmanifest.lua'
    manifest = manifest_path.read_text(encoding='utf-8')
    planned: list[tuple[Path, str, Path, str, str]] = []
    for weapon in weapons:
        path = weapon / 'weapons.meta'
        if not path.is_file():
            continue
        text = path.read_text(encoding='utf-8')
        info = xml(path).find('.//Item[@type="CWeaponInfo"]')
        if info is None:
            raise ValueError(f'Arme introuvable : {path}')
        if info.findtext('Group') in ('GROUP_SHOTGUN', 'GROUP_SNIPER'):
            continue
        points = info.findall('./AttachPoints/Item')
        clip = next((pt for pt in points if (pt.findtext('AttachBone') or '').lower() in ('wapclip', 'aapclip')), None)
        if clip is None:
            continue
        entries = clip.findall('./Components/Item')
        active = [entry for entry in entries if entry.find('Default') is not None
                  and entry.find('Default').get('value') == 'true']
        if len(active) != 1:
            continue
        original = components.get((active[0].findtext('Name') or '').lower())
        if original is None or original.find('ClipSize') is None:
            continue
        if int(original.find('ClipSize').get('value', '0')) >= 60:
            continue
        identifier = 'GF_' + weapon.name.removeprefix('WEAPON_') + '_CLIP_60'
        if any((entry.findtext('Name') or '').lower() == identifier.lower() for entry in entries):
            continue
        match = re.search(r'(<Item>\s*<AttachBone>\s*(?:WAPClip|AAPClip)\s*</AttachBone>\s*'
                          r'<Components>)(.*?)(</Components>\s*</Item>)', text, re.I | re.S)
        if not match:
            raise ValueError(f'Point de chargeur introuvable : {path}')
        added = f'\n                <Item><Name>{identifier}</Name><Default value="false" /></Item>\n              '
        updated = text[:match.start(3)].rstrip() + added + text[match.start(3):]
        clone = copy.deepcopy(original)
        clone.find('Name').text = identifier
        clone.find('ClipSize').set('value', '60')
        root = ET.Element('CWeaponComponentInfoBlob')
        ET.SubElement(root, 'Infos').append(clone)
        ET.indent(root, space='  ')
        component_text = '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding='unicode') + '\n'
        destination = weapon / 'components/GF_CLIP60/weaponcomponents.meta'
        if destination.exists():
            raise ValueError(f'Fichier existant à préserver : {destination}')
        relative = f'data/{weapon.name}/components/GF_CLIP60/weaponcomponents.meta'
        planned.append((path, updated, destination, component_text, relative))

    print(f'{len(planned)} chargeur(s) de 60 à ajouter')
    if args.essai:
        for path, *_ in planned:
            print(path.parent.name)
        return 0
    end = manifest.index('}', manifest.index('files {'))
    additions = ''.join(f"    '{item[4]}',\n" for item in planned if f"'{item[4]}'" not in manifest)
    for path, text, destination, component_text, _ in planned:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(component_text, encoding='utf-8', newline='\n')
        path.write_text(text, encoding='utf-8', newline='\n')
    manifest_path.write_text(manifest[:end] + additions + manifest[end:], encoding='utf-8', newline='\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
