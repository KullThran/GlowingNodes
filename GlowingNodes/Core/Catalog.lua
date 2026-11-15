-- Catalog.lua
-- Every ore and herb by node type (Copper Vein, Rich Thorium Vein, Peacebloom…),
-- so the player can switch off the ones they don't want: a hidden type doesn't
-- glow, isn't drawn on the maps and the arrow doesn't lead to it.
-- The IDs and levels are NodeData's; a test keeps the two lists together.
-- A node the catalog can't tell (no readable ID or name) is always shown.
local _, ns = ...

local Catalog = {}
ns.Catalog = Catalog

-- k, key, r, en, es, item, ids[, match = name patterns, ores only]
local function T(k, key, r, en, es, item, ids, match)
    return { k = k, key = key, r = r, en = en, es = es, item = item, ids = ids, match = match }
end

Catalog.TYPES = {
    T("ore", "copper", 1, "Copper Vein", "Filón de cobre", 2770,
        { 1731, 2055, 3763, 103713, 181248 }, { "copper vein", "cobre" }),
    T("ore", "tin", 65, "Tin Vein", "Filón de estaño", 2771,
        { 1732, 2054, 3764, 103711, 181249 }, { "tin vein", "estaño" }),
    T("ore", "incendicite", 65, "Incendicite Mineral Vein", "Filón de incendicita", 3340,
        { 1610, 1667 }, { "incendicite", "incendicita" }),
    T("ore", "silver", 75, "Silver Vein", "Filón de plata", 2775,
        { 1733, 105569, 73940 }, { "silver vein", "plata" }),
    T("ore", "bloodstone", 75, "Lesser Bloodstone Deposit", "Depósito de petrosangre inferior", 4278,
        { 2653 }, { "lesser bloodstone", "petrosangre" }),
    T("ore", "iron", 125, "Iron Deposit", "Depósito de hierro", 2772,
        { 1735, 73939 }, { "iron deposit", "hierro" }),
    T("ore", "indurium", 150, "Indurium Mineral Vein", "Filón de indurio", 5833,
        { 19903 }, { "indurium", "indurio" }),
    T("ore", "gold", 155, "Gold Vein", "Filón de oro", 2776,
        { 1734, 150080, 181109, 73941 }, { "gold vein", "filón de oro", "filon de oro", "oro cubierto" }),
    T("ore", "mithril", 175, "Mithril Deposit", "Depósito de mitril", 3858,
        { 2040, 150079, 176645, 123310 }, { "mithril", "mitril" }),
    T("ore", "truesilver", 230, "Truesilver Deposit", "Depósito de veraplata", 7911,
        { 2047, 150081, 181108, 123309 }, { "truesilver", "veraplata" }),
    T("ore", "darkiron", 230, "Dark Iron Deposit", "Depósito de hierro negro", 11370,
        { 165658 }, { "dark iron", "hierro negro" }),
    T("ore", "thorium", 245, "Small Thorium Vein", "Filón pequeño de torio", 10620,
        { 324, 150082, 176643, 123848 }, { "thorium", "torio" }),
    T("ore", "hakkari", 250, "Hakkari Thorium Vein", "Filón de torio de Hakkari", 10620,
        { 180215 }, { "hakkari thorium", "torio de hakkari" }),
    T("ore", "richthorium", 275, "Rich Thorium Vein", "Filón de torio enriquecido", 10620,
        { 175404, 177388 }, { "rich thorium", "torio enriquecido" }),

    T("herb", "silverleaf", 1, "Silverleaf", "Hojaplata", 765, { 1617, 3725, 657380 }),
    T("herb", "peacebloom", 1, "Peacebloom", "Flor de paz", 2447, { 1618, 3724, 657382 }),
    T("herb", "earthroot", 15, "Earthroot", "Raíz de tierra", 2449, { 1619, 3726 }),
    T("herb", "mageroyal", 50, "Mageroyal", "Marregal", 785, { 1620, 3727 }),
    T("herb", "briarthorn", 70, "Briarthorn", "Brezospina", 2450, { 1621, 3729 }),
    T("herb", "stranglekelp", 85, "Stranglekelp", "Alga estranguladora", 3820, { 2045 }),
    T("herb", "bruiseweed", 100, "Bruiseweed", "Hierba cardenal", 2453, { 1622, 3730 }),
    T("herb", "wildsteelbloom", 115, "Wild Steelbloom", "Acérita salvaje", 3355, { 1623 }),
    T("herb", "gravemoss", 120, "Grave Moss", "Musgo de tumba", 3369, { 1628 }),
    T("herb", "kingsblood", 125, "Kingsblood", "Sangrerregia", 3356, { 1624 }),
    T("herb", "liferoot", 150, "Liferoot", "Vidarraíz", 3357, { 2041 }),
    T("herb", "fadeleaf", 160, "Fadeleaf", "Pálida", 3818, { 2042 }),
    T("herb", "goldthorn", 170, "Goldthorn", "Espina de oro", 3821, { 2046 }),
    T("herb", "khadgarswhisker", 185, "Khadgar's Whisker", "Vibrisa de Khadgar", 3358, { 2043 }),
    T("herb", "wintersbite", 195, "Wintersbite", "Ivernalia", 3819, { 2044 }),
    T("herb", "firebloom", 205, "Firebloom", "Flor de fuego", 4625, { 2866 }),
    T("herb", "purplelotus", 210, "Purple Lotus", "Loto cárdeno", 8831, { 142140, 180165 }),
    T("herb", "arthastears", 220, "Arthas' Tears", "Lágrimas de Arthas", 8836, { 142141, 176642 }),
    T("herb", "sungrass", 230, "Sungrass", "Solea", 8838, { 142142, 176636, 180164 }),
    T("herb", "blindweed", 235, "Blindweed", "Carolina", 8839, { 142143 }),
    T("herb", "ghostmushroom", 245, "Ghost Mushroom", "Champiñón fantasma", 8845, { 142144 }),
    T("herb", "gromsblood", 250, "Gromsblood", "Gromsanguina", 8846, { 142145, 176637 }),
    T("herb", "goldensansam", 260, "Golden Sansam", "Sansam dorado", 13464, { 176583, 176638, 180167 }),
    T("herb", "dreamfoil", 270, "Dreamfoil", "Hojasueño", 13463, { 176584, 176639, 180168 }),
    T("herb", "mountainsilversage", 280, "Mountain Silversage", "Salviargenta de montaña", 13465,
        { 176586, 176640, 180166 }),
    T("herb", "plaguebloom", 285, "Plaguebloom", "Flor de peste", 13466, { 176587, 176641 }),
    T("herb", "icecap", 290, "Icecap", "Setelo", 13467, { 176588 }),
    T("herb", "blacklotus", 300, "Black Lotus", "Loto negro", 13468, { 176589 }),
}

-- ore names are searched in NodeData.orePatterns' order: "dark iron" before
-- "iron", "truesilver" before "silver", "rich thorium" before "thorium"
local MATCH_ORDER = {
    "darkiron", "truesilver", "richthorium", "hakkari", "thorium", "mithril", "indurium",
    "gold", "iron", "bloodstone", "silver", "incendicite", "tin", "copper",
}

Catalog.ByKey, Catalog.ByID = {}, {}
local herbNames = {} -- lower-case English/Spanish name -> key
for _, t in ipairs(Catalog.TYPES) do
    Catalog.ByKey[t.key] = t
    for _, id in ipairs(t.ids) do Catalog.ByID[id] = t end
    if t.k == "herb" then
        herbNames[t.en:lower()] = t.key
        herbNames[t.es:lower()] = t.key
    end
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local Normalize = ns.NodeData.NormalizeName

-- the types learned from the log (Forever's own new nodes): built on first use,
-- rebuilt by All() and whenever the log changes
local learned -- key -> type

local function KnownType(objectID, lname, kind)
    if objectID ~= nil and not IsSecret(objectID) then
        local t = Catalog.ByID[objectID]
        if t and (kind == nil or t.k == kind) then return t.key end
    end
    if not lname then return nil end
    if kind ~= "ore" and herbNames[lname] then return herbNames[lname] end
    if kind ~= "herb" then
        for _, key in ipairs(MATCH_ORDER) do
            for _, pattern in ipairs(Catalog.ByKey[key].match) do
                if lname:find(pattern, 1, true) then return key end
            end
        end
    end
end

local function NodeName(node)
    local name = node.n or node.en
    if type(name) ~= "string" or IsSecret(name) then return nil end
    return name
end

local seenNames -- key -> the name the game gave a node of that type

local function Scan()
    learned, seenNames = {}, {}
    local nodes = ns.global and ns.global.nodes
    if type(nodes) ~= "table" then return end
    for _, spots in pairs(nodes) do
        if type(spots) == "table" then
            for _, node in pairs(spots) do
                if type(node) == "table" and (node.k == "ore" or node.k == "herb") then
                    local name = NodeName(node)
                    local lname = Normalize(name)
                    local key = KnownType(node.o, lname, node.k)
                    if key then
                        seenNames[key] = seenNames[key] or name
                    elseif lname and lname ~= "" then
                        key = "name:" .. lname
                        local t = learned[key]
                        if not t then
                            learned[key] = { key = key, k = node.k, r = node.r, n = name, learned = true }
                        elseif not t.r and node.r then
                            t.r = node.r
                        end
                    end
                end
            end
        end
    end
end

ns.On("NodesChanged", function() learned, seenNames = nil, nil end)

-- the type's key for a node, or nil when it can't be told
function Catalog.TypeOf(objectID, name, kind)
    if IsSecret(name) then name = nil end
    local lname = Normalize(name)
    local key = KnownType(objectID, lname, kind)
    if key or not lname or lname == "" then return key end
    if not learned then Scan() end
    key = "name:" .. lname
    if learned[key] then return key end
end

-- every type of a kind ("ore" / "herb"): the fixed ones and the learned ones, by level
function Catalog.All(kind)
    Scan()
    local list = {}
    for _, t in ipairs(Catalog.TYPES) do
        if t.k == kind then list[#list + 1] = t end
    end
    for _, t in pairs(learned) do
        if t.k == kind then list[#list + 1] = t end
    end
    local order = {}
    for i, t in ipairs(list) do order[t] = i end
    table.sort(list, function(a, b)
        if a.r ~= b.r then
            if a.r == nil then return false end
            if b.r == nil then return true end
            return a.r < b.r
        end
        if a.learned ~= b.learned then return not a.learned end
        if a.learned then return a.key < b.key end
        return order[a] < order[b]
    end)
    return list
end

-- the name shown for a type: the one the game gave it in your log, else the
-- Spanish one with the addon in Spanish, else the English one
function Catalog.NameOf(t)
    if t.n then return t.n end
    if not seenNames then Scan() end
    if seenNames[t.key] then return seenNames[t.key] end
    if ns.LOCALE == "esES" and t.es then return t.es end
    return t.en
end

function Catalog.Shown(objectID, name, kind)
    local hidden = ns.db and ns.db.catalog and ns.db.catalog.hidden
    if not hidden or next(hidden) == nil then return true end
    local key = Catalog.TypeOf(objectID, name, kind)
    return not (key and hidden[key])
end

-- for log entries (o, n, k) and database spots (o, en, k)
function Catalog.ShownNode(node)
    return Catalog.Shown(node.o, node.n or node.en, node.k)
end
