#!/usr/bin/env python3
"""Vérifie les chargeurs ajoutés sans réduire les capacités d'origine."""
from __future__ import annotations

import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / 'server-data/resources/[gunfight]/gf_weapons/data'


def read_meta(path: Path) -> ET.Element:
    return ET.fromstring(path.read_text(encoding='utf-8').replace('UTF - 8', 'UTF-8'))


class ChargeursAjoutes(unittest.TestCase):
    def test_armes_gta_composants_de_60_et_modeles_origine(self) -> None:
        base = DATA / 'GF_VANILLA_60'
        weapons = read_meta(base / 'vanilla60.patch.meta')
        components = read_meta(base / 'weaponcomponents.meta')
        models = {
            'ASSAULTRIFLE': 'w_ar_assaultrifle_mag1',
            'BULLPUPRIFLE': 'w_ar_bullpuprifle_mag1',
            'CARBINERIFLE': 'w_ar_carbinerifle_mag1',
            'COMBATPDW': 'w_sb_pdw_mag1',
            'HEAVYPISTOL': 'w_pi_heavypistol_mag1',
            'PISTOL': 'w_pi_pistol_mag1',
            'PISTOL50': 'w_pi_pistol50_mag1',
            'SMG': 'w_sb_smg_mag1',
            'SPECIALCARBINE': 'w_ar_specialcarbine_mag1',
        }
        for name, model in models.items():
            with self.subTest(weapon=name):
                item = next(w for w in weapons.findall('.//Item[@type="CWeaponInfo"]')
                            if w.findtext('Name') == 'WEAPON_' + name)
                component_name = 'GF_' + name + '_CLIP_60'
                names = [node.text for node in item.findall('./AttachPoints/Item/Components/Item/Name')]
                self.assertIn(component_name, names)
                component = next(c for c in components.findall('.//Item[@type="CWeaponComponentClipInfo"]')
                                 if c.findtext('Name') == component_name)
                self.assertEqual('60', component.find('ClipSize').get('value'))
                self.assertEqual(model, (component.findtext('Model') or '').lower())

    def test_chargeurs_60_reutilisent_le_modele_sans_modifier_l_original(self) -> None:
        components: dict[str, ET.Element] = {}
        for path in DATA.rglob('weaponcomponents.meta'):
            for item in read_meta(path).iter('Item'):
                if item.get('type') == 'CWeaponComponentClipInfo' and item.findtext('Name'):
                    components[item.findtext('Name', '').lower()] = item
        checked = 0
        for weapon in DATA.glob('WEAPON_*'):
            path = weapon / 'weapons.meta'
            if not path.exists():
                continue
            info = read_meta(path).find('.//Item[@type="CWeaponInfo"]')
            if info is None:
                continue
            for point in info.findall('./AttachPoints/Item'):
                if (point.findtext('AttachBone') or '').lower() not in ('wapclip', 'aapclip'):
                    continue
                entries = point.findall('./Components/Item')
                default = next((e for e in entries if e.find('Default') is not None
                                and e.find('Default').get('value') == 'true'), None)
                if default is None:
                    continue
                original = components.get((default.findtext('Name') or '').lower())
                if original is None or original.find('ClipSize') is None:
                    continue
                generated = [e for e in entries if (e.findtext('Name') or '').startswith('GF_')
                             and (e.findtext('Name') or '').endswith('_CLIP_60')]
                capacity = int(original.find('ClipSize').get('value', '0'))
                if info.findtext('Group') in ('GROUP_SHOTGUN', 'GROUP_SNIPER'):
                    self.assertFalse(generated, f'{weapon.name} conserve ses chargeurs d’origine')
                elif capacity >= 60:
                    self.assertFalse(generated, f'{weapon.name} possède déjà {capacity} balles')
                else:
                    self.assertEqual(1, len(generated), weapon.name)
                    extended = components[(generated[0].findtext('Name') or '').lower()]
                    self.assertEqual('60', extended.find('ClipSize').get('value'), weapon.name)
                    self.assertEqual(original.findtext('Model'), extended.findtext('Model'), weapon.name)
                    self.assertEqual('false', generated[0].find('Default').get('value'), weapon.name)
                    checked += 1
        self.assertGreater(checked, 0, 'aucun chargeur généré')


if __name__ == '__main__':
    unittest.main()
