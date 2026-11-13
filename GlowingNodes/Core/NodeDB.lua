-- NodeDB.lua
-- The spots where ore veins and herbs can spawn, from a 1.12 world database
-- (Data/NodeSpawns.lua, built by tools/nodes/build_node_spawns.py), for the
-- maps: optional (map.database, off by default), drawn fainter than the
-- points you gathered, and left out where you have logged that node already.
-- Forever's new zones aren't in it: there the maps show what you gather.
-- The spots are kept in world yards, as HereBeDragons counts them, and put
-- on a zone's map the way SkinZones does (its rectangle of the world).
local _, ns = ...

local DB = {}
ns.NodeDB = DB

-- spots this close to a logged point of the same kind are that point
local SAME_YARDS = 30

function DB.Enabled()
    return ns.db ~= nil and ns.db.map.database == true and ns.NodeSpawns ~= nil
end

-- the node's name in the client's language: a herb is called as the herb it
-- gives; a vein keeps its English name where the client speaks English, else
-- takes the ore's
local function LocalName(kind, level, name)
    local loc = GetLocale and GetLocale() or "enUS"
    if loc == "enUS" or loc == "enGB" then return name end
    local item = ns.NodeData.ItemFor(kind, level, name)
    local get = C_Item and C_Item.GetItemNameByID or GetItemInfo
    local ok, local_ = pcall(get, item)
    if ok and type(local_) == "string" and local_ ~= "" then return local_ end
    return name
end

-- one node table per kind of node, shared by all its spots
local types
local function Types()
    if types then return types end
    types = {}
    for i, t in ipairs(ns.NodeSpawns.nodes) do
        types[i] = { k = t[1], r = t[2], en = t[3], o = t[4], c = 0, db = true }
    end
    return types
end

local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2

-- A zone's map is a rectangle of the world, and its corners hold bits of
-- the zones round it (Elwynn's top right is the Burning Steppes, with their
-- Black Lotus). The continent's map knows which zone a spot is in:
-- Owner(wx, wy) is false for a spot of another zone. Without that answer
-- (no such function, the sea between zones) the spot stays.
local function OwnerTest(mapID)
    local get = C_Map and C_Map.GetMapInfo
    local at = C_Map and C_Map.GetMapInfoAtPosition
    if not (get and at) then return nil end
    -- this map's zone (a town or cave map is part of one) and its continent
    local zoneID, id, found = mapID, mapID, false
    for _ = 1, 8 do
        local ok, info = pcall(get, id)
        if not ok or not info or not info.parentMapID or info.parentMapID == 0 then return nil end
        local ok2, parent = pcall(get, info.parentMapID)
        if not ok2 or not parent then return nil end
        if parent.mapType == CONTINENT then
            zoneID, id, found = id, info.parentMapID, true
            break
        end
        id = info.parentMapID
    end
    if not found then return nil end
    local left, top, width, height = ns.SkinZones.Frame(id)
    if not left then return nil end
    return function(wx, wy)
        local ok, info = pcall(at, id, (left - wx) / width, (top - wy) / height)
        if not ok or type(info) ~= "table" or not info.mapID then return true end
        return info.mapID == zoneID
    end
end

local cache, order = {}, {}
local KEEP = 6

function DB.Reset()
    wipe(cache)
    wipe(order)
    types = nil
end

-- this map's spots: { [key] = node } as the log keeps them (Gather.Key), or
-- nil (off, a continent or the world, or no part of the two continents)
function DB.Zone(mapID)
    if not (DB.Enabled() and mapID) then return nil end
    if cache[mapID] ~= nil then return cache[mapID] or nil end
    local zone = false
    local SZ = ns.SkinZones
    local left, top, width, height, instance = SZ.Frame(mapID)
    local lists = left and not SZ.IsOverview(mapID) and ns.NodeSpawns.instances[instance]
    if lists then
        zone = {}
        local G = ns.Gather
        local logged = G.Zone(mapID)
        local owner = OwnerTest(mapID)
        local all = Types()
        for i, s in pairs(lists) do
            local node = all[i]
            node.n = node.n or LocalName(node.k, node.r, node.en)
            local wx
            for num in s:gmatch("-?%d+") do
                if not wx then
                    wx = tonumber(num)
                else
                    local wy = tonumber(num)
                    local x, y = (left - wx) / width, (top - wy) / height
                    local here = x >= 0 and x <= 1 and y >= 0 and y <= 1 and (not owner or owner(wx, wy))
                    wx = nil
                    if here then
                        local mine = false
                        if logged then
                            for key, n in pairs(logged) do
                                if n.k == node.k then
                                    local lx, ly = G.Decode(key)
                                    local dx, dy = (x - lx) * width, (y - ly) * height
                                    if dx * dx + dy * dy <= SAME_YARDS * SAME_YARDS then mine = true break end
                                end
                            end
                        end
                        if not mine then zone[G.Key(x, y)] = node end
                    end
                end
            end
        end
    end
    cache[mapID] = zone
    order[#order + 1] = mapID
    if #order > KEEP then cache[table.remove(order, 1)] = nil end
    return zone or nil
end

-- the database's spots on a map: fn(key, node)
function DB.Each(mapID, fn)
    local zone = DB.Zone(mapID)
    if not zone then return end
    for key, node in pairs(zone) do fn(key, node) end
end

ns.On("NodesChanged", function() DB.Reset() end)
ns.On("Changed", function(key)
    if key == "*" or key == "map.database" or key == "language" then DB.Reset() end
end)
