-- FishSound.lua
-- Hear the splash: with a fishing pole equipped (and fish.splash on), sound
-- effects go up to full and music and ambience down to 10 %, so the bobber's
-- splash stands out. The pole taken off, the box unticked or the addon off,
-- your own levels come back. The master volume is never touched. Nothing here
-- knows when a fish bites: it only makes the game's own splash easier to hear.
--
-- Your levels are kept in global.splash before anything changes, so a game
-- closed with the pole on gives them back at the next login. A volume you
-- move while fishing is yours: it stays as you left it.
local _, ns = ...

local FS = {}
ns.FishSound = FS

-- CVar -> the level while fishing; music and ambience already quieter stay so
local CHANNELS = {
    { cvar = "Sound_SFXVolume", level = 1, up = true },
    { cvar = "Sound_MusicVolume", level = 0.1 },
    { cvar = "Sound_AmbienceVolume", level = 0.1 },
}

local function Get(name)
    local ok, v = pcall(C_CVar.GetCVar, name)
    return ok and tonumber(v) or nil
end

local function Put(name, value)
    pcall(C_CVar.SetCVar, name, tostring(value))
end

local function Same(a, b)
    return a ~= nil and b ~= nil and math.abs(a - b) < 0.001
end

function FS.Active()
    local db = ns.db
    return db ~= nil and db.enabled ~= false and db.fish ~= nil and db.fish.splash == true
        and ns.Navigator ~= nil and ns.Navigator.HasPole() == true
end

-- your levels first, then the fishing ones
local function Lower()
    local kept = {}
    for _, ch in ipairs(CHANNELS) do
        local own = Get(ch.cvar)
        if own then
            local level = ch.up and math.max(own, ch.level) or math.min(own, ch.level)
            kept[ch.cvar] = { own = own, set = level }
        end
    end
    ns.global.splash = kept
    for name, k in pairs(kept) do Put(name, k.set) end
    ns.Debug("SPLASH on: effects up, music and ambience down")
end

-- your levels back, but a volume you moved since stays yours
local function Restore()
    local kept = ns.global and ns.global.splash
    if not kept then return end
    for name, k in pairs(kept) do
        if type(k) == "table" and Same(Get(name), k.set) then Put(name, k.own) end
    end
    ns.global.splash = nil
    ns.Debug("SPLASH off: your levels back")
end

function FS.Update()
    if not ns.global then return end
    local active = FS.Active()
    if active and not ns.global.splash then
        Lower()
    elseif not active and ns.global.splash then
        Restore()
    end
end

-- at login: levels left lowered by a game closed while fishing come back,
-- unless the pole is still on
function FS.Login()
    FS.Update()
end

local frame = CreateFrame("Frame")
FS.frame = frame
frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGOUT" then
        -- the game saves the levels as they are now: yours
        Restore()
    else
        FS.Update()
    end
end)
pcall(frame.RegisterEvent, frame, "PLAYER_EQUIPMENT_CHANGED")
pcall(frame.RegisterEvent, frame, "PLAYER_LOGOUT")

ns.On("Enable", function() FS.Login() end)
ns.On("Changed", function(key)
    if key == "*" or key == "enabled" or key == "fish.splash" then FS.Update() end
end)
