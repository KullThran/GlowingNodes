-- Navigator.lua
-- Where the arrow points: the nearest spot of ore or herbs you can gather,
-- from your log and (if the arrow uses it) the spawn database. The game only
-- picks a node some 15-40 yards off, so this takes you there and the glow
-- takes over. It sees no live nodes: the minimap's dots are secret to addons,
-- so a spot is where nodes spawn, not where one is now.
-- No Blizzard waypoint: nothing here touches C_Map waypoints, the super
-- track or C_Navigation, so other addons keep their destination.
-- With a fishing pole equipped (and arrow.fish on) it leads to fishing
-- pools instead, one after another: a pool can't be picked by the game, so
-- in reach it waits FISH_WAIT seconds, longer while you fish there.
-- Logic only; UI/Arrow.lua draws what Update returns.
local _, ns = ...

local Nav = {}
ns.Navigator = Nav

Nav.TICK = 0.2            -- seconds between updates (UI/Arrow.lua)
Nav.SWITCH = 0.8          -- a new spot must be this much nearer to take over
Nav.ARRIVE_YARDS = 25
Nav.WAIT = 4              -- seconds in reach without a node: the spot is empty
Nav.EMPTY_FOR = 600       -- an empty spot comes back after this long
Nav.GATHERED_YARDS = 30
Nav.EMPTY_YARDS = 20      -- a spot this close to one found empty is the same node
Nav.GATHERED_WITHIN = 2
Nav.DIM_ALPHA = 0.45
Nav.FISH_WAIT = 10        -- seconds at a pool without a cast: it isn't there now

local KINDS = { ore = true, herb = true }

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- fn's answer, or nil when it is missing, fails or is secret
local function Ask(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok or IsSecret(a) then return nil end
    return a, b, c
end

local function HBD() return LibStub and LibStub("HereBeDragons-2.0", true) end

-- a fishing pole in the main hand: weapon (class 2), fishing pole (subclass
-- 20), as the item's type says it in every language
local MAIN_HAND, WEAPON, FISHING_POLE = 16, 2, 20
function Nav.HasPole()
    local id = Ask(GetInventoryItemID, "player", MAIN_HAND)
    if not id then return false end
    local instant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
    if not instant then return false end
    local ok, _, _, _, _, _, class, subclass = pcall(instant, id)
    return ok and class == WEAPON and subclass == FISHING_POLE or false
end

-- pools, not veins and herbs, now
function Nav.FishMode()
    return ns.db ~= nil and ns.db.arrow.fish == true and Nav.HasPole()
end

---------------------------------------------------------------------------
-- Candidates
---------------------------------------------------------------------------

local cache = {}   -- mapID -> list of spots
local target       -- the spot the arrow points to
local view = {}    -- what Update returns (one table, reused)

-- a kind the arrow leads to now: its box, its glow and its profession on
local function Wanted(kind)
    local db = ns.db
    if not (KINDS[kind] and db.arrow[kind] and db[kind] and db[kind].enabled) then return nil end
    return ns.Skills.Get(kind)
end

-- a node above your skill counts only when the arrow is told to lead there too
local function Reachable(required, skill)
    return ns.db.arrow.unskilled == true or (required or 1) <= skill
end

local function Add(list, hbd, mapID, key, node, skills)
    local kind = node.k
    local skill = skills[kind]
    if not skill or not Reachable(node.r, skill) then return end
    if not ns.Catalog.ShownNode(node) then return end -- switched off in the Catalog tab
    local x, y = ns.Gather.Decode(key)
    local wx, wy, instance = Ask(hbd.GetWorldCoordinatesFromZone, hbd, x, y, mapID)
    if not (wx and wy) then return end
    list[#list + 1] = { key = key, mapID = mapID, wx = wx, wy = wy, instance = instance,
        category = kind, node = node }
end

local function AddPool(list, hbd, mapID, key, node)
    if node.k ~= "fish" then return end
    local x, y = ns.Gather.Decode(key)
    local wx, wy, instance = Ask(hbd.GetWorldCoordinatesFromZone, hbd, x, y, mapID)
    if not (wx and wy) then return end
    list[#list + 1] = { key = key, mapID = mapID, wx = wx, wy = wy, instance = instance,
        category = "fish", node = node }
end

-- this map's spots the arrow may lead to (built once, until something changes)
function Nav.Candidates(mapID)
    local fish = Nav.FishMode()
    if cache[mapID] and cache[mapID].fish == fish then return cache[mapID] end
    local list = { fish = fish }
    local hbd = HBD()
    if hbd and mapID and fish then
        -- your pools, and the database's; no skill, no Catalog, no bobber glow
        for key, node in pairs(ns.Gather.Zone(mapID) or {}) do AddPool(list, hbd, mapID, key, node) end
        if ns.ArrowUsesDatabase() then
            ns.NodeDB.Each(mapID, function(key, node) AddPool(list, hbd, mapID, key, node) end, true)
        end
    elseif hbd and mapID then
        local skills = { ore = Wanted("ore") or false, herb = Wanted("herb") or false }
        for key, node in pairs(ns.Gather.Zone(mapID) or {}) do
            if skills[node.k] then Add(list, hbd, mapID, key, node, skills) end
        end
        if ns.ArrowUsesDatabase() then
            ns.NodeDB.Each(mapID, function(key, node)
                if skills[node.k] then Add(list, hbd, mapID, key, node, skills) end
            end, true)
        end
    end
    cache[mapID] = list
    return list
end

-- Empty places: a spot reached with no node to pick, or where you just
-- gathered. Kept by position, not by key, so a point that moves a few yards
-- (a rough point made exact) or the same node twice (your log and the
-- database) stays empty too. This session only, until a node may have
-- spawned there again.
local empty = {}   -- { mapID, wx, wy, r, at }
local arrivedAt    -- when the player came within reach of the target

local function MarkAt(mapID, wx, wy, r, now)
    empty[#empty + 1] = { mapID = mapID, wx = wx, wy = wy, r = r, at = now }
end

function Nav.MarkEmpty(spot, now)
    MarkAt(spot.mapID, spot.wx, spot.wy, Nav.EMPTY_YARDS, now)
end

function Nav.IsEmpty(spot, now)
    for i = #empty, 1, -1 do
        local e = empty[i]
        if now - e.at >= Nav.EMPTY_FOR then
            table.remove(empty, i)
        elseif e.mapID == spot.mapID then
            local dx, dy = spot.wx - e.wx, spot.wy - e.wy
            if dx * dx + dy * dy <= e.r * e.r then return true end
        end
    end
    return false
end

local function SameSpot(a, b)
    return a ~= nil and b ~= nil and a.mapID == b.mapID and a.key == b.key
end

-- the spots are read again; the arrow keeps its target and its arrival
function Nav.Refresh()
    wipe(cache)
end

-- the settings changed: start over
function Nav.Reset()
    wipe(cache)
    target, arrivedAt = nil, nil
end

function Nav.Target() return target end

-- A spot picked on a map (a click on its point): the arrow leads there,
-- nearer nodes or not, above your skill too, until you reach it or click it
-- again. Kept when the settings change; one at a time.
local chosen

-- returns true when the arrow now leads there, false when that click let go
-- of it, nil when the spot can't be placed in the world
function Nav.Choose(mapID, key, node)
    if chosen and chosen.mapID == mapID and chosen.key == key then
        chosen = nil
        return false
    end
    local hbd = HBD()
    if not (hbd and mapID and key and node) then return nil end
    local x, y = ns.Gather.Decode(key)
    local wx, wy, instance = Ask(hbd.GetWorldCoordinatesFromZone, hbd, x, y, mapID)
    if not (wx and wy) then return nil end
    chosen = { key = key, mapID = mapID, wx = wx, wy = wy, instance = instance, category = node.k, node = node }
    arrivedAt = nil
    return true
end

function Nav.Chosen() return chosen end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

local function Hidden(reason)
    view.state, view.reason = "hidden", reason
    return view
end

-- why the arrow stays out of sight now, or nil
-- the glow has a node the arrow would lead to: it takes over from here
local function HandsOver(current)
    if not (current and KINDS[current.category] and not current.blocked) then return false end
    if Nav.FishMode() then return false end -- leading to pools: a vein's glow isn't where it goes
    local skill = Wanted(current.category)
    if not skill then return false end
    return Reachable(current.required, current.skill or skill)
end

local function Reason()
    if (InCombatLockdown and InCombatLockdown()) or Ask(UnitAffectingCombat, "player") then return "combat" end
    if Ask(IsInInstance) then return "instance" end
    if Ask(UnitOnTaxi, "player") then return "taxi" end
    if Ask(UnitIsDeadOrGhost, "player") then return "dead" end
end
Nav.Reason = Reason -- why the arrow hides now, or nil (/gn diag says it)

function Nav.Update(now)
    view.reason, view.angle, view.yards, view.category, view.node = nil, nil, nil, nil, nil
    if not (ns.db and ns.db.enabled and ns.db.arrow.enabled) then
        view.state = "off"
        return view
    end
    local why = Reason()
    if why then return Hidden(why) end
    local hbd = HBD()
    local mapID = hbd and ns.Gather.PlayerPosition()
    local px, py, instance
    if mapID then px, py, instance = Ask(hbd.GetPlayerWorldPosition, hbd) end
    local facing = Ask(GetPlayerFacing)
    if not (px and py and type(facing) == "number") then return Hidden("position") end
    if HandsOver(ns.SoftTarget and ns.SoftTarget.current) then
        arrivedAt = nil -- the glow has it: the spot isn't empty
        return Hidden("glowing")
    end

    local function Vector(spot)
        if spot.instance ~= nil and instance ~= nil and spot.instance ~= instance then return nil end
        return Ask(hbd.GetWorldVector, hbd, instance, px, py, spot.wx, spot.wy)
    end

    -- a spot picked on a map comes first; reached, it is let go, and the
    -- arrow goes on as before (the glow takes over at the node)
    if chosen then
        local angle, yards = Vector(chosen)
        if yards and yards <= Nav.ARRIVE_YARDS then
            chosen = nil
        elseif yards then
            if target ~= chosen then arrivedAt = nil end
            target = chosen
            view.state = "guide"
            view.angle = angle - facing
            view.yards = yards
            view.category = chosen.category
            view.node = chosen.node
            return view
        end
    end

    -- the nearest spot; the one in use keeps it unless another is clearly nearer
    local list = Nav.Candidates(mapID)
    local best, bestAngle, bestYards
    for _, spot in ipairs(list) do
        if not Nav.IsEmpty(spot, now) then
            local angle, yards = Vector(spot)
            if yards and (not bestYards or yards < bestYards) then
                best, bestAngle, bestYards = spot, angle, yards
            end
        end
    end
    local keep
    if target and target.mapID == mapID and not Nav.IsEmpty(target, now) then
        for _, spot in ipairs(list) do
            if SameSpot(spot, target) then keep = spot break end
        end
    end
    if keep and best ~= keep then
        local angle, yards = Vector(keep)
        if yards and not (bestYards < Nav.SWITCH * yards) then
            best, bestAngle, bestYards = keep, angle, yards
        end
    end
    if not SameSpot(best, target) then arrivedAt = nil end
    target = best
    if not best then
        view.state = "empty"
        return view
    end
    -- in reach and no node picked for a while: nothing there now. A pool is
    -- never picked: it waits longer, and while you fish there it stays
    if bestYards <= Nav.ARRIVE_YARDS then
        local pool = best.category == "fish"
        arrivedAt = arrivedAt or now
        if pool and ns.SoftTarget and ns.SoftTarget.Fishing and ns.SoftTarget.Fishing() then arrivedAt = now end
        local wait = pool and Nav.FISH_WAIT or Nav.WAIT
        if now - arrivedAt >= wait then
            local picked = ns.SoftTarget and ns.SoftTarget.current
            if pool then
                ns.Debug(("ARROW marked empty: pool %s, %d yd off, no cast in %d s"):format(
                    tostring(best.node and (best.node.n or best.node.en)), bestYards + 0.5, wait))
            else
                ns.Debug(("ARROW marked empty: %s, %d yd off, no node of yours picked in %d s (the game picks: %s)"):format(
                    tostring(best.node and (best.node.n or best.node.en)), bestYards + 0.5, wait,
                    picked and tostring(picked.name) .. " (" .. tostring(picked.category) .. ")" or "nothing"))
            end
            Nav.MarkEmpty(best, now)
            arrivedAt = nil
            return Nav.Update(now)
        end
    else
        arrivedAt = nil
    end
    view.state = "guide"
    view.angle = bestAngle - facing
    view.yards = bestYards
    view.category = best.category
    view.node = best.node
    return view
end

-- Between two picks, every frame: the same target, from where you stand and
-- the way you face now, so the arrow turns smoothly. One vector, no search.
function Nav.Track()
    if view.state ~= "guide" or not target then return view end
    local hbd = HBD()
    local px, py, instance = Ask(hbd and hbd.GetPlayerWorldPosition, hbd)
    local facing = Ask(GetPlayerFacing)
    if not (px and py and type(facing) == "number") then return view end
    if target.instance ~= nil and instance ~= nil and target.instance ~= instance then return view end
    local angle, yards = Ask(hbd.GetWorldVector, hbd, instance, px, py, target.wx, target.wy)
    if angle and yards then view.angle, view.yards = angle - facing, yards end
    return view
end

-- A gather just now: every spot within reach of where you stand is empty.
-- A catch from a pool is the other way round: the pool is there, so the
-- arrow's pool in reach waits again.
local function Gathered()
    local last = ns.Gather.lastGather
    local now = GetTime()
    if not (last and last.mapID and last.at and now - last.at <= Nav.GATHERED_WITHIN) then return end
    local hbd = HBD()
    local px, py = Ask(hbd and hbd.GetPlayerWorldPosition, hbd)
    if last.kind == "fish" then
        if target and target.category == "fish" and arrivedAt and px and py then
            local dx, dy = target.wx - px, target.wy - py
            if dx * dx + dy * dy <= Nav.ARRIVE_YARDS * Nav.ARRIVE_YARDS then arrivedAt = now end
        end
        return
    end
    if Nav.FishMode() then return end -- a herb by the water: the pools round it are still there
    if px and py then MarkAt(last.mapID, px, py, Nav.GATHERED_YARDS, now) end
end

ns.On("NodesChanged", function()
    Gathered()
    Nav.Refresh()
end)
ns.On("Learned", function() Nav.Refresh() end)
-- a pole put on or taken off: pools or veins and herbs
local gear = CreateFrame("Frame")
gear:SetScript("OnEvent", function() Nav.Reset() end)
pcall(gear.RegisterEvent, gear, "PLAYER_EQUIPMENT_CHANGED")
ns.On("SkillsChanged", function() Nav.Refresh() end)
ns.On("Changed", function(key)
    if key == "*" or key == "profiles" or key == "catalog" or key == "map.database" or key == "ore.enabled" or key == "herb.enabled"
        or (type(key) == "string" and key:find("^arrow%.")) then
        Nav.Reset()
    end
end)
