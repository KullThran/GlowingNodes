-- Share.lua
-- The log as a text code: a backup, or for another character or a friend.
-- Export writes the points (of one zone or all) as one line of plain
-- characters, with a checksum; Import reads one back and joins it to the log
-- as the log itself would: a point already there (the same kind, a few yards
-- off) keeps the most of each count and the latest times, a rough point
-- settles on a precise one, the rest is added. Importing the same code twice
-- changes nothing. Only what a point may hold is taken from a code.
--
-- The code: "GN<version>:<checksum>:<data>". The data is a small table
-- written as tokens: { } a table (key, value, key, value...), i<base 36>,
-- an integer, f<number>, a number, s<text>, a text (%XX for the few
-- characters that would break it), T and F. Spaces and line breaks are not
-- part of it, so a code wrapped by a chat or a forum still reads.
local _, ns = ...

local Share = {}
ns.Share = Share

local VERSION = 1
local MAX_DEPTH = 8
local MAX_NAME = 100
local MAX_MOBS = 6
local MAX_KEY = 10000 * 10000 + 10000 + 1000 -- G.Key(1, 1), and a few spots taken
local KINDS = { ore = true, herb = true, skin = true, fish = true }
local COUNTS = { "o", "r", "c", "s", "t", "v" }
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local SMALL = 2 ^ 31 -- integers below it in base 36 (the game reads those back whole)

---------------------------------------------------------------------------
-- Writing and reading the tokens
---------------------------------------------------------------------------

local function B36(n)
    if n == 0 then return "0" end
    local out = {}
    while n > 0 do
        local d = n % 36
        out[#out + 1] = DIGITS:sub(d + 1, d + 1)
        n = (n - d) / 36
    end
    return table.concat(out):reverse()
end

local function Escape(s)
    return (s:gsub("[%z\1-\32%%,|\127]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Unescape(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function Order(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    return a < b
end

local function Write(out, v, depth)
    local t = type(v)
    if t == "table" then
        if depth > MAX_DEPTH then return end
        local keys = {}
        for k in pairs(v) do
            local tk = type(k)
            if tk == "number" or tk == "string" then keys[#keys + 1] = k end
        end
        table.sort(keys, Order)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            local before = #out
            Write(out, k, depth + 1)
            if #out > before then
                local mid = #out
                Write(out, v[k], depth + 1)
                if #out == mid then out[mid] = nil end -- a value that can't be written: its key goes too
            end
        end
        out[#out + 1] = "}"
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            out[#out + 1] = "i0,"
        elseif v == math.floor(v) and math.abs(v) < SMALL then
            out[#out + 1] = (v < 0 and "i-" .. B36(-v) or "i" .. B36(v)) .. ","
        else
            out[#out + 1] = "f" .. ("%.17g"):format(v) .. ","
        end
    elseif t == "string" then
        out[#out + 1] = "s" .. Escape(v) .. ","
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    end
end

function Share.Encode(v)
    local out = {}
    Write(out, v, 1)
    return table.concat(out)
end

-- the value the text holds, or nil (never an error)
function Share.Decode(s)
    if type(s) ~= "string" then return nil end
    local pos = 1
    local function Value(depth)
        if depth > MAX_DEPTH then error("deep", 0) end
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local t = {}
            while s:sub(pos, pos) ~= "}" do
                if pos > #s then error("short", 0) end
                local k = Value(depth + 1)
                local v = Value(depth + 1)
                if type(k) == "table" then error("key", 0) end
                t[k] = v
            end
            pos = pos + 1
            return t
        elseif c == "i" or c == "f" or c == "s" then
            local e = s:find(",", pos + 1, true)
            if not e then error("short", 0) end
            local body = s:sub(pos + 1, e - 1)
            pos = e + 1
            if c == "s" then return Unescape(body) end
            local n
            if c == "i" then
                local neg = body:sub(1, 1) == "-"
                if neg then body = body:sub(2) end
                n = body:find("^[0-9a-z]+$") and tonumber(body, 36)
                if n and neg then n = -n end
            else
                n = tonumber(body)
            end
            if not n then error("number", 0) end
            return n
        elseif c == "T" then
            pos = pos + 1
            return true
        elseif c == "F" then
            pos = pos + 1
            return false
        end
        error("bad", 0)
    end
    local ok, v = pcall(Value, 1)
    if not ok or pos ~= #s + 1 then return nil end
    return v
end

-- Adler-32: a code cut short or changed doesn't read
local function Sum(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

function Share.Pack(data)
    local body = Share.Encode(data)
    return ("GN%d:%s:%s"):format(VERSION, B36(Sum(body)), body)
end

-- the table a code holds, or nil and why: "bad" (not a code), "damaged"
-- (cut short or changed), "newer" (from a later version of the addon)
function Share.Unpack(code)
    if type(code) ~= "string" then return nil, "bad" end
    code = code:gsub("%s+", "")
    local version, sum, body = code:match("^GN(%d+):(%w+):(.*)$")
    if not version then return nil, "bad" end
    if tonumber(version) > VERSION then return nil, "newer" end
    if tonumber(sum, 36) ~= Sum(body) then return nil, "damaged" end
    local data = Share.Decode(body)
    if type(data) ~= "table" then return nil, "damaged" end
    return data
end

---------------------------------------------------------------------------
-- What a point may hold
---------------------------------------------------------------------------

local function Count(v)
    return type(v) == "number" and v == math.floor(v) and v >= 0 and v < 2 ^ 40
end

local function Name(v)
    return type(v) == "string" and #v > 0 and #v <= MAX_NAME
end

-- a clean copy of a point, or nil if it isn't one
local function Clean(raw)
    if type(raw) ~= "table" or not KINDS[raw.k] then return nil end
    local node = { k = raw.k }
    if Name(raw.n) then node.n = raw.n end
    for _, f in ipairs(COUNTS) do
        if Count(raw[f]) then node[f] = raw[f] end
    end
    if raw.p == false then node.p = false end
    if type(raw.x) == "table" then
        for id, n in pairs(raw.x) do
            if Count(id) and id > 0 and Count(n) and n > 0 then
                node.x = node.x or {}
                node.x[id] = n
            end
        end
    end
    if raw.k == "skin" and type(raw.mobs) == "table" then
        local list = {}
        for mob, n in pairs(raw.mobs) do
            if Name(mob) and Count(n) and n > 0 then list[#list + 1] = { mob, n } end
        end
        table.sort(list, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
        for i = 1, math.min(#list, MAX_MOBS) do
            node.mobs = node.mobs or {}
            node.mobs[list[i][1]] = list[i][2]
        end
    end
    return node
end

local function Item(raw)
    if type(raw) ~= "table" or not Name(raw.n) then return nil end
    return { n = raw.n, q = Count(raw.q) and raw.q <= 10 and raw.q or nil }
end

---------------------------------------------------------------------------
-- Export and import
---------------------------------------------------------------------------

-- the code for one zone (uiMapID) or, with none, the whole log; and how many
-- points and zones it holds. nil when there is nothing to export.
function Share.Export(mapID)
    local nodes, known = {}, ns.global.items or {}
    local items, points, zones = {}, 0, 0
    for id, zone in pairs(ns.global.nodes) do
        if (mapID == nil or id == mapID) and Count(id) and id > 0 and type(zone) == "table" then
            local out
            for key, raw in pairs(zone) do
                local node = Count(key) and key <= MAX_KEY and Clean(raw)
                if node then
                    out = out or {}
                    out[key] = node
                    points = points + 1
                    for itemID in pairs(node.x or {}) do items[itemID] = Item(known[itemID]) end
                end
            end
            if out then
                nodes[id] = out
                zones = zones + 1
            end
        end
    end
    if points == 0 then return nil, 0, 0 end
    return Share.Pack({ n = nodes, i = next(items) and items or nil }), points, zones
end

local function Most(here, node, f)
    if node[f] and (here[f] == nil or node[f] > here[f]) then here[f] = node[f] end
end

-- one point of a code into the log: true if added, false if joined
local function Join(mapID, key, node)
    local G = ns.Gather
    local all = ns.global.nodes
    local x, y = G.Decode(key)
    local hereKey, here = G.Near(mapID, node.k, x, y, node.p == false, node.k == "fish" and node.n or nil)
    if not here then
        all[mapID] = all[mapID] or {}
        local zone = all[mapID]
        while zone[key] do key = key + 1 end
        zone[key] = node
        return true
    end
    local zone = all[mapID]
    for _, f in ipairs({ "c", "s", "t", "v" }) do Most(here, node, f) end
    for _, f in ipairs({ "n", "o", "r" }) do
        if here[f] == nil then here[f] = node[f] end
    end
    if node.x then
        here.x = here.x or {}
        for id, n in pairs(node.x) do Most(here.x, node.x, id) end
    end
    if node.mobs then
        here.mobs = here.mobs or {}
        for mob in pairs(node.mobs) do Most(here.mobs, node.mobs, mob) end
        here.mobs = Clean({ k = "skin", mobs = here.mobs }).mobs
    end
    if here.p == false and node.p == nil then
        -- the code knows the very spot: the rough point settles there
        here.p = nil
        if hereKey ~= key then
            zone[hereKey] = nil
            while zone[key] do key = key + 1 end
            zone[key] = here
        end
    end
    return false
end

-- reads a code into the log. Returns { added, merged, zones }, or nil and
-- why ("bad", "damaged", "newer"); the log is left as it was then.
function Share.Import(code)
    local data, why = Share.Unpack(code)
    if not data then return nil, why end
    if type(data.n) ~= "table" then return nil, "bad" end
    local result = { added = 0, merged = 0, zones = 0 }
    local items = ns.global.items
    for mapID, zone in pairs(data.n) do
        if Count(mapID) and mapID > 0 and type(zone) == "table" then
            local keys = {}
            for key in pairs(zone) do
                if Count(key) and key <= MAX_KEY then keys[#keys + 1] = key end
            end
            table.sort(keys)
            local any = false
            for _, key in ipairs(keys) do
                local node = Clean(zone[key])
                if node then
                    any = true
                    if Join(mapID, key, node) then
                        result.added = result.added + 1
                    else
                        result.merged = result.merged + 1
                    end
                    if node.x and type(data.i) == "table" then
                        if not items then
                            ns.global.items = {}
                            items = ns.global.items
                        end
                        for id in pairs(node.x) do
                            if items[id] == nil then items[id] = Item(data.i[id]) end
                        end
                    end
                end
            end
            if any then result.zones = result.zones + 1 end
        end
    end
    if result.added + result.merged > 0 then ns.Fire("NodesChanged") end
    return result
end
