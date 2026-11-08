-- Widgets.lua
-- The options window is made of the alert card's materials: brown pebbled
-- leather, a cream running stitch, bronze corner caps and rims. Controls:
-- dark wells in bronze rims, grooves with a bronze ring for a knob, leather
-- plaques for tabs and buttons, gems for colours. Textures (Media/Art/f_*)
-- come from tools/photoshop/leather/Build-LeatherArt.ps1.
-- The "accent" is the colour of the node kind on the page: the tick, the
-- slider's fill, the lit plate under the pointer.
local _, ns = ...

local W = {}
ns.W = W

local ART = ns.ART
-- Fonts with the glyphs of the addon's language: Friz Quadrata and Morpheus
-- have no Cyrillic, Korean or Chinese. Every client ships these fonts (the
-- game's font families use them), so any language can be picked on any
-- client. Texts that come from the game (node and zone names) are in the
-- client's language and use the client's own font.
local probe = UIParent:CreateFontString(nil, "BACKGROUND")
local function FirstFont(...)
    for i = 1, select("#", ...) do
        local path = select(i, ...)
        if type(path) == "string" and probe:SetFont(path, 12, "") ~= false then
            return path
        end
    end
    return "Fonts\\FRIZQT__.TTF"
end
local LANG_FONTS = {
    ruRU = { "Fonts\\FRIZQT___CYR.TTF", "Fonts\\MORPHEUS_CYR.TTF" },
    koKR = { "Fonts\\2002.TTF", "Fonts\\2002.TTF" },
    zhCN = { "Fonts\\ARKai_T.ttf", "Fonts\\ARKai_T.ttf" },
    zhTW = { "Fonts\\bLEI00D.ttf", "Fonts\\bLEI00D.ttf" },
}
function W.FontsFor(lang)
    local f = LANG_FONTS[lang]
    if f then
        local body = FirstFont(f[1], STANDARD_TEXT_FONT)
        return body, FirstFont(f[2], body)
    end
    local body = FirstFont("Fonts\\FRIZQT__.TTF", STANDARD_TEXT_FONT)
    return body, FirstFont("Fonts\\MORPHEUS.TTF", body)
end
function W.SetFonts(lang)
    W.FONT, W.TITLE_FONT = W.FontsFor(lang)
    local client = ns.CLIENT_LOCALE or "enUS"
    W.CLIENT_FONT = LANG_FONTS[client] and (W.FontsFor(client)) or FirstFont(STANDARD_TEXT_FONT, W.FONT)
    -- game names with the title font only when they share its alphabet
    W.NAME_FONT = (W.FontsFor(client) == W.FONT) and W.TITLE_FONT or W.CLIENT_FONT
end
W.SetFonts(ns.LOCALE)

W.INK = { 0.95, 0.91, 0.82 }      -- cream text on brown leather, as on the alert
W.INK_SOFT = { 0.76, 0.70, 0.60 }
W.GOLD = { 0.98, 0.82, 0.56 }     -- warm gold headings
W.TAN = { 0.84, 0.76, 0.64 }
W.DEFAULT_ACCENT = { 0.92, 0.62, 0.36 } -- bronze-amber, the General page
W.accent = { unpack(W.DEFAULT_ACCENT) }

local accentPainters = {}
local refreshers = {}

function W.OnAccent(fn)
    accentPainters[#accentPainters + 1] = fn
    fn(unpack(W.accent))
end

function W.SetAccent(r, g, b)
    W.accent[1], W.accent[2], W.accent[3] = r, g, b
    for _, fn in ipairs(accentPainters) do fn(r, g, b) end
end

-- the accent as ink that reads on parchment (bright yellows and greens are
-- pulled towards brown)
function W.AccentInk(k)
    local r, g, b = unpack(W.accent)
    local m = k or 0.62
    return r * m + W.INK[1] * (1 - m), g * m + W.INK[2] * (1 - m), b * m + W.INK[3] * (1 - m)
end

function W.Track(widget)
    refreshers[#refreshers + 1] = widget
    return widget
end

function W.RefreshAll()
    for _, w in ipairs(refreshers) do
        if w.Refresh then w:Refresh() end
    end
end

---------------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------------

-- ink on paper: no drop shadow
function W.Text(parent, size, color, font, flags, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(font or W.FONT, size or 12, flags or "")
    local c = color or W.INK
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH("LEFT")
    fs:SetShadowOffset(0, 0)
    return fs
end

-- gold stamped on leather: dark pressed shadow
function W.GoldText(parent, size, font)
    local fs = W.Text(parent, size, W.GOLD, font or W.TITLE_FONT)
    fs:SetShadowColor(0.05, 0.02, 0, 0.95)
    fs:SetShadowOffset(1, -1)
    return fs
end

function W.Tex(parent, file, layer, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t:SetTexture(file:find("\\", 1, true) and file or (ART .. file))
    return t
end

function W.Ink(parent, file, layer, sub)
    local t = W.Tex(parent, file, layer, sub)
    t:SetVertexColor(unpack(W.INK))
    return t
end

-- a dark inset under a control, so it stands out from the page
function W.Backing(parent, alpha, l, t, r, b, anchor)
    local tex = parent:CreateTexture(nil, "BACKGROUND", nil, -2)
    tex:SetColorTexture(0.06, 0.035, 0.015, alpha or 0.45)
    tex:SetPoint("TOPLEFT", anchor or parent, "TOPLEFT", l or 0, t or 0)
    tex:SetPoint("BOTTOMRIGHT", anchor or parent, "BOTTOMRIGHT", r or 0, b or 0)
    return tex
end

function W.Tooltip(frame, title, text)
    if not (title or text) then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:AddLine(title, 1, 0.86, 0.6) end
        if text then GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Click()
    PlaySound(SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
end
W.Click = Click

-- Nine-slice from a square texture
function W.NineSlice(frame, file, texSize, corner, edge, layer, sub)
    local parts = {}
    local c = corner / texSize
    edge = edge or corner
    local coords = {
        { 0, c, 0, c }, { c, 1 - c, 0, c }, { 1 - c, 1, 0, c },
        { 0, c, c, 1 - c }, { c, 1 - c, c, 1 - c }, { 1 - c, 1, c, 1 - c },
        { 0, c, 1 - c, 1 }, { c, 1 - c, 1 - c, 1 }, { 1 - c, 1, 1 - c, 1 },
    }
    for i = 1, 9 do
        local t = W.Tex(frame, file, layer or "BACKGROUND", sub)
        t:SetTexCoord(unpack(coords[i]))
        parts[i] = t
    end
    local tl, tm, tr, ml, mm, mr, bl, bm, br = unpack(parts)
    tl:SetPoint("TOPLEFT") tl:SetSize(edge, edge)
    tr:SetPoint("TOPRIGHT") tr:SetSize(edge, edge)
    bl:SetPoint("BOTTOMLEFT") bl:SetSize(edge, edge)
    br:SetPoint("BOTTOMRIGHT") br:SetSize(edge, edge)
    tm:SetPoint("TOPLEFT", tl, "TOPRIGHT") tm:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    bm:SetPoint("TOPLEFT", bl, "TOPRIGHT") bm:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    ml:SetPoint("TOPLEFT", tl, "BOTTOMLEFT") ml:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    mr:SetPoint("TOPLEFT", tr, "BOTTOMLEFT") mr:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    mm:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT") mm:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    local obj = { parts = parts }
    function obj:SetVertexColor(r, g, b, a)
        for _, t in ipairs(parts) do t:SetVertexColor(r, g, b, a or 1) end
    end
    return obj
end

---------------------------------------------------------------------------
-- Three-slice along x: the caps keep their shape, the middle stretches
---------------------------------------------------------------------------

function W.ThreeSlice(parent, file, texW, capPx, capW, layer, sub)
    local c = capPx / texW
    local l = W.Tex(parent, file, layer, sub)
    local m = W.Tex(parent, file, layer, sub)
    local r = W.Tex(parent, file, layer, sub)
    l:SetTexCoord(0, c, 0, 1)
    m:SetTexCoord(c, 1 - c, 0, 1)
    r:SetTexCoord(1 - c, 1, 0, 1)
    l:SetPoint("TOPLEFT") l:SetPoint("BOTTOMLEFT") l:SetWidth(capW)
    r:SetPoint("TOPRIGHT") r:SetPoint("BOTTOMRIGHT") r:SetWidth(capW)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT") m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    local obj = { parts = { l, m, r } }
    function obj:SetVertexColor(cr, cg, cb, ca)
        for _, t in ipairs(self.parts) do t:SetVertexColor(cr, cg, cb, ca or 1) end
    end
    return obj
end

---------------------------------------------------------------------------
-- Section: a gold heading over a bronze rule led by a diamond
---------------------------------------------------------------------------

function W.Section(parent, title, w, h)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(w, h)
    local t = W.Text(s, 16, W.GOLD, W.TITLE_FONT)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(title or "")
    t:SetShadowColor(0, 0, 0, 1)
    t:SetShadowOffset(1, -1)
    local rule = W.Tex(s, "f_rule", "ARTWORK")
    rule:SetPoint("TOPLEFT", t, "BOTTOMLEFT", -4, 1)
    rule:SetSize(math.min(w, 250), 16)
    s.title = t
    s.y = -30
    function s:Add(widget, height, x)
        widget:SetPoint("TOPLEFT", self, "TOPLEFT", x or 2, self.y)
        widget:SetPoint("RIGHT", self, "RIGHT", 0, 0)
        self.y = self.y - height
        return widget
    end
    return s
end

---------------------------------------------------------------------------
-- Check: a dark well in a bronze rim, ticked in the page's colour
---------------------------------------------------------------------------

function W.Check(parent, label, tip, get, set, onLeather)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(22)
    local box = W.Tex(f, "f_check", "ARTWORK")
    box:SetSize(24, 24)
    box:SetPoint("LEFT", -4, 0)
    local tick = W.Tex(f, "f_tick", "OVERLAY")
    tick:SetSize(22, 22)
    tick:SetPoint("CENTER", box, "CENTER", 1, 1)
    local text = onLeather and W.GoldText(f, 12, W.FONT) or W.Text(f, 12)
    text:SetPoint("LEFT", box, "RIGHT", 3, 0)
    text:SetPoint("RIGHT", 0, 0)
    text:SetText(label)
    if not onLeather then
        text:SetShadowColor(0, 0, 0, 0.9)
        text:SetShadowOffset(1, -1)
    end
    local hover = false

    local function paint()
        local on = get()
        tick:SetShown(on)
        tick:SetVertexColor(W.AccentInk(0.9))
        box:SetVertexColor(hover and 1 or 0.9, hover and 1 or 0.9, hover and 1 or 0.9)
        if onLeather then
            text:SetTextColor(unpack(hover and W.INK or W.GOLD))
        else
            text:SetTextColor(unpack(hover and { 1, 1, 1 } or W.INK))
        end
    end
    f:SetScript("OnClick", function()
        set(not get())
        Click()
    end)
    f:SetScript("OnEnter", function() hover = true paint() end)
    f:SetScript("OnLeave", function() hover = false paint() end)
    W.Tooltip(f, label, tip)
    function f:Refresh() paint() end
    W.OnAccent(paint)
    return W.Track(f)
end

---------------------------------------------------------------------------
-- Slider: a groove in a bronze rim, filled in the page's colour up to the
-- value, with a bronze rivet for a knob
---------------------------------------------------------------------------

-- the groove, its fill and the knob on a Slider; returns the painter
function W.SliderTrack(s, knobSize)
    local track = CreateFrame("Frame", nil, s)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(16)
    track:SetFrameLevel(math.max(s:GetFrameLevel() - 1, 0))
    W.ThreeSlice(track, "f_track", 256, 16, 8, "BACKGROUND")
    local fill = CreateFrame("Frame", nil, track)
    fill:SetPoint("LEFT", 1, 0)
    fill:SetHeight(16)
    local paint = W.ThreeSlice(fill, "f_fill", 256, 12, 6, "ARTWORK")
    s:SetThumbTexture(ART .. "f_knob")
    s:GetThumbTexture():SetSize(knobSize or 20, knobSize or 20)
    W.OnAccent(function(r, g, b) paint:SetVertexColor(r, g, b, 1) end)
    local knob = knobSize or 20
    return function(p)
        -- up to the knob's centre, where the game draws it: the knob's centre
        -- runs from half a knob in to half a knob short of the end
        local w = knob / 2 + (s:GetWidth() - knob) * math.max(0, math.min(1, p)) - 1
        fill:SetShown(w >= 12)
        fill:SetWidth(math.max(w, 12))
    end
end

function W.Slider(parent, label, minV, maxV, step, get, set, fmt, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(42)
    local text = W.Text(f, 12)
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    local value = W.Text(f, 14, W.GOLD, W.TITLE_FONT)
    value:SetPoint("TOPRIGHT", -2, 2)
    value:SetJustifyH("RIGHT")
    value:SetShadowColor(0, 0, 0, 1)
    value:SetShadowOffset(1, -1)

    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(22)
    s:SetPoint("TOPLEFT", 0, -16)
    s:SetPoint("TOPRIGHT", 0, -16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local fillTo = W.SliderTrack(s)

    local format = fmt or function(v) return tostring(v) end
    local updating = false
    local function show(v)
        value:SetText(format(v))
        fillTo((v - minV) / (maxV - minV))
    end
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        show(v)
        if not updating and v ~= get() then set(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(math.min(math.max(self:GetValue() + delta * step, minV), maxV))
    end)
    s:SetScript("OnSizeChanged", function() show(get()) end)
    W.Tooltip(s, label, tip)
    function f:Refresh()
        updating = true
        s:SetValue(get())
        updating = false
        show(get())
    end
    f:Refresh()
    return W.Track(f)
end

---------------------------------------------------------------------------
-- Button: an iron plate in a bronze rim; lit in the page's colour on hover
---------------------------------------------------------------------------

function W.Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, 26)
    W.NineSlice(b, "f_button", 128, 24, 10, "BACKGROUND", 0)
    local glow = W.Tex(b, "f_tab_glow", "ARTWORK")
    glow:SetPoint("TOPLEFT", 2, -2)
    glow:SetPoint("BOTTOMRIGHT", -2, 2)
    glow:SetAlpha(0)
    local text = W.Text(b, 12, W.INK)
    text:SetPoint("CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText(label)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    b.text = text
    b:SetScript("OnEnter", function() glow:SetAlpha(0.3) end)
    b:SetScript("OnLeave", function() glow:SetAlpha(0) end)
    b:SetScript("OnMouseDown", function() text:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function() text:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnClick", function(self)
        Click()
        onClick(self)
    end)
    W.OnAccent(function(r, g, bb) glow:SetVertexColor(r, g, bb) end)
    return b
end

---------------------------------------------------------------------------
-- Selector:  label ............  <  value  >   (value in a dark well)
---------------------------------------------------------------------------

-- opts: leather (gold label on the cover), boxWidth, fontOf(value) for values
-- written in another alphabet
function W.Selector(parent, label, values, nameOf, get, set, extraWidth, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(26)
    local text = opts.leather and W.GoldText(f, 12, W.FONT) or W.Text(f, 12)
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("RIGHT", -(extraWidth or 0), 0)
    box:SetSize(opts.boxWidth or 140, 24)
    local well = CreateFrame("Frame", nil, box)
    well:SetPoint("TOPLEFT", 18, 1)
    well:SetPoint("BOTTOMRIGHT", -18, -1)
    W.NineSlice(well, "f_inset", 128, 24, 9, "BACKGROUND", 0)
    -- on the well itself: a child frame draws over its parent's text
    local valueText = W.Text(well, 12, W.INK)
    valueText:SetPoint("LEFT", 6, 0)
    valueText:SetPoint("RIGHT", -6, 0)
    valueText:SetJustifyH("CENTER")
    if valueText.SetWordWrap then valueText:SetWordWrap(false) end
    f.box = box

    local function index()
        local cur = get()
        for i, v in ipairs(values) do if v == cur then return i end end
        return 1
    end
    local function arrow(dir)
        local a = CreateFrame("Button", nil, box)
        a:SetSize(20, 20)
        a:SetPoint(dir < 0 and "LEFT" or "RIGHT", 0, 0)
        local t = W.Tex(a, "f_arrow", "ARTWORK")
        t:SetVertexColor(0.85, 0.85, 0.85)
        t:SetAllPoints()
        if dir < 0 then t:SetTexCoord(1, 0, 0, 1) end
        a:SetScript("OnEnter", function() t:SetVertexColor(1, 1, 1) end)
        a:SetScript("OnLeave", function() t:SetVertexColor(0.85, 0.85, 0.85) end)
        a:SetScript("OnClick", function()
            if #values == 0 then return end
            set(values[(index() - 1 + dir) % #values + 1])
            Click()
        end)
    end
    arrow(-1)
    arrow(1)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta)
        if #values == 0 then return end
        set(values[(index() - 1 - delta) % #values + 1])
    end)
    function f:Refresh()
        local v = get()
        if opts.fontOf then valueText:SetFont(opts.fontOf(v) or W.FONT, 12, "") end
        valueText:SetText(v ~= nil and nameOf(v) or "")
    end
    f:Refresh()
    return W.Track(f)
end

---------------------------------------------------------------------------
-- Colour: gems; the chosen one ringed in bronze
---------------------------------------------------------------------------

local function OpenPicker(r, g, b, onChange)
    local function current() return ColorPickerFrame:GetColorRGB() end
    local function cancel(previous)
        local p = previous or ColorPickerFrame.previousValues
        if type(p) == "table" then onChange(p.r or p[1] or r, p.g or p[2] or g, p.b or p[3] or b) end
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = function() onChange(current()) end,
            cancelFunc = function(previous) cancel(previous) end,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame.func = function() onChange(current()) end
        ColorPickerFrame.cancelFunc = function(previous) cancel(previous) end
        ColorPickerFrame:SetColorRGB(r, g, b)
        ShowUIPanel(ColorPickerFrame)
    end
end

W.PRESETS = {
    { 1.00, 0.55, 0.10 }, { 1.00, 0.82, 0.18 }, { 0.30, 0.95, 0.30 }, { 0.20, 0.85, 0.75 },
    { 0.30, 0.60, 1.00 }, { 0.70, 0.40, 1.00 }, { 1.00, 0.35, 0.60 }, { 0.95, 0.20, 0.15 },
    { 1.00, 1.00, 1.00 },
}

local function Same(c, r, g, b)
    return math.abs(c.r - r) < 0.02 and math.abs(c.g - g) < 0.02 and math.abs(c.b - b) < 0.02
end

function W.ColorRow(parent, label, tip, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(38)
    local text = W.Text(f, 12)
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)

    local loop = W.Tex(f, "f_ring", "OVERLAY")
    loop:SetSize(28, 28)

    local function dab(size, x, color, onClick)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(size, size)
        b:SetPoint("LEFT", x, 0)
        local t = W.Tex(b, "f_gem", "ARTWORK")
        t:SetAllPoints()
        if color then t:SetVertexColor(color[1], color[2], color[3]) end
        b.tex = t
        b:SetScript("OnClick", function() onClick() Click() end)
        b:SetScript("OnEnter", function() t:ClearAllPoints() t:SetPoint("CENTER") t:SetSize(size + 3, size + 3) end)
        b:SetScript("OnLeave", function() t:ClearAllPoints() t:SetAllPoints() end)
        return b
    end

    local main = dab(34, 48, nil, function()
        local c = get()
        OpenPicker(c.r, c.g, c.b, function(r, g, b) set(r, g, b) end)
    end)
    W.Tooltip(main, label, tip)
    local presets = {}
    for i, c in ipairs(W.PRESETS) do
        presets[i] = dab(20, 92 + (i - 1) * 21, c, function() set(c[1], c[2], c[3]) end)
        presets[i].color = c
    end

    function f:Refresh()
        local c = get()
        main.tex:SetVertexColor(c.r, c.g, c.b)
        loop:Hide()
        for _, p in ipairs(presets) do
            if Same(c, p.color[1], p.color[2], p.color[3]) then
                loop:ClearAllPoints()
                loop:SetPoint("CENTER", p, "CENTER", 0, 0)
                loop:Show()
            end
        end
    end
    f:Refresh()
    return W.Track(f)
end

---------------------------------------------------------------------------
-- Stamps in a row (the plate's states): small plates, the chosen one lit
---------------------------------------------------------------------------

function W.Stamps(parent, items, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(24)
    local buttons = {}
    local function paint()
        for _, b in ipairs(buttons) do
            local on = get() == b.value
            b.glow:SetAlpha(on and 0.35 or 0)
            b.text:SetTextColor(unpack(on and { 1, 1, 1 } or W.INK_SOFT))
        end
    end
    local count = #items
    for i, item in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(24)
        b.value = item[1]
        W.NineSlice(b, "f_button", 128, 24, 8, "BACKGROUND", 0)
        b.glow = W.Tex(b, "f_tab_glow", "ARTWORK")
        b.glow:SetPoint("TOPLEFT", 2, -2)
        b.glow:SetPoint("BOTTOMRIGHT", -2, 2)
        b.text = W.Text(b, 11)
        b.text:SetPoint("CENTER")
        b.text:SetJustifyH("CENTER")
        b.text:SetText(item[2])
        b.text:SetShadowColor(0, 0, 0, 1)
        b.text:SetShadowOffset(1, -1)
        b:SetScript("OnClick", function() set(item[1]) paint() Click() end)
        buttons[i] = b
    end
    f:SetScript("OnSizeChanged", function(_, w)
        local bw = (w - (count - 1) * 4) / count
        for i, b in ipairs(buttons) do
            b:ClearAllPoints()
            b:SetPoint("LEFT", (i - 1) * (bw + 4), 0)
            b:SetWidth(bw)
        end
    end)
    W.OnAccent(function(r, g, b)
        for _, btn in ipairs(buttons) do btn.glow:SetVertexColor(r, g, b) end
        paint()
    end)
    function f:Refresh() paint() end
    return W.Track(f)
end

---------------------------------------------------------------------------
-- Plate: a dark picture in a bronze frame, with bracket corners
---------------------------------------------------------------------------

function W.Plate(parent, w, h)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(w, h)
    W.NineSlice(p, "f_plate", 128, 24, 10, "BACKGROUND", 0)
    local corners = {
        { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
        { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 },
    }
    for _, c in ipairs(corners) do
        local t = W.Tex(p, "f_corner", "OVERLAY", 2)
        t:SetSize(20, 20)
        t:SetPoint(c[1], c[1]:find("LEFT") and -3 or 3, c[1]:find("TOP") and 3 or -3)
        t:SetTexCoord(c[2], c[3], c[4], c[5])
    end
    return p
end

---------------------------------------------------------------------------
-- Link: a label and an address to copy (the game can't open web pages);
-- clicking selects it all, Ctrl+C copies, Esc lets go
---------------------------------------------------------------------------

function W.Link(parent, label, url, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(24)
    local text = W.Text(f, 12, W.INK_SOFT)
    text:SetPoint("LEFT", 0, 0)
    text:SetWidth(78)
    text:SetText(label)
    local box = CreateFrame("EditBox", nil, f)
    box:SetPoint("LEFT", 80, 0)
    box:SetPoint("RIGHT", 0, 0)
    box:SetHeight(22)
    box:SetAutoFocus(false)
    box:SetFont(W.FONT, 11, "")
    box:SetTextColor(unpack(W.INK))
    box:SetTextInsets(8, 8, 0, 0)
    W.NineSlice(box, "f_inset", 128, 24, 9, "BACKGROUND", 0)
    local function reset()
        box:SetText(url)
        box:SetCursorPosition(0)
    end
    reset()
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) reset() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self, user) if user then reset() self:HighlightText() end end)
    W.Tooltip(box, label, tip)
    return f
end

---------------------------------------------------------------------------
-- Confirm: the game's yes/no dialog (deleting the log, reloading)
---------------------------------------------------------------------------

function W.Confirm(text, onAccept, acceptLabel)
    if not (StaticPopupDialogs and StaticPopup_Show) then
        onAccept()
        return
    end
    StaticPopupDialogs.GLOWINGNODES_CONFIRM = {
        text = "%s",
        button1 = acceptLabel or YES or "Yes",
        button2 = acceptLabel and (LATER or CANCEL or "Later") or (NO or "No"),
        OnAccept = function(_, data) if data then data() end end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    StaticPopup_Show("GLOWINGNODES_CONFIRM", text, nil, onAccept)
end
