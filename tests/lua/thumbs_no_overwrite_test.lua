-- Une capture automatique ne doit pas écraser une photo présente sur le serveur.
package.path = (os.getenv('GF_ROOT') or '.') .. '/tests/lua/lib/?.lua;' .. package.path
local T = require('assert')
local F = require('fivem')

local writes = 0
local files = { ['thumbs/weapons/WEAPON_TEST.png'] = 'photo' }

local sb = F.sandbox({
    resource = 'gf_thumbs',
    globals = {
        Config = { Kinds = { weapons = {} }, Folder = 'thumbs', MaxImageBytes = 1024 },
        Base64 = { decode = function() return '\137PNG\r\n\26\nimage' end },
        RegisterCommand = function() end,
    },
    exports = { gf_core = { IsAdmin = function() return true end } },
    files = files,
    overrides = {
        SaveResourceFile = function(resource, path, content, length)
            writes = writes + 1
            files[path] = content
            return true
        end,
    },
})

local function updatedCount()
    local count = 0
    for _, message in ipairs(sb.sent) do
        if message.nom == 'gf_thumbs:updated' then count = count + 1 end
    end
    return count
end

sb:load('server-data/resources/[gunfight]/gf_core/rate_limit.lua')
sb:load('server-data/resources/[gunfight]/gf_thumbs/server.lua')

-- Photo existante : une capture automatique ne doit pas l'écraser.
sb:emit('gf_thumbs:save', 'weapons', 'WEAPON_TEST', 'data:image/png;base64,abc', true)
T.check(writes == 0 and updatedCount() == 1, 'photo existante conservée')

-- Photo absente : la capture automatique doit être enregistrée.
files['thumbs/weapons/WEAPON_TEST.png'] = nil
sb:emit('gf_thumbs:save', 'weapons', 'WEAPON_TEST', 'data:image/png;base64,abc', true)
T.equal(writes, 1, 'nouvelle photo automatique enregistrée')

-- Photo existante : une capture manuelle doit pouvoir la remplacer.
files['thumbs/weapons/WEAPON_TEST.png'] = 'photo'
sb:emit('gf_thumbs:save', 'weapons', 'WEAPON_TEST', 'data:image/png;base64,abc', false)
T.equal(writes, 2, 'photo manuelle remplaçable')

T.finish('Photos')
