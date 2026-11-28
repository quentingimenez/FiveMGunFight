-- gf_weapons expose ses données d'armes : l'export GetWeaponMeta lit le
-- weapons.meta de la ressource courante et refuse tout nom non conforme.
package.path = (os.getenv('GF_ROOT') or '.') .. '/tests/lua/lib/?.lua;' .. package.path
local T = require('assert')
local F = require('fivem')

local meta = '<WeaponMeta><AttachPoints><Item><AttachBone>wapclip</AttachBone>' ..
    '<Components><Item><Name>COMPONENT_TEST_CLIP</Name></Item></Components></Item></AttachPoints></WeaponMeta>'
local files = { ['data/WEAPON_TEST/weapons.meta'] = meta }
local reads, lastRead = 0, nil

local sb = F.sandbox({
    resource = 'gf_weapons',
    files = files,
    overrides = {
        LoadResourceFile = function(resource, path)
            reads = reads + 1
            lastRead = { resource = resource, path = path }
            return files[path]
        end,
    },
})

sb:load('server-data/resources/[gunfight]/gf_weapons/server.lua')
local getWeaponMeta = sb.provided.GetWeaponMeta
T.check(type(getWeaponMeta) == 'function', 'export GetWeaponMeta enregistré')

-- Appel FiveM côté serveur : un seul argument, pas de forme colon.
T.equal(getWeaponMeta('WEAPON_TEST'), meta, 'contenu exact du weapons.meta')
T.equal(lastRead.resource, 'gf_weapons', 'lecture dans la ressource gf_weapons')
T.equal(lastRead.path, 'data/WEAPON_TEST/weapons.meta', 'chemin du fichier demandé')

local before = reads
T.equal(getWeaponMeta('WEAPON_ABSENT'), nil, 'arme valide mais fichier absent : nil')
T.equal(reads, before + 1, 'une lecture tentée pour un nom valide absent')

before = reads
for _, invalid in ipairs({ 'WEAPON_../x', 'weapon_test', '' }) do
    T.equal(getWeaponMeta(invalid), nil, 'nom invalide refusé : ' .. invalid)
end
T.equal(getWeaponMeta(nil), nil, 'nil refusé')
T.equal(getWeaponMeta(42), nil, 'nombre refusé')
T.equal(reads, before, 'aucune lecture pour un nom invalide')

T.finish('Métadonnées d\'armes')
