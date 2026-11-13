-- OpenMap.lua
-- Glowing Nodes with Open Map (all of Azeroth as one stitched world map,
-- OpenMapAPI). Where it's loaded:
--   * the switches (on the world map, ore, herbs, skinning) go in its menu,
--     not on a button of ours in the map's corner, where its own are;
--   * while the map is stitched, the zones round the one underneath show too:
--     their beads and hide areas, and the purple skinning zones, placed on
--     its stitched world (it isn't one rectangle: each area gets its own
--     place from its corners);
--   * our layers are kept above its art.
-- Without Open Map nothing here does anything.
local _, ns = ...
local L = ns.L

local O = {}
ns.OpenMap = O

-- how far round the map underneath (its widths) the neighbours are shown
O.NEAR = 0.6

function O.API()
    local api = rawget(_G, "OpenMapAPI")
    if type(api) == "table" and type(api.IsStitched) == "function" then return api end
end

-- the world map shows Open Map's stitched map now
function O.Stitched()
    local api = O.API()
    if not api then return false end
    local ok, on = pcall(api.IsStitched)
    return ok and on and true or false
end

---------------------------------------------------------------------------
-- Frame levels: the stitched art covers a band of levels on the map's canvas
---------------------------------------------------------------------------

local waiting = setmetatable({}, { __mode = "k" })

-- a frame of ours on the canvas: above the art (`above` levels over its top);
-- a frame level is restricted in combat: then lifted as it ends
function O.Lift(frame, above)
    if not (frame and O.Stitched()) then return end
    local api = O.API()
    local ok, top = pcall(api.ArtTopLevel or function() end)
    if not ok or type(top) ~= "number" then return end
    if InCombatLockdown and InCombatLockdown() then
        waiting[frame] = above or 1
        return
    end
    waiting[frame] = nil
    if frame:GetFrameLevel() <= top then frame:SetFrameLevel(top + (above or 1)) end
end

---------------------------------------------------------------------------
-- Places on the stitched map
---------------------------------------------------------------------------

-- a world spot (HereBeDragons' instance and yards) on the map underneath,
-- 0..1 its own rectangle and past it. Open Map takes the game's world
-- X, Y, which HereBeDragons keeps as y, x.
function O.Project(instance, wx, wy)
    local api = O.API()
    if not (api and api.CanvasFromWorldPos) then return end
    local ok, x, y = pcall(api.CanvasFromWorldPos, instance, wy, wx)
    if ok and type(x) == "number" and type(y) == "number" then return x, y end
end

-- a spot on one map (0..1) on another, through the stitched world
function O.ToMap(fromMapID, x, y, toMapID)
    local api = O.API()
    if not (api and api.WorldFromMap and api.MapFromWorld) then return end
    local ok, u, v = pcall(api.WorldFromMap, fromMapID, x, y)
    if not (ok and type(u) == "number" and type(v) == "number") then return end
    local ok2, mx, my = pcall(api.MapFromWorld, toMapID, u, v)
    if ok2 and type(mx) == "number" and type(my) == "number" then return mx, my end
end

local function Near(x, y)
    return x >= -O.NEAR and x <= 1 + O.NEAR and y >= -O.NEAR and y <= 1 + O.NEAR
end

-- the skinning zones on the map underneath and round it (see SkinZones)
function O.SkinAreas(mapID)
    return ns.SkinZones.ForProjection(mapID, O.Project, O.NEAR, "openmap:" .. tostring(mapID))
end

-- The logged spots of the zones round `hostID`, on its map:
-- fn(mapID, key, node, x, y, sx, sy), x, y on the host's map and sx, sy the
-- host's share of one of the zone's (to size an area). A zone whose map
-- doesn't come near is passed over whole.
function O.Neighbours(hostID, fn)
    if not (hostID and ns.global and ns.global.nodes) then return end
    for mapID, zone in pairs(ns.global.nodes) do
        if mapID ~= hostID then
            local l, t = O.ToMap(mapID, 0, 0, hostID)
            local r, b = O.ToMap(mapID, 1, 1, hostID)
            if l and r and math.max(l, r) > -O.NEAR and math.min(l, r) < 1 + O.NEAR
                and math.max(t, b) > -O.NEAR and math.min(t, b) < 1 + O.NEAR then
                local sx, sy = math.abs(r - l), math.abs(b - t)
                for key, node in pairs(zone) do
                    local nx, ny = ns.Gather.Decode(key)
                    local x, y = l + nx * (r - l), t + ny * (b - t)
                    if Near(x, y) then fn(mapID, key, node, x, y, sx, sy) end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Its menu: our switches
---------------------------------------------------------------------------

local ICONS = {
    ore = "Interface\\Icons\\INV_Ore_Copper_01",
    herb = "Interface\\Icons\\INV_Misc_Flower_02",
}

-- the switches go in its menu (true: our own button isn't wanted)
local registered
function O.RegisterMenu()
    if registered then return true end
    local api = O.API()
    if not (api and type(api.RegisterMenuToggle) == "function") then return false end
    local function Add(id, label, icon, get, set)
        local ok, err = pcall(api.RegisterMenuToggle, ns.NAME, {
            id = id, label = label, icon = icon, get = get, set = set, section = L.TITLE,
        })
        if not ok then ns.Debug("Open Map menu: " .. tostring(err)) end
        return ok
    end
    local ok = Add("worldMap", L.MAP_WORLD, ns.ART .. "emblem",
        function() return ns.db.map.worldMap end, function(v) ns.SetMap("worldMap", v and true or false) end)
    for _, kind in ipairs({ "ore", "herb", "skin" }) do
        ok = Add(kind, L["CAT_" .. kind], ICONS[kind] or ns.SkinZones.ICON,
            function() return ns.db.map.show[kind] end, function(v) ns.SetMap("show", v and true or false, kind) end) and ok
    end
    ok = Add("database", L.MAP_DATABASE, "Interface\\Icons\\INV_Misc_Book_09",
        function() return ns.db.map.database end, function(v) ns.SetMap("database", v and true or false) end) and ok
    registered = ok
    return ok
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local function RefreshWorld()
    if ns.MapPins then ns.MapPins:Refresh() end
    if ns.MapFilter then ns.MapFilter.RefreshWorld() end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    for frame, above in pairs(waiting) do
        waiting[frame] = nil
        if frame:IsShown() then O.Lift(frame, above) end
    end
end)

ns.On("Enable", function()
    local api = O.API()
    if not api then return end
    O.RegisterMenu()
    pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
    if type(api.RegisterCallback) == "function" then
        -- the map switched between Open Map's and the game's own: drawn again
        pcall(api.RegisterCallback, O, "OpenMap_StitchedChanged", function() RefreshWorld() end)
    end
end)
