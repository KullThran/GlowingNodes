-- Looks.lua
-- The looks a glow can wear, one per kind of node (the kind's "look"
-- setting). Each look says which textures it needs (made on the glow the
-- first time it shows, never before) and how it paints them on each frame.
-- What every look shares stays in Glow.lua: the frame, the fade, the states,
-- the pulse, the halo, the pillar of light, the "in reach" shock ring and the
-- level number.
--
-- look = {
--   id,
--   Build(glow)    makes its parts with glow:Part / glow:Parts
--   Paint(glow, f) f: elapsed, scale, r, g, b, strength, beat, a1, a2,
--                  power, speed, ready, locked (worked out by the glow)
--   Flare(glow)    optional, on "in reach"
--   beam = false   the kind's pillar of light is not drawn with it
--   shock = false  no shock ring on "in reach"
-- }
local _, ns = ...

local Looks = { LIST = {} }
ns.Looks = Looks

local sin, cos, pi, random, min, max, sqrt = math.sin, math.cos, math.pi, math.random, math.min, math.max, math.sqrt
local TAU = 2 * pi

local byId = {}

local function Add(look)
    byId[look.id] = look
    Looks.LIST[#Looks.LIST + 1] = look.id
    return look
end

-- the look for an id; the ring for nil or one that doesn't exist (a profile
-- edited by hand, or saved by a later version)
function Looks.Get(id)
    return byId[id] or byId.ring
end

---------------------------------------------------------------------------
-- Helpers the looks share
---------------------------------------------------------------------------

-- size and tint, white mixed in by `white` (0..1)
local function Tint(tex, w, h, r, g, b, a, white)
    tex:SetSize(max(w, 0.01), max(h, 0.01))
    if white then
        r, g, b = r + (1 - r) * white, g + (1 - g) * white, b + (1 - b) * white
    end
    tex:SetVertexColor(r, g, b, min(max(a, 0), 1))
end
Looks.Tint = Tint

-- a flat look turns inside its flattened rectangle: turning the texture
-- would turn the whole ellipse, so its texture coordinates turn instead, the
-- four corners of the image round (0.5, 0.5); the art leaves its corners empty
local CORNER_BASE = { 3 * pi / 4, 5 * pi / 4, pi / 4, 7 * pi / 4 } -- UL, LL, UR, LR
local function Corner(a, k)
    local base = CORNER_BASE[k + 1] + a
    return 0.5 + cos(base) * 0.7071, 0.5 - sin(base) * 0.7071
end

local function Turn(tex, a)
    local ulx, uly = Corner(a, 0)
    local llx, lly = Corner(a, 1)
    local urx, ury = Corner(a, 2)
    local lrx, lry = Corner(a, 3)
    tex:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry)
end
Looks.Turn = Turn

-- the halo: round, or flattened for the looks that lie on the ground
local function Halo(glow, f, flat, alpha)
    local hs = 230 * (0.94 + 0.06 * f.beat) * f.scale
    Tint(glow.halo, hs, flat and hs * 0.42 or hs, f.r, f.g, f.b, (alpha or 1) * f.a1 * 0.95)
end
Looks.Halo = Halo

local function Phase(glow, key)
    glow[key] = glow[key] or random() * TAU
end
Looks.Phase = Phase

---------------------------------------------------------------------------
-- Ring: halo, core, a turning ring of arcs, slow rays, rising glints
---------------------------------------------------------------------------

local GLINTS = 6

local function RespawnGlint(gl, now)
    local a, r = random() * TAU, sqrt(random())
    gl.x, gl.y = cos(a) * r * 40, sin(a) * r * 26 - 6
    gl.life = 0.7 + 0.9 * random()
    gl.age = now and 0 or -0.8 * random()
    gl.scale = 0.5 + 0.8 * random()
    gl.spin = (random() - 0.5) * 2
end

Add({
    id = "ring",
    Build = function(glow)
        glow:Part("halo2", "fx_halo", "BACKGROUND", 2)
        glow:Part("burst", "fx_burst", "BORDER", 0)
        glow:Part("ring", "fx_ring", "ARTWORK", 0)
        glow:Part("core", "fx_core", "ARTWORK", 1)
        for _, gl in ipairs(glow:Parts("glints", GLINTS, "fx_glint", "OVERLAY", 1)) do RespawnGlint(gl) end
        Phase(glow, "ringAngle")
        Phase(glow, "burstAngle")
    end,
    Flare = function(glow)
        for _, gl in ipairs(glow.glints) do RespawnGlint(gl, true) end
    end,
    Paint = function(glow, f)
        local scale, r, g, b, beat, a1, a2 = f.scale, f.r, f.g, f.b, f.beat, f.a1, f.a2
        glow.ringAngle = (glow.ringAngle + f.elapsed * 0.55 * f.speed) % TAU
        glow.burstAngle = (glow.burstAngle - f.elapsed * 0.18 * f.speed) % TAU
        Halo(glow, f)
        Tint(glow.halo2, 300 * scale, 300 * scale, r, g, b, a2)
        glow.halo2:SetShown(a2 > 0.01)
        local cs = 70 * (0.9 + 0.1 * beat) * scale
        Tint(glow.core, cs, cs, r, g, b, (a1 + a2) * 0.9, 0.55)
        Tint(glow.ring, 150 * scale, 150 * scale, r, g, b, a1 * 0.85 + a2 * 0.5)
        glow.ring:SetRotation(glow.ringAngle)
        Tint(glow.burst, 250 * scale, 250 * scale, r, g, b, a1 * 0.45 + a2 * 0.35)
        glow.burst:SetRotation(glow.burstAngle)
        -- glints rising out of the node
        for _, gl in ipairs(glow.glints) do
            gl.age = gl.age + f.elapsed * f.speed * (0.8 + 0.4 * f.ready)
            if gl.age >= gl.life then RespawnGlint(gl) end
            local tex = gl.tex
            local shine = gl.age > 0 and sin(pi * gl.age / gl.life) or 0
            local s = 30 * gl.scale * (0.35 + 0.65 * shine) * scale
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", glow.frame, "CENTER", gl.x * scale, (gl.y + 26 * max(gl.age, 0)) * scale)
            tex:SetRotation(gl.spin * max(gl.age, 0))
            Tint(tex, s, s, r, g, b, f.strength * shine * min(f.power, 1.6), 0.5)
        end
    end,
})

---------------------------------------------------------------------------
-- Swirl (the fishing bobber's): flat on the water, a wave ring turning
-- round the node and sparks leaping off its edge
---------------------------------------------------------------------------

local SPARKLES = 8
local SWIRL_SPEED = 0.6 -- radians a second

local function RespawnSparkle(s, now)
    s.angle = random() * TAU
    s.life = 0.6 + 0.6 * random()
    s.age = now and 0 or -0.5 * random()
    s.size = 10 + 8 * random()
end

Add({
    id = "swirl",
    shock = false,
    Build = function(glow)
        glow:Part("swirl", "fx_swirl", "ARTWORK", 0)
        for i, s in ipairs(glow:Parts("sparkles", SPARKLES, "fx_sparkle", "OVERLAY", 2)) do
            s.white = i % 2 == 0
            RespawnSparkle(s)
        end
        Phase(glow, "swirlAngle")
    end,
    Paint = function(glow, f)
        local scale, r, g, b = f.scale, f.r, f.g, f.b
        Halo(glow, f, true)
        glow.swirlAngle = (glow.swirlAngle + f.elapsed * SWIRL_SPEED) % TAU
        Turn(glow.swirl, glow.swirlAngle)
        Tint(glow.swirl, 170 * scale, 64 * scale, r, g, b, (f.a1 * 0.9 + f.a2 * 0.5) * (0.85 + 0.15 * f.beat))
        for _, s in ipairs(glow.sparkles) do
            s.age = s.age + f.elapsed
            if s.age >= s.life then RespawnSparkle(s, true) end
            local shine = s.age > 0 and sin(pi * s.age / s.life) or 0
            local size = s.size * (0.5 + 0.5 * shine) * scale
            local rise = 18 * max(s.age, 0) / s.life
            local tex = s.tex
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", glow.frame, "CENTER", cos(s.angle) * 80 * scale, (sin(s.angle) * 30 + rise) * scale)
            Tint(tex, size, size, r, g, b, f.strength * shine * min(f.power, 1.6), s.white and 0.85 or nil)
        end
    end,
})
