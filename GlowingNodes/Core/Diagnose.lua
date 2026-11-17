-- Diagnose.lua
-- /gn diag: a text to copy when reporting a problem. The client, the console
-- variables the addon sets (and what they were before it), the range the
-- game really keeps, what the glow sees now, the settings, the log, fishing,
-- the other addons loaded, and warnings for what is known to get in the way.
-- Its labels stay in English so every report reads the same. It never holds
-- the character's or the realm's name.
local _, ns = ...

local Diagnose = {}
ns.Diagnose = Diagnose

-- other addons that mark nodes too: two glows (or icons) on one node
local OTHER_GLOWS = { "nodesight", "interacticon", "interactglow", "fallenglow", "gatherlens" }

local function Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

local function CV(name)
    return C_CVar and Safe(C_CVar.GetCVar, name)
end

local function YesNo(v) return v and "yes" or "no" end

-- no "|" (the chat and edit boxes read it as a code)
local function Plain(v)
    return (tostring(v):gsub("|", "/"))
end

-- the addons loaded, by folder name, without this one
local function LoadedAddons()
    local A = C_AddOns or {}
    local count = A.GetNumAddOns or GetNumAddOns
    local info = A.GetAddOnInfo or GetAddOnInfo
    local loaded = A.IsAddOnLoaded or IsAddOnLoaded
    local list = {}
    local n = tonumber(Safe(count)) or 0
    for i = 1, n do
        local name = Safe(info, i)
        if type(name) == "string" and name ~= "GlowingNodes" and Safe(loaded, i) then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

function Diagnose.Report()
    local lines = {}
    local function Add(text) lines[#lines + 1] = Plain(text) end
    local warnings = {}
    local function Warn(text) warnings[#warnings + 1] = "WARNING: " .. Plain(text) end
    local db, ST = ns.db or {}, ns.SoftTarget

    Add(("Glowing Nodes %s diagnostic"):format(tostring(ns.VERSION)))
    local version, build, _, interface = Safe(GetBuildInfo)
    Add(("Client: %s (build %s, interface %s), %s"):format(tostring(version), tostring(build), tostring(interface),
        tostring(Safe(GetLocale))))
    Add("Date: " .. tostring(Safe(date, "%Y-%m-%d %H:%M")))
    local reason = ns.Navigator and ns.Navigator.Reason and Safe(ns.Navigator.Reason)
    Add(("State: addon %s; %s"):format(db.enabled ~= false and "on" or "off",
        reason and ("now " .. reason) or "not in combat, an instance, a taxi or dead"))

    -- the console variables
    local interact = tonumber(CV("SoftTargetInteract"))
    Add("Interact key: " .. ((interact and interact > 0) and "on" or "off"))
    if not interact or interact <= 0 then Warn("the Interact Key is off") end
    local before = ns.global and ns.global.savedCVars or {}
    for _, name in ipairs(ST and ST.CVARS or {}) do
        local default = C_CVar and Safe(C_CVar.GetCVarDefault, name)
        local was = before[name]
        Add(("  %s = %s (default %s, before the addon %s)"):format(name, tostring(CV(name)), tostring(default),
            was == nil and "not saved" or was == false and "unset" or tostring(was)))
    end
    local asked = ST and ST.Range and Safe(ST.Range)
    Add(("Range: asked %s yd, the game keeps %s"):format(tostring(asked), tostring(CV("SoftTargetInteractRange"))))
    local plates = tonumber(CV("nameplateGameObjectMaxDistance"))
    if plates and asked and plates < asked then
        Warn(("objects get a nameplate only within %d yd, under the %d yd range"):format(plates, asked))
    end
    if tonumber(CV("SoftTargetIconGameObject")) == 0 then
        Warn("world objects get no nameplate (SoftTargetIconGameObject 0): nothing can glow")
    end

    -- what the glow sees now
    local current = ST and ST.current
    Add("Target now: " .. (current and ST.Describe and Safe(ST.Describe, current) or "none"))

    -- the settings
    for _, cat in ipairs(ns.CATEGORIES or {}) do
        local c = db[cat]
        if type(c) == "table" then
            Add(("Look %s: %s, %s, size %s, intensity %s"):format(cat, c.enabled ~= false and "on" or "off",
                tostring(c.look), tostring(c.size), tostring(c.intensity)))
        end
    end
    Add(("Options: number %s, dim far %s, rare %s, only known %s, keep Interact Key %s, keep on node %s"):format(
        YesNo(db.showNumber), YesNo(db.dimFar), YesNo(db.rare ~= false), YesNo(db.onlyKnown),
        YesNo(db.keepInteract), YesNo(db.keepOnNode)))
    local skills = {}
    for _, cat in ipairs({ "ore", "herb", "skin", "fish" }) do
        local rank = ns.Skills and Safe(ns.Skills.Get, cat)
        skills[#skills + 1] = cat .. " " .. (rank and tostring(rank) or "-")
    end
    Add("Professions: " .. table.concat(skills, ", "))

    -- the log and the maps
    local points, zones = 0, 0
    if ns.Gather and ns.Gather.Total then points, zones = Safe(ns.Gather.Total) end
    local map = db.map or {}
    local mapID = C_Map and C_Map.GetBestMapForUnit and Safe(C_Map.GetBestMapForUnit, "player")
    Add(("Log: %s points in %s zones; map now %s; database %s, world map %s, minimap %s"):format(
        tostring(points), tostring(zones), tostring(mapID), YesNo(map.database), YesNo(map.worldMap),
        YesNo(map.minimap)))
    local hbd = LibStub and Safe(LibStub, "HereBeDragons-2.0", true)
    Add("HereBeDragons: " .. YesNo(hbd))

    -- fishing
    local fish = db.fish or {}
    local Nav = ns.Navigator
    local pole = Nav and Nav.HasPole and Safe(Nav.HasPole)
    local lure = ns.Lure and ns.Lure.Left and Safe(ns.Lure.Left)
    Add(("Fishing: pole %s; splash %s; easy cast %s; lure alert %s; lure %s"):format(YesNo(pole),
        fish.splash and tostring(fish.splashMode or "focus") or "off", YesNo(fish.easyCast),
        YesNo(db.alert == nil or db.alert.lure ~= false), lure and ("%d s left"):format(lure) or "none"))
    local arrow = db.arrow or {}
    Add("Arrow: " .. (arrow.enabled and "on" or "off"))

    -- the other addons
    local others = LoadedAddons()
    Add(("Other addons loaded (%d): %s"):format(#others, #others > 0 and table.concat(others, ", ") or "none"))
    for _, name in ipairs(others) do
        local lower = name:lower()
        for _, part in ipairs(OTHER_GLOWS) do
            if lower:find(part, 1, true) then
                Warn("another addon that marks nodes is loaded: " .. name .. " (two glows on one node)")
                break
            end
        end
    end

    for _, w in ipairs(warnings) do lines[#lines + 1] = w end
    return table.concat(lines, "\n")
end
