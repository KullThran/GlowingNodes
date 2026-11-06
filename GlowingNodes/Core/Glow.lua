-- Glow.lua
-- The glow drawn over a node: a wide halo, a bright core, a turning ring of
-- arcs, slow rays, an optional pillar of light, rising glints and a shock ring
-- when the node comes into reach, all additive and tinted with the colour the
-- player picked. The level number sits above it.
-- The same object draws the in-world glow (hung on the soft-target nameplate)
-- and the live preview in the options window.
local _, ns = ...
local Data = ns.NodeData

local Glow = {}
Glow.__index = Glow
ns.Glow = Glow

local ART = ns.ART
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" -- has the client's glyphs
local GLINTS = 6
local BURST_TIME = 0.55
local FADE_IN = 0.25
local BLEND = 0.3

local sin, cos, pi, random, min, max, sqrt = math.sin, math.cos, math.pi, math.random, math.min, math.max, math.sqrt
local TAU = 2 * pi

local function Approach(value, target, step)
    if value < target then return min(value + step, target) end
    return max(value - step, target)
end

local function Tex(frame, file, layer, sub)
    local t = frame:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t:SetTexture(ART .. file)
    t:SetBlendMode("ADD")
    if t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    return t
end

-- parent: frame the glow follows; returns the glow object
function Glow.New(parent)
    local self = setmetatable({}, Glow)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(1, 1)
    f:Hide()
    self.frame = f

    self.beam = Tex(f, "fx_beam", "BACKGROUND", 0)
    self.halo = Tex(f, "fx_halo", "BACKGROUND", 1)
    self.halo2 = Tex(f, "fx_halo", "BACKGROUND", 2)
    self.burst = Tex(f, "fx_burst", "BORDER", 0)
    self.ring = Tex(f, "fx_ring", "ARTWORK", 0)
    self.core = Tex(f, "fx_core", "ARTWORK", 1)
    self.shock = Tex(f, "fx_shock", "OVERLAY", 0)
    self.glints = {}
    for i = 1, GLINTS do
        self.glints[i] = { tex = Tex(f, "fx_glint", "OVERLAY", 1) }
    end
    for _, t in ipairs({ self.beam, self.halo, self.halo2, self.burst, self.ring, self.core, self.shock }) do
        t:SetPoint("CENTER")
    end
    self.beam:ClearAllPoints()
    self.beam:SetPoint("BOTTOM", f, "CENTER", 0, -12)

    -- level number: its own frame so it stays over the glow and the nameplate
    local tf = CreateFrame("Frame", nil, f)
    tf:SetSize(1, 1)
    tf:SetPoint("CENTER")
    self.textFrame = tf
    local text = tf:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT, 26, "THICKOUTLINE")
    text:SetPoint("BOTTOM", f, "CENTER", 0, 36)
    -- a soft dark patch behind the number, so it reads over its own glow
    local back = tf:CreateTexture(nil, "BACKGROUND")
    back:SetTexture(ART .. "fx_halo")
    back:SetVertexColor(0, 0, 0, 0.7)
    back:SetPoint("CENTER", text, "CENTER", 0, 0)
    self.textBack = back
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    self.text = text
    local small = tf:CreateFontString(nil, "OVERLAY")
    small:SetFont(FONT, 13, "OUTLINE")
    small:SetPoint("BOTTOM", text, "TOP", 0, -2)
    self.label = small

    self.t = random() * 10
    self.appear, self.ready, self.locked, self.burstAge = 0, 0, 0, BURST_TIME
    self.state = "ready"
    for _, g in ipairs(self.glints) do self:Respawn(g) end

    f:SetScript("OnUpdate", function(_, elapsed) self:Update(elapsed) end)
    return self
end

function Glow:Respawn(g, now)
    local a, r = random() * TAU, sqrt(random())
    g.x, g.y = cos(a) * r * 40, sin(a) * r * 26 - 6
    g.life = 0.7 + 0.9 * random()
    g.age = now and 0 or -0.8 * random()
    g.scale = 0.5 + 0.8 * random()
    g.spin = (random() - 0.5) * 2
end

-- cfg: the category settings (colour, intensity, size, pulse, beam)
-- opts: { scale = number, numberSize = n, greyLocked = bool, dimFar = bool }
function Glow:Configure(cfg, opts)
    self.cfg, self.opts = cfg, opts or {}
    local fontSize = (self.opts.numberSize or 26) * (self.opts.textScale or 1)
    self.text:SetFont(FONT, max(fontSize, 8), "THICKOUTLINE")
    self.label:SetFont(FONT, max(fontSize * 0.48, 8), "OUTLINE")
    self.fontSize = fontSize
end

function Glow:SetNumber(text, r, g, b, label)
    local size = self.fontSize or 26
    local chars = text and #text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or 0
    self.textBack:SetSize(size * (1.6 + 0.55 * chars), size * 2.1)
    self.textBack:SetShown(chars > 0)
    self.text:SetText(text or "")
    self.text:SetTextColor(r or 1, g or 1, b or 1)
    self.label:SetText(label or "")
end

function Glow:SetState(state)
    if state ~= self.state then
        if state == "ready" and self.frame:IsShown() then self:Flare() end
        self.state = state
    end
end

-- the "in reach" flash: shock ring and a burst of glints
function Glow:Flare()
    self.burstAge = 0
    for _, g in ipairs(self.glints) do self:Respawn(g, true) end
end

function Glow:Attach(anchor, x, y)
    local f = self.frame
    f:SetParent(anchor)
    f:ClearAllPoints()
    f:SetPoint("CENTER", anchor, "CENTER", x or 0, y or 0)
    if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
    local ok, level = pcall(anchor.GetFrameLevel, anchor)
    if ok and type(level) == "number" then
        f:SetFrameLevel(max(level - 1, 0))
        self.textFrame:SetFrameLevel(level + 5)
    end
    f:SetFrameStrata(anchor:GetFrameStrata() or "BACKGROUND")
    self.anchor = anchor
end

function Glow:Show(state)
    self.state = state or "ready"
    self.appear = 0
    self.ready = self.state == "ready" and 1 or 0
    self.locked = self.state == "locked" and 1 or 0
    self.burstAge = BURST_TIME
    self.frame:Show()
end

function Glow:Hide()
    self.frame:Hide()
    self.frame:ClearAllPoints()
    self.anchor = nil
end

function Glow:IsShown()
    return self.frame:IsShown()
end

function Glow:Update(elapsed)
    local cfg, opts = self.cfg, self.opts
    if not cfg then return end
    if elapsed > 0.1 then elapsed = 0.1 end
    self.t = self.t + elapsed
    self.appear = Approach(self.appear, 1, elapsed / FADE_IN)
    self.ready = Approach(self.ready, self.state == "ready" and 1 or 0, elapsed / BLEND)
    self.locked = Approach(self.locked, self.state == "locked" and 1 or 0, elapsed / BLEND)

    local scale = (cfg.size or 1) * (opts.scale or 1)
    local power = cfg.intensity or 1.5
    local t = self.t

    -- colour: the player's, or grey on a node they can't gather yet
    local c = cfg.color
    local r, g, b = c.r, c.g, c.b
    if opts.greyLocked and self.locked > 0 then
        local k = self.locked * 0.85
        r, g, b = r + (0.55 - r) * k, g + (0.55 - g) * k, b + (0.58 - b) * k
    end

    -- strength: far is softer (when wanted), locked is calmer
    local far = 1 - self.ready - self.locked
    if far < 0 then far = 0 end
    local strength = self.appear * (1 - (opts.dimFar and 0.45 or 0) * far) * (1 - 0.25 * self.locked)
    local beat = cfg.pulse and (0.78 + 0.22 * sin(t * TAU * (0.75 + 0.35 * self.ready))) or 1
    local speed = 1 - 0.5 * self.locked

    local a1 = min(power, 1) * strength * beat
    local a2 = max(power - 1, 0) * 0.6 * strength * beat

    local function paint(tex, size, alpha, white)
        tex:SetSize(size * scale, size * scale)
        if white then
            tex:SetVertexColor(r + (1 - r) * white, g + (1 - g) * white, b + (1 - b) * white, min(alpha, 1))
        else
            tex:SetVertexColor(r, g, b, min(alpha, 1))
        end
    end

    paint(self.halo, 230 * (0.94 + 0.06 * beat), a1 * 0.95)
    paint(self.halo2, 300, a2)
    self.halo2:SetShown(a2 > 0.01)
    paint(self.core, 70 * (0.9 + 0.1 * beat), (a1 + a2) * 0.9, 0.55)
    paint(self.ring, 150, (a1 * 0.85 + a2 * 0.5))
    self.ring:SetRotation(t * 0.55 * speed)
    paint(self.burst, 250, (a1 * 0.45 + a2 * 0.35))
    self.burst:SetRotation(-t * 0.18 * speed)

    if cfg.beam then
        self.beam:SetSize(84 * scale, 620 * scale) -- tall, to show over trees and rocks
        self.beam:SetVertexColor(r, g, b, min((a1 * 0.85 + a2 * 0.45), 1))
        self.beam:Show()
    else
        self.beam:Hide()
    end

    -- shock ring on "in reach"
    if self.burstAge < BURST_TIME then
        self.burstAge = self.burstAge + elapsed
        local p = self.burstAge / BURST_TIME
        local size = (90 + 220 * p) * scale
        self.shock:SetSize(size, size)
        self.shock:SetVertexColor(r + (1 - r) * 0.4, g + (1 - g) * 0.4, b + (1 - b) * 0.4, (1 - p) * min(power, 1.5))
        self.shock:Show()
    else
        self.shock:Hide()
    end

    -- glints rising out of the node
    for _, gl in ipairs(self.glints) do
        gl.age = gl.age + elapsed * speed * (0.8 + 0.4 * self.ready)
        if gl.age >= gl.life then self:Respawn(gl) end
        local tex = gl.tex
        local shine = gl.age > 0 and sin(pi * gl.age / gl.life) or 0
        local s = max(30 * gl.scale * (0.35 + 0.65 * shine) * scale, 0.01)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", self.frame, "CENTER", gl.x * scale, (gl.y + 26 * max(gl.age, 0)) * scale)
        tex:SetSize(s, s)
        tex:SetRotation(gl.spin * max(gl.age, 0))
        tex:SetVertexColor(r + (1 - r) * 0.5, g + (1 - g) * 0.5, b + (1 - b) * 0.5, min(strength * shine * min(power, 1.6), 1))
    end

    self.textFrame:SetAlpha(self.appear)
end

-- Text and colour of the level number for a target, shared with the preview
function Glow.NumberFor(required, skill, showMine, hasProfession)
    local r, g, b = Data.DifficultyColor(required, hasProfession and skill or nil)
    local text = required and tostring(required) or ns.L.UNKNOWN
    if showMine and hasProfession and skill then
        text = text .. " |cffd8e2e6· " .. skill .. "|r"
    end
    return text, r, g, b
end
