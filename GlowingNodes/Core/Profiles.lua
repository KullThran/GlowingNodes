-- Profiles.lua
-- Which settings a character uses (AceDB profiles): the shared one
-- ("Default", every character's until it picks another), its own (named
-- after the character, "Name - Realm") or any named one. A profile that
-- doesn't exist yet starts as a copy of the settings in use. What you have
-- gathered, the levels learned and the language are the account's: they
-- don't change with the profile.
local _, ns = ...
local L = ns.L

local P = {}
ns.Profiles = P

P.SHARED = "Default"

local function DB() return ns.Addon.db end

function P.Current() return DB():GetCurrentProfile() end
function P.CharKey() return DB().keys.char end

local function Exists(name)
    return DB().sv.profiles ~= nil and rawget(DB().sv.profiles, name) ~= nil
end

-- every profile, the shared one first, then this character's, then the rest
-- by name
function P.List()
    local seen, rest = {}, {}
    for _, name in ipairs(DB():GetProfiles()) do
        if name ~= P.SHARED and name ~= P.CharKey() and not seen[name] then
            seen[name] = true
            rest[#rest + 1] = name
        end
    end
    table.sort(rest, function(a, b) return a:lower() < b:lower() end)
    table.insert(rest, 1, P.CharKey())
    table.insert(rest, 1, P.SHARED)
    return rest
end

-- the profiles other than the one in use that hold settings
function P.Others()
    local out = {}
    for _, name in ipairs(P.List()) do
        if name ~= P.Current() and Exists(name) then out[#out + 1] = name end
    end
    return out
end

function P.Label(name)
    if name == P.SHARED then return L.PROFILE_SHARED end
    return name
end

function P.IsPerChar() return P.Current() == P.CharKey() end

-- use a profile; a new one starts as a copy of the settings in use
function P.Use(name)
    name = name and strtrim(name)
    if not name or name == "" or name == P.Current() then return false end
    local from, isNew = P.Current(), not Exists(name)
    DB():SetProfile(name)
    if isNew then DB():CopyProfile(from, true) end
    ns.Print(L.MSG_PROFILE:format(P.Label(name)))
    return true
end

function P.PerChar(on)
    return P.Use(on and P.CharKey() or P.SHARED)
end

-- the settings of another profile into the one in use
function P.CopyFrom(name)
    if not name or name == P.Current() or not Exists(name) then return false end
    DB():CopyProfile(name)
    ns.Print(L.MSG_PROFILE_COPIED:format(P.Label(name)))
    return true
end

-- not the one in use; characters that used it go back to the shared one
function P.Delete(name)
    if not name or name == P.Current() or not Exists(name) then return false end
    DB():DeleteProfile(name, true)
    ns.Print(L.MSG_PROFILE_DELETED:format(P.Label(name)))
    ns.Fire("Changed", "profiles")
    return true
end
