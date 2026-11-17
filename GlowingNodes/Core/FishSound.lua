-- FishSound.lua
-- Hear the splash: with a fishing pole equipped (and fish.splash on), sound
-- effects go up to full (the game's sound and effects turned on if they were
-- off) and the rest down: music, ambience and voices to 30 % on Balanced;
-- on Fishing only, silent, and pets', emotes' and error voices off. The splash
-- is an effect like any other (spells, creatures, steps): those can't be told
-- apart from it, so they stay. The pole taken off,
-- your own levels come back 10 seconds later (a quick swap to your weapon and
-- back doesn't flip them); turned off, or the addon off, at once. The master
-- volume is never touched. Nothing here knows when a fish bites: it only
-- makes the game's own splash easier to hear.
--
-- Your levels are kept in global.splash before anything changes, so a game
-- closed with the pole on gives them back at the next login. A volume you
-- move while fishing is yours: it stays as you left it.
local _, ns = ...

local FS = {}
ns.FishSound = FS

-- what changes: effects up to full; music, ambience and voices down to the
-- mode's level (already quieter, they stay so); the game's sound and effects
-- on; and on Fishing only (off = "focus"), the sounds of pets, emotes, error
-- voices and others' armour off. A setting this client lacks is left alone.
local CHANNELS = {
    { cvar = "Sound_SFXVolume", up = true },
    { cvar = "Sound_MusicVolume" },
    { cvar = "Sound_AmbienceVolume" },
    { cvar = "Sound_DialogVolume" },
    { cvar = "Sound_EnableAllSound", on = true },
    { cvar = "Sound_EnableSFX", on = true },
    { cvar = "Sound_EnablePetSounds", off = "focus" },
    { cvar = "Sound_EnableEmoteSounds", off = "focus" },
    { cvar = "Sound_EnableErrorSpeech", off = "focus" },
    { cvar = "Sound_EnableArmorFoleySoundForOthers", off = "focus" },
}
FS.CHANNELS = CHANNELS
FS.MODES = { "off", "balanced", "focus" } -- the picker's values ("off": fish.splash false)
FS.QUIET = { balanced = 0.3, focus = 0 }
FS.RESTORE_AFTER = 10 -- seconds without a pole before your levels come back

local function Mode()
    local mode = ns.db and ns.db.fish and ns.db.fish.splashMode
    return FS.QUIET[mode] and mode or "focus"
end

local function Quiet()
    return FS.QUIET[Mode()]
end

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
    local kept, mode = {}, Mode()
    for _, ch in ipairs(CHANNELS) do
        local own = Get(ch.cvar)
        if own then
            local level
            if ch.up then
                level = math.max(own, 1)
            elseif ch.on then
                level = 1
            elseif ch.off then
                level = mode == ch.off and 0 or nil
            else
                level = math.min(own, Quiet())
            end
            if level then kept[ch.cvar] = { own = own, set = level } end
        end
    end
    ns.global.splash = kept
    for name, k in pairs(kept) do Put(name, k.set) end
    ns.Debug("SPLASH on (" .. mode .. "): effects up, the rest down")
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

-- the splash wanted, pole or not
local function Wanted()
    local db = ns.db
    return db ~= nil and db.enabled ~= false and db.fish ~= nil and db.fish.splash == true
end

local waiting -- a restore due once the pole has stayed off a while

-- now: your levels back at once if they're due (login), no waiting
function FS.Update(now)
    if not ns.global then return end
    if FS.Active() then
        waiting = nil
        if not ns.global.splash then Lower() end
    elseif ns.global.splash then
        if now or not Wanted() then
            waiting = nil
            Restore()
        elseif not waiting then
            local token = {}
            waiting = token
            C_Timer.After(FS.RESTORE_AFTER, function()
                if waiting ~= token then return end
                waiting = nil
                if not FS.Active() then Restore() end
            end)
        end
    end
end

-- another mode while fishing: its levels at once (yours kept as they were)
function FS.Remode()
    if not (ns.global and ns.global.splash and FS.Active()) then return end
    Restore()
    Lower()
end

-- at login: levels left lowered by a game closed while fishing come back,
-- unless the pole is still on
function FS.Login()
    FS.Update(true)
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
    if key == "fish.splashMode" then FS.Remode() end
end)
