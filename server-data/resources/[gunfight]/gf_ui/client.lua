-- =============================================================================
--  gf_ui - CLIENT
--  Reçoit les événements du serveur et les transmet à la page HTML (NUI).
--
--  Événements utilisables par les autres ressources (TriggerClientEvent) :
--    gf_ui:hud        (data | nil)   { title, subtitle, timer, badge{text,color},
--                                      left{label,value,sub,color}, right{...} }
--    gf_ui:announce   (data)         { title, subtitle, duration }
--    gf_ui:killfeed   (entry)        { killer, killerTeam, victim, victimTeam, weapon }
--    gf_ui:scoreboard (data | nil)   { title, columns{}, rows{ {cells{}, color} } }
-- =============================================================================

local WEAPON_LABELS = {
    WEAPON_PISTOL = 'Pistolet', WEAPON_PISTOL50 = 'Pistolet .50', WEAPON_COMBATPISTOL = 'Pistolet de combat',
    WEAPON_APPISTOL = 'Pistolet AP', WEAPON_HEAVYPISTOL = 'Pistolet lourd', WEAPON_REVOLVER = 'Revolver',
    WEAPON_MICROSMG = 'Micro SMG', WEAPON_SMG = 'SMG', WEAPON_COMBATPDW = 'PDW',
    WEAPON_ASSAULTRIFLE = 'Fusil d\'assaut', WEAPON_CARBINERIFLE = 'Carabine', WEAPON_SPECIALCARBINE = 'Carabine spéciale',
    WEAPON_BULLPUPRIFLE = 'Fusil bullpup', WEAPON_ADVANCEDRIFLE = 'Fusil avancé', WEAPON_COMPACTRIFLE = 'Fusil compact',
    WEAPON_PUMPSHOTGUN = 'Fusil à pompe', WEAPON_SAWNOFFSHOTGUN = 'Canon scié', WEAPON_ASSAULTSHOTGUN = 'Fusil à pompe d\'assaut',
    WEAPON_SNIPERRIFLE = 'Sniper', WEAPON_HEAVYSNIPER = 'Sniper lourd', WEAPON_MARKSMANRIFLE = 'Fusil de précision',
    WEAPON_MG = 'Mitrailleuse', WEAPON_COMBATMG = 'Mitrailleuse de combat',
    WEAPON_GRENADE = 'Grenade', WEAPON_KNIFE = 'Couteau', WEAPON_UNARMED = 'Poings',
}

local labels = {}
for name, label in pairs(WEAPON_LABELS) do
    local h = joaat(name)
    labels[h] = label
    labels[h & 0xFFFFFFFF] = label
    if h > 0x7FFFFFFF then labels[h - 0x100000000] = label end
end

RegisterNetEvent('gf_ui:hud', function(d)
    SendNUIMessage({ type = 'hud', data = d })
end)

RegisterNetEvent('gf_ui:announce', function(d)
    SendNUIMessage({ type = 'announce', data = d })
end)

RegisterNetEvent('gf_ui:killfeed', function(e)
    local me = GetPlayerName(PlayerId())
    e.weaponLabel = e.weapon and labels[e.weapon] or nil
    e.involvesMe = (e.killer == me) or (e.victim == me)
    SendNUIMessage({ type = 'killfeed', data = e })
end)

RegisterNetEvent('gf_ui:scoreboard', function(d)
    SendNUIMessage({ type = 'scoreboard', data = d })
end)

-- Classement : maintenir la touche (Z par défaut, modifiable dans
-- Paramètres > Raccourcis clavier > FiveM)
RegisterCommand('+gf_scoreboard', function()
    SendNUIMessage({ type = 'scoreboard_visible', visible = true })
end, false)
RegisterCommand('-gf_scoreboard', function()
    SendNUIMessage({ type = 'scoreboard_visible', visible = false })
end, false)
RegisterKeyMapping('+gf_scoreboard', 'Gunfight : afficher le classement', 'keyboard', 'Z')
