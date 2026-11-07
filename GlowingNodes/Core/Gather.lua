-- Gather.lua
-- The gathering log, kept the way GatherMate2 keeps its database: every time
-- the player mines, picks a herb or skins, and every node the glow finds even
-- if it's left alone, the spot is written down on the zone's map
-- (account-wide, GlowingNodesDB.global.nodes). A spot met again counts up
-- instead of adding a point, so each node is one point.
-- How a gather is seen: the cast of Mining / Herb Gathering / Skinning
-- (UNIT_SPELLCAST_SENT names the target), written down once it succeeds.
local _, ns = ...

local G = {}
ns.Gather = G

-- one rank of each gathering spell is enough: the cast is matched by name
local KIND_SPELLS = {
    ore = { 2575, 2576, 3564, 10248 },
    herb = { 2366, 2368, 3570, 11993 },
    skin = { 8613, 8617, 8618, 10768 },
}
-- the same node gathered again: closer than this, in yards. Hides are not
-- nodes: mobs wander, so skinning marks an area (AREA_YARDS round) where
-- skinnable creatures roam, and skinning inside it adds to it.
local AREA_YARDS = 60
local MERGE_YARDS = { ore = 15, herb = 15, skin = AREA_YARDS }
G.AREA_YARDS = AREA_YARDS
local MAX_MOBS = 6
local LOG_SIZE = 100
local PENDING_FOR = 30

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and name and not IsSecret(name) then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and name and not IsSecret(name) then return name end
    end
end

local byID, byName
local function KindOf(spellID)
    if IsSecret(spellID) then return nil end
    if not byID then
        byID, byName = {}, {}
        for kind, ids in pairs(KIND_SPELLS) do
            for _, id in ipairs(ids) do
                byID[id] = kind
                local name = SpellName(id)
                if name then byName[name] = kind end
            end
        end
    end
    if spellID and byID[spellID] then return byID[spellID] end
    local name = spellID and SpellName(spellID)
    return name and byName[name]
end
G.KindOf = KindOf

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------

local function HBD() return LibStub and LibStub("HereBeDragons-2.0", true) end

-- the player's zone map and spot on it (0..1), or nil in instances
function G.PlayerPosition()
    local hbd = HBD()
    if hbd then
        local ok, x, y, mapID = pcall(hbd.GetPlayerZonePosition, hbd)
        if ok and x and y and mapID then return mapID, x, y end
    end
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local mapID = C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local x, y
            if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
            if x and y and (x > 0 or y > 0) then return mapID, x, y end
        end
    end
end

-- yards between two spots of one map (a rough guess without the map's size)
function G.Distance(mapID, x1, y1, x2, y2)
    local hbd = HBD()
    if hbd then
        local ok, d = pcall(hbd.GetZoneDistance, hbd, mapID, x1, y1, mapID, x2, y2)
        if ok and d then return d end
    end
    local dx, dy = (x2 - x1) * 1.5, y2 - y1 -- maps are 3:2
    return math.sqrt(dx * dx + dy * dy) * 1000
end

-- the key is the spot itself, to 1/10000 of the map, as GatherMate2 does
function G.Key(x, y)
    return math.floor(x * 10000 + 0.5) * 10000 + math.floor(y * 10000 + 0.5)
end

function G.Decode(key)
    return math.floor(key / 10000) / 10000, (key % 10000) / 10000
end

-- an area's radius as a share of the map's width and height
function G.AreaRadius(mapID)
    local hbd = HBD()
    if hbd and hbd.GetZoneSize then
        local ok, w, h = pcall(hbd.GetZoneSize, hbd, mapID)
        if ok and w and h and w > 0 and h > 0 then return AREA_YARDS / w, AREA_YARDS / h end
    end
    return AREA_YARDS / 1000, AREA_YARDS / 667
end

function G.MapName(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or ("#" .. tostring(mapID))
end

---------------------------------------------------------------------------
-- The log
---------------------------------------------------------------------------

function G.Zone(mapID)
    return ns.global.nodes[mapID]
end

-- Spots the glow saw but nobody stood on are rough (p = false): the game
-- picks a node within ~15-20 yards and the spot is where the player stood.
-- They merge from further off and settle on the node once the player is in
-- reach of it or gathers it.
local LOOSE_YARDS = 25
G.LOOSE_YARDS = LOOSE_YARDS

-- the point of this kind at that spot, if there is one (rough: the spot is
-- only where the player stood when the glow found it)
function G.Near(mapID, kind, x, y, rough)
    local zone = ns.global.nodes[mapID]
    if not zone then return nil end
    local best, bestKey, bestD
    for key, node in pairs(zone) do
        if node.k == kind then
            local nx, ny = G.Decode(key)
            local d = G.Distance(mapID, x, y, nx, ny)
            local reach = MERGE_YARDS[kind]
            if (rough or node.p == false) and reach < LOOSE_YARDS then reach = LOOSE_YARDS end
            if d <= reach and (not bestD or d < bestD) then
                best, bestKey, bestD = node, key, d
            end
        end
    end
    return bestKey, best
end

-- a point moved to another spot of its map (the next free key there)
local function Move(zone, key, node, x, y)
    local newKey = G.Key(x, y)
    if newKey == key then return key end
    while zone[newKey] and zone[newKey] ~= node do newKey = newKey + 1 end
    zone[key] = nil
    zone[newKey] = node
    return newKey
end

-- rough points of that kind round a spot now known exactly: the same node
-- seen from elsewhere, folded into it
local function Absorb(zone, mapID, kind, keep, x, y)
    for key, node in pairs(zone) do
        if node ~= keep and node.k == kind and node.p == false then
            local nx, ny = G.Decode(key)
            if G.Distance(mapID, x, y, nx, ny) <= LOOSE_YARDS then
                keep.s = (keep.s or 0) + (node.s or 0)
                zone[key] = nil
            end
        end
    end
end

-- how: { gathered = true } or { seen = count it, precise = in reach }
local function Put(kind, name, objectID, mapID, x, y, how)
    local nodes = ns.global.nodes
    nodes[mapID] = nodes[mapID] or {}
    local zone = nodes[mapID]
    local now = time()
    local precise = how.gathered or how.precise
    local key, node = G.Near(mapID, kind, x, y, not precise and kind ~= "skin")
    local isNew = node == nil
    if node then
        if how.gathered then
            node.c = (node.c or 0) + 1
            node.t = now
        elseif how.seen then
            node.s = (node.s or 0) + 1
        end
        node.v = now
        if name then node.n = name end
        if objectID then node.o = objectID end
        if kind == "skin" then
            if how.gathered or how.seen then
                -- the area follows where its creatures are skinned or found
                local ox, oy = G.Decode(key)
                local w = math.max((node.c or 0) + (node.s or 0), 1)
                key = Move(zone, key, node, ox + (x - ox) / w, oy + (y - oy) / w)
            end
        elseif node.p == false then
            if precise then
                key = Move(zone, key, node, x, y)
                node.p = nil
            elseif how.seen then
                -- seen again from elsewhere: towards the middle of those spots
                local ox, oy = G.Decode(key)
                local w = math.max(node.s or 1, 1)
                key = Move(zone, key, node, ox + (x - ox) / w, oy + (y - oy) / w)
            end
        end
    else
        key = G.Key(x, y)
        -- another kind at that very spot (a herb by a vein): the next free one
        while zone[key] do key = key + 1 end
        node = { k = kind, n = name, o = objectID, v = now }
        if how.gathered then
            node.c, node.t = 1, now
        else
            node.c, node.s = 0, 1
        end
        if not precise and kind ~= "skin" then node.p = false end
        zone[key] = node
    end
    if precise and kind ~= "skin" then Absorb(zone, mapID, kind, node, x, y) end
    if kind == "skin" and name and (how.gathered or how.seen) then
        -- the creatures skinned in the area, most skinned kept
        node.mobs = node.mobs or {}
        node.mobs[name] = (node.mobs[name] or 0) + 1
        local count = 0
        for _ in pairs(node.mobs) do count = count + 1 end
        if count > MAX_MOBS then
            local least, leastN
            for mob, n in pairs(node.mobs) do
                if mob ~= name and (not leastN or n < leastN) then least, leastN = mob, n end
            end
            if least then node.mobs[least] = nil end
        end
    end
    return node, isNew, key
end

function G.Record(kind, name, objectID, mapID, x, y)
    if not (ns.db and ns.db.map.record[kind]) then return end
    if not mapID then mapID, x, y = G.PlayerPosition() end
    if not mapID then
        ns.Debug("GATHER " .. tostring(name) .. ": no map position here")
        return
    end
    local node, isNew = Put(kind, name, objectID, mapID, x, y, { gathered = true })
    local now = time()
    local log = ns.global.gatherLog
    log[#log + 1] = { t = now, k = kind, n = name, m = mapID, x = math.floor(x * 1000 + 0.5) / 1000, y = math.floor(y * 1000 + 0.5) / 1000 }
    while #log > LOG_SIZE do table.remove(log, 1) end
    ns.Debug(("GATHER %s %s %.1f, %.1f %s"):format(kind, tostring(name), x * 100, y * 100, isNew and "new" or ("x" .. node.c)))
    ns.Fire("NodesChanged", mapID)
    return node, isNew
end

-- Seen, not gathered: the glow found a node (or a skinnable corpse). It goes
-- on the map too, as a rough point where the player stands; once the player
-- is in reach of it, it moves there (within a few yards of the node).
local seenGuids = {} -- guid -> time() counted, so one node held twice counts once
local SEEN_AGAIN = 600

function G.Seen(target)
    local kind = target and target.category
    if not kind or target.gnPrecise or not (ns.db and ns.db.map.record[kind]) then return end
    if kind == "skin" and not target.corpse then return end
    local inReach = kind ~= "skin" and target.state ~= nil and target.state ~= "far"
    if target.gnSeen and not inReach then return end
    local mapID, x, y = G.PlayerPosition()
    if not mapID then return end
    local count = false
    if not target.gnSeen then
        target.gnSeen = true
        local guid = target.guid
        if guid and not IsSecret(guid) then
            local last = seenGuids[guid]
            count = not last or time() - last > SEEN_AGAIN
            seenGuids[guid] = time()
        else
            count = true
        end
    end
    if inReach or kind == "skin" then target.gnPrecise = true end
    local name = target.name
    if IsSecret(name) then name = nil end
    local objectID = target.objectID
    if IsSecret(objectID) then objectID = nil end
    local node, isNew = Put(kind, name, objectID, mapID, x, y, { seen = count, precise = inReach })
    local required = target.required
    if type(required) == "number" and not IsSecret(required) then node.r = required end
    ns.Debug(("SEEN %s %s %.1f, %.1f %s%s"):format(kind, tostring(name), x * 100, y * 100,
        isNew and "new" or "known", inReach and " (in reach)" or ""))
    ns.Fire("NodesChanged", mapID)
end

ns.On("NodeFound", function(target) G.Seen(target) end)
ns.On("NodeUpdate", function(target) G.Seen(target) end)

-- maps with points, by name
function G.Maps()
    local list = {}
    for mapID, zone in pairs(ns.global.nodes) do
        if next(zone) then list[#list + 1] = mapID end
    end
    table.sort(list, function(a, b) return G.MapName(a) < G.MapName(b) end)
    return list
end

function G.Counts(mapID)
    local counts = { ore = 0, herb = 0, skin = 0 }
    local maps = mapID and { [mapID] = ns.global.nodes[mapID] } or ns.global.nodes
    for _, zone in pairs(maps) do
        for _, node in pairs(zone) do
            counts[node.k] = (counts[node.k] or 0) + 1
        end
    end
    return counts
end

function G.Total()
    local points, zones = 0, 0
    for _, zone in pairs(ns.global.nodes) do
        local n = 0
        for _ in pairs(zone) do n = n + 1 end
        if n > 0 then zones = zones + 1 end
        points = points + n
    end
    return points, zones
end

function G.Remove(mapID, key)
    local zone = ns.global.nodes[mapID]
    if zone and zone[key] then
        zone[key] = nil
        ns.Fire("NodesChanged", mapID)
    end
end

function G.ClearZone(mapID)
    ns.global.nodes[mapID] = nil
    ns.Fire("NodesChanged", mapID)
end

function G.ClearAll()
    wipe(ns.global.nodes)
    wipe(ns.global.gatherLog)
    ns.Fire("NodesChanged")
end

---------------------------------------------------------------------------
-- Seeing a gather
---------------------------------------------------------------------------

local pending = {} -- castGUID -> { kind, name, objectID, t }

local events = CreateFrame("Frame")
events:RegisterEvent("UNIT_SPELLCAST_SENT")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:SetScript("OnEvent", function(_, event, unit, ...)
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SENT" then
        local target, castGUID, spellID = ...
        local kind = KindOf(spellID)
        if not kind then return end
        if IsSecret(target) or target == "" then target = nil end
        -- the Interact Key doesn't always name its target: the node we glow on
        local cur = ns.SoftTarget and ns.SoftTarget.current
        if cur and cur.category ~= kind then cur = nil end
        local name = target or (cur and cur.name)
        local objectID = cur and cur.name == name and cur.objectID or nil
        local now = GetTime()
        for guid, p in pairs(pending) do
            if now - p.t > PENDING_FOR then pending[guid] = nil end
        end
        pending[castGUID or "?"] = { kind = kind, name = name, objectID = objectID, t = now }
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local castGUID, spellID = ...
        local p = pending[castGUID or "?"]
        pending[castGUID or "?"] = nil
        if not p then
            local kind = KindOf(spellID)
            if not kind then return end
            p = { kind = kind }
        end
        G.Record(p.kind, p.name, p.objectID)
    else
        local castGUID = ...
        if castGUID then pending[castGUID] = nil end
    end
end)
