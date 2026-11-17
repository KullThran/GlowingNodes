-- Glow.lua
-- The glow drawn over a node, additive and tinted with the colour the player
-- picked: a halo, an optional pillar of light, a shock ring when the node
-- comes into reach and the level number above it, plus the parts of its look
-- (Looks.lua: the ring, the swirl...), made the first time that look shows.
-- The same object draws the in-world glow (hung on the soft-target nameplate)
-- and the live preview in the options window.
local _, ns = ...
local Data = ns.NodeData
local Looks = ns.Looks

local Glow = {}
Glow.__index = Glow
ns.Glow = Glow

local ART = ns.ART
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" -- has the client's glyphs
local BURST_TIME = 0.55
local FADE_IN = 0.25
local FADE_OUT = 0.8 -- the glow going out when its time is up
local BLEND = 0.3

local sin, pi, random, min, max = math.sin, math.pi, math.random, math.min, math.max
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

    -- what every look shares; a look's own parts come with it (Glow:Part)
    self.beam = Tex(f, "fx_beam", "BACKGROUND", 0)
    self.halo = Tex(f, "fx_halo", "BACKGROUND", 1)
    self.shock = Tex(f, "fx_shock", "OVERLAY", 0)
    self.halo:SetPoint("CENTER")
    self.shock:SetPoint("CENTER")
    self.beam:SetPoint("BOTTOM", f, "CENTER", 0, -12)
    self.partsOf = {}
    self.f = {}

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
    -- the pulse and the turning parts move by phases of their own, stepped on
    -- each frame: worked out as time × speed, a change of speed (the blend
    -- into "ready" or "locked") made them leap, more the longer you played
    self.beatPhase = random() * TAU
    self.shownLook = false -- no look yet: Configure sets one up
    self.appear, self.ready, self.locked, self.burstAge = 0, 0, 0, BURST_TIME
    self.state = "ready"

    f:SetScript("OnUpdate", function(_, elapsed) self:Update(elapsed) end)
    return self
end

-- One part of a look: made once (centred, additive), kept as self[name] and
-- counted among the parts of the look being built, so it shows and hides
-- with that look. A part two looks share is made once and counted in both.
function Glow:Part(name, file, layer, sub)
    local t = self[name]
    if not t then
        t = Tex(self.frame, file, layer, sub)
        t:SetPoint("CENTER")
        self[name] = t
    end
    self:Count(t)
    return t
end

-- several parts of a kind, as a list of { tex = Texture } in self[name]
function Glow:Parts(name, n, file, layer, sub)
    local list = self[name]
    if not list then
        list = {}
        for i = 1, n do
            local t = Tex(self.frame, file, layer, sub)
            t:SetPoint("CENTER")
            list[i] = { tex = t }
        end
        self[name] = list
    end
    for _, p in ipairs(list) do self:Count(p.tex) end
    return list
end

function Glow:Count(t)
    local parts = self.partsOf[self.building]
    if parts and not parts[t] then
        parts[t] = true
        parts[#parts + 1] = t
    end
end

-- cfg: the category settings (colour, intensity, size, pulse, beam)
-- opts: { scale = number, numberSize = n, greyLocked = bool, dimFar = bool,
--         look = a look's id (Looks.LIST); the ring for nil or unknown }
function Glow:Configure(cfg, opts)
    self.cfg, self.opts = cfg, opts or {}
    self:ShowLook(self.opts.look)
    self:SetHole(self.opts.hole == true)
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
    self.label:SetTextColor(1, 0.82, 0.2) -- gold, over the number
end

function Glow:SetState(state)
    if state ~= self.state then
        if state == "ready" and self.frame:IsShown() then self:Flare() end
        self.state = state
    end
end

-- the "in reach" flash: the shock ring, and the look's own (the ring's glints)
function Glow:Flare()
    self.burstAge = 0
    if self.look and self.look.Flare then self.look.Flare(self) end
end

-- world: hung on a nameplate in the world. The game shrinks nameplates with
-- distance, and a glow that followed it was a faint ring around the
-- interact icon on a node far off; it keeps its own size instead (the UI's),
-- and only its drop to the ground (y) follows the nameplate, as perspective
-- shortens it.
function Glow:Attach(anchor, x, y, world)
    local f = self.frame
    f:SetParent(anchor)
    self.world, self.offX, self.offY, self.rel = world, x or 0, y or 0, nil
    if f.SetIgnoreParentScale then
        f:SetIgnoreParentScale(world and true or false)
        f:SetScale(world and UIParent:GetEffectiveScale() or 1)
    end
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

-- instant: no fade-in (a node the game picked again a moment after dropping
-- it: at a distance its pick can flicker, and a glow fading in from zero each
-- time would never get to show)
function Glow:Show(state, instant)
    self.state = state or "ready"
    self.appear = instant and 1 or 0
    self.ready = self.state == "ready" and 1 or 0
    self.locked = self.state == "locked" and 1 or 0
    self.burstAge = BURST_TIME
    self.fading = false
    self.frame:Show()
end

-- its time on the node is up: it goes out softly, then hides
function Glow:FadeOut()
    self.fading = true
end

function Glow:Hide()
    self.fading = false
    self.frame:Hide()
    self.frame:ClearAllPoints()
    self.anchor = nil
end

function Glow:IsShown()
    return self.frame:IsShown()
end

-- the nameplate's size against the UI's, for a world glow's drop to the ground
local function PlateRel(anchor)
    local ok, ps = pcall(anchor.GetEffectiveScale, anchor)
    local us = UIParent:GetEffectiveScale()
    if not ok or type(ps) ~= "number" or (issecretvalue and issecretvalue(ps)) or not us or us <= 0 then return nil end
    return ps / us
end
Glow.PlateRel = PlateRel

-- The bobber seen through its glow (opts.hole): the glow is drawn over the
-- world, so on the bobber a soft hole (a mask, see-through in the middle,
-- whole from its edge on) goes on every part, where the bobber floats. The
-- size at a glow size of 1, and how far over the glow's middle it sits.
-- The mask spans the whole glow (the pillar, the shock ring), so nothing lies
-- past its edge, where a client might hide it; the hole (64 x 92 at size 1)
-- is drawn in its middle (tools: the art is made to these numbers).
local MASK_W, MASK_H, HOLE_UP = 700, 1300, 16

function Glow:Mask(t, on)
    if not (t and t.AddMaskTexture and self.hole) then return end
    if on and not self.masked[t] then
        t:AddMaskTexture(self.hole)
        self.masked[t] = true
    elseif not on and self.masked[t] then
        t:RemoveMaskTexture(self.hole)
        self.masked[t] = nil
    end
end

function Glow:SetHole(on)
    if on and not self.hole then
        local f = self.frame
        local m = f.CreateMaskTexture and f:CreateMaskTexture()
        if not m then return end
        m:SetTexture(ART .. "fx_hole", "CLAMP", "CLAMP")
        m:SetPoint("CENTER", f, "CENTER", 0, HOLE_UP)
        m:SetSize(MASK_W, MASK_H)
        self.hole, self.masked = m, {}
    end
    if not self.hole then return end
    self.holeOn = on
    for _, t in ipairs({ self.halo, self.beam, self.shock }) do self:Mask(t, on) end
    for _, parts in pairs(self.partsOf) do
        for _, t in ipairs(parts) do self:Mask(t, on) end
    end
end

-- a change of look: the old one's parts hide, the new one's are made the
-- first time and show
function Glow:ShowLook(id)
    local look = Looks.Get(id)
    if self.shownLook == look.id then return end
    local old = self.shownLook and self.partsOf[self.shownLook]
    if old then
        for _, t in ipairs(old) do t:Hide() end
    end
    if not self.partsOf[look.id] then
        self.partsOf[look.id] = {}
        self.building = look.id
        look.Build(self)
        self.building = nil
    end
    for _, t in ipairs(self.partsOf[look.id]) do t:Show() end
    self.shownLook, self.look = look.id, look
end

function Glow:Update(elapsed)
    local cfg, opts = self.cfg, self.opts
    if not cfg then return end
    if elapsed > 0.1 then elapsed = 0.1 end
    if self.world and self.anchor then
        local f = self.frame
        local us = UIParent:GetEffectiveScale()
        if f:GetScale() ~= us then f:SetScale(us) end
        local rel = PlateRel(self.anchor)
        if rel and math.abs(rel - (self.rel or -1)) > 0.005 then
            self.rel = rel
            f:ClearAllPoints()
            f:SetPoint("CENTER", self.anchor, "CENTER", self.offX * rel, self.offY * rel)
        end
    end
    self.t = self.t + elapsed
    if self.fading then
        self.appear = Approach(self.appear, 0, elapsed / FADE_OUT)
        if self.appear <= 0 then
            self.frame:Hide()
            return
        end
    else
        self.appear = Approach(self.appear, 1, elapsed / FADE_IN)
    end
    self.ready = Approach(self.ready, self.state == "ready" and 1 or 0, elapsed / BLEND)
    self.locked = Approach(self.locked, self.state == "locked" and 1 or 0, elapsed / BLEND)

    local look = self.look or Looks.Get(opts.look)
    local scale = (cfg.size or 1) * (opts.scale or 1)
    local power = cfg.intensity or 1.5
    local speed = 1 - 0.5 * self.locked
    self.beatPhase = (self.beatPhase + elapsed * TAU * (0.75 + 0.35 * self.ready)) % TAU

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
    local beat = cfg.pulse and (0.78 + 0.22 * sin(self.beatPhase)) or 1

    local a1 = min(power, 1) * strength * beat
    local a2 = max(power - 1, 0) * 0.6 * strength * beat

    -- the pillar of light, with every look that isn't one itself
    if cfg.beam and look.beam ~= false then
        self.beam:SetSize(84 * scale, 620 * scale) -- tall, to show over trees and rocks
        self.beam:SetVertexColor(r, g, b, min((a1 * 0.85 + a2 * 0.45), 1))
        self.beam:Show()
    else
        self.beam:Hide()
    end

    -- shock ring on "in reach"
    if self.burstAge < BURST_TIME then
        self.burstAge = self.burstAge + elapsed
    end
    if self.burstAge < BURST_TIME and look.shock ~= false then
        local p = self.burstAge / BURST_TIME
        local size = (90 + 220 * p) * scale
        self.shock:SetSize(size, size)
        self.shock:SetVertexColor(r + (1 - r) * 0.4, g + (1 - g) * 0.4, b + (1 - b) * 0.4, (1 - p) * min(power, 1.5))
        self.shock:Show()
    else
        self.shock:Hide()
    end

    local f = self.f
    f.elapsed, f.scale, f.r, f.g, f.b = elapsed, scale, r, g, b
    f.strength, f.beat, f.a1, f.a2, f.power = strength, beat, a1, a2, power
    f.speed, f.ready, f.locked = speed, self.ready, self.locked
    look.Paint(self, f)
    if self.holeOn then
        local hole = self.hole
        hole:SetSize(MASK_W * scale, MASK_H * scale)
        hole:ClearAllPoints()
        hole:SetPoint("CENTER", self.frame, "CENTER", 0, HOLE_UP * scale)
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
