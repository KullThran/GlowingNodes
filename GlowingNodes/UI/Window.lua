-- Window.lua
-- The options window: a field notebook. Leather cover with the title stamped
-- in gold, a parchment page with paper index tabs down the left margin, and
-- on each page the settings written in ink. The node-kind pages show the
-- glow on a pasted plate; the Alert page shows the alert card itself.
-- Layout numbers match the art (tools/photoshop/nodes_art.py).
local _, ns = ...
local L = ns.L
local W = ns.W
local Glow, Skills, Sounds, Data = ns.Glow, ns.Skills, ns.Sounds, ns.NodeData

local Window = {}
ns.Window = Window

local WIDTH, HEIGHT = 768, 512
local HEADER_H = 64
local RAIL_X = 188               -- margin rule after the tabs
local CONTENT_X, CONTENT_Y = 204, 78
local TABS = { "general", "ore", "herb", "skin", "alert", "about" }
local SAMPLE = { ore = 65, herb = 50, skin = 35 }
local SAMPLE_NAME = { ore = "SAMPLE_NODE", herb = "PROF_herb", skin = "PROF_skin" }
local ICONS = {
    general = ns.ART .. "emblem",
    ore = Data.CATEGORY_ICONS.ore,
    herb = Data.CATEGORY_ICONS.herb,
    skin = Data.CATEGORY_ICONS.skin,
    alert = "Interface\\Icons\\INV_Letter_15",
    about = "Interface\\Icons\\INV_Misc_Book_09",
}

local frame
local pages, tabs = {}, {}
local current

local function AccentFor(tab)
    if ns.db[tab] and ns.db[tab].color then
        local c = ns.db[tab].color
        return c.r, c.g, c.b
    end
    return unpack(W.DEFAULT_ACCENT)
end

local function Pct(v) return ("%d%%"):format(v * 100 + 0.5) end

---------------------------------------------------------------------------
-- Node-kind page: plate with the glow, then Glow and Sound written beside
---------------------------------------------------------------------------

local function BuildPlate(page, cat)
    local plate = W.Plate(page, 206, 286)
    plate:SetPoint("TOPLEFT", 6, -6)
    if plate.SetClipsChildren then plate:SetClipsChildren(true) end

    local node = CreateFrame("Frame", nil, plate)
    node:SetSize(40, 40)
    node:SetPoint("CENTER", 0, -50)
    local icon = node:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICONS[cat])
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local anchor = CreateFrame("Frame", nil, plate)
    anchor:SetSize(1, 1)
    anchor:SetPoint("CENTER", node, "CENTER")
    anchor:SetFrameLevel(node:GetFrameLevel() + 1)
    local glow = Glow.New(anchor)
    local state = "ready"

    local caption = W.Text(page, 13, W.INK_SOFT, W.TITLE_FONT)
    caption:SetPoint("TOP", plate, "BOTTOM", 0, -8)
    caption:SetJustifyH("CENTER")

    local function apply()
        local db = ns.db
        glow:Configure(db[cat], { numberSize = db.numberSize, greyLocked = db.greyLocked, dimFar = db.dimFar, scale = 0.78 })
        local required = SAMPLE[cat]
        local skill = Skills.Get(cat)
        if state == "locked" then
            skill = required - 15
        elseif not skill or skill < required then
            skill = required + 10
        end
        if db.showNumber then
            glow:SetNumber(Glow.NumberFor(required, skill, db.showMine, true))
        else
            glow:SetNumber("")
        end
        caption:SetText(L.PLATE_CAPTION:format(L["CAT_" .. cat]))
        if not db[cat].enabled then glow:Hide() return end
        if not glow:IsShown() then
            glow:Attach(anchor, 0, 0)
            glow:Show(state)
        else
            glow:SetState(state)
        end
        glow.textFrame:SetFrameLevel(anchor:GetFrameLevel() + 8)
    end

    local stamps = W.Stamps(page, {
        { "far", L.STATE_FAR }, { "ready", L.STATE_READY }, { "locked", L.STATE_LOCKED },
    }, function() return state end, function(v)
        state = v
        apply()
        if v == "ready" then glow:Flare() end
    end)
    stamps:SetPoint("TOPLEFT", plate, "BOTTOMLEFT", 0, -32)
    stamps:SetPoint("TOPRIGHT", plate, "BOTTOMRIGHT", 0, -32)

    page.preview = { apply = apply }
end

local function BuildCategoryPage(page, cat)
    BuildPlate(page, cat)
    local cfg = function() return ns.db[cat] end
    local function setter(key) return function(v) ns.SetCat(cat, key, v) end end

    local glow = W.Section(page, L.CARD_GLOW, 300, 250)
    glow:SetPoint("TOPLEFT", 236, -2)
    glow:Add(W.Check(glow, L.GLOW_ON, L.GLOW_ON_TIP, function() return cfg().enabled end, setter("enabled")), 28)
    glow:Add(W.ColorRow(glow, L.COLOR, L.COLOR_TIP, function() return cfg().color end, function(r, g, b)
        ns.SetCat(cat, "color", { r = r, g = g, b = b })
    end), 44)
    glow:Add(W.Slider(glow, L.INTENSITY, 0.5, 3, 0.1, function() return cfg().intensity end, setter("intensity"), Pct), 46)
    glow:Add(W.Slider(glow, L.SIZE, 0.5, 2, 0.05, function() return cfg().size end, setter("size"), Pct), 48)
    glow:Add(W.Check(glow, L.PULSE, L.PULSE_TIP, function() return cfg().pulse end, setter("pulse")), 26)
    glow:Add(W.Check(glow, L.BEAM, L.BEAM_TIP, function() return cfg().beam end, setter("beam")), 26)

    local sound = W.Section(page, L.CARD_SOUND, 300, 130)
    sound:SetPoint("TOPLEFT", 236, -270)
    sound:Add(W.Check(sound, L.SOUND_ON, L.SOUND_ON_TIP, function() return cfg().soundOn end, setter("soundOn")), 28)
    local sel = sound:Add(W.Selector(sound, L.SOUND, Sounds.LIST, function(k) return L["SND_" .. k] end,
        function() return cfg().sound end, function(v)
            ns.SetCat(cat, "sound", v)
            Sounds.Play(v, cfg().volume, ns.db.channel, true)
        end, 72), 30)
    local play = W.Button(sel, L.TEST, 66, function() Sounds.PlayCategory(cat, true) end)
    play:SetPoint("RIGHT", 0, 0)
    play:SetHeight(24)
    sound:Add(W.Selector(sound, L.VOLUME, Sounds.VOLUMES, function(v) return L["VOL_" .. v] end,
        function() return cfg().volume end, function(v)
            ns.SetCat(cat, "volume", v)
            Sounds.Play(cfg().sound, v, ns.db.channel, true)
        end, 72), 30)
end

---------------------------------------------------------------------------
-- General page
---------------------------------------------------------------------------

local function BuildGeneralPage(page)
    local function get(key) return function() return ns.db[key] end end
    local function set(key) return function(v) ns.Set(key, v) end end

    local number = W.Section(page, L.CARD_NUMBER, 256, 160)
    number:SetPoint("TOPLEFT", 6, -2)
    number:Add(W.Check(number, L.SHOW_NUMBER, L.SHOW_NUMBER_TIP, get("showNumber"), set("showNumber")), 26)
    number:Add(W.Check(number, L.SHOW_MINE, L.SHOW_MINE_TIP, get("showMine"), set("showMine")), 26)
    number:Add(W.Slider(number, L.NUMBER_SIZE, 14, 44, 1, get("numberSize"), set("numberSize")), 48)
    number:Add(W.Check(number, L.ONLY_KNOWN, L.ONLY_KNOWN_TIP, get("onlyKnown"), set("onlyKnown")), 26)

    local sounds = W.Section(page, L.CARD_SOUNDS_GENERAL, 256, 90)
    sounds:SetPoint("TOPLEFT", 6, -170)
    sounds:Add(W.Selector(sounds, L.CHANNEL, Sounds.CHANNELS, function(c) return L["CH_" .. c] end,
        get("channel"), set("channel")), 30)
    sounds:Add(W.Check(sounds, L.SOUND_READY, L.SOUND_READY_TIP, get("soundOnReady"), set("soundOnReady")), 26)

    local legend = W.Section(page, L.CARD_LEGEND, 256, 120)
    legend:SetPoint("TOPLEFT", 6, -270)
    local items = {
        { { 1, 0.15, 0.12 }, L.LEG_RED }, { { 1, 0.5, 0.1 }, L.LEG_ORANGE }, { { 1, 1, 0 }, L.LEG_YELLOW },
        { { 0.25, 1, 0.25 }, L.LEG_GREEN }, { { 0.6, 0.6, 0.6 }, L.LEG_GREY },
    }
    for i, item in ipairs(items) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local dab = W.Tex(legend, "blot", "ARTWORK")
        dab:SetSize(16, 16)
        dab:SetPoint("TOPLEFT", 2 + col * 126, -32 - row * 19)
        dab:SetVertexColor(item[1][1], item[1][2], item[1][3], 0.95)
        local t = W.Text(legend, 11)
        t:SetPoint("LEFT", dab, "RIGHT", 4, 0)
        t:SetText(item[2])
    end
    local q = W.Text(legend, 14, { 1, 0.82, 0.2 }, W.TITLE_FONT)
    q:SetPoint("TOPLEFT", 130, -68)
    q:SetText("?")
    local qt = W.Text(legend, 10, W.INK_SOFT)
    qt:SetPoint("TOPLEFT", q, "TOPRIGHT", 6, 1)
    qt:SetWidth(112)
    qt:SetText(L.LEG_GOLD)

    local behaviour = W.Section(page, L.CARD_BEHAVIOUR, 256, 160)
    behaviour:SetPoint("TOPLEFT", 280, -2)
    behaviour:Add(W.Check(behaviour, L.DIM_FAR, L.DIM_FAR_TIP, get("dimFar"), set("dimFar")), 26)
    behaviour:Add(W.Check(behaviour, L.GREY_LOCKED, L.GREY_LOCKED_TIP, get("greyLocked"), set("greyLocked")), 26)
    behaviour:Add(W.Slider(behaviour, L.HEIGHT, -140, 60, 1, get("height"), set("height"), nil, L.HEIGHT_TIP), 48)
    behaviour:Add(W.Check(behaviour, L.KEEP_INTERACT, L.KEEP_INTERACT_TIP, get("keepInteract"), set("keepInteract")), 26)

    local status = W.Section(page, L.CARD_STATUS, 256, 230)
    status:SetPoint("TOPLEFT", 280, -170)
    local lines = W.Text(status, 11)
    lines:SetPoint("TOPLEFT", 2, -30)
    lines:SetPoint("RIGHT", 0, 0)
    lines:SetJustifyV("TOP")
    lines:SetSpacing(3)
    local reset = W.Button(status, L.RESET, 120, function()
        ns.Addon.db:ResetProfile()
        ns.Print(L.MSG_RESET)
    end)
    reset:SetPoint("BOTTOMLEFT", 0, 30)
    local forget = W.Button(status, L.FORGET, 120, function()
        wipe(ns.global.learned)
        ns.Print(L.MSG_FORGOT)
        ns.Fire("Learned")
    end)
    forget:SetPoint("BOTTOMRIGHT", 0, 30)
    local debug = W.Check(status, L.DEBUG, L.DEBUG_TIP, get("debug"), set("debug"))
    debug:SetPoint("BOTTOMLEFT", 2, 2)
    debug:SetPoint("RIGHT", 0, 0)

    function page:UpdateStatus()
        local out = {}
        local ok = ns.SoftTarget:InteractKeyOn()
        out[#out + 1] = (ok and "|cff8fdc78" or "|cffff7058") .. (ok and L.STATUS_INTERACT_ON or L.STATUS_INTERACT_OFF) .. "|r"
        if InCombatLockdown() then out[#out + 1] = "|cffffc848" .. L.STATUS_COMBAT .. "|r" end
        local other = ns.ConflictingAddon()
        if other then out[#out + 1] = "|cffffa448" .. L.STATUS_CONFLICT:format(other) .. "|r" end
        out[#out + 1] = L.STATUS_LEARNED:format(Skills.LearnedCount())
        out[#out + 1] = "|cffb4a68c" .. L.STATUS_LIMIT .. "|r"
        lines:SetText(table.concat(out, "\n"))
    end
end

---------------------------------------------------------------------------
-- Alert page: the card as it will look, and its settings
---------------------------------------------------------------------------

local function BuildAlertPage(page)
    local s = function() return ns.db.alert end
    local function get(key) return function() return s()[key] end end
    local function set(key) return function(v) ns.SetAlert(key, v) end end

    local sample = ns.Alert.NewCard(page)
    sample:SetPoint("TOPLEFT", -12, 4)
    sample:SetScale(0.92)
    local sampleCat = "ore"
    local function fill()
        sample:Fill({ category = sampleCat, name = sampleCat == "ore" and L.SAMPLE_NODE or L["CAT_" .. sampleCat],
            required = SAMPLE[sampleCat], skill = SAMPLE[sampleCat] + 10, hasProf = true, state = "ready" })
    end
    local stamps = W.Stamps(page, {
        { "ore", L.TAB_ore }, { "herb", L.TAB_herb }, { "skin", L.TAB_skin },
    }, function() return sampleCat end, function(v)
        sampleCat = v
        fill()
        sample:Flash()
    end)
    stamps:SetPoint("TOPLEFT", 16, -258)
    stamps:SetSize(206, 22)

    local main = W.Section(page, L.CARD_ALERT, 300, 220)
    main:SetPoint("TOPLEFT", 236, -2)
    main:Add(W.Check(main, L.ALERT_ON, L.ALERT_ON_TIP, get("enabled"), set("enabled")), 28)
    main:Add(W.Slider(main, L.DURATION, 3, 30, 1, get("duration"), set("duration"), function(v) return L.SECONDS:format(v) end), 48)
    main:Add(W.Slider(main, L.SCALE, 0.6, 1.5, 0.05, get("scale"), set("scale"), Pct), 48)
    main:Add(W.Check(main, L.ONLY_CAN, L.ONLY_CAN_TIP, get("onlyCan"), set("onlyCan")), 26)
    main:Add(W.Check(main, L.HIDE_COMBAT, nil, get("hideCombat"), set("hideCombat")), 26)

    local kinds = W.Section(page, L.CARD_ALERT_KINDS, 300, 110)
    kinds:SetPoint("TOPLEFT", 236, -230)
    for _, cat in ipairs(ns.CATEGORIES) do
        kinds:Add(W.Check(kinds, L["CAT_" .. cat], nil, get(cat), set(cat)), 24)
    end

    local move = W.Button(page, L.MOVE, 130, function(self)
        if ns.Alert:IsSampleShown() then
            ns.Alert:Dismiss()
            self.text:SetText(L.MOVE)
        else
            ns.Alert:ShowSample()
            self.text:SetText(L.MOVE_DONE)
        end
    end)
    move:SetPoint("TOPLEFT", 238, -350)
    local resetPos = W.Button(page, L.RESET_POS, 130, function() ns.Alert:ResetPosition() end)
    resetPos:SetPoint("LEFT", move, "RIGHT", 12, 0)
    page:SetScript("OnHide", function()
        if ns.Alert:IsSampleShown() then ns.Alert:Dismiss() end
        move.text:SetText(L.MOVE)
    end)

    page.preview = { apply = fill }
end

---------------------------------------------------------------------------
-- About page: what the addon does, its commands, the recommended addon by
-- the same author (KullThranUI) and the credits
---------------------------------------------------------------------------

local KUI_LINKS = {
    { "ABOUT_LINK_WEB", "https://kullthranui.com/" },
    { "ABOUT_LINK_CF", "https://www.curseforge.com/wow/addons/kullthranui-forever" },
    { "ABOUT_LINK_DISCORD", "https://discord.gg/cqAVWpeVvd" },
}

local function IsLoaded(name)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if not loaded then return false end
    local ok, result = pcall(loaded, name)
    return ok and result and true or false
end

local function BuildAboutPage(page)
    -- left: the addon
    local emblem = W.Tex(page, "emblem", "ARTWORK")
    emblem:SetSize(46, 46)
    emblem:SetPoint("TOPLEFT", 2, 0)
    local name = W.Text(page, 22, W.INK, W.TITLE_FONT)
    name:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 8, -4)
    name:SetText(L.TITLE)
    local by = W.Text(page, 11, W.INK_SOFT)
    by:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 1, -2)
    by:SetText(L.ABOUT_BY:format(ns.VERSION))

    local what = W.Section(page, L.ABOUT_WHAT, 250, 210)
    what:SetPoint("TOPLEFT", 6, -58)
    local y = -30
    for i = 1, 5 do
        local dot = W.Tex(what, "blot", "ARTWORK")
        dot:SetSize(9, 9)
        dot:SetPoint("TOPLEFT", 2, y - 3)
        W.OnAccent(function() dot:SetVertexColor(W.AccentInk(0.8)) end)
        local t = W.Text(what, 11)
        t:SetPoint("TOPLEFT", 16, y)
        t:SetWidth(232)
        t:SetSpacing(2)
        t:SetText(L["ABOUT_" .. i])
        local h = t:GetStringHeight()
        y = y - math.max(type(h) == "number" and h or 13, 13) - 8
    end

    local commands = W.Section(page, L.ABOUT_COMMANDS, 250, 100)
    commands:SetPoint("TOPLEFT", 6, -290)
    local cmds = W.Text(commands, 11)
    cmds:SetPoint("TOPLEFT", 2, -30)
    cmds:SetWidth(248)
    cmds:SetSpacing(4)
    cmds:SetText(L.ABOUT_CMDS)

    -- right: KullThranUI, by the same author
    local kui = W.Section(page, L.ABOUT_RECOMMENDED, 262, 270)
    kui:SetPoint("TOPLEFT", 276, -2)
    local logo = W.Tex(kui, "kullthranui", "ARTWORK")
    logo:SetSize(64, 64)
    logo:SetPoint("TOPLEFT", 0, -30)
    local kname = W.Text(kui, 20, W.INK, W.TITLE_FONT)
    kname:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -10)
    kname:SetText("KullThranUI")
    local from = W.Text(kui, 11, W.INK_SOFT)
    from:SetPoint("TOPLEFT", kname, "BOTTOMLEFT", 1, -3)
    from:SetText(L.ABOUT_KUI_FROM)
    local desc = W.Text(kui, 11)
    desc:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(258)
    desc:SetSpacing(2)
    desc:SetText(L.ABOUT_KUI_TEXT)
    local status = W.Text(kui, 11)
    status:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    status:SetWidth(258)
    local links = CreateFrame("Frame", nil, kui)
    links:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -8)
    links:SetSize(258, #KUI_LINKS * 28)
    for i, link in ipairs(KUI_LINKS) do
        local row = W.Link(links, L[link[1]], link[2], L.ABOUT_LINK_TIP)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
        row:SetPoint("RIGHT", 0, 0)
    end

    local credits = W.Section(page, L.ABOUT_CREDITS, 262, 90)
    credits:SetPoint("TOPLEFT", 276, -300)
    local ct = W.Text(credits, 10, W.INK_SOFT)
    ct:SetPoint("TOPLEFT", 2, -30)
    ct:SetWidth(258)
    ct:SetSpacing(2)
    ct:SetText(L.ABOUT_CREDITS_TEXT)

    function page:UpdateStatus()
        if IsLoaded("KullThranUI") then
            status:SetText("|cff8fdc78" .. L.ABOUT_KUI_ON .. "|r")
        else
            status:SetText("|cffffc848" .. L.ABOUT_KUI_OFF .. "|r")
        end
    end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function SelectTab(id)
    current = id
    ns.db.lastTab = id
    for tid, page in pairs(pages) do page:SetShown(tid == id) end
    W.SetAccent(AccentFor(id))
    for _, tab in pairs(tabs) do tab:Paint() end
    local page = pages[id]
    if page.preview then page.preview.apply() end
    if page.UpdateStatus then page:UpdateStatus() end
end

-- a paper index tab; the open one gets a wash of its colour and sits proud
local function BuildTab(parent, id, index)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(162, 40)
    b:SetPoint("TOPLEFT", 22, -HEADER_H - 16 - (index - 1) * 46)
    local paper = W.Tex(b, "tab", "BACKGROUND", 0)
    paper:SetAllPoints()
    local wash = W.Tex(b, "tab_wash", "BACKGROUND", 1)
    wash:SetAllPoints()
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 14, 0)
    icon:SetTexture(ICONS[id])
    if id ~= "general" then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    local text = W.Text(b, 15, W.INK, W.TITLE_FONT)
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    text:SetText(L["TAB_" .. id])
    local hover = false
    function b:Paint()
        local on = current == id
        local r, g, bb = AccentFor(id)
        wash:SetVertexColor(r, g, bb, on and 0.55 or (hover and 0.2 or 0))
        paper:SetVertexColor(on and 1 or 0.88, on and 1 or 0.86, on and 1 or 0.82)
        text:SetTextColor(unpack((on or hover) and W.INK or W.INK_SOFT))
        icon:SetDesaturated(not on and not hover)
        icon:SetAlpha(on and 1 or 0.75)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", on and 26 or 20, -HEADER_H - 16 - (index - 1) * 46)
    end
    b:SetScript("OnEnter", function() hover = true b:Paint() end)
    b:SetScript("OnLeave", function() hover = false b:Paint() end)
    b:SetScript("OnClick", function()
        if current ~= id then
            PlaySound(SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN or 836)
            SelectTab(id)
        end
    end)
    tabs[id] = b
end

local function SavePosition(f)
    local point, _, rel, x, y = f:GetPoint(1)
    ns.db.window = { point = point, rel = rel, x = x, y = y }
end

local function Build()
    local f = CreateFrame("Frame", "GlowingNodesWindow", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition(self) end)
    local pos = ns.db.window
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.rel or pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER", 0, 30)
    end
    f:Hide()
    tinsert(UISpecialFrames, "GlowingNodesWindow")

    local shadow = W.Tex(f, "fx_halo", "BACKGROUND", -8)
    shadow:SetPoint("TOPLEFT", -60, 50)
    shadow:SetPoint("BOTTOMRIGHT", 60, -70)
    shadow:SetVertexColor(0, 0, 0, 0.7)
    local book = W.Tex(f, "window", "BACKGROUND", -7)
    book:SetAllPoints()
    book:SetTexCoord(0, 0.75, 0, 1)

    -- cover: gold-stamped emblem and title
    local emblem = W.Tex(f, "emblem", "ARTWORK")
    emblem:SetSize(52, 52)
    emblem:SetPoint("CENTER", f, "TOPLEFT", 50, -34)
    local title = W.GoldText(f, 24)
    title:SetPoint("LEFT", emblem, "RIGHT", 8, 4)
    title:SetText(L.TITLE)
    local subtitle = W.Text(f, 11, W.TAN)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -1)
    subtitle:SetText(L.SUBTITLE)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(30, 30)
    close:SetPoint("TOPRIGHT", -56, -17)
    local x = W.Tex(close, "close", "ARTWORK")
    x:SetAllPoints()
    close:SetScript("OnEnter", function() x:SetVertexColor(1.25, 1.15, 0.95) end)
    close:SetScript("OnLeave", function() x:SetVertexColor(1, 1, 1) end)
    close:SetScript("OnClick", function() f:Hide() end)
    W.Tooltip(close, CLOSE or "Close")

    local master = W.Check(f, L.ENABLED, nil, function() return ns.db.enabled end, function(v) ns.Set("enabled", v) end, true)
    master:SetWidth(110)
    master:SetPoint("RIGHT", close, "LEFT", -20, 0)

    for i, id in ipairs(TABS) do BuildTab(f, id, i) end
    local version = W.Text(f, 10, W.INK_SOFT)
    version:SetPoint("BOTTOMLEFT", 30, 30)
    version:SetText("v" .. ns.VERSION .. "  ·  " .. L.FOOTER)

    for _, id in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, f)
        page:SetPoint("TOPLEFT", CONTENT_X, -CONTENT_Y)
        page:SetPoint("BOTTOMRIGHT", -26, 26)
        page:Hide()
        if id == "general" then BuildGeneralPage(page)
        elseif id == "alert" then BuildAlertPage(page)
        elseif id == "about" then BuildAboutPage(page)
        else BuildCategoryPage(page, id) end
        pages[id] = page
    end

    f:SetScript("OnShow", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN or 829)
        W.RefreshAll()
        SelectTab(ns.db.lastTab and pages[ns.db.lastTab] and ns.db.lastTab or "ore")
    end)
    f:SetScript("OnHide", function()
        PlaySound(SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE or 830)
    end)
    frame = f
end

function Window:Select(id)
    if frame and pages[id] then SelectTab(id) end
end

function Window:Toggle()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

function Window:Open()
    if not frame then Build() end
    frame:Show()
end

ns.On("Changed", function(key)
    if not (frame and frame:IsShown()) then return end
    W.RefreshAll()
    if current and type(key) == "string" and (key == "*" or key:find("^" .. current .. "%.color")) then
        W.SetAccent(AccentFor(current))
    end
    for _, tab in pairs(tabs) do tab:Paint() end
    local page = pages[current]
    if page and page.preview then page.preview.apply() end
    if page and page.UpdateStatus then page:UpdateStatus() end
end)

ns.On("Learned", function()
    local page = pages.general
    if frame and frame:IsShown() and page and page.UpdateStatus then page:UpdateStatus() end
end)
