-- Locales.lua
-- A missing key falls back to its English text (the key itself is never shown
-- for a key enUS defines). Each language file fills ns.L only for its client.
local _, ns = ...

local base = {}
ns.L_BASE = base
ns.L = setmetatable({}, {
    __index = function(_, key)
        return base[key] or key
    end,
})

local locale = GetLocale and GetLocale() or "enUS"
ns.LOCALE = locale

function ns.RegisterLocale(code, strings)
    if code == "enUS" then
        for k, v in pairs(strings) do base[k] = v end
        return
    end
    local codes = type(code) == "table" and code or { code }
    for _, c in ipairs(codes) do
        if c == locale then
            for k, v in pairs(strings) do rawset(ns.L, k, v) end
            return
        end
    end
end
