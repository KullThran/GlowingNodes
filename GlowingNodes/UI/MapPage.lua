-- MapPage.lua
-- The Map page: the zone's own map, as large as the page allows, with the
-- gathering log drawn on it (a bead per ore or herb node, a purple area where
-- hides were skinned) and the player's arrow. Under it, the filters with the
-- zone's counts and two buttons that open panels over the map: the log of
-- the latest gathers, and the options (what to log, where to show it).
local _, ns = ...
local L = ns.L
local W = ns.W

local MAP_W, MAP_H = 497, 331 -- the game's zone maps are 3:2
local PLATE_X, PLATE_Y = 15, 30
local KINDS = { "ore", "herb", "skin" }
local RECENT = 12
local PANEL_W = 214

function ns.BuildMapPage(page)
    local G, Pins = ns.Gather, ns.MapPins
    local shown -- uiMapID on the plate
    local maps = {}

    -----------------------------------------------------------------------
    -- Zone and map
    -----------------------------------------------------------------------

    local function RefreshMaps()
        wipe(maps)
        local here = G.PlayerPosition()
        local hasHere = false
        for _, id in ipairs(G.Maps()) do
            maps[#maps + 1] = id
            if id == here then hasHere = true end
        end
        if here and not hasHere then table.insert(maps, 1, here) end
        if not shown then shown = here or maps[1] end
    end

    local zone = W.Selector(page, L.MAP_ZONE, maps, function(id) return G.MapName(id) end,
        function() return shown end, function(id) shown = id page:UpdateStatus() end, 0,
        { boxWidth = 340, fontOf = function() return W.CLIENT_FONT end })
    zone:SetPoint("TOPLEFT", PLATE_X, -2)
    zone:SetWidth(MAP_W + 10)

    local plate = W.Plate(page, MAP_W + 10, MAP_H + 10)
    plate:SetPoint("TOPLEFT", PLATE_X, -PLATE_Y)
    local canvas = CreateFrame("Frame", nil, plate)
    canvas:SetSize(MAP_W, MAP_H)
    canvas:SetPoint("TOPLEFT", 5, -5)
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end

    -- a dark label over the map when there's nothing to show
    local notice = CreateFrame("Frame", nil, canvas)
    notice:SetFrameLevel(canvas:GetFrameLevel() + 6)
    notice:SetSize(MAP_W - 140, 46)
    notice:SetPoint("TOP", 0, -14)
    W.NineSlice(notice, "f_inset", 128, 24, 9, "BACKGROUND", 0)
    local empty = W.Text(notice, 12, W.INK)
    empty:SetPoint("LEFT", 10, 0)
    empty:SetPoint("RIGHT", -10, 0)
    empty:SetJustifyH("CENTER")
    empty:SetSpacing(2)

    local tiles = {}
    -- the zone's art, tile by tile, cut where the map ends
    local function DrawMap(mapID)
        for _, t in ipairs(tiles) do t:Hide() end
        local layers = mapID and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
        local layer = layers and layers[1]
        local files = layer and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(mapID, 1)
        if not (files and #files > 0 and layer.layerWidth and layer.layerWidth > 0) then return false end
        local lw, lh, tw, th = layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight
        local sx, sy = MAP_W / lw, MAP_H / lh
        local cols = math.ceil(lw / tw)
        for i, file in ipairs(files) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local left, top = col * tw, row * th
            local w, h = math.min(tw, lw - left), math.min(th, lh - top)
            local t = tiles[i]
            if not t then
                t = canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
                -- the game's parchment map, toned down to sit in the dark window
                t:SetVertexColor(0.8, 0.78, 0.74)
                if t.SetDesaturation then t:SetDesaturation(0.35) end
                tiles[i] = t
            end
            if w > 0 and h > 0 then
                t:SetTexture(file)
                t:SetTexCoord(0, w / tw, 0, h / th)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", canvas, "TOPLEFT", left * sx, -top * sy)
                t:SetSize(w * sx, h * sy)
                t:Show()
            end
        end
        return true
    end

    -- points on the map (hides: areas, under the points); right-click
    -- forgets one
    local pins, areas = {}, {}
    local function Pin(i, isArea)
        local list = isArea and areas or pins
        local p = list[i]
        if p then return p end
        p = CreateFrame("Button", nil, canvas)
        p:SetFrameLevel(canvas:GetFrameLevel() + (isArea and 1 or 3))
        p.tex = p:CreateTexture(nil, isArea and "ARTWORK" or "OVERLAY")
        p.tex:SetAllPoints()
        p.tex:SetTexture(ns.ART .. (isArea and "area" or "pin"))
        p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        p:SetScript("OnEnter", function(self)
            Pins.Tooltip(self, self.node)
            GameTooltip:AddLine(L.PIN_DELETE_HINT, 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                GameTooltip:Hide()
                G.Remove(self.mapID, self.key)
            end
        end)
        list[i] = p
        return p
    end

    local player = canvas:CreateTexture(nil, "OVERLAY", nil, 7)
    player:SetTexture("Interface\\Minimap\\MinimapArrow")
    player:SetSize(26, 26)
    player:Hide()

    local function DrawPins(mapID)
        for _, p in ipairs(pins) do p:Hide() end
        for _, p in ipairs(areas) do p:Hide() end
        local n, a = 0, 0
        local zoneNodes = mapID and G.Zone(mapID)
        if zoneNodes then
            local size = math.max(ns.db.map.pinSize, 8)
            local rw, rh = G.AreaRadius(mapID)
            for key, node in pairs(zoneNodes) do
                if ns.db.map.show[node.k] then
                    local isArea = node.k == "skin"
                    local p
                    if isArea then
                        a = a + 1
                        p = Pin(a, true)
                        p:SetSize(2 * rw * MAP_W, 2 * rh * MAP_H)
                    else
                        n = n + 1
                        p = Pin(n)
                        p:SetSize(size, size)
                    end
                    local x, y = G.Decode(key)
                    p.node, p.key, p.mapID = node, key, mapID
                    p.tex:SetVertexColor(Pins.Color(node.k))
                    p:ClearAllPoints()
                    p:SetPoint("CENTER", canvas, "TOPLEFT", x * MAP_W, -y * MAP_H)
                    p:Show()
                end
            end
        end
        return n + a
    end

    local function DrawPlayer()
        local mapID, x, y = G.PlayerPosition()
        if mapID and mapID == shown then
            player:ClearAllPoints()
            player:SetPoint("CENTER", canvas, "TOPLEFT", x * MAP_W, -y * MAP_H)
            local facing = GetPlayerFacing and GetPlayerFacing()
            if facing and player.SetRotation then player:SetRotation(facing) end
            player:Show()
        else
            player:Hide()
        end
    end
    local elapsed = 0
    page:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        DrawPlayer()
    end)

    -----------------------------------------------------------------------
    -- Panels over the map: the log, the options (one open at a time)
    -----------------------------------------------------------------------

    local panels = {}
    local function Panel()
        local f = CreateFrame("Frame", nil, plate)
        f:SetFrameLevel(canvas:GetFrameLevel() + 10)
        f:SetSize(PANEL_W, MAP_H - 12)
        f:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -6, -6)
        f:EnableMouse(true)
        W.NineSlice(f, "f_plate", 128, 24, 10, "BACKGROUND", 0)
        f:Hide()
        panels[#panels + 1] = f
        return f
    end
    local function Toggle(panel)
        local open = not panel:IsShown()
        for _, p in ipairs(panels) do p:Hide() end
        panel:SetShown(open)
    end

    -- the log: the latest gathers and the totals
    local logPanel = Panel()
    local recent = W.Section(logPanel, L.MAP_RECENT, PANEL_W - 24, 260)
    recent:SetPoint("TOPLEFT", 12, -10)
    local rows = {}
    for i = 1, RECENT do
        local dot = recent:CreateTexture(nil, "ARTWORK")
        dot:SetTexture(ns.ART .. "pin")
        dot:SetSize(9, 9)
        dot:SetPoint("TOPLEFT", 2, -32 - (i - 1) * 17)
        local t = W.Text(recent, 11, W.INK, W.CLIENT_FONT)
        t:SetPoint("TOPLEFT", 16, -30 - (i - 1) * 17)
        t:SetWidth(PANEL_W - 44)
        if t.SetWordWrap then t:SetWordWrap(false) end
        rows[i] = { dot = dot, text = t }
    end
    local total = W.Text(logPanel, 10, W.INK_SOFT)
    total:SetPoint("BOTTOMLEFT", 14, 12)
    total:SetWidth(PANEL_W - 28)
    total:SetSpacing(2)

    -- the options: what to log, where to show it, clearing
    local optPanel = Panel()
    local record = W.Section(optPanel, L.MAP_RECORD, PANEL_W - 24, 96)
    record:SetPoint("TOPLEFT", 12, -10)
    for _, kind in ipairs(KINDS) do
        record:Add(W.Check(record, L["CAT_" .. kind], kind == "skin" and L.MAP_RECORD_SKIN_TIP or L.MAP_RECORD_TIP,
            function() return ns.db.map.record[kind] end,
            function(v) ns.SetMap("record", v, kind) end), 22)
    end
    local show = W.Section(optPanel, L.MAP_SHOW, PANEL_W - 24, 118)
    show:SetPoint("TOPLEFT", 12, -110)
    show:Add(W.Check(show, L.MAP_WORLD, L.MAP_WORLD_TIP,
        function() return ns.db.map.worldMap end, function(v) ns.SetMap("worldMap", v) end), 22)
    show:Add(W.Check(show, L.MAP_MINIMAP, L.MAP_MINIMAP_TIP,
        function() return ns.db.map.minimap end, function(v) ns.SetMap("minimap", v) end), 22)
    show:Add(W.Slider(show, L.MAP_PIN_SIZE, 6, 20, 1,
        function() return ns.db.map.pinSize end, function(v) ns.SetMap("pinSize", v) end), 44)
    local clearZone = W.Button(optPanel, L.MAP_CLEAR_ZONE, PANEL_W - 24, function()
        if not shown then return end
        local name, id = G.MapName(shown), shown
        W.Confirm(L.MAP_CLEAR_ZONE_CONFIRM:format(name), function() G.ClearZone(id) end)
    end)
    clearZone:SetPoint("BOTTOMLEFT", 12, 44)
    local clearAll = W.Button(optPanel, L.MAP_CLEAR_ALL, PANEL_W - 24, function()
        W.Confirm(L.MAP_CLEAR_ALL_CONFIRM, function() G.ClearAll() end)
    end)
    clearAll:SetPoint("BOTTOMLEFT", 12, 12)

    -----------------------------------------------------------------------
    -- Under the map: filters with the zone's counts, the panels' buttons
    -----------------------------------------------------------------------

    local filters = {}
    for i, kind in ipairs(KINDS) do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(100, 26)
        b:SetPoint("TOPLEFT", plate, "BOTTOMLEFT", (i - 1) * 106, -6)
        W.NineSlice(b, "f_inset", 128, 24, 8, "BACKGROUND", 0)
        b.dot = b:CreateTexture(nil, "ARTWORK")
        b.dot:SetTexture(ns.ART .. "pin")
        b.dot:SetSize(12, 12)
        b.dot:SetPoint("LEFT", 8, 0)
        b.text = W.Text(b, 11)
        b.text:SetPoint("LEFT", b.dot, "RIGHT", 5, 0)
        b.text:SetPoint("RIGHT", -6, 0)
        if b.text.SetWordWrap then b.text:SetWordWrap(false) end
        b:SetScript("OnClick", function()
            ns.SetMap("show", not ns.db.map.show[kind], kind)
            W.Click()
        end)
        W.Tooltip(b, L["CAT_" .. kind], L.MAP_FILTER_TIP)
        b.kind = kind
        filters[i] = b
    end
    local optBtn = W.Button(page, L.MAP_OPTIONS_BTN, 90, function() Toggle(optPanel) end)
    optBtn:SetPoint("TOPRIGHT", plate, "BOTTOMRIGHT", 0, -6)
    local logBtn = W.Button(page, L.MAP_LOG_BTN, 90, function() Toggle(logPanel) end)
    logBtn:SetPoint("RIGHT", optBtn, "LEFT", -6, 0)

    -----------------------------------------------------------------------

    function page:UpdateStatus()
        RefreshMaps()
        zone:Refresh()
        local hasArt = DrawMap(shown)
        local n = DrawPins(shown)
        DrawPlayer()
        local msg
        if not shown then
            msg = L.MAP_NO_ZONE
        elseif n == 0 then
            -- points there, all filtered out, is not "nothing gathered"
            msg = next(ns.Gather.Zone(shown) or {}) and L.MAP_FILTERED or L.MAP_EMPTY
        elseif not hasArt then
            msg = L.MAP_NO_ART
        end
        empty:SetText(msg or "")
        notice:SetShown(msg ~= nil)

        local counts = G.Counts(shown)
        for _, b in ipairs(filters) do
            local on = ns.db.map.show[b.kind]
            b.dot:SetVertexColor(Pins.Color(b.kind))
            b.dot:SetAlpha(on and 1 or 0.3)
            b.text:SetText(L["CAT_" .. b.kind] .. "  " .. (counts[b.kind] or 0))
            b.text:SetTextColor(unpack(on and W.INK or W.INK_SOFT))
            b:SetAlpha(on and 1 or 0.7)
        end

        local log = ns.global.gatherLog
        for i, row in ipairs(rows) do
            local e = log[#log - i + 1]
            if e then
                row.dot:SetVertexColor(Pins.Color(e.k))
                row.dot:Show()
                local where = e.m ~= shown and ("  |cffa89880· " .. G.MapName(e.m) .. "|r") or ""
                row.text:SetText(("|cffd8c8a8%s|r  %s%s"):format(Pins.When(e.t), e.n or L["CAT_" .. e.k], where))
            else
                row.dot:Hide()
                row.text:SetText(i == 1 and L.MAP_NO_RECENT or "")
            end
        end

        local points, zones = G.Total()
        total:SetText(L.MAP_TOTAL:format(points, zones))
    end

    ns.On("NodesChanged", function()
        if page:IsVisible() then page:UpdateStatus() end
    end)
end
