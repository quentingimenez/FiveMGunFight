-- Script serveur de gf_weapons : propriétaire exclusif des fichiers
-- data/<ARME>/ de cette ressource. Il expose aux autres ressources (notamment
-- gf_inventory) la lecture des données d'armes, sans que celles-ci aient à
-- connaître le chemin des fichiers ni la ressource qui les détient.

exports('GetWeaponMeta', function(name)
    if type(name) ~= 'string' or not name:match('^WEAPON_[%w_]+$') then return nil end
    return LoadResourceFile(GetCurrentResourceName(), ('data/%s/weapons.meta'):format(name))
end)
