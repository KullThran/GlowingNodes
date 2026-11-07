-- NodeModel.lua
-- The node itself, in 3D, for the previews: a Tin vein, a Bruiseweed bush, a
-- dead Timber Wolf. A ModelScene with one actor; the camera is fitted to the
-- model's bounding box (Blizzard's orbit-camera convention: the camera sits
-- at target - distance * normal(yaw, pitch)) and the actor turns slowly.
-- Where the client has no ModelScene, or the model doesn't load, the caller
-- keeps its icon.
local _, ns = ...

local NodeModel = {}
ns.NodeModel = NodeModel

-- Model file IDs from the community listfile (wowdev/wow-listfile):
-- world/skillactivated/tradeskillnodes/tin_miningnode_01.m2, bush_bruiseweed01.m2.
-- Timber Wolf: creature display 604. Animation 6 is "Dead".
NodeModel.MODELS = {
    ore = { file = 219568 },
    herb = { file = 219440 },
    skin = { display = 604, anim = 6, yaw = 0.6 },
}

local FOV = 0.6       -- radians
local PITCH = 0.32    -- looking down a little, as you do at a node
local SPIN = 0.45     -- radians a second

local function Normal(yaw, pitch)
    return math.cos(-pitch) * math.cos(yaw), math.cos(-pitch) * math.sin(yaw), math.sin(-pitch)
end

local function Box(actor)
    if not actor.GetActiveBoundingBox then return end
    local a, b, c, d, e, f = actor:GetActiveBoundingBox()
    if type(a) == "table" and type(b) == "table" then
        return a.x, a.y, a.z, b.x, b.y, b.z
    end
    if type(a) == "number" and type(f) == "number" then return a, b, c, d, e, f end
end

local function Frame(scene, actor, fill)
    local x0, y0, z0, x1, y1, z1 = Box(actor)
    if not x0 then return false end
    local scale = actor.GetScale and actor:GetScale() or 1
    local r = 0.5 * math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2 + (z1 - z0) ^ 2) * scale
    if not (r > 0.01 and r < 1000) then return false end
    local tx, ty, tz = 0, 0, (z0 + z1) / 2 * scale
    local dist = r / math.sin(FOV / 2) / (fill or 0.9)
    local nx, ny, nz = Normal(0, PITCH)
    scene:SetCameraFieldOfView(FOV)
    scene:SetCameraNearClip(0.01)
    scene:SetCameraFarClip(dist * 4 + 100)
    scene:SetCameraPosition(tx - dist * nx, ty - dist * ny, tz - dist * nz)
    scene:SetCameraOrientationByYawPitchRoll(0, PITCH, 0)
    return true
end

-- parent: the frame to fill. onReady(true) once the model shows, onReady(false)
-- if it can't. Returns the scene (or nil when the client has none).
function NodeModel.New(parent, cat, onReady)
    local spec = NodeModel.MODELS[cat]
    if not spec then return end
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, parent)
    if not ok or not scene or not scene.CreateActor then return end
    scene:SetAllPoints()
    if scene.SetLightVisible then
        scene:SetLightVisible(true)
        scene:SetLightDirection(0.4, 0.3, -0.85)
        scene:SetLightAmbientColor(0.62, 0.58, 0.52)
        scene:SetLightDiffuseColor(0.95, 0.88, 0.78)
    end
    local actor = scene:CreateActor()
    if not actor then return end

    local yaw, ready, tries = spec.yaw or 0, false, 0
    local function load()
        local set
        if spec.file and actor.SetModelByFileID then
            set = actor:SetModelByFileID(spec.file)
        elseif spec.display and actor.SetModelByCreatureDisplayID then
            set = actor:SetModelByCreatureDisplayID(spec.display)
        end
        if spec.anim and actor.SetAnimation then actor:SetAnimation(spec.anim) end
        return set ~= false
    end

    scene:SetScript("OnUpdate", function(_, elapsed)
        if not ready then
            tries = tries + elapsed
            local loaded = not actor.IsLoaded or actor:IsLoaded()
            if loaded and Frame(scene, actor) then
                ready = true
                if onReady then onReady(true) end
            elseif tries > 3 then
                scene:SetScript("OnUpdate", nil)
                scene:Hide()
                if onReady then onReady(false) end
            end
            return
        end
        yaw = yaw + elapsed * SPIN
        actor:SetYaw(yaw)
    end)
    if not load() then
        scene:Hide()
        return
    end
    actor:SetYaw(yaw)
    return scene
end
