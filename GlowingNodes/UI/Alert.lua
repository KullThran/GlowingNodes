-- Alert.lua
-- "Node found" card, in the spirit of RareScanner's: a small square of the
-- notebook's leather with the material's icon in a brass ring, the node's
-- name on a paper label, the level it needs and how you stand. It appears
-- when a node starts to glow, stays while the node is your interact target
-- and for a few seconds after. Drag it anywhere; right-click closes it.
local _, ns = ...
local L = ns.L
local W = ns.W
local Data, Skills, Glow = ns.NodeData, ns.Skills, ns.Glow

local Alert = {}
ns.Alert = Alert

local SIZE = 256
local FADE_IN, FADE_OUT = 0.22, 0.45

local function Hex(r, g, b)
    return ("%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- The card itself, used by the live alert and by the preview in the window
function Alert.NewCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(SIZE, SIZE)

    c.edge = W.Tex(c, "alert_edge", "BACKGROUND", -2)
    c.edge:SetAllPoints()
    c.edge:SetBlendMode("ADD")
    local body = W.Tex(c, "alert", "BACKGROUND", 0)
    body:SetAllPoints()

    c.title = W.GoldText(c, 15)
    c.title:SetPoint("TOP", 0, -30)
    c.title:SetJustifyH("CENTER")

    c.halo = W.Tex(c, "emblem_glow", "BORDER")
    c.halo:SetSize(112, 112)
    c.halo:SetPoint("CENTER", c, "TOP", 0, -92)
    c.halo:SetBlendMode("ADD")
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(50, 50)
    c.icon:SetPoint("CENTER", c.halo, "CENTER")
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = W.Tex(c, "socket", "OVERLAY")
    ring:SetSize(78, 78)
    ring:SetPoint("CENTER", c.halo, "CENTER")

    c.name = W.Text(c, 14, W.INK, W.NAME_FONT) -- the game's name for the node
    c.name:SetPoint("CENTER", c, "TOP", 0, -153)
    c.name:SetWidth(164)
    c.name:SetJustifyH("CENTER")
    c.name:SetWordWrap(false)

    c.level = W.GoldText(c, 19, W.FONT)
    c.level:SetPoint("CENTER", c, "TOP", 0, -190)
    c.level:SetJustifyH("CENTER")
    c.level:SetFont(W.FONT, 19, "OUTLINE")

    c.info = W.Text(c, 11, W.TAN)
    c.info:SetPoint("CENTER", c, "TOP", 0, -214)
    c.info:SetJustifyH("CENTER")
    c.info:SetShadowOffset(1, -1)
    c.info:SetShadowColor(0, 0, 0, 0.9)

    c.t = 0
    c.pulse = 0
    c:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        self.pulse = math.max(self.pulse - elapsed / 3, 0)
        local base = 0.28 + 0.5 * self.pulse
        self.edge:SetAlpha(base + (0.12 + 0.3 * self.pulse) * math.sin(self.t * 4))
        self.halo:SetAlpha(0.65 + 0.25 * math.sin(self.t * 2.2))
    end)

    -- info: { category, name, required, skill, hasProf, state, objectID, icon }
    function c:Fill(info)
        local cat = info.category or "ore"
        local col = ns.db[cat] and ns.db[cat].color or { r = 1, g = 1, b = 1 }
        self.edge:SetVertexColor(col.r, col.g, col.b)
        self.halo:SetVertexColor(col.r, col.g, col.b)
        self.title:SetText(L["ALERT_TITLE_" .. cat])
        self.icon:SetTexture(info.icon or Data.IconFor(cat, info.required, info.name))
        if info.hidden then
            self.name:SetText("|cff9aa4a8" .. L.ALERT_HIDDEN .. "|r")
        else
            self.name:SetText(info.name or "")
        end
        local state = L["ALERT_STATE_" .. (info.state or "ready")]
        if not ns.PROFESSIONS[cat] then
            -- a chest: nothing to level, only whether it's in reach
            self.level:SetText("")
            self.info:SetText(state)
            return
        end
        if info.hidden then
            self.level:SetText("")
        else
            local text, r, g, b = Glow.NumberFor(info.required, info.skill, false, info.hasProf)
            self.level:SetText(L.ALERT_LEVEL:format("|cff" .. Hex(r, g, b) .. text .. "|r"))
        end
        local mine = info.hasProf and L.ALERT_MINE:format(info.skill or 0)
            or L.ALERT_NOPROF:format(L["PROF_" .. cat])
        self.info:SetText(mine .. "  ·  " .. state)
    end

    function c:Flash()
        self.pulse = 1
    end

    return c
end

---------------------------------------------------------------------------
-- The live alert
---------------------------------------------------------------------------

local frame, card
local shownGuid, lastSeen
local fading, fadeT = nil, 0

local function Settings()
    return ns.db.alert
end

local function Place()
    local p = Settings().point
    frame:ClearAllPoints()
    if p and p[1] then
        frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
    frame:SetScale(Settings().scale or 1)
end

local function Build()
    frame = CreateFrame("Frame", "GlowingNodesAlert", UIParent)
    frame:SetSize(SIZE, SIZE)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetClampRectInsets(14, -14, -14, 14)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    card = Alert.NewCard(frame)
    card:SetAllPoints()
    frame.card = card

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(24, 24)
    close:SetPoint("CENTER", frame, "TOPRIGHT", -48, -31)
    local x = W.Tex(close, "close", "OVERLAY", 3)
    x:SetAllPoints()
    close:SetScript("OnEnter", function() x:SetVertexColor(1.25, 1.15, 0.95) end)
    close:SetScript("OnLeave", function() x:SetVertexColor(1, 1, 1) end)
    close:SetScript("OnClick", function() Alert:Dismiss() end)
    W.Tooltip(close, CLOSE or "Close")

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, px, py = self:GetPoint(1)
        Settings().point = { point, rel, px, py }
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Alert:Dismiss() end
    end)
    W.Tooltip(frame, nil, L.ALERT_HINT)

    frame:SetScript("OnUpdate", function(self, elapsed)
        if fading == "in" then
            fadeT = math.min(fadeT + elapsed / FADE_IN, 1)
            self:SetAlpha(fadeT)
            self:SetScale((Settings().scale or 1) * (0.94 + 0.06 * fadeT))
            if fadeT >= 1 then fading = nil end
        elseif fading == "out" then
            fadeT = math.max(fadeT - elapsed / FADE_OUT, 0)
            self:SetAlpha(fadeT)
            if fadeT <= 0 then
                fading = nil
                self:Hide()
                shownGuid = nil
            end
        elseif not Alert.preview and shownGuid then
            local cur = ns.SoftTarget.current
            if cur and (cur.id or cur.guid) == shownGuid then
                lastSeen = GetTime()
            elseif GetTime() - (lastSeen or 0) > (Settings().duration or 10) then
                fading, fadeT = "out", self:GetAlpha() or 1
            end
        end
    end)
    Place()
end

-- true, or false and why not (for the debug log)
local function Wanted(target)
    local s = Settings()
    if not s.enabled then return false, "alert off" end
    if not (target.category and s[target.category]) then return false, "kind off" end
    if s.onlyCan and target.state == "locked" then return false, "level too low" end
    if s.hideCombat and InCombatLockdown() then return false, "in combat" end
    return true
end

local function InfoFor(target)
    return {
        category = target.category, name = target.name, required = target.required,
        skill = target.skill, hasProf = target.skill ~= nil, state = target.state, hidden = target.hidden,
    }
end

function Alert:Show(target)
    local ok, why = Wanted(target)
    if not ok then
        ns.Debug("alert skipped (" .. why .. ") " .. tostring(target.name))
        return
    end
    ns.Debug("ALERT " .. tostring(target.name))
    if not frame then Build() end
    Alert.preview = nil
    card:Fill(InfoFor(target))
    card:Flash()
    shownGuid, lastSeen = target.id or target.guid, GetTime()
    if not frame:IsShown() or fading == "out" then
        fadeT = fading == "out" and fadeT or 0
        fading = "in"
        frame:SetAlpha(fadeT)
        frame:Show()
    end
end

function Alert:Update(target)
    if frame and frame:IsShown() and shownGuid and (target.id or target.guid) == shownGuid and fading ~= "out" then
        card:Fill(InfoFor(target))
    end
end

function Alert:Dismiss()
    if frame and frame:IsShown() then
        Alert.preview = nil
        fading, fadeT = "out", frame:GetAlpha() or 1
    end
end

-- "Move" in the options: shows a sample card to drag around
function Alert:ShowSample()
    if not frame then Build() end
    Alert.preview = true
    card:Fill({ category = "ore", name = L.SAMPLE_NODE, required = 65, skill = 70, hasProf = true, state = "ready" })
    card:Flash()
    fading, fadeT = "in", 0
    frame:SetAlpha(0)
    frame:Show()
end

function Alert:IsSampleShown()
    return frame and frame:IsShown() and Alert.preview
end

function Alert:ResetPosition()
    Settings().point = nil
    if frame then Place() end
end

ns.On("NodeFound", function(target) Alert:Show(target) end)
ns.On("NodeUpdate", function(target) Alert:Update(target) end)
ns.On("Changed", function(key)
    if not frame then return end
    if key == "alert.scale" or key == "*" then Place() end
    if key == "*" or key == "alert.enabled" then
        if not Settings().enabled then Alert:Dismiss() end
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function()
    if ns.db and Settings().hideCombat and not Alert.preview then Alert:Dismiss() end
end)
