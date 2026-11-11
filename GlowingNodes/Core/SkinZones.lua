-- SkinZones.lua
-- Where skinnable creatures roam, as the game outlines a quest's area: the
-- purple areas of Data/SkinAreas.lua (built from a 1.12 world database by
-- tools/skinning/build_skin_areas.py), turned into a zone map's 0..1.
-- The areas are kept in world yards, as HereBeDragons counts them; a zone's
-- map is a plain rectangle of that world (left, top, width, height), so a
-- spot goes onto it with one subtraction and one division.
local _, ns = ...

local Z = {}
ns.SkinZones = Z

local function HBD() return LibStub and LibStub("HereBeDragons-2.0", true) end

-- the zone's rectangle of the world: left, top, width, height, instance
function Z.Frame(mapID)
    local hbd = HBD()
    local d = hbd and hbd.mapData and mapID and hbd.mapData[mapID]
    if not d or not d[1] or d[1] == 0 or d[2] == 0 then return nil end
    return d[3], d[4], d[1], d[2], d.instance
end

-- a world spot on the zone's map
function Z.ToMap(left, top, width, height, wx, wy)
    return (left - wx) / width, (top - wy) / height
end

local function Runs(s)
    local t = {}
    for n in s:gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

-- An area's place on a map is a line each way: x = ax + bx * world x,
-- y = ay + by * world y (a zone's map grows as the world's numbers fall,
-- so bx and by are below 0 there).

-- the runs of an area on the map: { left, top, right, bottom, ... }, the ones
-- off the map (and `margin` round it) left out
local function Place(runs, ox, oy, cell, f, margin)
    local out = {}
    local lo, hi = -margin, 1 + margin
    for i = 1, #runs - 2, 3 do
        local row, col, len = runs[i], runs[i + 1], runs[i + 2]
        local x0 = ox + col * cell
        local y0 = oy + row * cell
        local xa, xb = f[1] + f[2] * x0, f[1] + f[2] * (x0 + len * cell)
        local ya, yb = f[3] + f[4] * y0, f[3] + f[4] * (y0 + cell)
        local l, r = math.min(xa, xb), math.max(xa, xb)
        local t, b = math.min(ya, yb), math.max(ya, yb)
        if r > lo and l < hi and b > lo and t < hi then
            out[#out + 1] = l
            out[#out + 1] = t
            out[#out + 1] = r
            out[#out + 1] = b
        end
    end
    return out
end

-- the areas of one continent on a map. Frame(a) gives an area's line
-- { ax, bx, ay, by } (nil: the area isn't on this map at all)
local function Build(list, cell, Frame, margin)
    local Data = ns.NodeData
    local lo, hi = -margin, 1 + margin
    local out = {}
    for _, a in ipairs(list) do
        local alo, ahi, count, pc, pr, ox, oy, cols, rows, fill, rim =
            a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11]
        local f = Frame(a, ox, oy, cols * cell, rows * cell)
        if f then
            -- the area's box first: most areas are somewhere else
            local xa, xb = f[1] + f[2] * ox, f[1] + f[2] * (ox + cols * cell)
            local ya, yb = f[3] + f[4] * oy, f[3] + f[4] * (oy + rows * cell)
            local l, r = math.min(xa, xb), math.max(xa, xb)
            local t, b = math.min(ya, yb), math.max(ya, yb)
            if r > lo and l < hi and b > lo and t < hi then
                local area = {
                    lo = alo, hi = ahi, count = count,
                    need = { Data.SkinningLevel(alo), Data.SkinningLevel(ahi) },
                    w = r - l,
                    fill = Place(Runs(fill), ox, oy, cell, f, margin),
                    rim = Place(Runs(rim), ox, oy, cell, f, margin),
                }
                area.x = f[1] + f[2] * (ox + (pc + 0.5) * cell)
                area.y = f[3] + f[4] * (oy + (pr + 0.5) * cell)
                if #area.fill > 0 then out[#out + 1] = area end
            end
        end
    end
    return out
end

-- the few maps seen last, worked out once
local cache, order = {}, {}
local KEEP = 4

local function Keep(key, out)
    cache[key] = out
    order[#order + 1] = key
    if #order > KEEP then cache[table.remove(order, 1)] = nil end
    return out
end

-- The areas on a zone's map, each:
--   { lo, hi = creature levels, need = { min, max } skinning, count,
--     x, y = where its label goes (0..1), w = its width (0..1),
--     fill, rim = runs (see Place) }
-- nil when the map isn't on the two continents (or HereBeDragons is missing).
function Z.ForMap(mapID)
    if cache[mapID] then return cache[mapID] end
    local data = ns.SkinAreas
    local left, top, width, height, instance = Z.Frame(mapID)
    local list = data and left and data.instances[instance]
    if not list then return nil end
    -- a zone's map is a plain rectangle of the world: one line for all
    local f = { left / width, -1 / width, top / height, -1 / height }
    return Keep(mapID, Build(list, data.cell, function() return f end, 0))
end

-- The same, for a map whose world isn't one rectangle (Open Map's stitched
-- Azeroth): project(instance, wx, wy) -> x, y on the map (0..1 its own
-- rectangle, past it too), or nil. Each area gets its own line from two of
-- its corners (the stitched world is straight lines piece by piece), and the
-- areas up to `margin` maps round it are kept, as the view shows them too.
-- `key` caches it (nil: not cached).
function Z.ForProjection(mapID, project, margin, key)
    if key and cache[key] then return cache[key] end
    local data = ns.SkinAreas
    local _, _, _, _, instance = Z.Frame(mapID)
    local list = data and instance and data.instances[instance]
    if not list then return nil end
    local function Frame(_, ox, oy, dx, dy)
        local x0, y0 = project(instance, ox, oy)
        local x1, y1 = project(instance, ox + dx, oy + dy)
        if not (x0 and x1) then
            -- a corner off the stitched world: the middle and a step from it
            local cx, cy = ox + dx / 2, oy + dy / 2
            dx, dy = 100, 100
            x0, y0 = project(instance, cx, cy)
            x1, y1 = project(instance, cx + dx, cy + dy)
            if not (x0 and x1) then return nil end
            ox, oy = cx, cy
        end
        local bx, by = (x1 - x0) / dx, (y1 - y0) / dy
        return { x0 - bx * ox, bx, y0 - by * oy, by }
    end
    local out = Build(list, data.cell, Frame, margin or 0)
    -- (none: maybe its world isn't built yet; worked out again next time)
    if key and #out > 0 then Keep(key, out) end
    return out
end

-- "50" or "50-100"
function Z.Range(a, b)
    if not a then return "?" end
    if not b or a == b then return tostring(a) end
    return a .. "-" .. b
end

-- the look, the same on every map: the game's quest-area purple, a wash
-- with a stronger rim
Z.FILL = { 0.62, 0.32, 0.90, 0.30 }
Z.RIM = { 0.48, 0.18, 0.76, 0.85 }
Z.LABEL = { 0.93, 0.84, 1 } -- the label's ink without the profession
Z.ICON = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"

-- the label's colour: how hard the area is for the player's skinning
function Z.LabelColor(area)
    local skill = ns.Skills and ns.Skills.Get("skin")
    if skill then return ns.NodeData.DifficultyColor(area.need[1], skill) end
    return Z.LABEL[1], Z.LABEL[2], Z.LABEL[3]
end

function Z.Tooltip(owner, area)
    local L = ns.L
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.SKINZ_TITLE, 0.84, 0.62, 1)
    GameTooltip:AddLine(L.SKINZ_NEED:format(Z.Range(area.need[1], area.need[2])), 1, 1, 1)
    GameTooltip:AddLine(L.SKINZ_LEVEL:format(Z.Range(area.lo, area.hi)), 0.9, 0.9, 0.9)
    GameTooltip:AddLine(L.SKINZ_COUNT:format(area.count), 0.9, 0.9, 0.9)
    local skill = ns.Skills and ns.Skills.Get("skin")
    if skill then
        GameTooltip:AddLine(L.SKINZ_YOURS:format(skill), ns.NodeData.DifficultyColor(area.need[1], skill))
    end
    GameTooltip:AddLine(L.SKINZ_NOTE, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

-- a continent or the world: no areas drawn there (they'd be specks)
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
function Z.IsOverview(mapID)
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info ~= nil and info.mapType ~= nil and info.mapType <= CONTINENT
end

-- an area's label: the pelt and the skinning it needs, its tooltip on hover;
-- clicks, drags and the wheel go through to the map under it
function Z.NewLabel(parent)
    local W = ns.W
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(16)
    local back = W.NineSlice(b, "f_inset", 128, 24, 6, "BACKGROUND", 0)
    back:SetVertexColor(0.86, 0.66, 1, 0.95)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(Z.ICON)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    icon:SetSize(11, 11)
    icon:SetPoint("LEFT", 4, 0)
    b.text = W.Text(b, 10, Z.LABEL)
    b.text:SetPoint("LEFT", icon, "RIGHT", 3, 0)
    b.text:SetShadowColor(0, 0, 0, 1)
    b.text:SetShadowOffset(1, -1)
    if b.SetMouseMotionEnabled then
        b:SetMouseMotionEnabled(true)
        if b.SetMouseClickEnabled then b:SetMouseClickEnabled(false) end
    else
        b:EnableMouse(true)
    end
    b:SetScript("OnEnter", function(self) if self.area then Z.Tooltip(self, self.area) end end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- An area's label goes on its middle, in screen-sized units: `unit` is how
-- many of the layer's units one of the label's makes (1 on the Map page; on
-- the world map, which zooms its canvas, 1 / the canvas's scale). Labels never
-- cover each other: the widest areas get theirs first, a label that would
-- land on another is left out (zooming in makes room for it).
local LABEL_H = 16
function Z.PlaceLabels(layer, areas, cw, ch, opts, unit)
    unit = unit or 1
    layer.gnLabels = layer.gnLabels or {}
    local labels = layer.gnLabels
    local wanted = {}
    local m = opts.margin or 0
    for _, area in ipairs(areas or {}) do
        if area.lit and area.x > -m and area.x < 1 + m and area.y > -m and area.y < 1 + m
            and area.w * cw / unit >= (opts.labelMinW or 34) then
            wanted[#wanted + 1] = area
        end
    end
    table.sort(wanted, function(a, b) return a.w > b.w end)
    local placed, nl = {}, 0
    for _, area in ipairs(wanted) do
        local label = labels[nl + 1]
        if not label then
            label = opts.makeLabel(layer)
            labels[nl + 1] = label
        end
        label.text:SetText(Z.Range(area.need[1], area.need[2]))
        local tw = label.text:GetStringWidth()
        local lw = 22 + (type(tw) == "number" and tw or 30)
        -- its box on the layer, with a little air round it
        local x, y = area.x * cw, area.y * ch
        local hw, hh = (lw / 2 + 2) * unit, (LABEL_H / 2 + 1) * unit
        local free = true
        for _, p in ipairs(placed) do
            if math.abs(p[1] - x) < p[3] + hw and math.abs(p[2] - y) < p[4] + hh then
                free = false
                break
            end
        end
        if free then
            nl = nl + 1
            placed[#placed + 1] = { x, y, hw, hh }
            label.area = area
            label.text:SetTextColor(Z.LabelColor(area))
            label:SetWidth(lw)
            label:SetScale(unit)
            label:ClearAllPoints()
            -- an offset counts in the label's own scale
            label:SetPoint("CENTER", layer, "TOPLEFT", x / unit, -y / unit)
            label:Show()
        end
    end
    for i = nl + 1, #labels do labels[i]:Hide() end
end

-- Draws a map's areas into `layer` (a frame the size of the map, cw x ch):
-- textures for the runs, then the labels (Z.PlaceLabels). `layer.gnTex` and
-- `layer.gnLabels` keep them for the next time.
-- opts.pixel: snap to whole units (the Map page; the world map zooms);
-- opts.labelMinW, opts.dim(area) -> 0..1, opts.makeLabel(layer) -> frame.
function Z.Draw(layer, areas, cw, ch, opts, unit)
    layer.gnTex = layer.gnTex or {}
    local texs = layer.gnTex
    local nt = 0
    local snap = opts.pixel and function(v) return math.floor(v + 0.5) end or function(v) return v end
    local function Runs(runs, c, k)
        for i = 1, #runs - 3, 4 do
            -- neighbouring runs share their edges exactly: no seam, no overlap
            local l, t = snap(runs[i] * cw), snap(runs[i + 1] * ch)
            local r, b = snap(runs[i + 2] * cw), snap(runs[i + 3] * ch)
            if r > l and b > t then
                nt = nt + 1
                local tex = texs[nt]
                if not tex then
                    tex = layer:CreateTexture(nil, "ARTWORK")
                    texs[nt] = tex
                end
                tex:SetColorTexture(c[1], c[2], c[3], c[4] * k)
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", layer, "TOPLEFT", l, -t)
                tex:SetSize(r - l, b - t)
                tex:Show()
            end
        end
    end
    for _, area in ipairs(areas or {}) do
        local k = opts.dim and opts.dim(area) or 1
        area.lit = k >= 1
        Runs(area.fill, Z.FILL, k)
        Runs(area.rim, Z.RIM, k)
    end
    for i = nt + 1, #texs do texs[i]:Hide() end
    Z.PlaceLabels(layer, areas, cw, ch, opts, unit)
end
