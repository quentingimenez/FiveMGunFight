-- La pile de calques NUI est possédée par gf_ui : module pur + exports FiveM.
package.path = (os.getenv('GF_ROOT') or '.') .. '/tests/lua/lib/?.lua;' .. package.path
local T = require('assert')
local F = require('fivem')

-- ------------------------------------------------------------------ module pur
do
    local sb = F.sandbox({})
    sb:load('server-data/resources/[gunfight]/gf_ui/layers.lua')
    local Layers = sb.env.Layers

    T.equal(type(Layers), 'table', 'Layers est une table')
    T.equal(type(Layers.new), 'function', 'Layers.new existe')

    local stack = Layers.new()

    -- Push, doublon et sommet.
    T.equal(stack:push('gf_admin'), true, 'push gf_admin change la pile')
    T.equal(stack:count(), 1, 'count après un push')
    T.equal(stack:top(), 'gf_admin', 'top après un push')
    T.equal(stack:has('gf_admin'), true, 'has après un push')
    T.equal(stack:push('gf_admin'), false, 'doublon ne change pas la pile')
    T.equal(stack:count(), 1, 'count inchangé après doublon')
    T.equal(stack:top(), 'gf_admin', 'top inchangé après doublon')

    -- Pop absent.
    T.equal(stack:pop('gf_absent'), false, 'pop absent ne change pas la pile')

    -- Pop au milieu avec trois éléments.
    stack:push('gf_menu')
    stack:push('gf_maps')
    T.equal(stack:top(), 'gf_maps', 'top avec trois calques')
    T.equal(stack:pop('gf_menu'), true, 'pop au milieu change la pile')
    T.equal(stack:count(), 2, 'count après pop au milieu')
    T.equal(stack:top(), 'gf_maps', 'top correct après pop au milieu')
    T.equal(stack:has('gf_menu'), false, 'calque retiré absent')
    T.equal(stack:has('gf_admin'), true, 'calque en dessous conservé')
    T.equal(stack:has('gf_maps'), true, 'calque au-dessus conservé')

    -- Pile vide.
    stack:pop('gf_admin')
    stack:pop('gf_maps')
    T.equal(stack:count(), 0, 'count d\'une pile vide')
    T.equal(stack:top(), nil, 'top d une pile vide est nil')

    -- Noms invalides : nil, chaîne vide, nombre, booléen.
    T.equal(stack:push(nil), false, 'push(nil) refusé')
    T.equal(stack:push(''), false, 'push("") refusé')
    T.equal(stack:push(123), false, 'push(123) refusé')
    T.equal(stack:push(false), false, 'push(false) refusé')
    T.equal(stack:pop(nil), false, 'pop(nil) refusé')
    T.equal(stack:pop(''), false, 'pop("") refusé')
    T.equal(stack:pop(123), false, 'pop(123) refusé')
    T.equal(stack:pop(false), false, 'pop(false) refusé')
    T.equal(stack:has(nil), false, 'has(nil) faux')
    T.equal(stack:has(''), false, 'has("") faux')
    T.equal(stack:has(123), false, 'has(123) faux')
    T.equal(stack:has(false), false, 'has(false) faux')
    T.equal(stack:count(), 0, 'pile toujours vide après opérations invalides')
end

-- ------------------------------------------------------------ bac à sable FiveM
do
    local sb = F.sandbox({
        resource = 'gf_ui',
        globals = {
            joaat = function() return 1 end,
            RegisterCommand = function() end,
            RegisterKeyMapping = function() end,
            SetNuiFocusKeepInput = function() end,
        },
    })

    local changes = {}
    sb.env.AddEventHandler('gf_ui:layersChanged', function(count, top)
        changes[#changes + 1] = { count = count, top = top }
    end)

    sb:load('server-data/resources/[gunfight]/gf_ui/layers.lua')
    sb:load('server-data/resources/[gunfight]/gf_ui/client.lua')

    T.equal(type(sb.provided.PushLayer), 'function', 'export PushLayer fourni')
    T.equal(type(sb.provided.PopLayer), 'function', 'export PopLayer fourni')

    local function lastChange()
        return changes[#changes]
    end

    T.equal(sb.provided.PushLayer('gf_admin'), true, 'push gf_admin via export')
    T.equal(#changes, 1, 'un événement après le push')
    T.deepEqual(lastChange(), { count = 1, top = 'gf_admin' }, 'changement (1, gf_admin)')

    T.equal(sb.provided.PushLayer('gf_admin'), false, 'doublon via export')
    T.equal(#changes, 1, 'aucun événement pour un doublon')

    T.equal(sb.provided.PushLayer('gf_menu'), true, 'push gf_menu')
    T.equal(#changes, 2, 'deux événements')
    T.deepEqual(lastChange(), { count = 2, top = 'gf_menu' }, 'changement (2, gf_menu)')

    T.equal(sb.provided.PopLayer('gf_admin'), true, 'pop au milieu via export')
    T.equal(#changes, 3, 'trois événements')
    T.deepEqual(lastChange(), { count = 1, top = 'gf_menu' }, 'changement (1, gf_menu)')

    T.equal(sb.provided.PopLayer('gf_admin'), false, 'second pop de gf_admin')
    T.equal(sb.provided.PopLayer('gf_absent'), false, 'pop absent')
    T.equal(#changes, 3, 'aucun événement pour les pops sans effet')

    T.equal(sb.provided.PushLayer('gf_maps'), true, 'push gf_maps')
    T.equal(#changes, 4, 'quatre événements')
    T.deepEqual(lastChange(), { count = 2, top = 'gf_maps' }, 'changement (2, gf_maps)')

    sb:emit('onClientResourceStop', 'gf_maps')
    T.equal(#changes, 5, 'événement sur arrêt de gf_maps')
    T.deepEqual(lastChange(), { count = 1, top = 'gf_menu' }, 'changement (1, gf_menu)')

    sb:emit('onClientResourceStop', 'gf_maps')
    T.equal(#changes, 5, 'aucun événement si la ressource n a plus de calque')

    sb:emit('onClientResourceStop', 'gf_absent')
    T.equal(#changes, 5, 'aucun événement pour une ressource sans calque')

    sb:emit('onClientResourceStop', 'gf_menu')
    T.equal(#changes, 6, 'événement sur arrêt de gf_menu')
    T.deepEqual(lastChange(), { count = 0, top = nil }, 'changement (0, nil)')

    T.equal(sb.provided.PushLayer(nil), false, 'push(nil) refusé via export')
    T.equal(sb.provided.PushLayer(''), false, 'push("") refusé via export')
    T.equal(sb.provided.PopLayer(nil), false, 'pop(nil) refusé via export')
    T.equal(#changes, 6, 'aucun événement pour les exports invalides')
end

T.finish('Calques NUI')
