-- Tracking.lua
-- Find Herbs and Find Minerals take turns on the minimap, for a player who
-- has both (the game shows one at a time). Only out of combat, on the move,
-- not while casting, resting in a town or in an instance, and only when one
-- of the two is what's tracked: something else the player picked (Find
-- Treasure, a hunter's tracking) is theirs and is left alone. Each switch is
-- a spell with the global cooldown and a sound; the sound is muted for a
-- moment around it.
local _, ns = ...

local TR = {}
ns.Tracking = TR

local SPELLS = { herb = 2383, ore = 2580 } -- Find Herbs, Find Minerals
local EVERY = 3        -- seconds between switches
local MUTE_FOR = 0.6   -- the switch's sound comes back from the server: covered

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end

local function SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and Call(C_Spell.GetSpellName, id)
    if not name and GetSpellInfo then name = Call(GetSpellInfo, id) end
    if type(name) == "string" and not IsSecret(name) then return name end
end

local function Api()
    local m = C_Minimap
    if m and m.GetNumTrackingTypes and m.GetTrackingInfo and m.SetTracking then
        return m.GetNumTrackingTypes, m.GetTrackingInfo, m.SetTracking
    end
    if GetNumTrackingTypes and GetTrackingInfo and SetTracking then
        return GetNumTrackingTypes, GetTrackingInfo, SetTracking
    end
end

-- name, active, spellID of a tracking entry: a table on newer clients;
-- name, texture, active, category, nested, spellID on older ones
local function Entry(getInfo, i)
    local a, _, c, _, _, f = Call(getInfo, i)
    if type(a) == "table" then return a.name, a.active, a.spellID end
    return a, c, f
end

-- the herb and mineral entries, and what's tracked now ("herb", "ore",
-- "other", "both" or nil)
function TR.Find()
    local getNum, getInfo = Api()
    if not getNum then return nil end
    local names = { herb = SpellName(SPELLS.herb), ore = SPELLS.ore and SpellName(SPELLS.ore) }
    local found, active = {}, nil
    for i = 1, tonumber(Call(getNum)) or 0 do
        local name, on, spellID = Entry(getInfo, i)
        if IsSecret(name) then name = nil end
        if IsSecret(on) then on = nil end
        if IsSecret(spellID) then spellID = nil end
        local kind
        for k, id in pairs(SPELLS) do
            if spellID == id or (name and name == names[k]) then kind = k end
        end
        if kind then found[kind] = i end
        if on then
            local now = kind or "other"
            if active and active ~= now then active = "both" else active = now end
        end
    end
    return found, active
end

local function Busy()
    if InCombatLockdown() then return "combat" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return "dead" end
    if IsResting and IsResting() then return "resting" end
    if IsInInstance and IsInInstance() then return "instance" end
    if (UnitCastingInfo and UnitCastingInfo("player")) or (UnitChannelInfo and UnitChannelInfo("player")) then
        return "casting"
    end
    local speed = GetUnitSpeed and Call(GetUnitSpeed, "player")
    if type(speed) ~= "number" or IsSecret(speed) or speed <= 0 then return "standing" end
end

-- the switch's sound: off for a moment. If the game closes before it comes
-- back on, it is put back at the next login (global.sfxMuted).
local muteLeft
local function Unmute()
    muteLeft = nil
    if ns.global and ns.global.sfxMuted then
        ns.global.sfxMuted = nil
        pcall(C_CVar.SetCVar, "Sound_EnableSFX", "1")
    end
end

local function Mute()
    local ok, cur = pcall(C_CVar.GetCVar, "Sound_EnableSFX")
    if not ok or cur ~= "1" then return end
    ns.global.sfxMuted = true
    pcall(C_CVar.SetCVar, "Sound_EnableSFX", "0")
    muteLeft = MUTE_FOR
end

function TR.Step()
    if Busy() then return end
    local found, active = TR.Find()
    if not (found and found.herb and found.ore) then return end
    if active ~= "herb" and active ~= "ore" then return end -- none, both, or the player's own
    local nextKind = active == "herb" and "ore" or "herb"
    local _, _, setTracking = Api()
    Mute()
    Call(setTracking, found[nextKind], true)
end

TR.frame = CreateFrame("Frame")
TR.frame:Hide()
local since = 0
TR.frame:SetScript("OnUpdate", function(self, elapsed)
    if muteLeft then
        muteLeft = muteLeft - elapsed
        if muteLeft <= 0 then Unmute() end
    end
    since = since + elapsed
    if since >= EVERY then
        since = 0
        if ns.db and ns.db.trackSwitch then TR.Step() end
    end
    if not (ns.db and ns.db.trackSwitch) and not muteLeft then self:Hide() end
end)

local function Update()
    if not ns.db then return end
    if ns.db.trackSwitch then
        since = 0
        TR.frame:Show()
    end
end

ns.On("Enable", function()
    Unmute() -- left muted by a game closed mid-switch
    Update()
end)
ns.On("Changed", function(key)
    if key == "trackSwitch" or key == "*" then Update() end
end)
