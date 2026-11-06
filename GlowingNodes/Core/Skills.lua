-- Skills.lua
-- The player's gathering skills and the level a node needs.
-- Required level, most reliable first:
--   1. learned: the game's own "requires Mining 65" error, or a tooltip line
--      with the profession and a number, remembered per object ID and name;
--   2. NodeData by object ID, then by name;
--   3. skinning: the corpse level formula.
local _, ns = ...
local L = ns.L
local Data = ns.NodeData

local Skills = {}
ns.Skills = Skills

local SKILL_LINE = { ore = 186, herb = 182, skin = 393 }
-- Spells whose name is the profession's name in the client's language
local SPELL = { ore = 2575, herb = 2366, skin = 8613 }
local NAMES = {
    ore = { "mining", "minería", "mineria", "bergbau", "minage", "estrazione", "mineração", "горное дело", "채광", "采矿", "採礦" },
    herb = { "herbalism", "herboristería", "herboristeria", "kräuterkunde", "herboristerie", "erbalismo", "herborismo", "травничество", "약초채집", "草药学", "草藥學" },
    skin = { "skinning", "desuello", "desollar", "kürschnerei", "dépeçage", "scuoiatura", "esfolamento", "снятие шкур", "무두질", "剥皮", "剝皮" },
}

local cache = {}      -- category -> rank (false = not learned)
local cacheTime = 0

local function SafeCall(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g end
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        return SafeCall(C_Spell.GetSpellName, id)
    end
    return (SafeCall(GetSpellInfo, id))
end

-- Adds the client's own names (skill line, spell) to the lookup lists
local function LearnLocalNames()
    for cat, id in pairs(SKILL_LINE) do
        local list = NAMES[cat]
        local function add(name)
            if type(name) == "string" and name ~= "" then
                name = name:lower()
                for _, n in ipairs(list) do if n == name then return end end
                table.insert(list, 1, name)
            end
        end
        if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
            local info = SafeCall(C_SkillInfo.GetSkillLineInfoByID, id)
            if type(info) == "table" then add(info.name) end
        end
        add(SpellName(SPELL[cat]))
    end
end

local function MatchCategory(name)
    if type(name) ~= "string" then return nil end
    name = name:lower()
    for cat, list in pairs(NAMES) do
        for _, n in ipairs(list) do
            if name == n then return cat end
        end
    end
end

local function ReadSkills()
    wipe(cache)
    -- Forever: C_SkillInfo by skill line ID
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        for cat, id in pairs(SKILL_LINE) do
            local info = SafeCall(C_SkillInfo.GetSkillLineInfoByID, id)
            if type(info) == "table" and not info.isHeader then
                local rank, maxRank = tonumber(info.rank) or 0, tonumber(info.maxRank) or 0
                if rank > 0 or maxRank > 0 then cache[cat] = rank end
            end
        end
    end
    -- Professions tab (modern clients)
    if GetProfessions and GetProfessionInfo then
        local list = { SafeCall(GetProfessions) }
        for i = 1, 6 do
            if list[i] then
                local name, _, rank, _, _, _, line = SafeCall(GetProfessionInfo, list[i])
                for cat, id in pairs(SKILL_LINE) do
                    if cache[cat] == nil and (line == id or MatchCategory(name) == cat) then
                        cache[cat] = tonumber(rank) or 0
                    end
                end
            end
        end
    end
    -- Skill list (classic clients), by name
    local count = (C_SkillInfo and C_SkillInfo.GetNumSkillLines and SafeCall(C_SkillInfo.GetNumSkillLines))
        or (GetNumSkillLines and SafeCall(GetNumSkillLines)) or 0
    for i = 1, count do
        local name, isHeader, rank
        if C_SkillInfo and C_SkillInfo.GetSkillLineInfo then
            local info = SafeCall(C_SkillInfo.GetSkillLineInfo, i)
            if type(info) == "table" then
                name, isHeader, rank = info.name, info.isHeader, info.rank
                local cat = info.skillID and (info.skillID == 186 and "ore" or info.skillID == 182 and "herb" or info.skillID == 393 and "skin")
                if cat and cache[cat] == nil then cache[cat] = tonumber(rank) or 0 end
            end
        elseif GetSkillLineInfo then
            local n, header, _, r = SafeCall(GetSkillLineInfo, i)
            name, isHeader, rank = n, header, r
        end
        if name and not isHeader then
            local cat = MatchCategory(name)
            if cat and cache[cat] == nil then cache[cat] = tonumber(rank) or 0 end
        end
    end
    for cat in pairs(SKILL_LINE) do
        if cache[cat] == nil then cache[cat] = false end
    end
    cacheTime = GetTime()
end

-- The player's rank in the profession of that category, or nil without it
function Skills.Get(category)
    if GetTime() - cacheTime > 5 then ReadSkills() end
    local rank = cache[category]
    if rank == false then return nil end
    return rank
end

function Skills.Invalidate()
    cacheTime = 0
end

function Skills.ProfessionName(category)
    return NAMES[category] and NAMES[category][1] and (L["PROF_" .. category]) or category
end

---------------------------------------------------------------------------
-- Required level
---------------------------------------------------------------------------

local function LearnedKeys(objectID, name)
    local lname = Data.NormalizeName(name)
    return objectID and ("o" .. objectID) or nil, lname and ("n" .. lname) or nil
end

function Skills.Learned(objectID, name)
    local learned = ns.global and ns.global.learned
    if not learned then return nil end
    local ko, kn = LearnedKeys(objectID, name)
    return (ko and learned[ko]) or (kn and learned[kn]) or nil
end

function Skills.Remember(objectID, name, level, category)
    local learned = ns.global and ns.global.learned
    if not (learned and level and level > 0 and level <= 450) then return end
    local ko, kn = LearnedKeys(objectID, name)
    local changed = false
    if ko and learned[ko] ~= level then learned[ko] = level changed = true end
    if kn and learned[kn] ~= level then learned[kn] = level changed = true end
    if changed then
        ns.Print(L.MSG_LEARNED:format(name or ("#" .. tostring(objectID)), L["PROF_" .. (category or "ore")], level))
        ns.Fire("Learned")
    end
end

function Skills.LearnedCount()
    local n = 0
    for key in pairs(ns.global and ns.global.learned or {}) do
        if key:sub(1, 1) == "o" then n = n + 1 end
    end
    return n
end

-- "Requires Mining 65" / "Requiere Minería (65)": category and level, or nil
function Skills.ParseRequirement(text)
    if type(text) ~= "string" then return nil end
    local lower = text:lower()
    for cat, list in pairs(NAMES) do
        for _, n in ipairs(list) do
            local s, e = lower:find(n, 1, true)
            if s then
                local level = tonumber(lower:sub(e + 1):match("(%d+)") or lower:sub(1, s - 1):match("(%d+)%D*$"))
                if level then return cat, level end
            end
        end
    end
end

-- target: { category, objectID, name, level }  ->  required, source
function Skills.Required(target)
    local learned = Skills.Learned(target.objectID, target.name)
    if learned then return learned, "learned" end
    if target.tooltipLevel then return target.tooltipLevel, "tooltip" end
    if target.category == "skin" or target.corpse then
        return Data.SkinningLevel(target.level), "formula"
    end
    local _, level = Data.Lookup(target.objectID, target.name, target.category)
    if level then return level, "data" end
    return nil, "unknown"
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        LearnLocalNames()
        Skills.Invalidate()
    elseif event == "UI_ERROR_MESSAGE" then
        local a, b = ...
        local text = type(b) == "string" and b or a
        local cat, level = Skills.ParseRequirement(text)
        local target = ns.SoftTarget and ns.SoftTarget.current
        -- only for the node the interact key is on, and the same profession
        -- (a mouse click on another node would teach the wrong one)
        if cat and level and target and cat == target.category and (target.objectID or target.name) then
            Skills.Remember(target.objectID, target.name, level, cat)
        end
    else
        Skills.Invalidate()
    end
end)
for _, event in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "LEARNED_SPELL_IN_TAB", "UI_ERROR_MESSAGE" }) do
    pcall(events.RegisterEvent, events, event)
end
