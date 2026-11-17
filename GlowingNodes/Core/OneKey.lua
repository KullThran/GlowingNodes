-- OneKey.lua
-- Fishing with one key: with fish.oneKey on and a fishing pole equipped, the
-- key (or keys) bound to Interact does what comes next, through a secure
-- button of the game's own:
--   nothing out           -> casts Fishing
--   the line out          -> the game's Interact again: it loots the bobber
--   no lure on the pole   -> puts on the best lure in the bags first
--   a node or NPC in reach -> the game's Interact (gather it, talk)
-- In combat, and without the pole, the key is the game's. You press every
-- time: nothing is cast or looted on its own, and nothing here knows when a
-- fish bites (the splash is yours to hear).
local _, ns = ...

local OK = {}
ns.OneKey = OK

OK.BUTTON = "GlowingNodesOneKeyButton"
OK.FISHING = 7620     -- Fishing; cast by its name, the game picks your rank
OK.EVERY = 0.25       -- seconds between looks while the pole is on
OK.HOLD = 1           -- after a cast, the key stays the game's this long (the line goes out)
OK.LURE_HOLD = 4      -- after putting a lure on (it takes a moment)
OK.LURE_CHECK = 6     -- by then the lure is on the pole, or it didn't take
OK.LURE_RETRY = 300   -- a lure that didn't take isn't tried again for this long
-- the lures, best first: Aquadynamic Fish Attractor (+100), Bright Baubles
-- and Flesh Eating Worm (+75), Aquadynamic Fish Lens and Nightcrawlers (+50),
-- Shiny Bauble (+25)
OK.LURES = { 6533, 6532, 7307, 6811, 6530, 6529 }

local function Ask(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

local function InCombat()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

function OK.Wanted()
    local db = ns.db
    return db ~= nil and db.enabled ~= false and db.fish ~= nil and db.fish.oneKey == true
        and ns.Navigator ~= nil and ns.Navigator.HasPole() == true
end

-- the keys bound to Interact
function OK.Keys()
    if not GetBindingKey then return {} end
    local got = { pcall(GetBindingKey, "INTERACTTARGET") }
    if not got[1] then return {} end
    local keys = {}
    for i = 2, #got do
        if got[i] then keys[#keys + 1] = got[i] end
    end
    return keys
end

local function SpellName()
    local name = C_Spell and Ask(C_Spell.GetSpellName, OK.FISHING)
    if not name and GetSpellInfo then name = Ask(GetSpellInfo, OK.FISHING) end
    return name
end

local owner = CreateFrame("Frame") -- holds the bindings; looks while the pole is on
owner:Hide()
OK.owner = owner

local mode, boundItem   -- what the key does now: nil (the game's), "cast", "lure"
local holdUntil = 0     -- the key stays the game's until then
local lureItem, lureAt  -- a lure just put on, to see whether it took
local tried = {}        -- itemID -> when it didn't take

local function Release()
    if mode and ClearOverrideBindings and not InCombat() then pcall(ClearOverrideBindings, owner) end
    mode, boundItem = nil, nil
end
OK.Release = Release

local function Button()
    if OK.button then return OK.button end
    if InCombat() then return nil end
    local b = CreateFrame("Button", OK.BUTTON, UIParent, "SecureActionButtonTemplate")
    b:SetSize(1, 1)
    b:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100) -- out of sight
    -- pressed: the key is the game's while the line goes out or the lure goes on
    b:HookScript("PostClick", function()
        local now = GetTime()
        if mode == "lure" then
            lureItem, lureAt = boundItem, now
            holdUntil = now + OK.LURE_HOLD
        else
            holdUntil = now + OK.HOLD
        end
        Release()
    end)
    OK.button = b
    return b
end

-- casting, channelling (the line out) or a loot window open
local function Busy()
    if Ask(UnitChannelInfo, "player") or Ask(UnitCastingInfo, "player") then return true end
    return LootFrame ~= nil and LootFrame.IsShown ~= nil and LootFrame:IsShown() == true
end

-- something by you the Interact key acts on (a node, a chest, an NPC)
local function InReach()
    local soft = Ask(UnitExists, "softinteract") or Ask(UnitIsGameObject, "softinteract")
    return soft and Ask(UnitIsInInteractRange, "softinteract") == true
end

local function LureLeft()
    return ns.Lure and ns.Lure.Left and ns.Lure.Left()
end

-- the best lure in the bags to put on, when the pole has none
local function LureToUse(now)
    if ns.db.fish.oneKeyLure == false or LureLeft() then return nil end
    local count = GetItemCount or (C_Item and C_Item.GetItemCount)
    for _, id in ipairs(OK.LURES) do
        if (Ask(count, id) or 0) > 0 and not (tried[id] and now - tried[id] < OK.LURE_RETRY) then return id end
    end
end

-- what the key should do now: nil, "cast", or "lure" and which
function OK.Want(now)
    if not OK.Wanted() or InCombat() or Busy() or now < holdUntil or InReach() then return nil end
    local lure = LureToUse(now)
    if lure then return "lure", lure end
    return "cast"
end

function OK.Update(now)
    now = now or GetTime()
    if InCombat() then return end -- the bindings were let go as combat began
    if lureItem and now >= lureAt + OK.LURE_CHECK then
        if not LureLeft() then tried[lureItem] = now end -- not for your skill, or none left
        lureItem = nil
    end
    local want, item = OK.Want(now)
    if want == mode and item == boundItem then return end
    if not want then
        Release()
        return
    end
    local keys = OK.Keys()
    local b = #keys > 0 and SetOverrideBindingClick and Button()
    local spell = SpellName()
    if not (b and (want == "lure" or spell)) then
        Release()
        return
    end
    if want == "cast" then
        b:SetAttribute("type", "spell")
        b:SetAttribute("spell", spell)
    else
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/use item:" .. item .. "\n/use 16")
    end
    -- the game's buttons act on the press or the release (its key-down
    -- setting): ours too, once, not on both
    local down = C_CVar and Ask(C_CVar.GetCVar, "ActionButtonUseKeyDown") == "1"
    b:RegisterForClicks(down and "AnyDown" or "AnyUp")
    if mode then pcall(ClearOverrideBindings, owner) end
    for _, key in ipairs(keys) do pcall(SetOverrideBindingClick, owner, true, key, OK.BUTTON) end
    mode, boundItem = want, item
end

---------------------------------------------------------------------------
-- The one key for everything, set from the Fishing tab: the game's Interact
-- binding (it gathers, opens and, with the pole, casts and loots)
---------------------------------------------------------------------------

function OK.KeyName(key)
    return (GetBindingText and Ask(GetBindingText, key)) or key
end

-- the Interact keys as the game writes them ("F / Button 4"), or nil
function OK.KeyText()
    local keys = OK.Keys()
    if #keys == 0 then return nil end
    for i, key in ipairs(keys) do keys[i] = OK.KeyName(key) end
    return table.concat(keys, " / ")
end

local function SaveKeys()
    local set = GetCurrentBindingSet and Ask(GetCurrentBindingSet)
    if SaveBindings and set then pcall(SaveBindings, set) end
end

-- key: as the game names it ("F", "SHIFT-G", "BUTTON4"). The Interact keys
-- you had stay; what the key did before is said.
function OK.Bind(key)
    if InCombat() then
        ns.Print(ns.L.KEY_COMBAT)
        return false
    end
    if not (SetBinding and key) then return false end
    local before = GetBindingAction and Ask(GetBindingAction, key) or ""
    if not pcall(SetBinding, key, "INTERACTTARGET") then return false end
    SaveKeys()
    local name = OK.KeyName(key)
    ns.Print(ns.L.KEY_SET:format(name))
    if before ~= "" and before ~= "INTERACTTARGET" then
        ns.Print(ns.L.KEY_WAS:format(name, _G["BINDING_NAME_" .. before] or before))
    end
    return true
end

-- Interact on no key at all
function OK.Unbind()
    if InCombat() then
        ns.Print(ns.L.KEY_COMBAT)
        return false
    end
    if not SetBinding then return false end
    for _, key in ipairs(OK.Keys()) do pcall(SetBinding, key) end
    SaveKeys()
    ns.Print(ns.L.KEY_CLEARED)
    return true
end

local since = 0
owner:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < OK.EVERY then return end
    since = 0
    OK.Update()
end)

-- looks only while it can be wanted; the key is the game's otherwise
local function Watch()
    local on = OK.Wanted()
    owner:SetShown(on)
    if on then OK.Update() else Release() end
end
OK.Watch = Watch

owner:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        Release() -- combat about to start: bindings can still change now
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
        Watch()
    elseif unit == nil or unit == "player" then
        if OK.Wanted() then OK.Update() end
    end
end)
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED",
    "UPDATE_BINDINGS", "PLAYER_SOFT_INTERACT_CHANGED", "BAG_UPDATE", "UNIT_INVENTORY_CHANGED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "LOOT_OPENED", "LOOT_CLOSED" }) do
    pcall(owner.RegisterEvent, owner, event)
end
ns.On("Enable", Watch)
ns.On("Changed", function(key)
    if key == "fish.oneKeyLure" and OK.Wanted() then OK.Update() end
    if key == "*" or key == "enabled" or key == "fish.oneKey" then
        Watch()
        if key == "fish.oneKey" and ns.db.fish.oneKey and #OK.Keys() == 0 then
            ns.Print(ns.L.ONE_KEY_NO_KEY)
        end
    end
end)
