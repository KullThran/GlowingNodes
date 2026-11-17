-- CopyBox.lua
-- A small window with a text to copy (Ctrl+C): the diagnostic of /gn diag.
-- The text is selected when it opens and can't be typed over; Escape or
-- Close shuts it, and it can be dragged.
local _, ns = ...
local W = ns.W

local Box = {}
ns.CopyBox = Box

local WIDTH, HEIGHT = 520, 380

local function Build()
    local f = CreateFrame("Frame", "GlowingNodesCopyBox", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    W.NineSlice(f, "f_plate", 128, 24, 10, "BACKGROUND", 0)
    f:Hide()
    table.insert(UISpecialFrames, "GlowingNodesCopyBox")
    Box.frame = f

    local title = W.GoldText(f, 16, W.TITLE_FONT)
    title:SetPoint("TOPLEFT", 18, -16)
    Box.title = title
    local hint = W.Text(f, 11, W.INK_SOFT)
    hint:SetPoint("TOPLEFT", 18, -42)
    hint:SetWidth(WIDTH - 36)
    hint:SetSpacing(2)
    Box.hint = hint

    local well = CreateFrame("Frame", nil, f)
    well:SetPoint("TOPLEFT", 14, -78)
    well:SetPoint("BOTTOMRIGHT", -14, 50)
    W.NineSlice(well, "f_inset", 128, 24, 9, "BACKGROUND", 0)
    local scroll = CreateFrame("ScrollFrame", nil, well)
    scroll:SetPoint("TOPLEFT", 8, -6)
    scroll:SetPoint("BOTTOMRIGHT", -8, 6)
    Box.scroll = scroll
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFont(W.CLIENT_FONT or W.FONT, 11, "")
    edit:SetTextColor(unpack(W.INK))
    edit:SetWidth(WIDTH - 28 - 16)
    scroll:SetScrollChild(edit)
    Box.edit = edit
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 40)))
    end)
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function() edit:SetFocus() end)
    -- read only: whatever is typed, the text comes back, selected
    edit:SetScript("OnTextChanged", function(self, user)
        if user then
            self:SetText(Box.text or "")
            self:HighlightText()
        end
    end)
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)

    local close = W.Button(f, CLOSE or "Close", 120, function() f:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -14, 14)
    Box.close = close
end

-- shows the window with that text, selected for Ctrl+C
function Box:Show(title, hint, text)
    if not Box.frame then Build() end
    Box.text = text or ""
    Box.title:SetText(title or "")
    Box.hint:SetText(hint or "")
    Box.edit:SetText(Box.text)
    Box.scroll:SetVerticalScroll(0)
    Box.frame:Show()
    Box.edit:SetFocus()
    Box.edit:HighlightText()
end
