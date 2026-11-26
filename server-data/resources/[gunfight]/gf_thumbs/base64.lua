-- Encodage / décodage base64 (pour transporter les PNG en data URL)
Base64 = {}

local CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local DECODE = {}
for i = 1, #CHARS do DECODE[CHARS:byte(i)] = i - 1 end

function Base64.encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = (a << 16) | ((b or 0) << 8) | (c or 0)
        out[#out + 1] = CHARS:sub((n >> 18) + 1, (n >> 18) + 1)
            .. CHARS:sub(((n >> 12) & 63) + 1, ((n >> 12) & 63) + 1)
            .. (b and CHARS:sub(((n >> 6) & 63) + 1, ((n >> 6) & 63) + 1) or '=')
            .. (c and CHARS:sub((n & 63) + 1, (n & 63) + 1) or '=')
    end
    return table.concat(out)
end

-- Retourne nil si la chaîne n'est pas du base64 valide
function Base64.decode(text)
    if type(text) ~= 'string' or #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local c1, c2, c3, c4 = text:byte(i, i + 3)
        local a, b = DECODE[c1], DECODE[c2]
        local c = c3 == 61 and 0 or DECODE[c3]
        local d = c4 == 61 and 0 or DECODE[c4]
        if not (a and b and c and d) then return nil end
        local n = (a << 18) | (b << 12) | (c << 6) | d
        out[#out + 1] = string.char((n >> 16) & 255)
        if c3 ~= 61 then out[#out + 1] = string.char((n >> 8) & 255) end
        if c4 ~= 61 then out[#out + 1] = string.char(n & 255) end
    end
    return table.concat(out)
end
