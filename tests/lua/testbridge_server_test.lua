-- Serveur de la passerelle de test NUI : garde d'activation et journal.
-- Le harnais fait lever F.STOP à Wait : on vérifie le code exécuté avant le
-- fil d'arrêt, sans compter sur l'exécution différée du CreateThread.
package.path = (os.getenv('GF_ROOT') or '.') .. '/tests/lua/lib/?.lua;' .. package.path
local T = require('assert')
local F = require('fivem')

local base = 'server-data/resources/[gunfight]/gf_testbridge/'

local function chargerServeur(convar, globals)
    local printed = {}
    local commandes = {}
    local evenements = {}
    local sb = F.sandbox({
        resource = 'gf_testbridge',
        globals = {
            print = function(...)
                local parties = {}
                for i = 1, select('#', ...) do parties[#parties + 1] = tostring((select(i, ...))) end
                printed[#printed + 1] = table.concat(parties, ' ')
            end,
            GetConvar = function() return convar end,
            RegisterCommand = function(nom, fn, restreint)
                commandes[nom] = { fn = fn, restreint = restreint }
            end,
            GetPlayers = function() return {} end,
            StopResource = function() end,
        },
    })
    for cle, valeur in pairs(globals or {}) do sb.env[cle] = valeur end
    sb:load(base .. 'guard.lua')
    sb:load(base .. 'protocol.lua')
    sb:load(base .. 'server.lua')
    return sb, printed, commandes, evenements
end

-- Convar absente ou fausse : message de désactivation, aucune commande.
for _, convar in ipairs({ '', 'false', 'TRUE' }) do
    local _, printed, commandes = chargerServeur(convar)
    T.equal(printed[1], '[gf_testbridge] désactivé : gf_dev_testbridge doit valoir "true"',
        'désactivation pour convar ' .. convar)
    T.equal(commandes.gf_bridge, nil, 'aucune commande enregistrée pour convar ' .. convar)
end

-- Convar exacte : prêt, commande restreinte, rapport valide imprimé.
do
    local sb, printed, commandes = chargerServeur('true')
    T.equal(printed[1], '[gf_testbridge] prêt (développement)', 'message de prêt')
    T.check(commandes.gf_bridge ~= nil, 'commande gf_bridge enregistrée')
    T.equal(commandes.gf_bridge.restreint, true, 'commande restreinte')

    local evenements = sb.events
    T.check(evenements['gf_testbridge:rapport'] ~= nil, 'écoute du rapport')
    T.check(evenements['gf_testbridge:clientPret'] ~= nil, 'écoute du client prêt')

    evenements['gf_testbridge:rapport'][1]({
        page = 'gf_admin', action = 'status', etat = 'ferme', calques = 0, sommet = 'aucun',
    })
    T.equal(printed[#printed],
        '[gf_testbridge] page=gf_admin action=status etat=ferme calques=0 sommet=aucun',
        'rapport valide imprimé')
    local avant = #printed
    evenements['gf_testbridge:rapport'][1]({ page = 'gf_lobby' })
    T.equal(#printed, avant, 'rapport invalide ignoré')
end

-- whoami : identifiants du joueur unique, pour poser un principal admin local.
do
    local _, printed, commandes = chargerServeur('true', {
        GetPlayers = function() return { '7' } end,
        GetPlayerIdentifiers = function()
            return { 'license:abc123', 'ip:10.0.0.1', 'fivem:42' }
        end,
    })
    commandes.gf_bridge.fn(0, { 'whoami' })
    T.equal(printed[#printed], '[gf_testbridge] identifiants : license:abc123, fivem:42',
        'identifiants du joueur unique')
end

T.finish('testbridge_server_test')
