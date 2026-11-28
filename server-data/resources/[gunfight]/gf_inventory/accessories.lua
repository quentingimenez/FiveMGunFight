-- Catalogue fermé côté serveur. Les composants GTA proviennent des références
-- FiveM ; ceux des armes ajoutées sont lus dans leurs fichiers weapons.meta.
WeaponAccessories = {}

local vanilla = {
    WEAPON_SPECIALCARBINE = { clip = { 'COMPONENT_SPECIALCARBINE_CLIP_01', 'COMPONENT_SPECIALCARBINE_CLIP_02', 'COMPONENT_SPECIALCARBINE_CLIP_03' },
        sight = { 'COMPONENT_AT_SCOPE_MEDIUM' },
        grip = { 'COMPONENT_AT_AR_AFGRIP' },
        light = { 'COMPONENT_AT_AR_FLSH' },
        suppressor = { 'COMPONENT_AT_AR_SUPP_02' } },
    WEAPON_APPISTOL = { clip = { 'COMPONENT_APPISTOL_CLIP_01', 'COMPONENT_APPISTOL_CLIP_02' },
        light = { 'COMPONENT_AT_PI_FLSH' },
        suppressor = { 'COMPONENT_AT_PI_SUPP' } },
}

local labels = { clip = 'Chargeur', sight = 'Viseur', grip = 'Poignée', light = 'Lampe', suppressor = 'Silencieux', laser = 'Laser' }
local bones = { wapclip = 'clip', aapclip = 'clip', wapscop = 'sight', wapscop_2 = 'sight',
    wapsupp = 'suppressor', wapgrip = 'grip', wapflsh = 'light', wapflshlasr = 'light', waplaser = 'laser' }
-- Ce composant est facultatif pour GTA mais reste installé initialement en jeu.
local optionalDefaults = {
    WEAPON_QUEENBEE16YELLOW = { suppressor = 'COMPONENT_AT_QUEENBEE16YELLOW_SUPP' },
    WEAPON_RRC3_ACHROMIC = {
        suppressor = 'did_rrc3_achromic_supp',
        sight = 'did_rrc3_achromic_scope2',
        grip = 'did_rrc3_achromic_afgrip',
    },
    WEAPON_WOLFRIFLE = { suppressor = 'wolfrifle_supp' },
}
-- Chargeurs GTA d'origine, sans chargeur de 60 ajouté.
local stockMagazines = { WEAPON_APPISTOL = true }

function WeaponAccessories.catalog(name)
    local result = {}
    local data = vanilla[name]
    if data then
        for kind, components in pairs(data) do
            local options = {}
            local aliases = {}
            for index, component in ipairs(components) do
                if kind == 'clip' and index > 1 and not stockMagazines[name] then
                    aliases[component] = 'GF_' .. name:sub(8) .. '_CLIP_60'
                else
                    options[#options + 1] = component
                end
            end
            if kind == 'clip' then
                local extended = 'GF_' .. name:sub(8) .. '_CLIP_60'
                if stockMagazines[name] then aliases[extended] = components[1]
                else options[#options + 1] = extended end
            end
            result[kind] = { label = labels[kind], options = options, default = kind == 'clip' and components[1] or '' }
            if kind == 'clip' and #options == 1 then result[kind].hidden = true end
            if next(aliases) then result[kind].aliases = aliases end
        end
        return result
    end
    if type(name) ~= 'string' or not name:match('^WEAPON_[%w_]+$') then return result end
    local xml = exports.gf_weapons:GetWeaponMeta(name)
    local points = xml and xml:match('<AttachPoints>(.-)</AttachPoints>')
    if not points then return result end
    for bone, components in points:gmatch('<Item>%s*<AttachBone>(.-)</AttachBone>%s*<Components>(.-)</Components>%s*</Item>') do
        local kind = bones[bone:lower()]
        if kind then
            local group = result[kind] or { label = labels[kind], options = {}, default = '' }
            for entry in components:gmatch('<Item>(.-)</Item>') do
                local component = entry:match('<Name>%s*([%w_]+)%s*</Name>')
                if component then
                    group.options[#group.options + 1] = component
                    if entry:match('<Default%s+value="true"') and group.default == '' then group.default = component end
                end
            end
            result[kind] = group
        end
    end
    local weaponGroup = xml and xml:match('<Group>%s*([^<%s]+)%s*</Group>')
    local originalOnly = weaponGroup == 'GROUP_SHOTGUN' or weaponGroup == 'GROUP_SNIPER'
    if result.clip and originalOnly then
        local clip = result.clip
        clip.aliases = clip.aliases or {}
        clip.aliases['GF_' .. name:sub(8) .. '_CLIP_60'] = clip.default ~= '' and clip.default or clip.options[1]
        if #clip.options == 1 then clip.hidden = true end
    elseif result.clip then
        local clip = result.clip
        local extended = 'GF_' .. name:sub(8) .. '_CLIP_60'
        local exists = false
        for _, component in ipairs(clip.options) do if component == extended then exists = true break end end
        if exists then
            local original = clip.default ~= '' and clip.default or clip.options[1]
            local aliases = {}
            for _, component in ipairs(clip.options) do
                if component ~= original and component ~= extended then aliases[component] = extended end
            end
            clip.options = { original, extended }
            if next(aliases) then clip.aliases = aliases end
        end
    end
    if name == 'WEAPON_SCARH' and result.sight then
        -- Conserver le choix enregistré avant le remplacement du modèle.
        result.sight.aliases = { COMPONENT_AT_SCOPE_MAX = 'GF_SCARH_SCOPE_TALL' }
    end
    local defaults = optionalDefaults[name] or {}
    for kind, component in pairs(defaults) do
        local group = result[kind]
        if group then
            for _, option in ipairs(group.options) do
                if option == component then group.default = component group.applyDefault = true break end
            end
        end
    end
    -- Un chargeur fixe ne constitue pas un choix de personnalisation.
    if result.clip and #result.clip.options < 2 and not result.clip.hidden then result.clip = nil end
    return result
end

function WeaponAccessories.validate(catalog, selection)
    if type(selection) ~= 'table' then return nil end
    local result = {}
    for kind, choice in pairs(selection) do
        local group = catalog[kind]
        if not group or type(choice) ~= 'string' then return nil end
        choice = group.aliases and group.aliases[choice] or choice
        local valid = choice == '' and kind ~= 'clip'
        for _, option in ipairs(group.options) do if option == choice then valid = true end end
        if not valid then return nil end
        result[kind] = choice
    end
    return result
end
