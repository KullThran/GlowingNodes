-- CatalogPage.lua
-- The Catalog tab: every ore and herb type (Core/Catalog.lua) in two columns,
-- each with a switch. A type switched off doesn't glow, isn't drawn on the
-- maps and the arrow doesn't lead to it.
local _, ns = ...

local L, W = ns.L, ns.W

local COL_W, ROW_H = 258, 24
local COL_X = { ore = 2, herb = 274 }
local PAGE_H = 408                 -- the window's page area
local LIST_TOP, BOTTOM, NOTE_H = 30, 12, 30
local LIST_H = PAGE_H - LIST_TOP - BOTTOM - NOTE_H -- 14 rows

local function Hidden(key)
    return ns.db.catalog.hidden[key] == true
end

local function ItemName(itemID)
    if not (itemID and C_Item and C_Item.GetItemNameByID) then return nil end
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok and type(name) == "string" and name ~= "" then return name end
    if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
end

local function NewRow(list)
    local row = CreateFrame("Frame", nil, list.content)
    row:SetSize(COL_W - 14, ROW_H)
    row:EnableMouse(true)
    row.check = W.Check(row, nil, nil,
        function() return row.type ~= nil and not Hidden(row.type.key) end,
        function(on) if row.type then ns.SetHidden(row.type.key, not on) end end)
    row.check:SetPoint("LEFT", 4, 0)
    row.check:SetWidth(22)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 26, 0)
    row.level = W.Text(row, 12)
    row.level:SetPoint("RIGHT", -4, 0)
    row.level:SetJustifyH("RIGHT")
    row.level:SetWidth(34)
    row.name = W.Text(row, 12)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.level, "LEFT", -4, 0)
    row.name:SetShadowColor(0, 0, 0, 0.9)
    row.name:SetShadowOffset(1, -1)
    row:SetScript("OnEnter", function(self)
        local t = self.type
        if not t then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.Catalog.NameOf(t), 1, 0.86, 0.6)
        if t.r then GameTooltip:AddLine(L.CATALOG_LEVEL:format(t.r), 0.9, 0.9, 0.9) end
        local item = ItemName(t.item)
        if item then GameTooltip:AddLine(L.CATALOG_GIVES:format(item), 0.9, 0.9, 0.9) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- a row shows its type: icon, name, and the level in the game's difficulty
-- colour against your skill (neutral without the profession); dimmed when off
local function Fill(row, t)
    row.type = t
    ns.MapPins.Paint(row.icon, { k = t.k, r = t.r, n = t.en or t.n })
    row.name:SetText(ns.Catalog.NameOf(t))
    row.level:SetText(t.r and tostring(t.r) or "")
    local skill = ns.Skills.Get(t.k)
    if skill then
        row.level:SetTextColor(ns.NodeData.DifficultyColor(t.r, skill))
    else
        row.level:SetTextColor(unpack(W.INK_SOFT))
    end
    row:SetAlpha(Hidden(t.key) and 0.55 or 1)
    row.check:Refresh()
end

function ns.BuildCatalogPage(page)
    page.lists, page.rows, page.all, page.none = {}, {}, {}, {}
    local pools = {}

    local function SetAll(kind, hidden)
        for _, t in ipairs(ns.Catalog.All(kind)) do
            ns.db.catalog.hidden[t.key] = hidden or nil
        end
        ns.Fire("Changed", "catalog")
    end

    for _, kind in ipairs({ "ore", "herb" }) do
        local head = W.Section(page, kind == "ore" and L.CARD_CATALOG_ORE or L.CARD_CATALOG_HERB, COL_W, LIST_TOP)
        head:SetPoint("TOPLEFT", COL_X[kind], -2)
        local none = W.Button(head, L.CATALOG_NONE, 62, function() SetAll(kind, true) end)
        none:SetHeight(22)
        none:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, 2)
        local all = W.Button(head, L.CATALOG_ALL, 62, function() SetAll(kind, false) end)
        all:SetHeight(22)
        all:SetPoint("RIGHT", none, "LEFT", -4, 0)
        page.all[kind], page.none[kind] = all, none

        local list = W.ScrollList(page, COL_W, LIST_H)
        list:SetPoint("TOPLEFT", page, "TOPLEFT", COL_X[kind], -LIST_TOP)
        page.lists[kind] = list
        pools[kind] = {}
        page.rows[kind] = {}
    end

    local note = W.Text(page, 11, W.INK_SOFT)
    note:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, BOTTOM)
    note:SetWidth(2 * COL_W + 12)
    note:SetText(L.CATALOG_NOTE)

    -- every time the tab is shown or a switch moves: types learned since
    -- (Forever's new nodes) get their row
    function page:UpdateStatus()
        for kind, list in pairs(self.lists) do
            local types, pool, rows = ns.Catalog.All(kind), pools[kind], {}
            for i, t in ipairs(types) do
                local row = pool[i] or NewRow(list)
                pool[i] = row
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", list.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
                Fill(row, t)
                row:Show()
                rows[i] = row
            end
            for i = #types + 1, #pool do pool[i]:Hide() pool[i].type = nil end
            self.rows[kind] = rows
            list:SetContentHeight(#types * ROW_H)
        end
    end
end
