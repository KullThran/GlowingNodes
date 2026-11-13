-- MapFilter.lua
-- What the maps show, switched on and off from the map itself: ore veins,
-- herbs and skinning (the hide areas you skinned and the purple skinning
-- zones, one switch, the same as the Skinning filter under the Map page). The same little
-- leather panel opens from a button on the Map page and from a button on the
-- game's world map (which also has its master switch, "On the world map").
-- The world map also gets the skinning zones as a layer of its own.
-- With Open Map (UI/OpenMap.lua) the switches go in its menu instead, and
-- while its map is stitched the zones round the one underneath show too.
local _, ns = ...
local L = ns.L
local W = ns.W

local F = {}
ns.MapFilter = F

local MENU_W = 200
local ROW = 24
local menus = {}

local function Items(worldMap)
    local map = function() return ns.db.map end
    local items = {}
    if worldMap then
        items[#items + 1] = { L.MAP_WORLD, L.MAP_WORLD_TIP,
            function() return map().worldMap end, function(v) ns.SetMap("worldMap", v) end }
    end
    for _, kind in ipairs({ "ore", "herb", "skin" }) do
        items[#items + 1] = { L["CAT_" .. kind], kind == "skin" and L.MAP_SKINZ_TIP or L.MAP_FILTER_TIP,
            function() return map().show[kind] end, function(v) ns.SetMap("show", v, kind) end, kind }
    end
    items[#items + 1] = { L.MAP_DATABASE, L.MAP_DATABASE_TIP,
        function() return map().database end, function(v) ns.SetMap("database", v) end }
    return items
end

-- the panel; anchor it, then :Toggle() it from its button
function F.Menu(owner, worldMap)
    local items = Items(worldMap)
    local f = CreateFrame("Frame", nil, owner)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:SetSize(MENU_W, 42 + #items * ROW)
    f:EnableMouse(true)
    f:Hide()
    W.NineSlice(f, "f_plate", 128, 24, 10, "BACKGROUND", 0)
    local title = W.GoldText(f, 14)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText(L.MAP_FILTERS)
    local checks = {}
    for i, item in ipairs(items) do
        local c = W.Check(f, item[1], item[2], item[3], item[4])
        c:SetPoint("TOPLEFT", 16, -14 - i * ROW)
        c:SetPoint("RIGHT", -10, 0)
        -- a swatch of what it shows: the kind's colour, or the zones' purple
        if item[5] then
            local dot = f:CreateTexture(nil, "ARTWORK")
            dot:SetSize(10, 10)
            dot:SetPoint("RIGHT", c, "RIGHT", -2, 0)
            if item[5] == "zones" then
                dot:SetColorTexture(ns.SkinZones.RIM[1], ns.SkinZones.RIM[2], ns.SkinZones.RIM[3], 1)
            else
                dot:SetTexture(ns.ART .. "pin")
                c.paintDot = function() dot:SetVertexColor(ns.MapPins.Color(item[5])) end
            end
        end
        checks[i] = c
    end
    function f:Refresh()
        for _, c in ipairs(checks) do
            c:Refresh()
            if c.paintDot then c.paintDot() end
        end
    end
    function f:Toggle()
        if self:IsShown() then self:Hide() else self:Refresh() self:Show() end
    end
    -- a click anywhere else closes it
    f:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() and not owner:IsMouseOver() then self:Hide() end
    end)
    f:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    f:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    menus[#menus + 1] = f
    return f
end

ns.On("Changed", function()
    for _, m in ipairs(menus) do
        if m:IsShown() then m:Refresh() end
    end
end)

---------------------------------------------------------------------------
-- The game's world map: a button in its corner, and the skinning zones
---------------------------------------------------------------------------

local LAYER = "GlowingNodesSkinZonesTemplate"
local provider

-- one pin the size of the whole map, holding every area of it: the areas are
-- drawn in the map's own units, so they zoom with it
local function SetupLayer()
    if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and WorldMapFrame.pinPools
        and MapCanvasDataProviderMixin and MapCanvasPinMixin) then return end
    local SZ = ns.SkinZones
    local pinMixin = CreateFromMixins(MapCanvasPinMixin)
    function pinMixin:OnLoad() self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
    local opts = { labelMinW = 45, makeLabel = SZ.NewLabel }
    -- the labels keep their size on screen as the map zooms
    local function Unit(pin)
        local map = pin.GetMap and pin:GetMap()
        local scale = map and map.GetCanvasScale and map:GetCanvasScale()
        if type(scale) ~= "number" or scale <= 0 then return 1 end
        return 1 / scale
    end
    function pinMixin:OnAcquired(areas, cw, ch)
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
        if self.SetIgnoreGlobalPinScale then self:SetIgnoreGlobalPinScale(true) end
        self:SetSize(cw, ch)
        self:SetPosition(0.5, 0.5)
        self.gnAreas, self.gnW, self.gnH = areas, cw, ch
        SZ.Draw(self, areas, cw, ch, opts, Unit(self))
        self:Show()
        ns.OpenMap.Lift(self, 1)
    end
    function pinMixin:OnCanvasScaleChanged()
        if MapCanvasPinMixin.OnCanvasScaleChanged then MapCanvasPinMixin.OnCanvasScaleChanged(self) end
        if self.gnAreas then SZ.PlaceLabels(self, self.gnAreas, self.gnW, self.gnH, opts, Unit(self)) end
    end
    pinMixin.SetPassThroughButtons = function() end -- as HereBeDragons: no combat error

    local pool = CreateUnsecuredRegionPoolInstance and CreateUnsecuredRegionPoolInstance(LAYER) or CreateFramePool("FRAME")
    pool.parent = WorldMapFrame:GetCanvas()
    pool.createFunc = function()
        local f = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
        f:SetSize(1, 1)
        -- the layer itself takes no mouse: the map under it keeps its clicks
        f:EnableMouse(false)
        return Mixin(f, pinMixin)
    end
    pool.resetFunc = function(_, pin)
        pin:Hide()
        pin:ClearAllPoints()
        pin.pinTemplate = nil
        pin.owningMap = nil
    end
    pool.creationFunc = pool.createFunc
    pool.resetterFunc = pool.resetFunc
    WorldMapFrame.pinPools[LAYER] = pool

    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(LAYER)
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        local map = ns.db and ns.db.map
        if not (map and map.worldMap and map.show.skin) then return end
        local canvasMap = self:GetMap()
        local mapID = canvasMap:GetMapID()
        if not mapID or SZ.IsOverview(mapID) then return end
        -- Open Map's stitched map: this zone's and its neighbours', on its world
        local stitched = ns.OpenMap.Stitched()
        opts.margin = stitched and ns.OpenMap.NEAR or 0
        local areas = stitched and ns.OpenMap.SkinAreas(mapID) or SZ.ForMap(mapID)
        if not areas or #areas == 0 then return end
        local canvas = canvasMap:GetCanvas()
        canvasMap:AcquirePin(LAYER, areas, canvas:GetWidth(), canvas:GetHeight())
    end
    WorldMapFrame:AddDataProvider(provider)
end

function F.RefreshWorld()
    if provider and WorldMapFrame and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end

-- the button: the addon's emblem in a bronze ring, top right of the map
local button
local function SetupButton()
    if button or not WorldMapFrame then return end
    -- Open Map has its own buttons there: the switches go in its menu
    if ns.OpenMap.RegisterMenu() then return end
    local holder = WorldMapFrame.ScrollContainer or WorldMapFrame
    local b = CreateFrame("Button", "GlowingNodesWorldMapButton", WorldMapFrame)
    b:SetSize(32, 32)
    b:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -8, -8)
    b:SetFrameLevel(math.min(holder:GetFrameLevel() + 200, 9000))
    W.NineSlice(b, "f_button", 128, 24, 9, "BACKGROUND", 0)
    local icon = W.Tex(b, "emblem", "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("CENTER")
    local glow = W.Tex(b, "f_tab_glow", "OVERLAY")
    glow:SetPoint("TOPLEFT", 2, -2)
    glow:SetPoint("BOTTOMRIGHT", -2, 2)
    glow:SetVertexColor(unpack(W.DEFAULT_ACCENT))
    glow:SetAlpha(0)
    local menu = F.Menu(b, true)
    menu:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -4)
    b:SetScript("OnClick", function()
        W.Click()
        menu:Toggle()
    end)
    b:SetScript("OnEnter", function(self)
        glow:SetAlpha(0.35)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L.TITLE, 1, 0.86, 0.6)
        GameTooltip:AddLine(L.MAP_FILTERS_TIP, 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        glow:SetAlpha(0)
        GameTooltip:Hide()
    end)
    WorldMapFrame:HookScript("OnHide", function() menu:Hide() end)
    button = b
end

ns.On("Enable", function()
    local ok, err = pcall(SetupLayer)
    if not ok then ns.Debug("skinning zones on the world map: " .. tostring(err)) end
    ok, err = pcall(SetupButton)
    if not ok then ns.Debug("world map button: " .. tostring(err)) end
end)

ns.On("Changed", function(key)
    if key == "*" or (type(key) == "string" and key:find("^map%.")) then F.RefreshWorld() end
end)
