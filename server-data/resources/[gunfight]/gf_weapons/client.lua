-- =============================================================================
--  gf_weapons - CLIENT
--  Noms affichés des armes ajoutées et de leurs accessoires
--  (data/<ARME>/names.json, écrit par scripts/ajouter_arme.py).
-- =============================================================================
local RES = GetCurrentResourceName()
local index = LoadResourceFile(RES, 'data/index.json')
local ok, weapons = pcall(json.decode, index or '')
if ok and type(weapons) == 'table' then
    for _, weapon in ipairs(weapons) do
        local raw = LoadResourceFile(RES, ('data/%s/names.json'):format(weapon))
        local good, names = pcall(json.decode, raw or '')
        if good and type(names) == 'table' then
            for key, text in pairs(names) do
                if type(key) == 'string' and type(text) == 'string' then AddTextEntry(key, text) end
            end
        end
    end
end
