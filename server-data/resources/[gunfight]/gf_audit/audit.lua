-- =============================================================================
--  Module serveur pur d'audit de la vie et de l'armure.
--  Aucune sanction : ce module observe et signale, sans modifier le jeu.
--  Aucune native, aucune horloge et aucun accès à Config : tout est paramétré.
-- =============================================================================

AuditVie = {}

-- Nombre fini : refuse nil, les chaînes, NaN et les infinis.
local function estNombreFini(valeur)
    return type(valeur) == 'number'
        and valeur == valeur
        and valeur ~= math.huge
        and valeur ~= -math.huge
end

-- État vierge d'un joueur, créé à la demande.
local function etatNeuf(maintenant)
    return {
        vie = nil,
        armure = nil,
        derniere = maintenant,
        graceJusque = 0,
        permis = { vie = 0, armure = 0, jusque = 0 },
        mortelle = nil,
    }
end

-- Récupère l'état du joueur, en le créant s'il n'existe pas encore.
local function garantir(etat, src, maintenant)
    local joueur = etat[src]
    if not joueur then
        joueur = etatNeuf(maintenant)
        etat[src] = joueur
    end
    return joueur
end

-- Nouveau conteneur d'audit (aucun joueur suivi au départ).
function AuditVie.nouveau()
    return {}
end

-- Apparition : on repart d'une référence inconnue et d'une nouvelle grâce.
function AuditVie.apparition(etat, src, maintenant, regles)
    local joueur = etatNeuf(maintenant)
    joueur.graceJusque = maintenant + regles.graceMs
    etat[src] = joueur
end

-- Soin accordé par le serveur : la prochaine mesure devient la référence.
function AuditVie.soinAccorde(etat, src, maintenant, regles)
    local joueur = garantir(etat, src, maintenant)
    joueur.graceJusque = maintenant + regles.graceMs
    joueur.vie = nil
    joueur.armure = nil
end

-- Objet de soin utilisé : autorise une hausse sur la statistique visée.
function AuditVie.objetUtilise(etat, src, stat, quantite, dureeMs, maintenant, regles)
    local cible = nil
    if stat == 'health' then
        cible = 'vie'
    elseif stat == 'armour' then
        cible = 'armure'
    end
    if not cible then return end
    if not estNombreFini(quantite) or not estNombreFini(dureeMs) then return end

    local joueur = garantir(etat, src, maintenant)
    joueur.permis[cible] = joueur.permis[cible] + quantite
    joueur.permis.jusque = math.max(joueur.permis.jusque or 0, maintenant + dureeMs + regles.graceMs)
end

-- Touche potentiellement mortelle acceptée : on note l'instant le plus ancien.
function AuditVie.touche(etat, src, willKill, acceptee, maintenant)
    if not (willKill and acceptee) then return end
    local joueur = garantir(etat, src, maintenant)
    if not joueur.mortelle then joueur.mortelle = { instant = maintenant } end
end

-- Mort confirmée : la référence est perdue jusqu'à la prochaine apparition.
function AuditVie.mort(etat, src)
    local joueur = etat[src]
    if not joueur then return end
    joueur.mortelle = nil
    joueur.vie = nil
    joueur.armure = nil
end

-- Oubli complet d'un joueur.
function AuditVie.oublier(etat, src)
    etat[src] = nil
end

-- Mesure des valeurs rapportées : retourne la liste des anomalies observées.
function AuditVie.mesure(etat, src, vie, armure, mort, maintenant, regles)
    local anomalies = {}
    -- Validation stricte avant toute lecture ou écriture de l'état.
    if type(etat) ~= 'table'
        or not estNombreFini(src)
        or not estNombreFini(vie)
        or not estNombreFini(armure)
        or not estNombreFini(maintenant) then
        return anomalies
    end

    if mort == true then
        AuditVie.mort(etat, src)
        return anomalies
    end

    local joueur = garantir(etat, src, maintenant)

    -- Une touche mortelle non suivie d'une mort devient une anomalie unique.
    if joueur.mortelle and maintenant - joueur.mortelle.instant > regles.fenetreMortMs then
        anomalies[#anomalies + 1] = {
            type = 'touche-mortelle-sans-mort',
            depuisMs = maintenant - joueur.mortelle.instant,
            vie = vie,
        }
        joueur.mortelle = nil
    end

    -- Les permissions périmées ne sont plus valables.
    if joueur.permis.jusque < maintenant then
        joueur.permis.vie = 0
        joueur.permis.armure = 0
    end

    -- Période de grâce ou référence inconnue : la mesure devient la référence.
    if maintenant < joueur.graceJusque or joueur.vie == nil or joueur.armure == nil then
        joueur.vie = vie
        joueur.armure = armure
        joueur.derniere = maintenant
        return anomalies
    end

    -- Vie puis armure : hausse autorisée par le permis et la tolérance.
    local mesures = { { stat = 'vie', valeur = vie, reference = joueur.vie },
                      { stat = 'armure', valeur = armure, reference = joueur.armure } }
    for i = 1, #mesures do
        local entree = mesures[i]
        local hausse = entree.valeur - entree.reference
        local permis = joueur.permis[entree.stat] or 0
        if hausse > permis + regles.tolerance then
            anomalies[#anomalies + 1] = {
                type = 'soin-sans-objet',
                stat = entree.stat,
                avant = entree.reference,
                apres = entree.valeur,
                permis = permis,
            }
        end
        if hausse > 0 then
            joueur.permis[entree.stat] = permis - math.min(hausse, permis)
        end
        joueur[entree.stat] = entree.valeur
    end

    joueur.derniere = maintenant
    return anomalies
end
