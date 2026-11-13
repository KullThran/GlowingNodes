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

ns.CATEGORIES = { "ore", "herb", "skin", "chest" }
-- the kinds a gathering profession goes with (a level to show, a skill to
-- have); chests and quest objects have none
ns.PROFESSIONS = { ore = true, herb = true, skin = true }

local function Category(r, g, b, sound)
    return {
        enabled = true,
        color = { r = r, g = g, b = b },
        intensity = 1.6,
        size = 1.2,
        pulse = true,
        beam = true,
        glowTime = 0, -- seconds a node glows once lit; 0: as long as it is the target
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
        chest = Category(1.00, 0.84, 0.36, "bell"),
        showNumber = true,
        showMine = false,
        numberSize = 26,
        onlyKnown = false,
        dimFar = false, -- the game only finds nodes close by: glow at full from the first moment
        greyLocked = false,
        height = -45,
        keepInteract = true,
        trackSwitch = false, -- Find Herbs and Find Minerals take turns
        keepOnNode = true, -- the Interact Key stays on the node, not on what you have selected
        channel = "SFX",
        soundOnReady = false,
        debug = false,
        window = {},
        windowScale = 1, -- the options window's zoom, 0.5-1.5 (as in KullThranUI)
        lastTab = "ore",
        alert = {
            enabled = true,
            ore = true, herb = true, skin = true, chest = true,
            unlock = true, -- a profession up: say which nodes seen can now be gathered
            duration = 10,
            scale = 1,
            onlyCan = false,
            hideCombat = true,
            point = nil, -- { point, relPoint, x, y } once dragged
        },
        map = {
            record = { ore = true, herb = true, skin = true }, -- what goes in the log
            -- what the maps draw; skinning (your hide areas and the purple
            -- skinning zones of Data/SkinAreas.lua) starts off
            show = { ore = true, herb = true, skin = false },
            -- the spots of Data/NodeSpawns.lua (where ore and herbs can
            -- spawn, from the 1.12 world database), fainter than your own
            database = false,
            worldMap = true,
            minimap = true,
            pinSize = 12,
        },
    },
    global = {
        learned = {}, -- "o<objectID>" / "n<lower name>" -> required skill seen in game
        language = "auto", -- the addon's language: "auto" follows the client
        nodes = {},     -- [uiMapID][x*1e4 .. y*1e4] = { k = kind, n = name, c = gathered, s = seen, t = last gathered,
                        --   v = last met, o = objectID, r = level needed, p = false while only seen from afar }
        gatherLog = {}, -- last gathers, newest last: { t, k, n, m = uiMapID, x, y }
        items = {},     -- itemID -> { n = name, q = quality } of what nodes dropped (node.x[itemID] = times)
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

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function Addon:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("GlowingNodesDB", ns.DEFAULTS, true)
    ns.db = self.db.profile
    ns.global = self.db.global
    -- the language picked in the window (the window is built later, on use)
    ns.UseLanguage(ns.global.language)
    if ns.W then ns.W.SetFonts(ns.LOCALE) end
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

-- A test build put a game waypoint on logged nodes; that's gone. If it left
-- one behind (kept in global.farWaypoint), it is cleared once, and only if
-- the game's waypoint is still that one.
local function ClearOldWaypoint()
    local old = ns.global.farWaypoint
    if not old then return end
    ns.global.farWaypoint = nil
    if not (C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.ClearUserWaypoint) then return end
    local pos
    if C_Map.GetUserWaypointPositionForMap then
        local ok, p = pcall(C_Map.GetUserWaypointPositionForMap, old.mapID)
        if ok then pos = p end
    end
    local x, y = pos and pos.x, pos and pos.y
    if pos and pos.GetXY then x, y = pos:GetXY() end
    if type(x) == "number" and math.abs(x - old.x) < 2e-3 and math.abs(y - old.y) < 2e-3 then
        pcall(C_Map.ClearUserWaypoint)
    end
end

function Addon:OnEnable()
    ns.Fire("Enable")
    pcall(ClearOldWaypoint)
    self:ScheduleTimer(function()
        -- other addons set the same ranges as they log in (their own values):
        -- ours again, written only where they differ
        if ns.db.enabled and ns.SoftTarget then ns.SoftTarget:ApplyCVars() end
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

-- ns.SetMap("worldMap", true) / ns.SetMap("show", false, "herb")
function ns.SetMap(key, value, kind)
    if kind then
        ns.db.map[key][kind] = value
    else
        ns.db.map[key] = value
    end
    ns.Fire("Changed", "map." .. key)
end

-- the addon's language; it takes a /reload, as the texts are built once
function ns.SetLanguage(code)
    ns.global.language = code
    ns.Fire("LanguageChanged", ns.ResolveLanguage(code) ~= ns.LOCALE)
end

function Addon:Slash(input)
    local cmd = strtrim((input or ""):lower())
    if cmd == "" or cmd == "config" or cmd == "options" then
        ns.Window:Toggle()
    elseif cmd == "map" or cmd == "mapa" then
        ns.Window:Open()
        ns.Window:Select("map")
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
    elseif cmd:match("^rango %d+$") or cmd:match("^range %d+$") then
        ns.SoftTarget:SetRange(tonumber(cmd:match("%d+")))
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
