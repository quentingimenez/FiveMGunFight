-- Protocole pur de la passerelle de test NUI : aucune API FiveM ici.
-- Les deux côtés (serveur et client) partagent cette définition pour que
-- chaque rapport reste une seule ligne de journal, sans guillemet ni saut
-- de ligne injectés par une page ou un argument de commande.
GfTestbridge = {}

-- Pages NUI pilôtables par la passerelle.
GfTestbridge.PAGES = { 'gf_admin', 'gf_maps', 'gf_vehicles', 'gf_menu' }

-- Commande d'ouverture possédée par chaque ressource.
GfTestbridge.COMMANDES = {
    gf_admin = 'admin',
    gf_maps = 'editor',
    gf_vehicles = 'customveh',
    gf_menu = 'armes',
}

-- Vrai si la page fait partie de la liste blanche.
function GfTestbridge.estPage(page)
    for _, nom in ipairs(GfTestbridge.PAGES) do
        if page == nom then return true end
    end
    return false
end

-- Commande associée à une page, ou nil si la page est inconnue.
function GfTestbridge.commande(page)
    return GfTestbridge.COMMANDES[page]
end

-- Le sommet reste un identifiant simple. Le détail accepte les lettres
-- accentuées (UTF-8) mais refuse guillemet et caractères de contrôle, pour
-- qu'un rapport ne puisse pas falsifier le journal serveur en une seule ligne.
local SOMMET = '^[%w_-]+$'
local INTERDITS = '[%c"]'

-- Construit la ligne canonique d'un rapport, ou renvoie nil si le rapport est
-- invalide. Le détail n'est ajouté que s'il n'est pas vide après validation.
function GfTestbridge.ligne(rapport)
    if type(rapport) ~= 'table' then return nil end
    if not GfTestbridge.estPage(rapport.page) then return nil end

    local actions = { open = true, close = true, status = true }
    if not actions[rapport.action] then return nil end

    local etats = { ouvert = true, ferme = true, echec = true, refus = true }
    if not etats[rapport.etat] then return nil end

    -- Un entier strict : 2.5, "x" ou nil sont refusés.
    local calques = tonumber(rapport.calques)
    if calques == nil or calques ~= math.floor(calques) then return nil end
    if calques < 0 or calques > 32 then return nil end

    if type(rapport.sommet) ~= 'string' then return nil end
    local sommet = rapport.sommet
    if sommet == '' then
        sommet = 'aucun'
    elseif #sommet > 64 or not string.match(sommet, SOMMET) then
        return nil
    end

    local detail = nil
    if rapport.detail ~= nil then
        if type(rapport.detail) ~= 'string' then return nil end
        if rapport.detail ~= '' then
            if #rapport.detail > 120 or string.find(rapport.detail, INTERDITS) then
                return nil
            end
            detail = rapport.detail
        end
    end

    local ligne = ('[gf_testbridge] page=%s action=%s etat=%s calques=%d sommet=%s')
        :format(rapport.page, rapport.action, rapport.etat, calques, sommet)
    if detail then ligne = ligne .. (' detail="%s"'):format(detail) end
    return ligne
end
