-- MapPins.lua
-- The gathering log drawn on the game's maps: a bead in the node kind's
-- colour on the world map (the map being looked at) and on the minimap (the
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

local function When(t)
    if not t then return "" end
    local ok, today = pcall(date, "%Y%m%d")
    local ok2, day = pcall(date, "%Y%m%d", t)
    if ok and ok2 and today == day then return date("%H:%M", t) end
    return date("%d/%m/%Y", t)
end
Pins.When = When

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
    if node.t then GameTooltip:AddLine(L.PIN_LAST:format(When(node.t)), 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end

-- the tooltip of a point, on any map
function Pins.Tooltip(owner, node)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if node.k == "skin" then return AreaTooltip(node) end
    local r, g, b = Pins.Color(node.k)
    GameTooltip:AddLine(node.n or L["CAT_" .. node.k], r, g, b)
    GameTooltip:AddLine(L["PROF_" .. node.k], 0.8, 0.8, 0.8)
    if (node.c or 1) > 0 then
        GameTooltip:AddLine(L.PIN_COUNT:format(node.c or 1), 1, 1, 1)
    else
        GameTooltip:AddLine(L.PIN_SEEN, 1, 1, 1)
    end
    if node.r then GameTooltip:AddLine(L.PIN_LEVEL:format(node.r), 0.8, 0.8, 0.8) end
    if node.p == false then GameTooltip:AddLine(L.PIN_ROUGH, 0.7, 0.7, 0.7) end
    local last = node.t or node.v
    if last then GameTooltip:AddLine(L.PIN_LAST:format(When(last)), 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Pin frames, pooled
---------------------------------------------------------------------------

local function NewPin()
    local f = CreateFrame("Button", nil, UIParent)
    f:SetSize(12, 12)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    f.tex:SetTexture(ns.ART .. "pin")
    f:SetScript("OnEnter", function(self) if self.node then Pins.Tooltip(self, self.node) end end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

local function Pool()
    local pool = { free = {}, used = {} }
    function pool:Acquire(node, size)
        local pin = table.remove(self.free) or NewPin()
        pin.node = node
        pin:SetSize(size, size)
        pin.tex:SetVertexColor(Pins.Color(node.k))
        self.used[#self.used + 1] = pin
        return pin
    end
    function pool:ReleaseAll()
        for i = #self.used, 1, -1 do
            local pin = self.used[i]
            pin.node = nil
            pin:Hide()
            self.free[#self.free + 1] = pin
            self.used[i] = nil
        end
    end
    return pool
end

local worldPool, miniPool = Pool(), Pool()

-- beads: ore and herbs (hides are drawn as areas)
local function Visible(node)
    return node.k ~= "skin" and ns.db.map.show[node.k]
end

---------------------------------------------------------------------------
-- World map: the points of the map on show
---------------------------------------------------------------------------

function Pins:RefreshWorld()
    if not HBDP then return end
    HBDP:RemoveAllWorldMapIcons(REF)
    worldPool:ReleaseAll()
    if not (ns.db and ns.db.map.worldMap) then return end
    local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    local zone = mapID and ns.Gather.Zone(mapID)
    if not zone then return end
    local size = ns.db.map.pinSize
    for key, node in pairs(zone) do
        if Visible(node) then
            local x, y = ns.Gather.Decode(key)
            local pin = worldPool:Acquire(node, size)
            HBDP:AddWorldMapIconMap(REF, pin, mapID, x, y, 0)
        end
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
        if not (map and map.worldMap and map.show.skin) then return end
        local canvasMap = self:GetMap()
        local mapID = canvasMap:GetMapID()
        local zone = mapID and ns.Gather.Zone(mapID)
        if not zone then return end
        local canvas = canvasMap:GetCanvas()
        local cw, ch = canvas:GetWidth(), canvas:GetHeight()
        local rw, rh = ns.Gather.AreaRadius(mapID)
        for key, node in pairs(zone) do
            if node.k == "skin" then
                local x, y = ns.Gather.Decode(key)
                canvasMap:AcquirePin(AREA, node, x, y, 2 * rw * cw, 2 * rh * ch)
            end
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
    local zone = mapID and ns.Gather.Zone(mapID)
    if not zone then return end
    local size = math.max(ns.db.map.pinSize - 2, 6)
    for key, node in pairs(zone) do
        if Visible(node) then
            local x, y = ns.Gather.Decode(key)
            local pin = miniPool:Acquire(node, size)
            HBDP:AddMinimapIconMap(REF, pin, mapID, x, y, false, false)
        end
    end
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
    if key == "*" or (type(key) == "string" and (key:find("^map%.") or key:find("%.color$"))) then
        Pins:Refresh()
    end
end)

local zoneEvents = CreateFrame("Frame")
zoneEvents:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
zoneEvents:SetScript("OnEvent", function()
    if ns.db then Pins:RefreshMinimap() end
end)
