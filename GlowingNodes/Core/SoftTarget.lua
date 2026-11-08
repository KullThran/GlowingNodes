-- SoftTarget.lua
-- Addons can't see world objects, with one exception: the game's soft
-- targeting picks one interaction target ("softinteract", the node or corpse
-- the Interact Key would use, the nearest one up to about 40 yards) and, with
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
local RANGE = 60 -- the default asked of the game; /gn range <yards> tries others
local MAX_RANGE = 500
-- Forever's own limit on nameplates of world objects (30 by default): the glow
-- hangs on that nameplate, so it is raised along with the soft-target range
local OBJECT_PLATE_RANGE = 60

local CVARS = {
    "SoftTargetInteract", "SoftTargetIconGameObject", "SoftTargetInteractRange",
    "SoftTargetInteractArc", "SoftTargetInteractOnlyInRange", "SoftTargetNameplateInteract",
    "nameplateGameObjectMaxDistance", "SoftTargetMatchLocked",
}

local CURSOR_KEYWORDS = {
    { "gather", "herb" }, { "herb", "herb" },
    { "mine", "ore" }, { "mining", "ore" },
    { "skin", "skin" },
    -- chests, lockboxes and the things quests send you to pick up; a plain
    -- "interact" (mailboxes, doors, chairs) is not one
    { "lootall", "chest" }, { "pickup", "chest" }, { "picklock", "chest" }, { "quest", "chest" },
    { "interact", "other" },
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

-- The gate is a CVar the game keeps on the server: written too often, the
-- server answers "You're doing that too fast". So it is written at most once
-- a second, and it stays open a moment after the glow goes, which keeps it
-- still while the Interact Key hops between a mob and a corpse or a node.
local GATE_EVERY = 1.0
local GATE_CLOSE_AFTER = 2.0
local gateWant, gateWantSince, gateWritten = nil, 0, -100

local function FlushGate(force)
    if gateWant == nil or InCombatLockdown() then return end
    -- the setting as it really is: another addon that drives the same
    -- nameplate, or the game's options, may have
    -- changed it behind our back, and a remembered "open" would keep the glow
    -- off while the game has already picked the node
    local actual = GetCV("SoftTargetNameplateInteract")
    if actual ~= nil then gateOpen = actual == "1" end
    if gateWant == gateOpen then return end
    local now = GetTime()
    if not force then
        if now - gateWritten < GATE_EVERY then return end
        if not gateWant and now - gateWantSince < GATE_CLOSE_AFTER then return end
    end
    gateOpen = gateWant
    gateWritten = now
    ns.Debug(("GATE %s at %.1f"):format(gateOpen and "open" or "closed", now))
    SetCV("SoftTargetNameplateInteract", gateOpen and 1 or 0)
end

local function SetGate(open, force)
    if open ~= gateWant then
        gateWant = open
        gateWantSince = GetTime()
    end
    FlushGate(force)
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
    SetCV("SoftTargetInteractRange", ST.Range())
    SetCV("SoftTargetInteractArc", 2)        -- all around, not only ahead
    SetCV("SoftTargetInteractOnlyInRange", 0) -- also nodes a few steps away
    SetCV("nameplateGameObjectMaxDistance", math.max(ST.Range(), OBJECT_PLATE_RANGE))
    -- By default the game moves the Interact Key to whatever you have
    -- selected (the mob you just killed, an NPC), and the node by you loses
    -- its pick, and its glow. Off, the key stays on what's nearest.
    if ns.db.keepOnNode then
        SetCV("SoftTargetMatchLocked", 0)
    elseif saved.SoftTargetMatchLocked then
        SetCV("SoftTargetMatchLocked", saved.SoftTargetMatchLocked)
    end
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
        for _, pair in ipairs({ { "Mine", "ore" }, { "GatherHerbs", "herb" }, { "Skin", "skin" }, { "Pickup", "chest" },
            { "LootAll", "chest" }, { "Interact", "other" }, { "PickLock", "chest" }, { "Quest", "chest" } }) do
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

-- Tooltip lines of a unit (corpses). C_TooltipInfo only reads data. A hidden
-- GameTooltip is for clients without it: on clients that have it, SetUnit on
-- our own tooltip runs Blizzard's tooltip code with the unit's secret GUID
-- and taints it (a "Lua Taint: GlowingNodes" error on every poll).
local scanTip
local function TooltipLines(unit)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = Safe(C_TooltipInfo.GetUnit, unit)
        if type(data) == "table" and type(data.lines) == "table" then
            for _, line in ipairs(data.lines) do
                local text = type(line) == "table" and line.leftText
                if type(text) == "string" and not IsSecret(text) then
                    lines[#lines + 1] = text
                end
            end
        end
        return lines
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
    -- a corpse whose GUID the game keeps secret is cached as "the corpse in
    -- front of you", briefly, so it isn't read again on every poll
    local key, keep = guid, 2
    if not key or IsSecret(key) then key, keep = "?", 0.5 end
    local cached = corpseCache[key]
    if cached and now - cached.t < keep then return cached.category, cached.blocked, cached.tooltipLevel end
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
    corpseCache[key] = { t = now, category = cat, blocked = blocked, tooltipLevel = tooltipLevel }
    return cat, blocked, tooltipLevel
end

---------------------------------------------------------------------------
-- Target and nameplate
---------------------------------------------------------------------------

local function GetPlate(unit)
    return C_NamePlate and Safe(C_NamePlate.GetNamePlateForUnit, unit)
end

-- What the glow hangs on: the nameplate itself. Not its UnitFrame: on world
-- objects Blizzard keeps the UnitFrame hidden (seen in game: UnitFrame
-- visible false, alpha 0, the nameplate visible), and a glow hung there was
-- hidden with it.
local function PlateAnchor(plate)
    return plate
end
ST.PlateAnchor = PlateAnchor

local function PlateUnit(plate)
    local unit = plate.namePlateUnitToken
    if type(unit) ~= "string" then
        local uf = plate.UnitFrame
        unit = type(uf) == "table" and uf.unit or nil
    end
    if type(unit) == "string" and not IsSecret(unit) then return unit end
end

-- The soft target's nameplate: asked for by name, then looked for among the
-- nameplates the game has up (a world object that is the soft target).
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
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, p in ipairs(plates) do
                local unit = PlateUnit(p)
                if unit and Safe(UnitIsGameObject, unit) == true and Safe(UnitIsUnit, unit, SOFT) == true then
                    return SOFT, p -- the same object: asked about as the soft target
                end
            end
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

-- At the edge of reach the game's answer flips from one poll to the next: a
-- new state shows once it has held a moment, or the glow would flare and
-- change on every poll. A node just picked shows its state at once.
local STATE_HOLD = 0.2

local function Settle(target, state)
    if target.shownState == nil or state == target.shownState then
        target.shownState, target.nextState = state, nil
        return state
    end
    local now = GetTime()
    if target.nextState ~= state then
        target.nextState, target.nextSince = state, now
    elseif now - target.nextSince >= STATE_HOLD then
        target.shownState, target.nextState = state, nil
    end
    return target.shownState
end

local function GlowOptions()
    local db = ns.db
    return { numberSize = db.numberSize, greyLocked = db.greyLocked, dimFar = db.dimFar, scale = 1 }
end

---------------------------------------------------------------------------
-- The loop
---------------------------------------------------------------------------

local shownAt
local function Release(why)
    if glow and glow:IsShown() then
        if ns.db and ns.db.debug then
            ns.Debug(("RELEASE (%s) after %.1f s"):format(why or "?", GetTime() - (shownAt or GetTime())))
        end
        glow:Hide()
    end
end

-- debug: what the glow and the nameplate look like while it's up
local function V(region, method)
    if not region or not region[method] then return "?" end
    local ok, v = pcall(region[method], region)
    if not ok or IsSecret(v) then return "?" end
    if type(v) == "number" then return ("%.2f"):format(v) end
    return tostring(v)
end

local function Watch(target, plate)
    if not (ns.db.debug and glow and glow:IsShown() and target) then return end
    target.watched = target.watched or 0
    if target.watched >= 4 or GetTime() - (target.watchAt or 0) < 1 then return end
    target.watched, target.watchAt = target.watched + 1, GetTime()
    -- nothing that measures: nameplates are restricted regions, and asking
    -- where they are (GetCenter) is refused and taints
    local f, a = glow.frame, glow.anchor
    ns.Debug(("WATCH %s: glow shown %s visible %s alpha %s/%s strata %s; anchor %s visible %s alpha %s; plate shown %s visible %s alpha %s strata %s; state %s, fade-in %.2f"):format(
        tostring(target.name), V(f, "IsShown"), V(f, "IsVisible"), V(f, "GetAlpha"), V(f, "GetEffectiveAlpha"),
        V(f, "GetFrameStrata"), a == plate and "plate" or "UnitFrame", V(a, "IsVisible"), V(a, "GetEffectiveAlpha"),
        V(plate, "IsShown"), V(plate, "IsVisible"), V(plate, "GetEffectiveAlpha"), V(plate, "GetFrameStrata"),
        tostring(target.state), glow.appear or -1))
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

-- for the debug log: what the game hides about a node it won't name (in
-- instances it may keep the GUID, name and position secret)
local function Hidden(unit)
    local function What(fn, ...)
        if not fn then return "absent" end
        local ok, v = pcall(fn, ...)
        if not ok then return "error" end
        if IsSecret(v) then return "secret" end
        return tostring(v)
    end
    local lines = TooltipLines(unit)
    local instanceType = IsInInstance and select(2, IsInInstance())
    local mapID = C_Map and C_Map.GetBestMapForUnit and What(C_Map.GetBestMapForUnit, "player")
    local onMap = ns.Gather and ns.Gather.PlayerPosition and ns.Gather.PlayerPosition()
    return ("HIDDEN guid=%s name=%s tooltip %d lines [%s] instance=%s map=%s map position=%s"):format(
        What(UnitGUID, unit), What(UnitName, unit), #lines, table.concat(lines, " | "),
        tostring(instanceType), tostring(mapID), onMap and "yes" or "no")
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
        Release("off")
        ST.current = nil
        return
    end
    local unit, plate, unknown = Resolve()
    if not unit then
        SetGate(unknown == true) -- in doubt, let the game show its target
        Release(unknown and "the game won't say what's targeted" or "nothing targeted")
        ST.current = nil
        return
    end

    local guid = Safe(UnitGUID, unit)
    -- what tells this target from the last one: its GUID, or, where the game
    -- keeps that secret, its name and kind (else it would be a new node on
    -- every poll: fade-in, sound and alert over and over)
    local name = Safe(UnitName, unit)
    local isObject = Safe(UnitIsGameObject, unit) == true
    -- an object's name the game keeps secret (in instances): its tooltip's
    -- first line, if that is readable
    if not guid and not name and isObject then name = TooltipLines(unit)[1] end
    local id = guid or ("?" .. tostring(name) .. (isObject and "|o" or "|u"))
    local previous = ST.current
    local target
    if previous and previous.id == id then
        target = previous
    else
        -- hidden: the game gives neither its GUID nor its name (in dungeons)
        target = { id = id, guid = guid, name = name, hidden = isObject and not guid and not name }
        local kind, objectID = ParseGUID(guid)
        -- a GUID the game keeps secret still leaves its kind
        isObject = isObject or kind == "GameObject"
        if not kind and isObject then kind = "GameObject" end
        target.kind = kind
        if isObject then
            target.objectID = objectID
            local cat, blocked = CursorCategory(unit)
            if cat ~= "ore" and cat ~= "herb" then
                local dataCat = Data.Lookup(objectID, target.name, nil)
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
        target.pickedTime = GetTime()
        if target.kind == "GameObject" and target.category then
            ns.Debug(("PICK %s (%s) at %.1f, nameplate setting %s%s"):format(tostring(target.name), target.category,
                target.pickedTime, tostring(GetCV("SoftTargetNameplateInteract")),
                InCombatLockdown() and ", IN COMBAT: the setting can't change until it ends" or ""))
            if not (guid and target.name) then ns.Debug(Hidden(unit)) end
        end
        -- where the game picked it, to tell its range from the nameplate's
        if target.category == "ore" or target.category == "herb" then
            target.pickedAt = { PlayerPosition() }
        end
        local memory = seen[id]
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
    local profession = ns.PROFESSIONS[target.category] == true
    local skill = profession and Skills.Get(target.category) or nil
    local hasProf = skill ~= nil
    -- "only professions I have" is about professions: chests always count
    local wanted = cfg ~= nil and cfg.enabled and not (profession and db.onlyKnown and not hasProf)
    SetGate(wanted)
    ST.current = target
    if not wanted or not plate then
        -- without a plate the gate has just been opened: the glow (and its
        -- sound) follow on the next tick, when the game has made the plate
        Release(not wanted and "not a node we glow" or "the nameplate is gone")
        if not wanted and not target.logged then
            target.logged = true
            -- living mobs are no news: only objects and corpses are logged
            if target.kind == "GameObject" then ns.Debug(Describe(target)) end
        elseif wanted then
            -- the gate is open but the game gives this node no nameplate
            target.waitSince = target.waitSince or GetTime()
            if not target.noPlateLogged and GetTime() - target.waitSince > 1.5 then
                target.noPlateLogged = true
                ns.Debug(("NO PLATE %s; nameplate setting %s, in combat %s"):format(Describe(target),
                    tostring(GetCV("SoftTargetNameplateInteract")), tostring(InCombatLockdown() and true or false)))
            end
        end
        return
    end

    local required, source = Skills.Required(target)
    target.required, target.source, target.skill = required, source, skill
    -- The game greys the cursor ("Unable…") for a node out of reach too, so
    -- what it showed when the node was picked far off says nothing: it is read
    -- again on every poll, and it only means "level too low" for a node whose
    -- level isn't known; a known level is trusted over it.
    if target.kind == "GameObject" then
        local cat, blocked = CursorCategory(unit)
        if cat then target.blocked = blocked end
    end
    local locked = profession and not hasProf or false
    if hasProf then
        if required then
            locked = skill < required
        else
            locked = target.blocked or false
        end
    end
    local state = Settle(target, ReadState(unit, locked))
    target.state = state
    -- in reach as the client says it: the map log takes the spot as exact
    -- only then (an unanswered question is not a yes)
    target.inReach = UnitIsInInteractRange ~= nil and Safe(UnitIsInInteractRange, unit) == true
    local inRange = state ~= "far"

    if not glow then glow = Glow.New(nil) end
    local anchor = PlateAnchor(plate)
    if glow.anchor ~= anchor or target.isNew then
        glow:Configure(cfg, GlowOptions())
        glow:Attach(anchor, 0, db.height, true)
        shownAt = GetTime()
        glow:Show(state, target.found)
    else
        glow:SetState(state)
    end
    if db.showNumber and profession and not target.hidden then
        local text, r, g, b = Glow.NumberFor(required, skill, db.showMine, hasProf)
        glow:SetNumber(text, r, g, b)
    else
        glow:SetNumber("")
    end

    target.isNew = false
    Watch(target, plate)
    Announce(target)
    if not target.found then
        target.found = true
        target.foundAt = { PlayerPosition() }
        local rel = Glow.PlateRel and Glow.PlateRel(plate)
        ns.Debug(("GLOW %s #%s, %.1f s after the game picked it, nameplate at %s%% of the UI's size"):format(
            tostring(target.name), tostring(guid and guid:sub(-8)), GetTime() - (target.pickedTime or GetTime()),
            rel and ("%d"):format(rel * 100 + 0.5) or "?"))
        ns.Fire("NodeFound", target)
    else
        ns.Fire("NodeUpdate", target)
    end
    if inRange and db.debug and target.foundAt and not target.measured then
        target.measured = true
        ST:Measure(target)
    end
    seen[id] = { t = GetTime(), foundAt = target.foundAt, pickedAt = target.pickedAt, measured = target.measured }
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
-- the pick range asked of the game: the profile's (/gn range <yards>) or 60
function ST.Range()
    local r = ns.db and tonumber(ns.db.pickRange)
    if r and r >= 10 and r <= MAX_RANGE then return r end
    return RANGE
end

-- /gn range <yards>: ask the game for that pick range and object nameplate
-- distance, and say what it really keeps (it may cap them)
function ST:SetRange(yards)
    yards = math.floor(math.max(10, math.min(MAX_RANGE, yards)) + 0.5)
    ns.db.pickRange = yards
    if InCombatLockdown() then
        pending = "apply"
    else
        ST:ApplyCVars()
    end
    ST:PrintRange()
end

function ST:PrintRange()
    ns.Print(L.MSG_RANGE:format(ST.Range(), tostring(GetCV("SoftTargetInteractRange"))))
    ns.Print(L.MSG_PLATE_RANGE:format(tostring(GetCV("nameplateMaxDistance")), tostring(GetCV("nameplateGameObjectMaxDistance"))))
    local function cv(name)
        local v = GetCV(name)
        local d = C_CVar and C_CVar.GetCVarDefault and Safe(C_CVar.GetCVarDefault, name)
        return ("%s = %s (default %s)"):format(name, tostring(v), tostring(d))
    end
    local extra = { cv("SoftTargetInteractRangeIsHard"), cv("SoftTargetWorldtextFarDist"),
        cv("SoftTargetWorldtextNearDist"), cv("SoftTargetInteractArc") }
    ns.Print(table.concat(extra, "; "))
    ns.Debug("RANGE " .. table.concat(extra, "; "))
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
            Release("off")
            ST:RestoreCVars()
        end
        ST.current = nil
        ST.poller:SetShown(ns.db.enabled)
    end
    if glow and glow.anchor and ST.current and ST.current.category then
        local cfg = ns.db[ST.current.category]
        if cfg then glow:Configure(cfg, GlowOptions()) end
        glow:Attach(glow.anchor, 0, ns.db.height, true)
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
    if ns.db.enabled then SetGate(false, true) end
    Release("combat started")
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
    if glow and plate and (glow.anchor == plate or glow.anchor == PlateAnchor(plate)) then Release("the game removed the nameplate") end
end

function handlers.PLAYER_SOFT_INTERACT_CHANGED()
    -- another target: what was read of "the corpse in front" is about the last one
    corpseCache["?"] = nil
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

local HARD = { enabled = true, keepInteract = true, keepOnNode = true, onlyKnown = true, ["*"] = true }

ns.On("Changed", function(key)
    local hard = HARD[key] or (type(key) == "string" and key:find("%.enabled$") ~= nil and not key:find("^alert%."))
    ST:Refresh(key == "enabled" or key == "keepInteract", hard)
end)
