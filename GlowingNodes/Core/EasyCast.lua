-- EasyCast.lua
-- Double right-click to cast: with a fishing pole equipped (and fish.easyCast
-- on), out of combat, a quick right-click on the world arms the right mouse
-- button for a moment (DOUBLE seconds): the next right-click casts Fishing
-- through a secure button of the game's own, and the right button is the
-- game's again. A single right-click stays as it was (loot the bobber, talk,
-- turn the camera). You always press: nothing is cast on its own, and nothing
-- here knows when a fish bites.
local _, ns = ...

local EC = {}
ns.EasyCast = EC

EC.DOUBLE = 0.4      -- seconds the right button stays armed after a click
EC.HELD = 0.3        -- a press held longer turned the camera: not a click
EC.FISHING = 7620    -- Fishing; cast by its name, the game picks your rank
EC.BUTTON = "GlowingNodesCastButton"

local function Ask(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

local function InCombat()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

function EC.Wanted()
    local db = ns.db
    return db ~= nil and db.enabled ~= false and db.fish ~= nil and db.fish.easyCast == true
        and ns.Navigator ~= nil and ns.Navigator.HasPole() == true
end

local function SpellName()
    local name = C_Spell and Ask(C_Spell.GetSpellName, EC.FISHING)
    if not name and GetSpellInfo then name = Ask(GetSpellInfo, EC.FISHING) end
    return name
end

-- holds the binding while armed; its OnUpdate runs only while needed
local owner = CreateFrame("Frame")
owner:Hide()
EC.owner = owner

local button     -- the secure button, made on first use (out of combat)
local armedUntil -- the right button casts until then
local pressAt    -- a right-click on the world, not let go yet

function EC.Disarm()
    if not armedUntil then return end
    armedUntil = nil
    if ClearOverrideBindings and not InCombat() then pcall(ClearOverrideBindings, owner) end
end

local function Button()
    if button then return button end
    if InCombat() then return nil end
    button = CreateFrame("Button", EC.BUTTON, UIParent, "SecureActionButtonTemplate")
    button:SetSize(1, 1)
    button:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100) -- out of sight
    button:SetAttribute("type", "spell")
    -- the cast done: the right button is the game's again
    button:HookScript("PostClick", function() EC.Disarm() end)
    return button
end

function EC.Arm(now)
    if InCombat() or not EC.Wanted() or not SetOverrideBindingClick then return false end
    local b, spell = Button(), SpellName()
    if not (b and spell) then return false end
    b:SetAttribute("spell", spell)
    -- the game's buttons act on the press or the release (its key-down
    -- setting): ours too, once, not on both
    local down = C_CVar and Ask(C_CVar.GetCVar, "ActionButtonUseKeyDown") == "1"
    b:RegisterForClicks(down and "AnyDown" or "AnyUp")
    local ok = pcall(SetOverrideBindingClick, owner, true, "BUTTON2", EC.BUTTON)
    if not ok then return false end
    armedUntil = now + EC.DOUBLE
    owner:Show()
    return true
end

-- a mouse button pressed on the world
function EC.OnMouseDown(which)
    if which ~= "RightButton" or armedUntil or InCombat() or not EC.Wanted() then return end
    -- on a creature or a person the right-click is theirs (talk, attack)
    if UnitExists and Ask(UnitExists, "mouseover") then return end
    pressAt = GetTime()
    owner:Show()
end

owner:SetScript("OnUpdate", function()
    local now = GetTime()
    if pressAt and not (IsMouseButtonDown and IsMouseButtonDown("RightButton")) then
        -- let go: a quick click arms, a long press turned the camera
        local quick = now - pressAt <= EC.HELD
        pressAt = nil
        if quick then EC.Arm(now) end
    end
    if armedUntil and now > armedUntil then EC.Disarm() end
    if not (pressAt or armedUntil) then owner:Hide() end
end)

if WorldFrame and WorldFrame.HookScript then
    WorldFrame:HookScript("OnMouseDown", function(_, which) EC.OnMouseDown(which) end)
end

-- combat about to start (bindings can still change now), the pole taken off
-- or the box unticked: the right button is the game's again
owner:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        pressAt = nil
        EC.Disarm()
    elseif not EC.Wanted() then
        pressAt = nil
        EC.Disarm()
    end
end)
pcall(owner.RegisterEvent, owner, "PLAYER_REGEN_DISABLED")
pcall(owner.RegisterEvent, owner, "PLAYER_EQUIPMENT_CHANGED")
ns.On("Changed", function(key)
    if key == "*" or key == "enabled" or key == "fish.easyCast" then
        if not EC.Wanted() then
            pressAt = nil
            EC.Disarm()
        end
    end
end)
