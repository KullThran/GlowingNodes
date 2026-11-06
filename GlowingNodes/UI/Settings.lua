-- Settings.lua
-- An entry under Esc > Options > AddOns that opens the addon's own window.
-- A canvas panel only: no settings registered in Blizzard's list, so nothing
-- of this addon runs inside the options search.
local _, ns = ...
local L = ns.L
local W = ns.W

local function Build()
    local panel = CreateFrame("Frame")
    panel.name = "Glowing Nodes"

    local gem = W.Tex(panel, "emblem", "ARTWORK")
    gem:SetSize(56, 56)
    gem:SetPoint("TOPLEFT", 16, -16)
    local title = W.GoldText(panel, 26)
    title:SetPoint("LEFT", gem, "RIGHT", 12, 4)
    title:SetText(L.TITLE)
    local text = W.Text(panel, 12, { 0.85, 0.82, 0.76 })
    text:SetPoint("TOPLEFT", gem, "BOTTOMLEFT", 0, -14)
    text:SetWidth(520)
    text:SetText(L.SETTINGS_TEXT .. "\n\n" .. L.STATUS_LIMIT)

    -- the game's own button: ink on the dark options panel wouldn't read
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(220, 28)
    open:SetText(L.OPEN)
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        ns.Window:Open()
    end)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -18)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

ns.On("Enable", function()
    local ok, err = pcall(Build)
    if not ok then ns.Debug("settings panel: " .. tostring(err)) end
end)
