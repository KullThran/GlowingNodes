-- Arrow.lua
-- The arrow on screen: a leather and bronze arrowhead that turns towards the
-- spot Core/Navigator.lua picks, the gem in the category's colour, and under
-- it, still, the item's icon in a bronze ring and the yards. It is our own
-- frame, not a Blizzard waypoint. Turned on and off with the key binding
-- (Bindings.xml), /gn flecha or the Arrow tab; dragged when unlocked.
local _, ns = ...
local L = ns.L
local W = ns.W

local Arrow = {}
ns.Arrow = Arrow

local SIZE = 96          -- the arrowhead's frame; its textures fill it and turn
local RING, ICON = 34, 26
local DASH = "—"

BINDING_HEADER_GLOWINGNODES = "Glowing Nodes"
BINDING_NAME_GLOWINGNODES_ARROW = L.BINDING_ARROW

local function Settings() return ns.db.arrow end

local function Place(frame)
    local p = Settings().point
    frame:ClearAllPoints()
    if p and p[1] then
        frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

local function Build()
    local f = CreateFrame("Frame", "GlowingNodesArrow", UIParent)
    f:SetSize(SIZE, SIZE)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()
    Arrow.frame = f
    Arrow.body = W.Tex(f, "f_navarrow", "ARTWORK", 0)
    Arrow.body:SetAllPoints()
    Arrow.gem = W.Tex(f, "f_navgem", "ARTWORK", 1)
    Arrow.gem:SetAllPoints()
    -- the still part under the arrowhead
    Arrow.icon = f:CreateTexture(nil, "ARTWORK", nil, 2)
    Arrow.icon:SetSize(ICON, ICON)
    Arrow.icon:SetPoint("TOP", f, "BOTTOM", 0, -(RING - ICON) / 2)
    Arrow.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Arrow.ring = W.Tex(f, "f_navring", "OVERLAY", 0)
    Arrow.ring:SetSize(RING, RING)
    Arrow.ring:SetPoint("CENTER", Arrow.icon, "CENTER", 0, 0)
    Arrow.yards = W.GoldText(f, 15)
    Arrow.yards:SetPoint("TOP", Arrow.ring, "BOTTOM", 0, -2)
    Arrow.yards:SetJustifyH("CENTER")

    f:SetScript("OnDragStart", function(self)
        if not Settings().locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint(1)
        ns.SetArrow("point", { point, rel, x, y })
    end)

    -- the frame hides while the arrow has nothing to show; this one keeps
    -- asking the Navigator as long as the arrow is on
    local driver = CreateFrame("Frame")
    local wait = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        wait = wait + elapsed
        if wait < ns.Navigator.TICK then return end
        wait = 0
        Arrow:Refresh(GetTime())
    end)
    driver:Hide()
    Arrow.driver = driver
end

-- shows what the Navigator says now
function Arrow:Refresh(now)
    if not self.frame then return end
    local view = ns.Navigator.Update(now)
    local f = self.frame
    if view.state == "off" or view.state == "hidden" then
        f:Hide()
        return
    end
    local set = Settings()
    if view.state == "empty" then
        f:SetAlpha(ns.Navigator.DIM_ALPHA)
        self.body:SetRotation(0)
        self.gem:SetRotation(0)
        self.gem:SetVertexColor(0.55, 0.50, 0.45)
        self.icon:Hide()
        self.yards:SetText(DASH)
        self.yards:SetShown(set.showDistance)
        f:Show()
        return
    end
    f:SetAlpha(1)
    self.body:SetRotation(view.angle)
    self.gem:SetRotation(view.angle)
    local c = ns.db[view.category] and ns.db[view.category].color
    if c then self.gem:SetVertexColor(c.r, c.g, c.b) end
    local node = view.node
    self.icon:SetTexture(ns.NodeData.IconFor(view.category, node.r, node.n))
    self.icon:Show()
    self.yards:SetText(L.ARROW_YARDS:format(math.floor(view.yards + 0.5)))
    self.yards:SetShown(set.showDistance)
    f:Show()
end

-- the settings again: size, place, locked, on or off
function Arrow:Apply()
    if not self.frame then Build() end
    local set = Settings()
    local f = self.frame
    f:SetScale(set.scale or 1)
    f:EnableMouse(not set.locked)
    Place(f)
    if set.enabled then
        self.driver:Show()
        self:Refresh(GetTime())
    else
        self.driver:Hide()
        f:Hide()
    end
end

ns.On("Enable", function() Arrow:Apply() end)
ns.On("Changed", function(key)
    if not ns.db then return end
    if key == "*" or key == "profiles" or (type(key) == "string" and key:find("^arrow%.")) then
        Arrow:Apply()
    end
end)
