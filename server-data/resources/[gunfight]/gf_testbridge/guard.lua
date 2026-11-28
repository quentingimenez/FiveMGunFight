-- Passerelle de test NUI : garde d'activation, développement uniquement.
-- La convar n'est acceptée que sous la forme exacte de la chaîne "true".
GfTestbridgeGuard = {}

function GfTestbridgeGuard.allowed(valeur)
    return valeur == 'true'
end
