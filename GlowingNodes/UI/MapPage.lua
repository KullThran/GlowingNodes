-- MapPage.lua
-- The Map page: the zone's own map, as large as the page allows, with the
-- gathering log drawn on it (a bead per ore or herb node, a purple area where
-- hides were skinned), the purple areas where skinnable creatures roam (as
-- the game outlines a quest's area, with the skinning they need) and the
-- player's arrow. The map zooms with the mouse wheel and is dragged about;
-- a continent shows its zones, and a click opens one; Back (or a right-click)
-- goes to the map seen before, or up to the continent. A search box finds
-- zones, nodes, creatures and drops. Under the map, the filters with the
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
local SEARCH_W = 190
local RESULTS = 8
local RESULTS_W = 270
local ZOOM_MAX, ZOOM_STEP = 8, 1.25
local HISTORY = 20
local LABEL_MIN_W = 34 -- px: a smaller area shows its label once zoomed in

local function Lower(s) return type(s) == "string" and s:lower() or "" end
local function Has(text, q) return q ~= "" and Lower(text):find(q, 1, true) ~= nil end

local function MapInfo(id)
    return id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
end

-- a continent or the world: no points of its own, its zones open with a click
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
local function IsOverview(id)
    local info = MapInfo(id)
    return info ~= nil and info.mapType ~= nil and info.mapType <= CONTINENT
end

function ns.BuildMapPage(page)
    local G, Pins, SZ, Data = ns.Gather, ns.MapPins, ns.SkinZones, ns.NodeData
    local shown -- uiMapID on the plate
    local maps = {}
    local history = {} -- maps seen before, for Back
    local zoom, panX, panY = 1, 0, 0
    local query = "" -- the search, lower case: what matches it stands out
    local Go, Back, Redraw

    -----------------------------------------------------------------------
    -- Zone and map
    -----------------------------------------------------------------------

    local function RefreshMaps()
        wipe(maps)
        local here = G.PlayerPosition()
        local has = {}
        for _, id in ipairs(G.Maps()) do
            maps[#maps + 1] = id
            has[id] = true
        end
        if here and not has[here] then
            table.insert(maps, 1, here)
            has[here] = true
        end
        if not shown then shown = here or maps[1] end
        -- a map opened from a continent or the search, with nothing logged
        if shown and not has[shown] then table.insert(maps, 1, shown) end
    end

    local zone = W.Selector(page, L.MAP_ZONE, maps, function(id) return G.MapName(id) end,
        function() return shown end, function(id) Go(id) end, 0,
        { boxWidth = 236, fontOf = function() return W.CLIENT_FONT end })
    zone:SetPoint("TOPLEFT", PLATE_X, -2)
    zone:SetWidth(MAP_W + 10 - SEARCH_W - 10)

    local plate = W.Plate(page, MAP_W + 10, MAP_H + 10)
    plate:SetPoint("TOPLEFT", PLATE_X, -PLATE_Y)
    -- the window on the map: it clips the map, which is MAP_W x MAP_H times
    -- the zoom and moves under it
    local canvas = CreateFrame("Frame", nil, plate)
    canvas:SetSize(MAP_W, MAP_H)
    canvas:SetPoint("TOPLEFT", 5, -5)
    if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, canvas)
    content:SetFrameLevel(canvas:GetFrameLevel() + 1)
    local base = content:GetFrameLevel()

    local function CW() return MAP_W * zoom end
    local function CH() return MAP_H * zoom end
    local function ApplyPan()
        panX = math.max(0, math.min(panX, CW() - MAP_W))
        panY = math.max(0, math.min(panY, CH() - MAP_H))
        content:SetSize(CW(), CH())
        content:ClearAllPoints()
        content:SetPoint("TOPLEFT", canvas, "TOPLEFT", -panX, panY)
    end
    ApplyPan()

    -- a dark label over the map when there's nothing to show
    local notice = CreateFrame("Frame", nil, canvas)
    notice:SetFrameLevel(canvas:GetFrameLevel() + 8)
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
        local sx, sy = CW() / lw, CH() / lh
        local cols = math.ceil(lw / tw)
        for i, file in ipairs(files) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            local left, top = col * tw, row * th
            local w, h = math.min(tw, lw - left), math.min(th, lh - top)
            local t = tiles[i]
            if not t then
                t = content:CreateTexture(nil, "BACKGROUND", nil, 1)
                -- the game's parchment map, toned down to sit in the dark window
                t:SetVertexColor(0.8, 0.78, 0.74)
                if t.SetDesaturation then t:SetDesaturation(0.35) end
                tiles[i] = t
            end
            if w > 0 and h > 0 then
                t:SetTexture(file)
                t:SetTexCoord(0, w / tw, 0, h / th)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", content, "TOPLEFT", left * sx, -top * sy)
                t:SetSize(w * sx, h * sy)
                t:Show()
            end
        end
        return true
    end

    -----------------------------------------------------------------------
    -- What the search matches
    -----------------------------------------------------------------------

    -- the name a point matches the search by (its own, a creature skinned
    -- there, an item it dropped, its kind), or nil
    local function MatchName(node, q)
        if q == "" then return nil end
        if Has(node.n, q) then return node.n end
        if node.en and Has(node.en, q) then return node.n or node.en end -- a database spot's English name
        if node.mobs then
            for mob in pairs(node.mobs) do
                if Has(mob, q) then return mob end
            end
        end
        if node.x then
            local items = ns.global.items or {}
            for id in pairs(node.x) do
                local item = items[id]
                if item and Has(item.n, q) then return item.n end
            end
        end
        if Has(L["CAT_" .. node.k], q) then return L["CAT_" .. node.k] end
        return nil
    end

    -- the skinning areas a search picks: the word for them, or a skill
    -- level they need (one number)
    local function SkinMatch(area)
        if query == "" then return true end
        local level = tonumber(query)
        if level then
            return area.need[1] ~= nil and area.need[1] <= level and level <= (area.need[2] or area.need[1])
        end
        return Has(L.MAP_SKINZ, query) or Has(L.CAT_skin, query) or Has(L.PROF_skin, query)
    end

    -----------------------------------------------------------------------
    -- Points of the log; right-click forgets one
    -----------------------------------------------------------------------

    local pins, areas = {}, {}
    local function Pin(i, isArea)
        local list = isArea and areas or pins
        local p = list[i]
        if p then return p end
        p = CreateFrame("Button", nil, content)
        p:SetFrameLevel(base + (isArea and 2 or 5))
        p.tex = p:CreateTexture(nil, isArea and "ARTWORK" or "OVERLAY")
        p.tex:SetAllPoints()
        p.tex:SetTexture(ns.ART .. (isArea and "area" or "pin"))
        p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        p:SetScript("OnEnter", function(self)
            Pins.Tooltip(self, self.node)
            if not self.node.db then
                GameTooltip:AddLine(L.PIN_DELETE_HINT, 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end
        end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p:SetScript("OnClick", function(self, button)
            -- the database's spots aren't yours to forget: its switch hides them
            if button == "RightButton" and not self.node.db then
                GameTooltip:Hide()
                G.Remove(self.mapID, self.key)
            end
        end)
        list[i] = p
        return p
    end

    local function DrawPins(mapID)
        for _, p in ipairs(pins) do p:Hide() end
        for _, p in ipairs(areas) do p:Hide() end
        local n, a = 0, 0
        local zoneNodes = mapID and G.Zone(mapID)
        if zoneNodes then
            local size = math.max(ns.db.map.pinSize, 8)
            local rw, rh = G.AreaRadius(mapID)
            local cw, ch = CW(), CH()
            for key, node in pairs(zoneNodes) do
                if ns.db.map.show[node.k] then
                    local isArea = node.k == "skin"
                    local hit = query ~= "" and MatchName(node, query) ~= nil
                    local p
                    if isArea then
                        a = a + 1
                        p = Pin(a, true)
                        p:SetSize(2 * rw * cw, 2 * rh * ch)
                    else
                        n = n + 1
                        p = Pin(n)
                        local s = hit and math.floor(size * 1.4 + 0.5) or size
                        p:SetSize(s, s)
                    end
                    local x, y = G.Decode(key)
                    p.node, p.key, p.mapID = node, key, mapID
                    p.tex:SetVertexColor(Pins.Color(node.k))
                    p:SetAlpha((query == "" or hit) and 1 or 0.22)
                    p:ClearAllPoints()
                    p:SetPoint("CENTER", content, "TOPLEFT", x * cw, -y * ch)
                    p:Show()
                end
            end
        end
        -- the database's spots (Core/NodeDB.lua): fainter and smaller
        if mapID then
            local size = math.max(ns.db.map.pinSize - Pins.DB_SMALLER, 6)
            local cw, ch = CW(), CH()
            ns.NodeDB.Each(mapID, function(key, node)
                if ns.db.map.show[node.k] then
                    local hit = query ~= "" and MatchName(node, query) ~= nil
                    n = n + 1
                    local p = Pin(n)
                    local s = hit and math.floor(size * 1.4 + 0.5) or size
                    p:SetSize(s, s)
                    local x, y = G.Decode(key)
                    p.node, p.key, p.mapID = node, key, mapID
                    p.tex:SetVertexColor(Pins.Color(node.k))
                    p:SetAlpha((query == "" or hit) and Pins.DB_ALPHA or 0.12)
                    p:ClearAllPoints()
                    p:SetPoint("CENTER", content, "TOPLEFT", x * cw, -y * ch)
                    p:Show()
                end
            end)
        end
        return n + a
    end

    -----------------------------------------------------------------------
    -- Where skinnable creatures roam (Core/SkinZones.lua)
    -----------------------------------------------------------------------

    local skinLayer = CreateFrame("Frame", nil, content)
    skinLayer:SetAllPoints()
    skinLayer:SetFrameLevel(base + 1)
    local skinOpts = {
        pixel = true, -- rows snap to whole pixels, so neighbouring runs meet exactly
        labelMinW = LABEL_MIN_W,
        dim = function(area) return SkinMatch(area) and 1 or 0.3 end,
        makeLabel = function(layer)
            local b = SZ.NewLabel(layer)
            b:SetFrameLevel(base + 3)
            return b
        end,
    }

    local function DrawSkin(mapID)
        -- the Skinning filter shows them, with the hide areas
        local list = ns.db.map.show.skin and mapID and not IsOverview(mapID) and SZ.ForMap(mapID)
        SZ.Draw(skinLayer, list or {}, CW(), CH(), skinOpts)
    end

    -----------------------------------------------------------------------
    -- A continent: a badge on each zone with points; a click opens a zone
    -----------------------------------------------------------------------

    local badges = {}
    local function Badge(i)
        local b = badges[i]
        if b then return b end
        b = CreateFrame("Button", nil, content)
        b:SetFrameLevel(base + 5)
        b:SetHeight(18)
        W.NineSlice(b, "f_inset", 128, 24, 7, "BACKGROUND", 0)
        local dot = b:CreateTexture(nil, "ARTWORK")
        dot:SetTexture(ns.ART .. "pin")
        dot:SetSize(10, 10)
        dot:SetPoint("LEFT", 5, 0)
        dot:SetVertexColor(1, 0.84, 0.5)
        b.text = W.Text(b, 10, W.INK)
        b.text:SetPoint("LEFT", dot, "RIGHT", 3, 0)
        b:SetScript("OnClick", function(self) Go(self.mapID) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(G.MapName(self.mapID), 1, 0.86, 0.6)
            local c = G.Counts(self.mapID)
            for _, kind in ipairs(KINDS) do
                if (c[kind] or 0) > 0 then
                    GameTooltip:AddLine(L["CAT_" .. kind] .. ": " .. c[kind], Pins.Color(kind))
                end
            end
            GameTooltip:AddLine(L.MAP_OPEN_ZONE, 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        badges[i] = b
        return b
    end

    local function DrawBadges(mapID)
        local n = 0
        if mapID and IsOverview(mapID) and C_Map and C_Map.GetMapRectOnMap then
            local cw, ch = CW(), CH()
            for _, id in ipairs(G.Maps()) do
                local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, id, mapID)
                if id ~= mapID and ok and minX and maxX and minY and maxY and maxX > minX then
                    local x, y = (minX + maxX) / 2, (minY + maxY) / 2
                    if x > 0 and x < 1 and y > 0 and y < 1 then
                        n = n + 1
                        local b = Badge(n)
                        local total = 0
                        for _, v in pairs(G.Counts(id)) do total = total + v end
                        b.mapID = id
                        b.text:SetText(total)
                        local tw = b.text:GetStringWidth()
                        b:SetWidth(24 + (type(tw) == "number" and tw or 14))
                        b:ClearAllPoints()
                        b:SetPoint("CENTER", content, "TOPLEFT", x * cw, -y * ch)
                        b:Show()
                    end
                end
            end
        end
        for i = n + 1, #badges do badges[i]:Hide() end
    end

    local playerFrame = CreateFrame("Frame", nil, content)
    playerFrame:SetAllPoints()
    playerFrame:SetFrameLevel(base + 6)
    local player = playerFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    player:SetTexture("Interface\\Minimap\\MinimapArrow")
    player:SetSize(26, 26)
    player:Hide()

    local function DrawPlayer()
        local mapID, x, y = G.PlayerPosition()
        if shown and mapID ~= shown then
            -- the continent the player is on, or another map
            x, y = nil, nil
            local ok, pos = pcall(C_Map.GetPlayerMapPosition, shown, "player")
            if ok and pos then
                if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
            end
        end
        if shown and x and y and (x > 0 or y > 0) then
            player:ClearAllPoints()
            player:SetPoint("CENTER", content, "TOPLEFT", x * CW(), -y * CH())
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

    -- everything on the map, at the zoom it has now
    function Redraw()
        DrawMap(shown)
        local n = DrawPins(shown)
        DrawSkin(shown)
        DrawBadges(shown)
        DrawPlayer()
        return n
    end

    -----------------------------------------------------------------------
    -- Zoom, drag, clicks
    -----------------------------------------------------------------------

    -- the pointer on the map's window, from its top left
    local function Cursor()
        if not GetCursorPosition then return nil end
        local x, y = GetCursorPosition()
        local s = canvas:GetEffectiveScale()
        local l, t = canvas:GetLeft(), canvas:GetTop()
        if not (x and y and s and s > 0 and l and t) then return nil end
        return x / s - l, t - y / s
    end

    -- zoomed about a point of the window (cx, cy), which stays put
    local function ZoomTo(z, cx, cy)
        z = math.max(1, math.min(ZOOM_MAX, z))
        if math.abs(z - zoom) < 0.001 then return end
        cx, cy = cx or MAP_W / 2, cy or MAP_H / 2
        local fx, fy = (panX + cx) / CW(), (panY + cy) / CH()
        zoom = z
        panX, panY = fx * CW() - cx, fy * CH() - cy
        ApplyPan()
        Redraw()
        page:UpdateNav()
    end

    -- the zone under the pointer on a continent
    local function ZoneAtCursor()
        if not (shown and IsOverview(shown) and C_Map and C_Map.GetMapInfoAtPosition) then return nil end
        local x, y = Cursor()
        if not x then return nil end
        local ok, info = pcall(C_Map.GetMapInfoAtPosition, shown, (panX + x) / CW(), (panY + y) / CH())
        if ok and info and info.mapID and info.mapID ~= shown then return info end
    end

    function Go(id, noHistory)
        if not id then return end
        if shown and id ~= shown and not noHistory then
            history[#history + 1] = shown
            if #history > HISTORY then table.remove(history, 1) end
        end
        shown = id
        zoom, panX, panY = 1, 0, 0
        ApplyPan()
        GameTooltip:Hide()
        page:UpdateStatus()
    end

    local function Parent(id)
        local info = MapInfo(id)
        local parent = info and info.parentMapID
        if parent and parent ~= 0 and MapInfo(parent) and info.mapType and info.mapType > 1 then return parent end
    end

    function Back()
        local prev = table.remove(history)
        if prev then
            Go(prev, true)
        elseif shown and Parent(shown) then
            Go(Parent(shown), true)
        end
    end

    local dragged -- the press became a drag: no click
    local drag    -- the map (or, unzoomed, the window) being dragged
    canvas:RegisterForDrag("LeftButton")
    canvas:SetScript("OnMouseDown", function() dragged = false end)
    canvas:SetScript("OnDragStart", function()
        dragged = true
        if zoom <= 1 then
            -- nothing to move: the window moves, as anywhere else on it
            local win = page:GetParent()
            local start = win and win:GetScript("OnDragStart")
            if start then
                start(win)
                drag = { window = win }
            end
            return
        end
        local x, y = Cursor()
        if x then drag = { x = x, y = y, px = panX, py = panY } end
    end)
    canvas:SetScript("OnDragStop", function()
        if drag and drag.window then
            local stop = drag.window:GetScript("OnDragStop")
            if stop then stop(drag.window) end
        end
        drag = nil
    end)
    canvas:SetScript("OnMouseUp", function(_, button)
        if dragged then return end
        if button == "RightButton" then
            if zoom > 1 then ZoomTo(1) else Back() end
        elseif button == "LeftButton" then
            local info = ZoneAtCursor()
            if info then Go(info.mapID) end
        end
    end)
    canvas:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown and IsControlKeyDown() then
            -- Ctrl + wheel sizes the window, here too
            local win = page:GetParent()
            local wheel = win and win:GetScript("OnMouseWheel")
            if wheel then wheel(win, delta) end
            return
        end
        local x, y = Cursor()
        ZoomTo(zoom * (delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP), x, y)
    end)

    local hovered
    canvas:SetScript("OnLeave", function()
        if hovered then GameTooltip:Hide() end
        hovered = nil
    end)
    canvas:SetScript("OnUpdate", function()
        if drag and not drag.window then
            local x, y = Cursor()
            if x then
                panX, panY = drag.px - (x - drag.x), drag.py - (y - drag.y)
                ApplyPan()
            end
        end
        -- a continent: the zone under the pointer, named
        if not (canvas.IsMouseOver and canvas:IsMouseOver()) or drag then return end
        local info = ZoneAtCursor()
        local id = info and info.mapID
        if id == hovered then return end
        hovered = id
        if not info then
            GameTooltip:Hide()
            return
        end
        GameTooltip:SetOwner(canvas, "ANCHOR_CURSOR")
        GameTooltip:AddLine(info.name or G.MapName(id), 1, 0.86, 0.6)
        GameTooltip:AddLine(L.MAP_OPEN_ZONE, 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)

    -- buttons down the map's left edge: back, zoom in and out, hide areas
    local navY = -6
    local function NavButton(tip, text, onClick)
        local b = CreateFrame("Button", nil, canvas)
        b:SetSize(24, 24)
        b:SetFrameLevel(canvas:GetFrameLevel() + 8)
        b:SetPoint("TOPLEFT", 6, navY)
        navY = navY - 27
        W.NineSlice(b, "f_button", 128, 24, 8, "BACKGROUND", 0)
        local glow = W.Tex(b, "f_tab_glow", "ARTWORK")
        glow:SetPoint("TOPLEFT", 2, -2)
        glow:SetPoint("BOTTOMRIGHT", -2, 2)
        glow:SetAlpha(0)
        W.OnAccent(function(r, g, bb) glow:SetVertexColor(r, g, bb) end)
        if text then
            b.label = W.Text(b, 16, W.INK, W.TITLE_FONT)
            b.label:SetPoint("CENTER", 0, 1)
            b.label:SetText(text)
            b.label:SetShadowColor(0, 0, 0, 1)
            b.label:SetShadowOffset(1, -1)
        end
        b:SetScript("OnEnter", function(self)
            if self:IsEnabled() then glow:SetAlpha(0.3) end
        end)
        b:SetScript("OnLeave", function() glow:SetAlpha(0) end)
        b:SetScript("OnClick", function(self)
            W.Click()
            onClick(self)
        end)
        b:SetMotionScriptsWhileDisabled(true)
        W.Tooltip(b, tip[1], tip[2])
        return b
    end

    local backBtn = NavButton({ L.MAP_BACK, L.MAP_BACK_TIP }, nil, function() Back() end)
    local arrow = W.Tex(backBtn, "f_arrow", "OVERLAY")
    arrow:SetSize(16, 16)
    arrow:SetPoint("CENTER", -1, 0)
    arrow:SetTexCoord(1, 0, 0, 1) -- it points left
    local zoomIn = NavButton({ L.MAP_ZOOM_IN, L.MAP_ZOOM_TIP }, "+", function() ZoomTo(zoom * ZOOM_STEP) end)
    local zoomOut = NavButton({ L.MAP_ZOOM_OUT, L.MAP_ZOOM_TIP }, "-", function() ZoomTo(zoom / ZOOM_STEP) end)
    navY = navY - 4
    -- what the map shows: ore, herbs, hides, skinning zones (UI/MapFilter.lua)
    local filterMenu
    local filterBtn = NavButton({ L.MAP_FILTERS, L.MAP_FILTERS_TIP }, nil, function(self)
        filterMenu:Toggle()
    end)
    filterMenu = ns.MapFilter.Menu(filterBtn, false)
    filterMenu:SetPoint("TOPLEFT", filterBtn, "TOPRIGHT", 4, 0)
    local funnel = W.Tex(filterBtn, "emblem", "OVERLAY")
    funnel:SetSize(20, 20)
    funnel:SetPoint("CENTER")

    local function Shade(b, on, tex)
        b:SetEnabled(on)
        local k = on and 1 or 0.45
        if tex then tex:SetVertexColor(k, k, k) end
        if b.label then b.label:SetTextColor(W.INK[1] * k, W.INK[2] * k, W.INK[3] * k) end
    end
    function page:UpdateNav()
        Shade(backBtn, #history > 0 or (shown ~= nil and Parent(shown) ~= nil), arrow)
        Shade(zoomIn, zoom < ZOOM_MAX)
        Shade(zoomOut, zoom > 1)
    end

    -----------------------------------------------------------------------
    -- Search: zones, nodes, creatures and drops
    -----------------------------------------------------------------------

    local search = CreateFrame("EditBox", nil, page)
    search:SetSize(SEARCH_W, 24)
    search:SetPoint("TOPLEFT", PLATE_X + MAP_W + 10 - SEARCH_W, -3)
    search:SetAutoFocus(false)
    search:SetMaxLetters(40)
    -- what is searched for is the game's names, in the client's language
    search:SetFont(W.CLIENT_FONT, 12, "")
    search:SetTextColor(unpack(W.INK))
    search:SetTextInsets(22, 20, 0, 0)
    W.NineSlice(search, "f_inset", 128, 24, 9, "BACKGROUND", 0)
    local glass = search:CreateTexture(nil, "OVERLAY")
    glass:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    glass:SetSize(14, 14)
    glass:SetPoint("LEFT", 6, -1)
    glass:SetVertexColor(0.86, 0.78, 0.64)
    local hint = W.Text(search, 11, W.INK_SOFT)
    hint:SetPoint("LEFT", 24, 0)
    hint:SetPoint("RIGHT", -20, 0)
    if hint.SetWordWrap then hint:SetWordWrap(false) end
    hint:SetText(L.MAP_SEARCH)
    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", -4, 0)
    local clearX = W.Tex(clear, "f_close", "ARTWORK")
    clearX:SetAllPoints()
    clear:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
    end)
    clear:Hide()
    W.Tooltip(search, L.MAP_SEARCH, L.MAP_SEARCH_TIP)

    local results = CreateFrame("Frame", nil, page)
    results:SetFrameLevel(canvas:GetFrameLevel() + 30)
    results:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -2)
    results:SetWidth(RESULTS_W)
    results:EnableMouse(true)
    W.NineSlice(results, "f_plate", 128, 24, 10, "BACKGROUND", 0)
    results:Hide()

    local found = {}
    local Pick
    local resultRows = {}
    for i = 1, RESULTS do
        local row = CreateFrame("Button", nil, results)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 20)
        row:SetPoint("RIGHT", -8, 0)
        local hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.85, 0.6, 0.12)
        hl:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(12, 12)
        row.icon:SetPoint("LEFT", 2, 0)
        row.text = W.Text(row, 11, W.INK, W.CLIENT_FONT)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.text:SetPoint("RIGHT", -2, 0)
        if row.text.SetWordWrap then row.text:SetWordWrap(false) end
        row:SetScript("OnEnter", function(self) if self.result then hl:Show() end end)
        row:SetScript("OnLeave", function() hl:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.result then
                W.Click()
                Pick(self.result)
            end
        end)
        resultRows[i] = row
    end

    -- every zone and continent of the world, for the search (once)
    local zoneList
    local function AllZones()
        if zoneList then return zoneList end
        zoneList = {}
        local seen = {}
        local function Add(id)
            if seen[id] then return end
            seen[id] = true
            local info = MapInfo(id)
            if info and type(info.name) == "string" and info.name ~= "" then
                zoneList[#zoneList + 1] = { id = id, name = info.name, low = info.name:lower() }
            end
        end
        -- the top of the player's map: the world
        local root = G.PlayerPosition() or 947
        for _ = 1, 6 do
            local info = MapInfo(root)
            local parent = info and info.parentMapID
            if not parent or parent == 0 or not MapInfo(parent) then break end
            root = parent
        end
        if C_Map and C_Map.GetMapChildrenInfo then
            local ok, kids = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
            if ok and type(kids) == "table" then
                for _, kid in ipairs(kids) do
                    if kid.mapID and kid.mapType and kid.mapType <= 3 then Add(kid.mapID) end
                end
            end
        end
        for _, id in ipairs(G.Maps()) do Add(id) end
        return zoneList
    end

    -- results, best first: zones named so, the points of this map, of
    -- other maps (one row per name and map), zones that only contain it
    local function Search(q)
        wipe(found)
        if q == "" then return found end
        for _, z in ipairs(AllZones()) do
            local at = z.low:find(q, 1, true)
            if at then
                found[#found + 1] = { zone = z.id, text = z.name, rank = at == 1 and 0 or 3, count = 0 }
            end
        end
        local groups = {}
        for mapID, zoneNodes in pairs(ns.global.nodes) do
            for _, node in pairs(zoneNodes) do
                local name = MatchName(node, q)
                if name then
                    local key = mapID .. "\1" .. name
                    local g = groups[key]
                    if not g then
                        g = { map = mapID, text = name, kind = node.k, count = 0, rank = mapID == shown and 1 or 2 }
                        groups[key] = g
                        found[#found + 1] = g
                    end
                    g.count = g.count + 1
                end
            end
        end
        table.sort(found, function(a, b)
            if a.rank ~= b.rank then return a.rank < b.rank end
            if a.count ~= b.count then return a.count > b.count end
            return a.text < b.text
        end)
        return found
    end

    local function ShowResults()
        if query == "" or not search:HasFocus() then
            results:Hide()
            return
        end
        Search(query)
        local n = math.min(#found, RESULTS)
        for i, row in ipairs(resultRows) do
            local r = found[i]
            row.result = r
            if r then
                if r.zone then
                    row.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
                    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    row.icon:SetVertexColor(1, 1, 1)
                    row.text:SetText(("%s  |cffa89880%s|r"):format(r.text, L.MAP_ZONE))
                else
                    row.icon:SetTexture(ns.ART .. "pin")
                    row.icon:SetTexCoord(0, 1, 0, 1)
                    row.icon:SetVertexColor(Pins.Color(r.kind))
                    row.text:SetText(("%s  |cffa89880· %s  x%d|r"):format(r.text, G.MapName(r.map), r.count))
                end
                row.icon:Show()
                row:Show()
            elseif i == 1 then
                row.icon:Hide()
                -- a number lights the skinning zones that need it: say so
                local level = tonumber(query)
                row.text:SetText("|cffa89880" .. (level and L.SKINZ_NEED:format(level) or L.MAP_NO_RESULTS) .. "|r")
                row:Show()
            else
                row:Hide()
            end
        end
        results:SetHeight(16 + math.max(n, 1) * 20)
        results:Show()
    end

    function Pick(r)
        search:ClearFocus()
        results:Hide()
        if r.zone then
            -- a zone: open it; the search has done its job
            search:SetText("")
            Go(r.zone)
        elseif r.map ~= shown then
            -- a point: its map, with the search kept so it stands out
            Go(r.map)
        end
    end

    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        hint:SetShown(text == "" and not self:HasFocus())
        clear:SetShown(text ~= "")
        local q = Lower(text):match("^%s*(.-)%s*$") or ""
        if q == query then return end
        query = q
        ShowResults()
        Redraw()
    end)
    search:SetScript("OnEditFocusGained", function()
        hint:Hide()
        ShowResults()
    end)
    search:SetScript("OnEditFocusLost", function(self)
        hint:SetShown((self:GetText() or "") == "")
        -- a click on a result arrives after the focus goes
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, function() if not search:HasFocus() then results:Hide() end end)
        else
            results:Hide()
        end
    end)
    search:SetScript("OnEnterPressed", function(self)
        Search(query)
        if found[1] then Pick(found[1]) else self:ClearFocus() end
    end)
    search:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") end
        self:ClearFocus()
    end)

    -----------------------------------------------------------------------
    -- Panels over the map: the log, the options (one open at a time)
    -----------------------------------------------------------------------

    local panels = {}
    local function Panel()
        local f = CreateFrame("Frame", nil, plate)
        f:SetFrameLevel(canvas:GetFrameLevel() + 12)
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
    -- each chip as wide as its text, up to the Log button (see FitFilters)
    local measure = W.Text(page, 11)
    measure:Hide()
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

    -- The chips take the width their text needs ("Vene di minerale  12" is
    -- twice "Erbe  3"); if all of them don't fit before the Log button, each
    -- gives up a share of what's missing, and only then is a text cut short.
    local CHIP_GAP, CHIP_PAD = 6, 33 -- dot, its gap and the margins
    local CHIPS_W = MAP_W + 10 - 2 * 90 - 6 - 8
    local function FitFilters()
        local widths, total = {}, 0
        for i, b in ipairs(filters) do
            measure:SetText(b.text:GetText() or "")
            local tw = (measure.GetUnboundedStringWidth or measure.GetStringWidth)(measure)
            widths[i] = math.ceil(type(tw) == "number" and tw or 60) + CHIP_PAD
            total = total + widths[i]
        end
        local over = total + CHIP_GAP * (#filters - 1) - CHIPS_W
        for i, b in ipairs(filters) do
            local w = widths[i]
            if over > 0 then w = w - math.ceil(over * widths[i] / total) end
            b:SetWidth(math.max(w, 40))
            b:ClearAllPoints()
            if i == 1 then
                b:SetPoint("TOPLEFT", plate, "BOTTOMLEFT", 0, -6)
            else
                b:SetPoint("LEFT", filters[i - 1], "RIGHT", CHIP_GAP, 0)
            end
        end
    end

    -----------------------------------------------------------------------

    function page:UpdateStatus()
        RefreshMaps()
        zone:Refresh()
        local hasArt = DrawMap(shown)
        local n = DrawPins(shown)
        DrawSkin(shown)
        DrawBadges(shown)
        DrawPlayer()
        self:UpdateNav()
        local msg
        if not shown then
            msg = L.MAP_NO_ZONE
        elseif IsOverview(shown) then
            msg = nil -- a continent: its zones are the points
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
        FitFilters()

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

    page:SetScript("OnHide", function()
        results:Hide()
        filterMenu:Hide()
        search:ClearFocus()
    end)

    ns.On("NodesChanged", function()
        if page:IsVisible() then page:UpdateStatus() end
    end)
end
