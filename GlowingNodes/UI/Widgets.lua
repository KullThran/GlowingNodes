-- Widgets.lua
-- The options window is a gatherer's field notebook: parchment in a stitched
-- leather cover. The widgets are written on the page: ink check boxes, an
-- engraved ruler with a brass needle, watercolour dabs for colours, ruled
-- stamps for buttons. Textures come from tools/photoshop/Build-NodesArt.ps1.
-- The "accent" is the colour of the node kind on the page, used as coloured
-- ink and watercolour washes, never as glow.
local _, ns = ...

local W = {}
ns.W = W

local ART = ns.ART
-- Fonts with the glyphs of the client's language: Friz Quadrata and Morpheus
-- have no Cyrillic, Korean or Chinese, so those clients get their own fonts.
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
local CLIENT = GetLocale and GetLocale() or "enUS"
W.FONT = FirstFont(STANDARD_TEXT_FONT, "Fonts\\FRIZQT__.TTF")
if CLIENT == "ruRU" then
    W.TITLE_FONT = FirstFont("Fonts\\MORPHEUS_CYR.TTF", W.FONT)
elseif CLIENT == "koKR" or CLIENT == "zhCN" or CLIENT == "zhTW" then
    W.TITLE_FONT = W.FONT
else
    W.TITLE_FONT = FirstFont("Fonts\\MORPHEUS.TTF", W.FONT)
end

W.INK = { 0.92, 0.85, 0.70 }      -- light ink: the page is dark vellum
W.INK_SOFT = { 0.64, 0.56, 0.43 }
W.GOLD = { 0.93, 0.79, 0.50 }
W.TAN = { 0.74, 0.62, 0.45 }
W.DEFAULT_ACCENT = { 0.56, 0.36, 0.14 } -- sepia, the General page
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
-- Section: a heading written in the notebook, underlined with a flourish
---------------------------------------------------------------------------

function W.Section(parent, title, w, h)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(w, h)
    local t = W.Text(s, 16, W.INK, W.TITLE_FONT)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(title or "")
    local rule = W.Ink(s, "flourish", "ARTWORK")
    rule:SetPoint("TOPLEFT", t, "BOTTOMLEFT", -2, -1)
    rule:SetSize(math.min(w, 200), 12)
    rule:SetAlpha(0.8)
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
-- Check: an inked box, ticked in the page's colour
---------------------------------------------------------------------------

function W.Check(parent, label, tip, get, set, onLeather)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(22)
    local box = W.Tex(f, "check_box", "ARTWORK")
    box:SetSize(22, 22)
    box:SetPoint("LEFT", -3, 0)
    local tick = W.Tex(f, "check_tick", "OVERLAY")
    tick:SetSize(24, 24)
    tick:SetPoint("CENTER", box, "CENTER", 2, 3)
    local text = onLeather and W.GoldText(f, 12, W.FONT) or W.Text(f, 12)
    text:SetPoint("LEFT", box, "RIGHT", 4, 0)
    text:SetPoint("RIGHT", 0, 0)
    text:SetText(label)
    local hover = false

    local function paint()
        local on = get()
        tick:SetShown(on)
        if onLeather then
            box:SetVertexColor(unpack(W.GOLD))
            tick:SetVertexColor(1, 0.9, 0.62)
            text:SetTextColor(unpack(hover and { 1, 0.92, 0.7 } or W.GOLD))
        else
            box:SetVertexColor(unpack(W.INK))
            tick:SetVertexColor(W.AccentInk(0.75))
            if hover then
                text:SetTextColor(W.AccentInk(0.7))
            else
                text:SetTextColor(unpack(on and W.INK or W.INK_SOFT))
            end
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
-- Slider: a ruler with a brass needle, coloured wash up to the value
---------------------------------------------------------------------------

function W.Slider(parent, label, minV, maxV, step, get, set, fmt, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(42)
    local text = W.Text(f, 12)
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    local value = W.Text(f, 13, W.INK, W.TITLE_FONT)
    value:SetPoint("TOPRIGHT", -2, 1)
    value:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(22)
    s:SetPoint("TOPLEFT", 0, -16)
    s:SetPoint("TOPRIGHT", 0, -16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    local wash = W.Tex(s, "wash", "BACKGROUND")
    wash:SetPoint("LEFT", 0, -3)
    wash:SetHeight(18)
    local ruler = W.Ink(s, "ruler", "ARTWORK")
    ruler:SetPoint("LEFT", 0, 0)
    ruler:SetPoint("RIGHT", 0, 0)
    ruler:SetHeight(20)
    s:SetThumbTexture(ART .. "nib")
    local thumb = s:GetThumbTexture()
    thumb:SetSize(18, 18)

    local format = fmt or function(v) return tostring(v) end
    local updating = false
    local function show(v)
        value:SetText(format(v))
        local p = (v - minV) / (maxV - minV)
        wash:SetWidth(math.max(s:GetWidth() * p, 0.01))
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
    W.OnAccent(function(r, g, b) wash:SetVertexColor(r, g, b, 0.5) end)
    f:Refresh()
    return W.Track(f)
end

---------------------------------------------------------------------------
-- Button: a ruled stamp; a wash of colour on hover
---------------------------------------------------------------------------

function W.Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, 26)
    local wash = W.Tex(b, "wash", "BACKGROUND", -1)
    wash:SetPoint("TOPLEFT", 2, 2)
    wash:SetPoint("BOTTOMRIGHT", -2, -4)
    wash:SetAlpha(0)
    W.NineSlice(b, "stamp9", 64, 10, 8, "BACKGROUND", 0)
    local text = W.Text(b, 12)
    text:SetPoint("CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText(label)
    b.text = text
    b:SetScript("OnEnter", function() wash:SetAlpha(1) end)
    b:SetScript("OnLeave", function() wash:SetAlpha(0) end)
    b:SetScript("OnMouseDown", function() text:SetPoint("CENTER", 1, -1) end)
    b:SetScript("OnMouseUp", function() text:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnClick", function(self)
        Click()
        onClick(self)
    end)
    W.OnAccent(function(r, g, bb) wash:SetVertexColor(r, g, bb, 0.45) end)
    return b
end

---------------------------------------------------------------------------
-- Selector:  label ............  <  value  >   (value underlined)
---------------------------------------------------------------------------

function W.Selector(parent, label, values, nameOf, get, set, extraWidth)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(26)
    local text = W.Text(f, 12)
    text:SetPoint("LEFT", 0, 0)
    text:SetText(label)
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("RIGHT", -(extraWidth or 0), 0)
    box:SetSize(140, 24)
    local valueText = W.Text(box, 12, W.INK)
    valueText:SetPoint("CENTER", 0, 1)
    valueText:SetJustifyH("CENTER")
    local line = W.Ink(box, "divider", "ARTWORK")
    line:SetPoint("BOTTOMLEFT", 22, 1)
    line:SetPoint("BOTTOMRIGHT", -22, 1)
    line:SetHeight(6)

    local function index()
        local cur = get()
        for i, v in ipairs(values) do if v == cur then return i end end
        return 1
    end
    local function arrow(dir)
        local a = CreateFrame("Button", nil, box)
        a:SetSize(22, 22)
        a:SetPoint(dir < 0 and "LEFT" or "RIGHT", 0, 0)
        local t = W.Ink(a, "arrow", "ARTWORK")
        t:SetAllPoints()
        if dir < 0 then t:SetTexCoord(1, 0, 0, 1) end
        a:SetScript("OnEnter", function() t:SetVertexColor(W.AccentInk(0.8)) end)
        a:SetScript("OnLeave", function() t:SetVertexColor(unpack(W.INK)) end)
        a:SetScript("OnClick", function()
            set(values[(index() - 1 + dir) % #values + 1])
            Click()
        end)
    end
    arrow(-1)
    arrow(1)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta)
        set(values[(index() - 1 - delta) % #values + 1])
    end)
    function f:Refresh()
        valueText:SetText(nameOf(get()))
    end
    f:Refresh()
    return W.Track(f)
end

---------------------------------------------------------------------------
-- Colour: watercolour dabs; the chosen one has a pencil loop round it
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

    local loop = W.Tex(f, "circle", "OVERLAY")
    loop:SetVertexColor(0.86, 0.80, 0.68)
    loop:SetSize(30, 30)

    local function dab(size, x, color, onClick)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(size, size)
        b:SetPoint("LEFT", x, 0)
        local t = W.Tex(b, "blot", "ARTWORK")
        t:SetAllPoints()
        if color then t:SetVertexColor(color[1], color[2], color[3], 0.95) end
        b.tex = t
        b:SetScript("OnClick", function() onClick() Click() end)
        b:SetScript("OnEnter", function() t:SetSize(size + 3, size + 3) t:ClearAllPoints() t:SetPoint("CENTER") end)
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
        main.tex:SetVertexColor(c.r, c.g, c.b, 0.95)
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
-- Stamps in a row (the plate's states)
---------------------------------------------------------------------------

function W.Stamps(parent, items, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(22)
    local buttons = {}
    local function paint()
        for _, b in ipairs(buttons) do
            local on = get() == b.value
            b.wash:SetAlpha(on and 1 or 0)
            b.text:SetTextColor(unpack(on and W.INK or W.INK_SOFT))
        end
    end
    local count = #items
    for i, item in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(22)
        b.value = item[1]
        b.wash = W.Tex(b, "wash", "BACKGROUND", -1)
        b.wash:SetPoint("TOPLEFT", 1, 2)
        b.wash:SetPoint("BOTTOMRIGHT", -1, -3)
        W.NineSlice(b, "stamp9", 64, 10, 7, "BACKGROUND", 0)
        b.text = W.Text(b, 11)
        b.text:SetPoint("CENTER")
        b.text:SetJustifyH("CENTER")
        b.text:SetText(item[2])
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
        for _, btn in ipairs(buttons) do btn.wash:SetVertexColor(r, g, b, 0.45) end
        paint()
    end)
    function f:Refresh() paint() end
    return W.Track(f)
end

---------------------------------------------------------------------------
-- Plate: a dark picture pasted in with four photo corners
---------------------------------------------------------------------------

function W.Plate(parent, w, h)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(w, h)
    W.NineSlice(p, "plate9", 64, 8, 6, "BACKGROUND", 0)
    local corners = {
        { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
        { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 },
    }
    for _, c in ipairs(corners) do
        local t = W.Tex(p, "corner", "OVERLAY", 2)
        t:SetSize(22, 22)
        t:SetPoint(c[1], c[1]:find("LEFT") and -4 or 4, c[1]:find("TOP") and 4 or -4)
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
    box:SetTextInsets(6, 6, 0, 0)
    W.NineSlice(box, "stamp9", 64, 10, 7, "BACKGROUND", 0)
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
