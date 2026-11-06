-- SoftTarget.lua
-- Addons can't see world objects, with one exception: the game's soft
-- targeting picks one interaction target ("softinteract", the node or corpse
-- the Interact Key would use, the nearest one within ~15 yards) and, with
-- SoftTargetNameplateInteract on, gives it a nameplate. The glow hangs on that
-- nameplate. The nameplate is only switched on ("the gate") for targets that
-- glow, so NPCs, mailboxes and chairs keep working as usual.
-- Kind of node: from its cursor icon (Mine / GatherHerbs / Skin, greyed out
-- "Unable…" when the game refuses), else from NodeData by ID and name.
-- Approach first shown to work on Forever by Forever Loot Sparkles (GPL-3.0).
local _, ns = ...
local L = ns.L
local Data, Skills, Glow, Sounds = ns.NodeData, ns.Skills, ns.Glow, ns.Sounds

local ST = {}
ns.SoftTarget = ST
ST.current = nil

local SOFT = "softinteract"
local POLL = 0.1
local RANGE = 60 -- asked as far as it goes
-- Forever's own limit on nameplates of world objects (30 by default): the glow
-- hangs on that nameplate, so it is raised along with the soft-target range
local OBJECT_PLATE_RANGE = 60

local CVARS = {
    "SoftTargetInteract", "SoftTargetIconGameObject", "SoftTargetInteractRange",
    "SoftTargetInteractArc", "SoftTargetInteractOnlyInRange", "SoftTargetNameplateInteract",
    "nameplateGameObjectMaxDistance",
}

local CURSOR_KEYWORDS = {
    { "gather", "herb" }, { "herb", "herb" },
    { "mine", "ore" }, { "mining", "ore" },
    { "skin", "skin" },
    { "lootall", "other" }, { "pickup", "other" }, { "picklock", "other" },
    { "interact", "other" }, { "quest", "other" },
}

local glow             -- the one in-world glow
local PlayerPosition
local gateOpen         -- SoftTargetNameplateInteract as we last set it (nil: unknown)
local pending          -- "apply" / "restore" after combat
local activePlates = {}
local corpseCache = {} -- guid -> { t, category, tooltipLevel }
-- Nodes seen lately. The interact key can hop between a node and a mob next
-- to it; coming back to the node must not flash, sound or alert again.
local seen = {}         -- guid -> { t, foundAt, measured }
local SEEN_FOR = 30
local tooltipLevels = {} -- lower name -> level read from the world tooltip

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function Safe(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) then return nil end
    return v
end

---------------------------------------------------------------------------
-- CVars
---------------------------------------------------------------------------

local function GetCV(name)
    local ok, v = pcall(C_CVar.GetCVar, name)
    if ok then return v end
end

local function SetCV(name, value)
    value = tostring(value)
    local current = GetCV(name)
    if current == nil or current == value then return end
    pcall(C_CVar.SetCVar, name, value)
end

local function SetGate(open)
    if open == gateOpen or InCombatLockdown() then return end
    gateOpen = open
    SetCV("SoftTargetNameplateInteract", open and 1 or 0)
end

local function Saved()
    ns.global.savedCVars = ns.global.savedCVars or {}
    return ns.global.savedCVars
end

function ST:ApplyCVars(force)
    if InCombatLockdown() then pending = "apply" return end
    local saved = Saved()
    local first = saved.SoftTargetInteract == nil
    for _, name in ipairs(CVARS) do
        if saved[name] == nil then saved[name] = GetCV(name) or false end
    end
    if first or force or ns.db.keepInteract then
        SetCV("SoftTargetInteract", 3)       -- Interact Key on, for everything
        SetCV("SoftTargetIconGameObject", 1) -- world objects get a nameplate at all
    end
    SetCV("SoftTargetInteractRange", RANGE)
    SetCV("SoftTargetInteractArc", 2)        -- all around, not only ahead
    SetCV("SoftTargetInteractOnlyInRange", 0) -- also nodes a few steps away
    SetCV("nameplateGameObjectMaxDistance", OBJECT_PLATE_RANGE)
    gateOpen = nil
end

function ST:RestoreCVars()
    if InCombatLockdown() then pending = "restore" return end
    local saved = ns.global.savedCVars
    if not saved then return end
    for name, value in pairs(saved) do
        if value ~= false then SetCV(name, value) end
    end
    ns.global.savedCVars = nil
    gateOpen = nil
end

function ST:InteractKeyOn()
    local v = tonumber(GetCV("SoftTargetInteract"))
    return v ~= nil and v > 0
end

---------------------------------------------------------------------------
-- Classification
---------------------------------------------------------------------------

local probe = UIParent:CreateTexture(nil, "BACKGROUND")
probe:Hide()

local function ReadCursorName(name)
    if type(name) ~= "string" then return nil end
    name = name:lower()
    local blocked = name:find("unable", 1, true) ~= nil
    for _, entry in ipairs(CURSOR_KEYWORDS) do
        if name:find(entry[1], 1, true) then return entry[2], blocked end
    end
    return nil, blocked
end

local cursorIDs
local function CursorIDs()
    if cursorIDs then return cursorIDs end
    cursorIDs = {}
    if GetFileIDFromPath then
        for _, pair in ipairs({ { "Mine", "ore" }, { "GatherHerbs", "herb" }, { "Skin", "skin" }, { "Pickup", "other" },
            { "LootAll", "other" }, { "Interact", "other" }, { "PickLock", "other" }, { "Quest", "other" } }) do
            for _, prefix in ipairs({ "", "Unable" }) do
                local path = "Interface\\Cursor\\" .. prefix .. pair[1]
                local id = Safe(GetFileIDFromPath, path) or Safe(GetFileIDFromPath, path .. ".blp")
                if id then cursorIDs[id] = { pair[2], prefix ~= "" } end
            end
        end
    end
    return cursorIDs
end

-- category ("ore"/"herb"/"skin"/"other"/nil) and greyed-out flag from the cursor
local function CursorCategory(unit)
    if not SetUnitCursorTexture then return nil end
    if not Safe(SetUnitCursorTexture, probe, unit, nil, true) then return nil end
    local tex = probe:GetTexture()
    local atlas = probe.GetAtlas and probe:GetAtlas()
    if IsSecret(tex) then tex = nil end
    if IsSecret(atlas) then atlas = nil end
    local known = type(tex) == "number" and CursorIDs()[tex]
    if known then return known[1], known[2] end
    local cat, blocked = ReadCursorName(tex)
    if not cat then
        local c2, b2 = ReadCursorName(atlas)
        cat, blocked = c2, blocked or b2
    end
    return cat, blocked or false
end

local function ParseGUID(guid)
    if type(guid) ~= "string" or IsSecret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    return kind, tonumber(id)
end

-- Tooltip lines of a unit (corpses), modern API first, then a hidden tooltip
local scanTip
local function TooltipLines(unit)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = Safe(C_TooltipInfo.GetUnit, unit)
        if type(data) == "table" and data.lines then
            for _, line in ipairs(data.lines) do
                if type(line.leftText) == "string" and not IsSecret(line.leftText) then
                    lines[#lines + 1] = line.leftText
                end
            end
            if #lines > 0 then return lines end
        end
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "GlowingNodesScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    if pcall(scanTip.SetUnit, scanTip, unit) then
        for i = 1, scanTip:NumLines() do
            local fs = _G["GlowingNodesScanTipTextLeft" .. i]
            local text = fs and fs:GetText()
            if type(text) == "string" and not IsSecret(text) then lines[#lines + 1] = text end
        end
    end
    scanTip:Hide()
    return lines
end

local function SkinnableKind(lines)
    local leather, rock, herb = _G.UNIT_SKINNABLE_LEATHER, _G.UNIT_SKINNABLE_ROCK, _G.UNIT_SKINNABLE_HERB
    for _, text in ipairs(lines) do
        if leather and text:find(leather, 1, true) then return "skin" end
        if rock and text:find(rock, 1, true) then return "ore" end
        if herb and text:find(herb, 1, true) then return "herb" end
    end
end

local function HasLootLeft(guid)
    if not (guid and CanLootUnit) then return false end
    local ok, hasLoot = pcall(CanLootUnit, guid)
    return ok and not IsSecret(hasLoot) and hasLoot == true
end

-- A dead mob that can be skinned (or mined/herbed): its category, or nil
local function CorpseCategory(unit, guid)
    if Safe(UnitIsDead, unit) ~= true then return nil end
    if HasLootLeft(guid) then return nil end -- loot first, then skin
    local now = GetTime()
    local cached = guid and corpseCache[guid]
    if cached and now - cached.t < 2 then return cached.category, cached.blocked, cached.tooltipLevel end
    local cat, blocked = CursorCategory(unit)
    local tooltipLevel
    if cat ~= "skin" and cat ~= "ore" and cat ~= "herb" then
        local lines = TooltipLines(unit)
        cat = SkinnableKind(lines)
        for _, text in ipairs(lines) do
            local c, lvl = Skills.ParseRequirement(text)
            if c and lvl then tooltipLevel = lvl end
        end
    end
    if guid then corpseCache[guid] = { t = now, category = cat, blocked = blocked, tooltipLevel = tooltipLevel } end
    return cat, blocked, tooltipLevel
end

---------------------------------------------------------------------------
-- Target and nameplate
---------------------------------------------------------------------------

local function GetPlate(unit)
    return C_NamePlate and Safe(C_NamePlate.GetNamePlateForUnit, unit)
end

local function Resolve()
    local isUnit, isObject = Safe(UnitExists, SOFT), Safe(UnitIsGameObject, SOFT)
    if isUnit == false and isObject == false then return nil end
    local plate = GetPlate(SOFT)
    if plate then return SOFT, plate end
    for unit in pairs(activePlates) do
        if Safe(UnitIsUnit, unit, SOFT) == true then
            plate = GetPlate(unit)
            if plate then return unit, plate end
        end
    end
    if isUnit or isObject then return SOFT, nil end
    return nil, nil, true -- the client won't say
end

local function ReadState(unit, locked)
    local inRange = UnitIsInInteractRange and Safe(UnitIsInInteractRange, unit)
    if inRange == false then return "far" end
    if locked then return "locked" end
    return "ready"
end

local function GlowOptions()
    local db = ns.db
    return { numberSize = db.numberSize, greyLocked = db.greyLocked, dimFar = db.dimFar, scale = 1 }
end

---------------------------------------------------------------------------
-- The loop
---------------------------------------------------------------------------

local function Release()
    if glow and glow:IsShown() then glow:Hide() end
end

-- once per node, when its glow first shows (or first comes into reach)
local function Announce(target)
    if target.sounded then return end
    local cfg = ns.db[target.category]
    if not (cfg and cfg.soundOn) then return end
    if ns.db.soundOnReady and target.state ~= "ready" then return end
    target.sounded = true
    Sounds.PlayCategory(target.category)
end

local function Describe(t)
    if not t then return L.MSG_NO_TARGET end
    return ("%s [%s] id=%s cat=%s need=%s (%s) mine=%s state=%s%s"):format(
        tostring(t.name), tostring(t.kind), tostring(t.objectID), tostring(t.category),
        tostring(t.required), tostring(t.source), tostring(t.skill), tostring(t.state),
        t.blocked and " unable" or "")
end

-- Where the player stands, in yards (nil where the game hides it)
PlayerPosition = function()
    if not UnitPosition then return nil end
    local ok, y, x, _, instance = pcall(UnitPosition, "player")
    if ok and type(x) == "number" and not IsSecret(x) then return x, y, instance end
end

function ST:Evaluate()
    local db = ns.db
    if not db.enabled then
        Release()
        ST.current = nil
        return
    end
    local unit, plate, unknown = Resolve()
    if not unit then
        SetGate(unknown == true) -- in doubt, let the game show its target
        Release()
        ST.current = nil
        return
    end

    local guid = Safe(UnitGUID, unit)
    local previous = ST.current
    local target
    if previous and guid and previous.guid == guid then
        target = previous
    else
        target = { guid = guid, name = Safe(UnitName, unit) }
        local kind, id = ParseGUID(guid)
        target.kind = kind
        if Safe(UnitIsGameObject, unit) == true or kind == "GameObject" then
            target.objectID = id
            local cat, blocked = CursorCategory(unit)
            if cat ~= "ore" and cat ~= "herb" then
                local dataCat = Data.Lookup(id, target.name, nil)
                cat = dataCat or cat
            end
            target.category, target.blocked = cat, blocked
            target.tooltipLevel = target.name and tooltipLevels[Data.NormalizeName(target.name)]
        else
            local cat, blocked, tooltipLevel = CorpseCategory(unit, guid)
            target.category, target.blocked, target.tooltipLevel = cat, blocked, tooltipLevel
            target.corpse = cat ~= nil
            target.dead = Safe(UnitIsDead, unit) == true
            target.level = Safe(UnitLevel, unit)
        end
        target.isNew = true
        -- where the game picked it, to tell its range from the nameplate's
        if target.category == "ore" or target.category == "herb" then
            target.pickedAt = { PlayerPosition() }
        end
        local memory = guid and seen[guid]
        if memory and GetTime() - memory.t < SEEN_FOR then
            target.found, target.sounded, target.logged = true, true, true
            target.foundAt, target.measured = memory.foundAt, memory.measured
            target.pickedAt = memory.pickedAt
        end
    end
    -- a corpse looted just now becomes skinnable: look again
    if target.kind ~= "GameObject" and not target.category and not target.objectID then
        local cat, blocked, tooltipLevel = CorpseCategory(unit, guid)
        if cat then
            target.category, target.blocked, target.tooltipLevel, target.corpse = cat, blocked, tooltipLevel, true
            target.level = Safe(UnitLevel, unit)
            target.isNew = true
        end
    end

    local cfg = target.category and db[target.category]
    local skill = target.category and Skills.Get(target.category)
    local hasProf = skill ~= nil
    local wanted = cfg ~= nil and cfg.enabled and not (db.onlyKnown and not hasProf)
    SetGate(wanted)
    ST.current = target
    if not wanted or not plate then
        -- without a plate the gate has just been opened: the glow (and its
        -- sound) follow on the next tick, when the game has made the plate
        Release()
        if not wanted and not target.logged then
            target.logged = true
            -- living mobs are no news: only objects and corpses are logged
            if target.kind == "GameObject" then ns.Debug(Describe(target)) end
        elseif wanted then
            -- the gate is open but the game gives this node no nameplate
            target.waitSince = target.waitSince or GetTime()
            if not target.noPlateLogged and GetTime() - target.waitSince > 1.5 then
                target.noPlateLogged = true
                ns.Debug("NO PLATE " .. Describe(target))
            end
        end
        return
    end

    local required, source = Skills.Required(target)
    target.required, target.source, target.skill = required, source, skill
    local locked = target.blocked or not hasProf or (required and skill < required) or false
    local state = ReadState(unit, locked)
    target.state = state
    local inRange = state ~= "far"

    if not glow then glow = Glow.New(nil) end
    if glow.anchor ~= plate or target.isNew then
        glow:Configure(cfg, GlowOptions())
        glow:Attach(plate, 0, db.height)
        glow:Show(state)
    else
        glow:SetState(state)
    end
    if db.showNumber then
        local text, r, g, b = Glow.NumberFor(required, skill, db.showMine, hasProf)
        glow:SetNumber(text, r, g, b)
    else
        glow:SetNumber("")
    end

    target.isNew = false
    Announce(target)
    if not target.found then
        target.found = true
        target.foundAt = { PlayerPosition() }
        ns.Debug("GLOW " .. tostring(target.name) .. " #" .. tostring(guid and guid:sub(-8)))
        ns.Fire("NodeFound", target)
    else
        ns.Fire("NodeUpdate", target)
    end
    if inRange and db.debug and target.foundAt and not target.measured then
        target.measured = true
        ST:Measure(target)
    end
    if guid then
        seen[guid] = { t = GetTime(), foundAt = target.foundAt, pickedAt = target.pickedAt, measured = target.measured }
    end
    if not target.logged then
        target.logged = true
        ns.Debug(Describe(target))
    end
end

function ST:GetGlow()
    return glow
end

-- With debug on: how far away the node lit up, from where the player stood
-- then to where it came into reach (plus the reach itself, ~5 yards).
-- Exact when walking straight at it.
function ST:Measure(t)
    local x1, y1, i1 = PlayerPosition()
    local function dist(at)
        if not (at and at[1] and x1) or at[3] ~= i1 then return nil end
        return math.floor(math.sqrt((x1 - at[1]) ^ 2 + (y1 - at[2]) ^ 2) + 5.5)
    end
    local glowAt, pickedAt = dist(t.foundAt), dist(t.pickedAt)
    if not glowAt then
        ns.Print(L.MSG_NO_MEASURE)
        return
    end
    ns.Print(L.MSG_MEASURED:format(t.name or "?", pickedAt or glowAt, glowAt))
end

function ST:PrintInfo()
    ns.Print(Describe(ST.current))
end

-- /gn rango: how far the game really lets soft targeting reach, and whether
-- nodes show up as vignettes (what RareScanner uses), which would allow an
-- alert from further away than the glow can reach
function ST:PrintRange()
    ns.Print(L.MSG_RANGE:format(RANGE, tostring(GetCV("SoftTargetInteractRange"))))
    ns.Print(L.MSG_PLATE_RANGE:format(tostring(GetCV("nameplateMaxDistance")), tostring(GetCV("nameplateGameObjectMaxDistance"))))
    -- every console variable of this client about soft targeting, interaction
    -- or object distances, with its value and help text, kept in the saved
    -- variables (global.cvarScan) to look for a range setting of Forever's own
    local getAll = (C_Console and C_Console.GetAllCommands) or ConsoleGetAllCommands
    if not getAll then
        ns.Print(L.MSG_CVAR_NONE)
    else
        local list = Safe(getAll) or {}
        local scan = {}
        for _, cmd in ipairs(list) do
            local name = type(cmd) == "table" and cmd.command
            if type(name) == "string" then
                local lower = name:lower()
                if lower:find("softtarget", 1, true) or lower:find("interact", 1, true)
                    or lower:find("objectdist", 1, true) or lower:find("maxdist", 1, true)
                    or lower:find("range", 1, true) or lower:find("gather", 1, true)
                    or lower:find("nameplate", 1, true) or lower:find("object", 1, true)
                    or lower:find("unitname", 1, true) or lower:find("track", 1, true) then
                    scan[#scan + 1] = name .. " = " .. tostring(GetCV(name)) .. "   -- " .. tostring(cmd.help or "")
                end
            end
        end
        table.sort(scan)
        ns.global.cvarScan = scan
        ns.Print(L.MSG_CVAR_SCAN:format(#scan))
    end
    local V = C_VignetteInfo
    if not (V and V.GetVignettes and V.GetVignetteInfo) then
        ns.Print(L.MSG_NO_VIGNETTES)
        return
    end
    local count = 0
    for _, guid in ipairs(Safe(V.GetVignettes) or {}) do
        local info = Safe(V.GetVignetteInfo, guid)
        if type(info) == "table" and type(info.name) == "string" and not IsSecret(info.name) then
            count = count + 1
            if count <= 10 then ns.Print("   - " .. info.name) end
        end
    end
    ns.Print(L.MSG_VIGNETTES:format(count))
end

-- Called when settings change. hard: switch on/off, re-read the target.
-- Otherwise only the look changes, so the glow in front of the player
-- updates live without flashing in again or replaying its sound.
function ST:Refresh(force, hard)
    if hard then
        if ns.db.enabled then
            ST:ApplyCVars(force)
        else
            Release()
            ST:RestoreCVars()
        end
        ST.current = nil
        ST.poller:SetShown(ns.db.enabled)
    end
    if glow and glow.anchor and ST.current and ST.current.category then
        local cfg = ns.db[ST.current.category]
        if cfg then glow:Configure(cfg, GlowOptions()) end
        glow.frame:ClearAllPoints()
        glow.frame:SetPoint("CENTER", glow.anchor, "CENTER", 0, ns.db.height)
    end
end

---------------------------------------------------------------------------
-- World tooltip: "Requires Mining 65" on a node the mouse is over
---------------------------------------------------------------------------

local function ReadWorldTooltip(tip)
    if tip ~= GameTooltip or not tip:IsShown() then return end
    if Safe(UnitExists, "mouseover") then return end -- a unit, not an object
    local first = _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
    if type(first) ~= "string" or IsSecret(first) then return end
    for i = 2, tip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if type(text) == "string" and not IsSecret(text) then
            local cat, level = Skills.ParseRequirement(text)
            if cat and level then
                tooltipLevels[Data.NormalizeName(first)] = level
                local t = ST.current
                if t and t.name == first and t.category == cat then
                    Skills.Remember(t.objectID, t.name, level, cat)
                end
                return
            end
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

ST.poller = CreateFrame("Frame")
ST.poller:Hide()
local since = 0
ST.poller:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since >= POLL then
        since = 0
        ST:Evaluate()
    end
end)

local handlers = {}

function handlers.PLAYER_LOGIN()
    if ns.db.enabled then ST:ApplyCVars() end
    ST.poller:SetShown(ns.db.enabled)
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnShow", ReadWorldTooltip)
    end
end

-- account settings can arrive after login and overwrite ours
function handlers.PLAYER_ENTERING_WORLD()
    if ns.db.enabled then ST:ApplyCVars() end
end
handlers.VARIABLES_LOADED = handlers.PLAYER_ENTERING_WORLD

-- CVars can't change in combat: close the gate as the fight starts, or every
-- corpse would keep a 0% nameplate until it ends
function handlers.PLAYER_REGEN_DISABLED()
    if ns.db.enabled then SetGate(false) end
    Release()
end

function handlers.PLAYER_REGEN_ENABLED()
    if pending == "apply" then ST:ApplyCVars() elseif pending == "restore" then ST:RestoreCVars() end
    pending = nil
    ST.current = nil
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
    activePlates[unit] = true
    -- a world object with a nameplate of its own (not the soft target): if
    -- this ever shows up, every node in view could glow, not only the nearest
    if ns.db.debug and Safe(UnitIsGameObject, unit) == true and Safe(UnitIsUnit, unit, SOFT) ~= true then
        ns.Debug("OBJECT PLATE " .. tostring(Safe(UnitName, unit)) .. " (" .. unit .. ")")
    end
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
    activePlates[unit] = nil
    local plate = GetPlate(unit)
    if glow and plate and glow.anchor == plate then Release() end
end

function handlers.PLAYER_SOFT_INTERACT_CHANGED()
    if ns.db.enabled then ST:Evaluate() end
end

function handlers.LOOT_CLOSED()
    wipe(corpseCache) -- corpses just looted can be skinned now
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if ns.db and handlers[event] then handlers[event](...) end
end)
for event in pairs(handlers) do
    pcall(events.RegisterEvent, events, event)
end

local HARD = { enabled = true, keepInteract = true, onlyKnown = true, ["*"] = true }

ns.On("Changed", function(key)
    local hard = HARD[key] or (type(key) == "string" and key:find("%.enabled$") ~= nil and not key:find("^alert%."))
    ST:Refresh(key == "enabled" or key == "keepInteract", hard)
end)
