-- =============================================================================
--  gf_killcam - RECORD (client)
--  Échantillonne la position, le cap et la caméra du joueur local, puis envoie
--  les échantillons au serveur par lots. Le client ne décide de rien : c'est le
--  serveur qui horodate les échantillons et construit le clip de killcam.
-- =============================================================================

local lot = {}
local prochainEchantillon = 0
local prochainEnvoi = 0
local actif = false

--- Vrai si l'enregistrement est autorisé : ressource active, mode reconnu et
--- joueur en vie. Le ped doit exister (0 signifie « pas encore créé »).
--- @return boolean
local function peutEnregistrer()
    if not Config.Enabled then return false end

    local mode = LocalPlayer.state.gf_mode
    if type(mode) ~= 'string' or Config.Modes[mode] ~= true then return false end

    local ped = PlayerPedId()
    if ped == 0 or IsEntityDead(ped) then return false end

    return true
end

--- Remet le collecteur à zéro : vide le lot et décale les échéances pour ne
--- jamais envoyer de données d'un autre mode ou d'un joueur mort.
local function reinitialiser(maintenant)
    lot = {}
    prochainEchantillon = maintenant + Config.SampleMs
    prochainEnvoi = maintenant + Config.BatchMs
end

--- Construit un échantillon à partir de l'état actuel du joueur local.
--- `t` vaut 0 : le serveur se charge de l'horodatage.
--- @return table
local function faireEchantillon()
    local ped = PlayerPedId()
    local position = GetEntityCoords(ped)
    local camera = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)

    local vehicule = GetVehiclePedIsIn(ped, false)
    local modeleVehicule = 0
    if vehicule ~= 0 then modeleVehicule = GetEntityModel(vehicule) end

    return {
        t = 0,
        x = position.x, y = position.y, z = position.z,
        h = GetEntityHeading(ped),
        cx = camera.x, cy = camera.y, cz = camera.z,
        rx = rotation.x, ry = rotation.y, rz = rotation.z,
        w = GetSelectedPedWeapon(ped),
        a = IsPlayerFreeAiming(PlayerId()) == true,
        s = IsPedShooting(ped) == true,
        v = modeleVehicule,
    }
end

CreateThread(function()
    while true do
        Wait(0)

        local maintenant = GetGameTimer()
        local autorise = peutEnregistrer()

        if not autorise then
            -- On ne garde rien d'une période invalide (mort, changement de mode).
            if actif then
                reinitialiser(maintenant)
                actif = false
            end
        else
            if not actif then
                reinitialiser(maintenant)
                actif = true
            end

            if maintenant >= prochainEchantillon then
                -- Un lot ne dépasse jamais 15 échantillons : on envoie immédiatement
                -- s'il est plein, même si l'échéance de lot n'est pas encore atteinte.
                if #lot >= 15 then
                    TriggerServerEvent('gf_killcam:samples', lot)
                    lot = {}
                    prochainEnvoi = maintenant + Config.BatchMs
                end

                lot[#lot + 1] = faireEchantillon()
                prochainEchantillon = maintenant + Config.SampleMs
            end

            if maintenant >= prochainEnvoi then
                if #lot > 0 then
                    TriggerServerEvent('gf_killcam:samples', lot)
                    lot = {}
                end
                prochainEnvoi = maintenant + Config.BatchMs
            end
        end
    end
end)
