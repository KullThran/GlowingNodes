-- Locales.lua
-- A missing key falls back to its English text (the key itself is never shown
-- for a key enUS defines). Every language file is kept, so the player can pick
-- the addon's language apart from the client's (ns.UseLanguage, on login).
local _, ns = ...

local base = {}
ns.L_BASE = base
ns.L = setmetatable({}, {
    __index = function(_, key)
        return base[key] or key
    end,
})

ns.CLIENT_LOCALE = GetLocale and GetLocale() or "enUS"
ns.LOCALE = "enUS"

ns.LANGUAGES = { "enUS", "esES", "deDE", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
ns.LANGUAGE_NAMES = {
    enUS = "English", esES = "Español", deDE = "Deutsch", frFR = "Français", itIT = "Italiano",
    ptBR = "Português", ruRU = "Русский", koKR = "한국어", zhCN = "简体中文", zhTW = "繁體中文",
}

local tables = {}

-- "auto" (or nil) follows the client; a language without its file is English
function ns.ResolveLanguage(code)
    if code == nil or code == "auto" then code = ns.CLIENT_LOCALE end
    if code == "enUS" or tables[code] then return code end
    return "enUS"
end

function ns.UseLanguage(code)
    code = ns.ResolveLanguage(code)
    for k in pairs(ns.L) do rawset(ns.L, k, nil) end
    local strings = tables[code]
    if strings then
        for k, v in pairs(strings) do rawset(ns.L, k, v) end
    end
    ns.LOCALE = code
end

function ns.RegisterLocale(code, strings)
    if code == "enUS" then
        for k, v in pairs(strings) do base[k] = v end
        return
    end
    local codes = type(code) == "table" and code or { code }
    for _, c in ipairs(codes) do
        tables[c] = strings
        -- until the saved choice is read, the client's language
        if c == ns.CLIENT_LOCALE then ns.UseLanguage(c) end
    end
end
