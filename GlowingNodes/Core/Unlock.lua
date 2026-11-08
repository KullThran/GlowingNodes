-- Unlock.lua
-- When a gathering profession goes up, the nodes you saw on the map but
-- couldn't gather yet, that you now can, are named in the chat: what, its
-- level, how many and where. Only nodes never gathered, with the level they
-- need known (logged as the glow found them).
local _, ns = ...
local L = ns.L
local Skills = ns.Skills

local U = {}
ns.Unlock = U

local KINDS = { "ore", "herb" } -- hides follow the mob's level: no fixed spot to go back to
local MAX_ZONES = 3
local SETTLE = 0.5 -- the skill is read a moment after the game says it moved

local last = {} -- kind -> the skill last seen

-- nodes of that kind first in reach between two skills: name and level ->
-- { name, level, count, maps }
function U.Between(kind, from, to)
    local groups, list = {}, {}
    for mapID, zone in pairs(ns.global.nodes or {}) do
        for _, node in pairs(zone) do
            local r = node.r
            if node.k == kind and (node.c or 0) == 0 and type(r) == "number" and r > from and r <= to then
                local key = (node.n or "?") .. "|" .. r
                local g = groups[key]
                if not g then
                    g = { name = node.n or L["CAT_" .. kind], level = r, count = 0, maps = {}, mapList = {} }
                    groups[key] = g
                    list[#list + 1] = g
                end
                g.count = g.count + 1
                if not g.maps[mapID] then
                    g.maps[mapID] = true
                    g.mapList[#g.mapList + 1] = mapID
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.level < b.level or (a.level == b.level and a.name < b.name) end)
    return list
end

local function Say(kind, list)
    for _, g in ipairs(list) do
        local names = {}
        for i, mapID in ipairs(g.mapList) do
            if i > MAX_ZONES then names[#names] = names[#names] .. " …" break end
            names[#names + 1] = ns.Gather.MapName(mapID)
        end
        ns.Print(L.MSG_UNLOCK:format(g.name, g.level, g.count, table.concat(names, ", ")))
    end
    if #list > 0 then ns.Sounds.PlayCategory(kind) end
end

function U.Check()
    Skills.Invalidate()
    for _, kind in ipairs(KINDS) do
        local now = Skills.Get(kind)
        local before = last[kind]
        last[kind] = now
        if before and now and now > before and ns.db.alert.unlock then
            Say(kind, U.Between(kind, before, now))
        end
    end
end

-- a moment after the game says a skill moved: the skill read then is the new one
local timer = CreateFrame("Frame")
timer:Hide()
local wait = 0
timer:SetScript("OnUpdate", function(self, elapsed)
    wait = wait - elapsed
    if wait <= 0 then
        self:Hide()
        U.Check()
    end
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
    if not ns.db then return end
    wait = SETTLE
    timer:Show()
end)
for _, event in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do
    pcall(events.RegisterEvent, events, event)
end

-- where the skills stand at login: nothing to tell yet
ns.On("Enable", function()
    for _, kind in ipairs(KINDS) do last[kind] = Skills.Get(kind) end
end)
