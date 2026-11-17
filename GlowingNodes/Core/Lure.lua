-- Lure.lua
-- The lure on your fishing pole: with the pole equipped (and alert.lure on),
-- the chat says when 30 seconds are left and when it has run out, with the
-- bobber's sound. Each once per lure. Taken off, or put on with no lure,
-- nothing is said. It only reads the time the game shows on the pole.
local _, ns = ...

local Lure = {}
ns.Lure = Lure

Lure.SOON = 30   -- seconds left that call for a word
Lure.EVERY = 1   -- seconds between looks at the pole

local left     -- seconds left at the last look; nil: no lure (or no pole)
local warned   -- the "30 seconds" already said for this lure

function Lure.Wanted()
    local db = ns.db
    return db ~= nil and db.enabled ~= false and db.alert ~= nil and db.alert.lure ~= false
        and ns.Navigator ~= nil and ns.Navigator.HasPole() == true
end

-- seconds the lure on the main hand has left, or nil
local function Left()
    if not GetWeaponEnchantInfo then return nil end
    local ok, has, ms = pcall(GetWeaponEnchantInfo)
    if ok and has and type(ms) == "number" then return ms / 1000 end
end
Lure.Left = Left
Lure.Left = Left

local function Say(text)
    ns.Print(text)
    ns.Sounds.PlayCategory("fish")
end

function Lure.Check()
    if not Lure.Wanted() then
        left, warned = nil, nil
        return
    end
    local now = Left()
    if now then
        if now > Lure.SOON then
            warned = nil -- a new lure
        elseif not warned then
            warned = true
            Say(ns.L.LURE_SOON)
        end
    elseif left then
        Say(ns.L.LURE_GONE)
        warned = nil
    end
    left = now
end

-- a look every second, only while the pole is on
local frame = CreateFrame("Frame")
Lure.frame = frame
local since = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < Lure.EVERY then return end
    since = 0
    Lure.Check()
end)

local function Watch()
    local on = Lure.Wanted()
    if not on then left, warned = nil, nil end
    frame:SetShown(on)
    if on then Lure.Check() end
end
Lure.Watch = Watch

frame:SetScript("OnEvent", Watch)
pcall(frame.RegisterEvent, frame, "PLAYER_EQUIPMENT_CHANGED")
ns.On("Enable", Watch)
ns.On("Changed", function(key)
    if key == "*" or key == "enabled" or key == "alert.lure" then Watch() end
end)
frame:Hide()
