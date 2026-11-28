-- Protocole et garde de la passerelle de test NUI : tests T1 purs (aucune
-- API FiveM). Lancer depuis la racine : lua5.4 tests/lua/testbridge_protocol_test.lua
package.path = (os.getenv('GF_ROOT') or '.') .. '/tests/lua/lib/?.lua;' .. package.path
local T = require('assert')
local F = require('fivem')

local base = 'server-data/resources/[gunfight]/gf_testbridge/'

-- ---------------------------------------------------------------------- garde
do
    local sb = F.sandbox({})
    sb:load(base .. 'guard.lua')
    local garde = sb.env.GfTestbridgeGuard
    T.equal(type(garde), 'table', 'GfTestbridgeGuard est une table')
    T.equal(garde.allowed('true'), true, 'allowed("true") est vrai')
    for _, valeur in ipairs({ 'TRUE', 'True', 'true ', ' true', '1', true, 1, '' }) do
        T.equal(garde.allowed(valeur), false, 'allowed refuse ' .. tostring(valeur))
    end
    T.equal(garde.allowed(nil), false, 'allowed refuse nil')
end

-- ------------------------------------------------------------------ protocole
local G
do
    local sb = F.sandbox({})
    sb:load(base .. 'protocol.lua')
    G = sb.env.GfTestbridge
    T.equal(type(G), 'table', 'GfTestbridge est une table')

    T.equal(#G.PAGES, 4, 'quatre pages')
    T.equal(G.estPage('gf_admin'), true, 'estPage gf_admin')
    T.equal(G.estPage('gf_maps'), true, 'estPage gf_maps')
    T.equal(G.estPage('gf_vehicles'), true, 'estPage gf_vehicles')
    T.equal(G.estPage('gf_menu'), true, 'estPage gf_menu')
    T.equal(G.estPage('gf_lobby'), false, 'estPage refuse gf_lobby')
    T.equal(G.estPage(nil), false, 'estPage refuse nil')

    T.equal(G.commande('gf_admin'), 'admin', 'commande admin')
    T.equal(G.commande('gf_maps'), 'editor', 'commande editor')
    T.equal(G.commande('gf_vehicles'), 'customveh', 'commande customveh')
    T.equal(G.commande('gf_menu'), 'armes', 'commande armes')
    T.equal(G.commande('gf_inconnue'), nil, 'commande inconnue')
end

local function rapport(champs)
    local r = { page = 'gf_admin', action = 'status', etat = 'ouvert', calques = 1, sommet = 'gf_admin' }
    for cle, valeur in pairs(champs or {}) do r[cle] = valeur end
    return r
end

local CANONIQUE = '[gf_testbridge] page=gf_admin action=status etat=ouvert calques=1 sommet=gf_admin'
T.equal(G.ligne(rapport()), CANONIQUE, 'ligne canonique exacte')

-- Lignes valides pour les trois actions et les quatre états.
for _, action in ipairs({ 'open', 'close', 'status' }) do
    local ligne = G.ligne(rapport({ action = action }))
    T.check(type(ligne) == 'string', 'ligne valide pour action ' .. action)
    T.check(ligne:find('action=' .. action, 1, true) ~= nil, 'action dans la ligne ' .. action)
end
for _, etat in ipairs({ 'ouvert', 'ferme', 'echec', 'refus' }) do
    local ligne = G.ligne(rapport({ etat = etat }))
    T.check(type(ligne) == 'string', 'ligne valide pour etat ' .. etat)
    T.check(ligne:find('etat=' .. etat, 1, true) ~= nil, 'etat dans la ligne ' .. etat)
end

-- Détail ajouté seulement s'il est non vide.
T.equal(
    G.ligne(rapport({ detail = 'un calque est déjà ouvert' })),
    CANONIQUE .. ' detail="un calque est déjà ouvert"',
    'détail ajouté entre guillemets'
)
T.equal(G.ligne(rapport({ detail = '' })), CANONIQUE, 'détail vide omis')

-- Rejets : rapport, page, action, état et calques.
T.equal(G.ligne(nil), nil, 'rapport nil refusé')
T.equal(G.ligne('texte'), nil, 'rapport non-table refusé')
T.equal(G.ligne(rapport({ page = 'gf_lobby' })), nil, 'page inconnue refusée')
T.equal(G.ligne(rapport({ action = 'toggle' })), nil, 'action inconnue refusée')
T.equal(G.ligne(rapport({ etat = 'unknown' })), nil, 'etat inconnu refusé')
for _, calques in ipairs({ -1, 33, 2.5, 'x' }) do
    T.equal(G.ligne(rapport({ calques = calques })), nil, 'calques invalide ' .. tostring(calques))
end
local sansCalques = rapport()
sansCalques.calques = nil
T.equal(G.ligne(sansCalques), nil, 'calques nil refusé')
T.equal(G.ligne(rapport({ calques = 0 })):find('calques=0', 1, true) ~= nil, true, 'calques 0 accepté')
T.equal(G.ligne(rapport({ calques = 32 })):find('calques=32', 1, true) ~= nil, true, 'calques 32 accepté')
T.equal(G.ligne(rapport({ calques = '3' })):find('calques=3', 1, true) ~= nil, true, 'calques "3" accepté')

-- Assainissement : ni guillemet ni saut de ligne dans la ligne finale.
T.equal(
    G.ligne(rapport({ sommet = '' })),
    '[gf_testbridge] page=gf_admin action=status etat=ouvert calques=1 sommet=aucun',
    'sommet vide devient aucun'
)
local injection = G.ligne(rapport({ sommet = 'evil" \n foo', detail = 'x" \n y' }))
T.equal(injection, nil, 'injection de guillemets et de retour ligne refusée')
local detailLong = string.rep('a', 121)
T.equal(G.ligne(rapport({ detail = detailLong })), nil, 'détail trop long refusé')
local sommetLong = string.rep('a', 65)
T.equal(G.ligne(rapport({ sommet = sommetLong })), nil, 'sommet trop long refusé')
T.equal(G.ligne(rapport({ sommet = 'gf_admin' })), CANONIQUE, 'sommet alphanumérique accepté')

T.finish('testbridge_protocol_test')
