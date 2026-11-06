-- Init.lua
-- The addon object (AceAddon), its saved settings (AceDB), a tiny message bus
-- the modules use to react to setting changes, and the slash command.
local ADDON_NAME, ns = ...
local L = ns.L

local Addon = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
ns.Addon = Addon
ns.NAME = ADDON_NAME
ns.MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
ns.ART = ns.MEDIA .. "Art\\"
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "?"

ns.CATEGORIES = { "ore", "herb", "skin" }

local function Category(r, g, b, sound)
    return {
        enabled = true,
        color = { r = r, g = g, b = b },
        intensity = 1.6,
        size = 1.2,
        pulse = true,
        beam = true,
        soundOn = true,
        sound = sound,
        volume = 2,
    }
end

ns.DEFAULTS = {
    profile = {
        enabled = true,
        ore = Category(1.00, 0.58, 0.12, "ore_ping"),
        herb = Category(0.22, 1.00, 0.38, "herb_chime"),
        skin = Category(0.78, 0.38, 1.00, "skin_thump"),
        showNumber = true,
        showMine = false,
        numberSize = 26,
        onlyKnown = false,
        dimFar = false, -- the game only finds nodes close by: glow at full from the first moment
        greyLocked = false,
        height = -45,
        keepInteract = true,
        channel = "SFX",
        soundOnReady = false,
        debug = false,
        window = {},
        lastTab = "ore",
        alert = {
            enabled = true,
            ore = true, herb = true, skin = true,
            duration = 10,
            scale = 1,
            onlyCan = false,
            hideCombat = true,
            point = nil, -- { point, relPoint, x, y } once dragged
        },
    },
    global = {
        learned = {}, -- "o<objectID>" / "n<lower name>" -> required skill seen in game
    },
}

---------------------------------------------------------------------------
-- Message bus: ns.On("Changed", fn) / ns.Fire("Changed", key)
---------------------------------------------------------------------------

local listeners = {}

function ns.On(message, fn)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], fn)
end

function ns.Fire(message, ...)
    for _, fn in ipairs(listeners[message] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok and ns.db and ns.db.debug then
            ns.Print("|cffff5555error|r " .. tostring(err))
        end
    end
end

-- With debug on, what the addon says is also kept in the saved variables
-- (GlowingNodesDB.global.log, last 150 lines), to read after a /reload
local LOG_SIZE = 150

function ns.Log(text)
    if not (ns.db and ns.db.debug and ns.global) then return end
    ns.global.log = ns.global.log or {}
    local log = ns.global.log
    local ok, stamp = pcall(date, "%H:%M:%S")
    text = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    log[#log + 1] = (ok and stamp or "?") .. " " .. text
    while #log > LOG_SIZE do table.remove(log, 1) end
end

function ns.Print(text)
    print("|cff3fe0c5Glowing Nodes|r " .. tostring(text))
    ns.Log(text)
end

function ns.Debug(text)
    if ns.db and ns.db.debug then
        print("|cff3fe0c5GN|r|cff8899aa " .. tostring(text) .. "|r")
        ns.Log(text)
    end
end

-- The other addon that drives the same soft-target nameplate.
ns.CONFLICTS = { "ForeverLootSparkles", "Lueur" }

function ns.ConflictingAddon()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if not loaded then return nil end
    for _, name in ipairs(ns.CONFLICTS) do
        local ok, isLoaded = pcall(loaded, name)
        if ok and isLoaded then
            if name == "ForeverLootSparkles" then
                local db = _G.ForeverLootSparklesDB
                if not db or db.sparkleOre ~= false or db.sparkleHerbs ~= false or db.sparkleCorpseLoot ~= false then
                    return name
                end
            else
                return name
            end
        end
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("GlowingNodesDB", ns.DEFAULTS, true)
    ns.db = self.db.profile
    ns.global = self.db.global
    local function Reload()
        ns.db = self.db.profile
        ns.Fire("Changed", "*")
    end
    self.db.RegisterCallback(self, "OnProfileChanged", Reload)
    self.db.RegisterCallback(self, "OnProfileCopied", Reload)
    self.db.RegisterCallback(self, "OnProfileReset", Reload)

    self:RegisterChatCommand("gn", "Slash")
    self:RegisterChatCommand("kn", "Slash") -- the old command, kept
    self:RegisterChatCommand("glowingnodes", "Slash")
end

function Addon:OnEnable()
    ns.Fire("Enable")
    self:ScheduleTimer(function()
        local other = ns.ConflictingAddon()
        if other and ns.db.enabled then
            ns.Print(L.MSG_CONFLICT:format(other))
        end
    end, 6)
end

function ns.Set(key, value)
    ns.db[key] = value
    ns.Fire("Changed", key)
end

function ns.SetAlert(key, value)
    ns.db.alert[key] = value
    ns.Fire("Changed", "alert." .. key)
end

function ns.SetCat(category, key, value)
    ns.db[category][key] = value
    ns.Fire("Changed", category .. "." .. key)
end

function Addon:Slash(input)
    local cmd = strtrim((input or ""):lower())
    if cmd == "" or cmd == "config" or cmd == "options" then
        ns.Window:Toggle()
    elseif cmd == "on" or cmd == "off" then
        ns.Set("enabled", cmd == "on")
        ns.Print(cmd == "on" and L.MSG_ON or L.MSG_OFF)
    elseif cmd == "reset" then
        self.db:ResetProfile()
        ns.Print(L.MSG_RESET)
    elseif cmd == "debug" then
        ns.Set("debug", not ns.db.debug)
        ns.Print("debug " .. (ns.db.debug and "on" or "off"))
    elseif cmd == "rango" or cmd == "range" then
        ns.SoftTarget:PrintRange()
    elseif cmd == "info" then
        ns.SoftTarget:PrintInfo()
    else
        ns.Print(L.MSG_HELP)
    end
end

-- Addon compartment (minimap addon menu), where the client has one.
function GlowingNodes_OnCompartmentClick()
    if ns.Window then ns.Window:Toggle() end
end
