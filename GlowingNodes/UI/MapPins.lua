-- MapPins.lua
-- The gathering log drawn on the game's maps: the icon of what the node
-- gives on the world map (the map being looked at) and on the minimap (the
-- player's zone), placed by HereBeDragons-Pins as for GatherMate2. Hides are
-- areas, not beads: a wash the size of the area in yards on the world map
-- (its own map layer, so it zooms with the map); none on the minimap.
local _, ns = ...
local L = ns.L

local Pins = {}
ns.MapPins = Pins

local REF = "GlowingNodes"
local HBD = LibStub("HereBeDragons-2.0", true)
local HBDP = LibStub("HereBeDragons-Pins-2.0", true)

function Pins.Color(kind)
    local c = ns.db and ns.db[kind] and ns.db[kind].color
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- A pin wears the icon of what its node gives (Tin Ore, Silver Ore,
-- Peacebloom...), cut round, in its own colours: no two kinds of ore or herb
-- look alike. Database spots carry only their English name (en). Ores and
-- herbs go by their catalog type (the object's ID first, so any client
-- language works); one the catalog doesn't know wears the plain ore or herb
-- icon rather than another node's.
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

function Pins.Icon(node)
    local Data = ns.NodeData
    if node.k == "ore" or node.k == "herb" then
        local key = ns.Catalog.TypeOf(node.o, node.n or node.en, node.k)
        local t = key and ns.Catalog.ByKey[key]
        return t and Data.ItemIcon(t.item) or Data.CATEGORY_ICONS[node.k]
    end
    return Data.IconFor(node.k, node.r, node.n or node.en)
end

function Pins.Paint(tex, node)
    tex:SetTexture(Pins.Icon(node))
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetVertexColor(1, 1, 1)
    if not tex.gnRound then
        local parent = tex.GetParent and tex:GetParent()
        if parent and parent.CreateMaskTexture and tex.AddMaskTexture then
            local mask = parent:CreateMaskTexture()
            if mask then
                mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(tex)
                tex:AddMaskTexture(mask)
                tex.gnRound = mask
            end
        end
    end
end

local function When(t)
    if not t then return "" end
    local ok, today = pcall(date, "%Y%m%d")
    local ok2, day = pcall(date, "%Y%m%d", t)
    if ok and ok2 and today == day then return date("%H:%M", t) end
    return date("%d/%m/%Y", t)
end
Pins.When = When

-- what dropped there, most first, each in its quality's colour
local function DropLines(node)
    local drops = ns.Gather.Drops(node)
    if #drops == 0 then return end
    GameTooltip:AddLine(L.PIN_DROPS, 0.8, 0.8, 0.8)
    for _, d in ipairs(drops) do
        local r, g, b = 1, 1, 1
        local c = d.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[d.quality]
        if c then r, g, b = c.r, c.g, c.b end
        GameTooltip:AddDoubleLine("  " .. d.name, "x" .. d.times, r, g, b, 0.8, 0.8, 0.8)
    end
end
Pins.DropLines = DropLines

-- a fishing pool's catch: "Gives: Oily Blackmouth", in its quality's colour
local function GivesLine(node)
    local id = node.i or (node.o and ns.NodeDB.PoolItem(node.o))
    if not id then return end
    local get = C_Item and C_Item.GetItemNameByID or GetItemInfo
    local ok, name = pcall(get, id)
    if not (ok and type(name) == "string" and name ~= "") then return end
    local quality = C_Item and C_Item.GetItemQualityByID and select(2, pcall(C_Item.GetItemQualityByID, id))
    if type(quality) ~= "number" and GetItemInfo then
        local ok2, _, _, q = pcall(GetItemInfo, id)
        quality = ok2 and q or nil
    end
    local c = type(quality) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    GameTooltip:AddLine(L.FISH_GIVES:format(name), c and c.r or 1, c and c.g or 1, c and c.b or 1)
end

-- the tooltip of a hide area: the creatures skinned there
local function AreaTooltip(node)
    local r, g, b = Pins.Color("skin")
    GameTooltip:AddLine(L.AREA_TITLE, r, g, b)
    local mobs = {}
    for name, n in pairs(node.mobs or {}) do mobs[#mobs + 1] = { name, n } end
    if #mobs == 0 and node.n then mobs[1] = { node.n, math.max((node.c or 1) + (node.s or 0), 1) } end
    table.sort(mobs, function(a, b2) return a[2] > b2[2] end)
    for _, m in ipairs(mobs) do
        GameTooltip:AddDoubleLine(m[1], "x" .. m[2], 1, 1, 1, 0.8, 0.8, 0.8)
    end
    if (node.c or 1) > 0 then
        GameTooltip:AddLine(L.AREA_SKINNED:format(node.c or 1), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine(L.PIN_SEEN, 0.8, 0.8, 0.8)
    end
    DropLines(node)
    if node.t then GameTooltip:AddLine(L.PIN_LAST:format(When(node.t)), 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end

-- the level a point needs, in the game's difficulty colour against your skill
-- (as on the glow); neutral without the profession
local function LevelLine(node)
    local skill = ns.Skills.Get(node.k)
    local r, g, b = 0.8, 0.8, 0.8
    if skill then r, g, b = ns.NodeData.DifficultyColor(node.r, skill) end
    GameTooltip:AddLine(L.PIN_LEVEL:format(node.r), r, g, b)
end

-- the tooltip of a point, on any map
function Pins.Tooltip(owner, node)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if node.k == "skin" then return AreaTooltip(node) end
    local r, g, b = Pins.Color(node.k)
    local fish = node.k == "fish"
    GameTooltip:AddLine(node.n or ns.KindLabel(node.k), r, g, b)
    GameTooltip:AddLine(L["PROF_" .. node.k], 0.8, 0.8, 0.8)
    if fish then GivesLine(node) end
    if node.db then
        -- a spot of the 1.12 database: maybe there, never gathered by you
        if node.r and not fish then LevelLine(node) end
        GameTooltip:AddLine(L.PIN_DATABASE, 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(L.PIN_ARROW_HINT, 0.6, 0.6, 0.6)
        GameTooltip:Show()
        return
    end
    if (node.c or 1) > 0 then
        GameTooltip:AddLine(L.PIN_COUNT:format(node.c or 1), 1, 1, 1)
    else
        GameTooltip:AddLine(L.PIN_SEEN, 1, 1, 1)
    end
    if node.r and not fish then LevelLine(node) end
    if node.p == false then GameTooltip:AddLine(L.PIN_ROUGH, 0.7, 0.7, 0.7) end
    DropLines(node)
    local last = node.t or node.v
    if last then GameTooltip:AddLine(L.PIN_LAST:format(When(last)), 0.7, 0.7, 0.7) end
    GameTooltip:AddLine(L.PIN_ARROW_HINT, 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- a click on a point: the arrow leads there (turned on if it was off); a
-- click on the point it leads to lets go, back to the nearest node
function Pins.Lead(mapID, key, node)
    local Nav = ns.Navigator
    if not (Nav and mapID and key and node) or node.k == "skin" then return end
    if not ns.db.arrow.enabled then ns.SetArrow("enabled", true) end
    local on = Nav.Choose(mapID, key, node)
    if on == true then
        ns.Print(L.MSG_ARROW_TO:format(node.n or ns.KindLabel(node.k)))
    elseif on == false then
        ns.Print(L.MSG_ARROW_NEAREST)
    end
end

function Pins.OnPinClick(pin, button)
    if button == "LeftButton" and pin.node then
        GameTooltip:Hide()
        Pins.Lead(pin.mapID, pin.key, pin.node)
    end
end

---------------------------------------------------------------------------
-- Pin frames, pooled
---------------------------------------------------------------------------

local function NewPin()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetSize(12, 12)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f:SetScript("OnEnter", function(self) if self.node then Pins.Tooltip(self, self.node) end end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnClick", Pins.OnPinClick)
    return f
end

-- the database's spots: fainter and smaller than the points you gathered
local DB_ALPHA, DB_SMALLER = 0.55, 3
Pins.DB_ALPHA, Pins.DB_SMALLER = DB_ALPHA, DB_SMALLER

-- a vein or herb gathered a moment ago: fainter for 5 minutes, the node not
-- back yet (a pool you fished is still there: it stays bright)
local RECENT_FOR, RECENT_ALPHA = 300, 0.4
Pins.RECENT_FOR, Pins.RECENT_ALPHA = RECENT_FOR, RECENT_ALPHA
local liftAt -- when the next faint point brightens: the maps are redrawn then

local function LiftAt(at)
    if liftAt and liftAt <= at then return end
    liftAt = at
    C_Timer.After(math.max(at - time(), 0) + 1, function()
        if liftAt ~= at then return end
        liftAt = nil
        ns.Fire("NodesChanged")
    end)
end

-- how see-through a point is drawn, on any map
function Pins.Alpha(node, now)
    if node.db then return DB_ALPHA end
    local t = node.t
    if t and node.k ~= "fish" and (node.c or 1) > 0 then
        now = now or time()
        if now - t < RECENT_FOR then
            LiftAt(t + RECENT_FOR)
            return RECENT_ALPHA
        end
    end
    return 1
end

local function Pool()
    local pool = { free = {}, used = {} }
    function pool:Acquire(node, size, mapID, key)
        local pin = table.remove(self.free) or NewPin()
        pin.node, pin.mapID, pin.key = node, mapID, key
        pin:SetSize(size, size)
        Pins.Paint(pin.tex, node)
        pin:SetAlpha(Pins.Alpha(node))
        self.used[#self.used + 1] = pin
        return pin
    end
    function pool:ReleaseAll()
        for i = #self.used, 1, -1 do
            local pin = self.used[i]
            pin.node, pin.mapID, pin.key = nil, nil, nil
            pin:Hide()
            self.free[#self.free + 1] = pin
            self.used[i] = nil
        end
    end
    return pool
end

local worldPool, miniPool = Pool(), Pool()
local SHOW_PARENT = 1 -- HBD_PINS_WORLDMAP_SHOW_PARENT

-- beads: ore and herbs (hides are drawn as areas), unless switched off in the Catalog tab
-- your own points show unless "My gathered spots" is off; the database's
-- have their own switch (Core/NodeDB.lua)
function Pins.Mine()
    return ns.db.map.mine ~= false
end

local function Visible(node)
    if not node.db and not Pins.Mine() then return false end
    return node.k ~= "skin" and ns.db.map.show[node.k] and ns.Catalog.ShownNode(node) or false
end
Pins.Visible = Visible

---------------------------------------------------------------------------
-- World map: the points of the map on show
---------------------------------------------------------------------------

function Pins:RefreshWorld()
    if not HBDP then return end
    HBDP:RemoveAllWorldMapIcons(REF)
    worldPool:ReleaseAll()
    if not (ns.db and ns.db.map.worldMap) then return end
    local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not mapID then return end
    local zone = ns.Gather.Zone(mapID)
    local size = ns.db.map.pinSize
    for key, node in pairs(zone or {}) do
        if Visible(node) then
            local x, y = ns.Gather.Decode(key)
            local pin = worldPool:Acquire(node, size, mapID, key)
            HBDP:AddWorldMapIconMap(REF, pin, mapID, x, y, 0)
        end
    end
    ns.NodeDB.Each(mapID, function(key, node)
        if Visible(node) then
            local x, y = ns.Gather.Decode(key)
            local pin = worldPool:Acquire(node, math.max(size - DB_SMALLER, 5), mapID, key)
            HBDP:AddWorldMapIconMap(REF, pin, mapID, x, y, 0)
        end
    end)
    -- Open Map's stitched map shows the zones round this one too: their beads,
    -- on their own maps, marked to show beyond them (it places them)
    if ns.OpenMap.Stitched() and not ns.SkinZones.IsOverview(mapID) then
        ns.OpenMap.Neighbours(mapID, function(nodeMap, key, node)
            if Visible(node) then
                local x, y = ns.Gather.Decode(key)
                local pin = worldPool:Acquire(node, size, nodeMap, key)
                HBDP:AddWorldMapIconMap(REF, pin, nodeMap, x, y, SHOW_PARENT)
            end
        end)
    end
end

---------------------------------------------------------------------------
-- World map: hide areas, a map layer of their own. The pins carry no scaling
-- limits, so they are sized in the map's own units and zoom with it.
---------------------------------------------------------------------------

local AREA = "GlowingNodesAreaPinTemplate"
local areaProvider

local function SetupAreaLayer()
    if areaProvider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and WorldMapFrame.pinPools
        and MapCanvasDataProviderMixin and MapCanvasPinMixin) then return end
    local pinMixin = CreateFromMixins(MapCanvasPinMixin)
    function pinMixin:OnLoad() self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
    function pinMixin:OnAcquired(node, x, y, w, h)
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
        if self.SetIgnoreGlobalPinScale then self:SetIgnoreGlobalPinScale(true) end
        self.node = node
        self:SetSize(w, h)
        self.tex:SetVertexColor(Pins.Color("skin"))
        self:SetPosition(x, y)
        self:Show()
        ns.OpenMap.Lift(self, 2)
    end
    function pinMixin:OnReleased() self.node = nil end
    pinMixin.SetPassThroughButtons = function() end -- as HereBeDragons: no combat error

    local pool = CreateUnsecuredRegionPoolInstance and CreateUnsecuredRegionPoolInstance(AREA) or CreateFramePool("FRAME")
    pool.parent = WorldMapFrame:GetCanvas()
    pool.createFunc = function()
        local f = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
        f:SetSize(1, 1)
        f.tex = f:CreateTexture(nil, "BACKGROUND")
        f.tex:SetAllPoints()
        f.tex:SetTexture(ns.ART .. "area")
        -- a tooltip on hover, but clicks go through to the map
        if f.SetMouseMotionEnabled then
            f:SetMouseMotionEnabled(true)
            if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
            f:SetScript("OnEnter", function(self) if self.node then Pins.Tooltip(self, self.node) end end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return Mixin(f, pinMixin)
    end
    pool.resetFunc = function(_, pin)
        pin:Hide()
        pin:ClearAllPoints()
        pin:OnReleased()
        pin.pinTemplate = nil
        pin.owningMap = nil
    end
    pool.creationFunc = pool.createFunc
    pool.resetterFunc = pool.resetFunc
    WorldMapFrame.pinPools[AREA] = pool

    areaProvider = CreateFromMixins(MapCanvasDataProviderMixin)
    function areaProvider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(AREA)
    end
    function areaProvider:RefreshAllData()
        self:RemoveAllData()
        local map = ns.db and ns.db.map
        if not (map and map.worldMap and map.show.skin and Pins.Mine()) then return end
        local canvasMap = self:GetMap()
        local mapID = canvasMap:GetMapID()
        if not mapID then return end
        local canvas = canvasMap:GetCanvas()
        local cw, ch = canvas:GetWidth(), canvas:GetHeight()
        local rw, rh = ns.Gather.AreaRadius(mapID)
        for key, node in pairs(ns.Gather.Zone(mapID) or {}) do
            if node.k == "skin" then
                local x, y = ns.Gather.Decode(key)
                canvasMap:AcquirePin(AREA, node, x, y, 2 * rw * cw, 2 * rh * ch)
            end
        end
        -- Open Map's stitched map: the zones round this one too, sized in
        -- their own map's yards
        if ns.OpenMap.Stitched() and not ns.SkinZones.IsOverview(mapID) then
            ns.OpenMap.Neighbours(mapID, function(nodeMap, _, node, x, y, sx, sy)
                if node.k == "skin" then
                    local nw, nh = ns.Gather.AreaRadius(nodeMap)
                    canvasMap:AcquirePin(AREA, node, x, y, 2 * nw * sx * cw, 2 * nh * sy * ch)
                end
            end)
        end
    end
    WorldMapFrame:AddDataProvider(areaProvider)
end

function Pins:RefreshAreas()
    if areaProvider and WorldMapFrame:IsShown() then areaProvider:RefreshAllData() end
end

---------------------------------------------------------------------------
-- Minimap: the points of the player's zone
---------------------------------------------------------------------------

function Pins:RefreshMinimap()
    if not HBDP then return end
    HBDP:RemoveAllMinimapIcons(REF)
    miniPool:ReleaseAll()
    if not (ns.db and ns.db.map.minimap) then return end
    local mapID = ns.Gather.PlayerPosition()
    if not mapID then return end
    local size = math.max(ns.db.map.pinSize - 2, 6)
    for key, node in pairs(ns.Gather.Zone(mapID) or {}) do
        if Visible(node) then
            local x, y = ns.Gather.Decode(key)
            local pin = miniPool:Acquire(node, size, mapID, key)
            HBDP:AddMinimapIconMap(REF, pin, mapID, x, y, false, false)
        end
    end
    ns.NodeDB.Each(mapID, function(key, node)
        if Visible(node) then
            local x, y = ns.Gather.Decode(key)
            local pin = miniPool:Acquire(node, math.max(size - DB_SMALLER, 5), mapID, key)
            HBDP:AddMinimapIconMap(REF, pin, mapID, x, y, false, false)
        end
    end)
end

function Pins:Refresh()
    self:RefreshMinimap()
    if WorldMapFrame and WorldMapFrame:IsShown() then
        self:RefreshWorld()
        self:RefreshAreas()
    end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local hooked
local function HookWorldMap()
    if hooked or not (WorldMapFrame and HBDP) then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", function() Pins:RefreshWorld() end)
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Pins:RefreshWorld() end)
    end
end

ns.On("Enable", function()
    HookWorldMap()
    local ok, err = pcall(SetupAreaLayer)
    if not ok then ns.Debug("hide areas on the world map: " .. tostring(err)) end
    Pins:Refresh()
end)

ns.On("NodesChanged", function() Pins:Refresh() end)

ns.On("Changed", function(key)
    if key == "*" or key == "catalog" or (type(key) == "string" and (key:find("^map%.") or key:find("%.color$"))) then
        Pins:Refresh()
    end
end)

-- the minimap shows the player's map's points: redrawn when that map
-- changes, sub-maps too (a cave, a town), not on every sub-zone name
local zoneEvents = CreateFrame("Frame")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_ENTERING_WORLD" }) do
    zoneEvents:RegisterEvent(event)
end
local lastMap
zoneEvents:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if mapID == lastMap and event ~= "PLAYER_ENTERING_WORLD" then return end
    lastMap = mapID
    Pins:RefreshMinimap()
end)
