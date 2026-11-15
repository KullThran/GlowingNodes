-- Navigator.lua
-- Where the arrow points: the nearest spot of ore or herbs you can gather,
-- from your log and (if the arrow uses it) the spawn database. The game only
-- picks a node some 15-40 yards off, so this takes you there and the glow
-- takes over. It sees no live nodes: the minimap's dots are secret to addons,
-- so a spot is where nodes spawn, not where one is now.
-- No Blizzard waypoint: nothing here touches C_Map waypoints, the super
-- track or C_Navigation, so other addons keep their destination.
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
Nav.GATHERED_WITHIN = 2
Nav.DIM_ALPHA = 0.45

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

local function Add(list, hbd, mapID, key, node, skills)
    local kind = node.k
    local skill = skills[kind]
    if not skill or (node.r or 1) > skill then return end
    local x, y = ns.Gather.Decode(key)
    local wx, wy, instance = Ask(hbd.GetWorldCoordinatesFromZone, hbd, x, y, mapID)
    if not (wx and wy) then return end
    list[#list + 1] = { key = key, mapID = mapID, wx = wx, wy = wy, instance = instance,
        category = kind, node = node }
end

-- this map's spots the arrow may lead to (built once, until something changes)
function Nav.Candidates(mapID)
    if cache[mapID] then return cache[mapID] end
    local list = {}
    local hbd = HBD()
    if hbd and mapID then
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

function Nav.Reset()
    wipe(cache)
    target = nil
end

function Nav.Target() return target end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

local function Hidden(reason)
    view.state, view.reason = "hidden", reason
    return view
end

-- why the arrow stays out of sight now, or nil
local function Reason()
    if (InCombatLockdown and InCombatLockdown()) or Ask(UnitAffectingCombat, "player") then return "combat" end
    if Ask(IsInInstance) then return "instance" end
    if Ask(UnitOnTaxi, "player") then return "taxi" end
    if Ask(UnitIsDeadOrGhost, "player") then return "dead" end
end

function Nav.Update(now)
    view.reason, view.angle, view.yards, view.category, view.node = nil, nil, nil, nil, nil
    if not (ns.db and ns.db.arrow.enabled) then
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
    local current = ns.SoftTarget and ns.SoftTarget.current
    if current and current.category then return Hidden("glowing") end

    local function Vector(spot)
        if spot.instance ~= nil and instance ~= nil and spot.instance ~= instance then return nil end
        return Ask(hbd.GetWorldVector, hbd, instance, px, py, spot.wx, spot.wy)
    end

    -- the nearest spot; the one in use keeps it unless another is clearly nearer
    local list = Nav.Candidates(mapID)
    local best, bestAngle, bestYards
    for _, spot in ipairs(list) do
        local angle, yards = Vector(spot)
        if yards and (not bestYards or yards < bestYards) then
            best, bestAngle, bestYards = spot, angle, yards
        end
    end
    local keep
    if target and target.mapID == mapID then
        for _, spot in ipairs(list) do
            if spot == target then keep = spot break end
        end
    end
    if keep and best ~= keep then
        local angle, yards = Vector(keep)
        if yards and not (bestYards < Nav.SWITCH * yards) then
            best, bestAngle, bestYards = keep, angle, yards
        end
    end
    target = best
    if not best then
        view.state = "empty"
        return view
    end
    view.state = "guide"
    view.angle = bestAngle - facing
    view.yards = bestYards
    view.category = best.category
    view.node = best.node
    return view
end

ns.On("NodesChanged", function() Nav.Reset() end)
ns.On("Learned", function() Nav.Reset() end)
ns.On("Changed", function(key)
    if key == "*" or key == "profiles" or key == "map.database" or key == "ore.enabled" or key == "herb.enabled"
        or (type(key) == "string" and key:find("^arrow%.")) then
        Nav.Reset()
    end
end)
