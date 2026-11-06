-- NodeData.lua
-- Profession level each gathering node needs. Looked up by the object's ID
-- (from its GUID, the same in every language), then by its name in English or
-- Spanish (the Spanish names are the client's own, Forever 1.60.1 included).
-- Anything missing here is learned in game: see Skills.lua.
local _, ns = ...

local Data = {}
ns.NodeData = Data

-- objectID -> required level
Data.oreIDs = {
    [1731] = 1, [2055] = 1, [3763] = 1, [103713] = 1, [181248] = 1,               -- Copper
    [1732] = 65, [2054] = 65, [3764] = 65, [103711] = 65, [181249] = 65,          -- Tin
    [1610] = 65, [1667] = 65,                                                     -- Incendicite
    [1733] = 75, [105569] = 75, [73940] = 75,                                     -- Silver
    [2653] = 75,                                                                  -- Lesser Bloodstone
    [1735] = 125, [73939] = 125,                                                  -- Iron
    [19903] = 150,                                                                -- Indurium
    [1734] = 155, [150080] = 155, [181109] = 155, [73941] = 155,                  -- Gold
    [2040] = 175, [150079] = 175, [176645] = 175, [123310] = 175,                 -- Mithril
    [2047] = 230, [150081] = 230, [181108] = 230, [123309] = 230,                 -- Truesilver
    [165658] = 230,                                                               -- Dark Iron
    [324] = 245, [150082] = 245, [176643] = 245, [123848] = 245,                  -- Small Thorium
    [180215] = 250,                                                               -- Hakkari Thorium
    [175404] = 275, [177388] = 275,                                               -- Rich Thorium
}

Data.herbIDs = {
    [1617] = 1, [3725] = 1, [657380] = 1,                                         -- Silverleaf
    [1618] = 1, [3724] = 1, [657382] = 1,                                         -- Peacebloom
    [1619] = 15, [3726] = 15,                                                     -- Earthroot
    [1620] = 50, [3727] = 50,                                                     -- Mageroyal
    [1621] = 70, [3729] = 70,                                                     -- Briarthorn
    [2045] = 85,                                                                  -- Stranglekelp
    [1622] = 100, [3730] = 100,                                                   -- Bruiseweed
    [1623] = 115,                                                                 -- Wild Steelbloom
    [1628] = 120,                                                                 -- Grave Moss
    [1624] = 125,                                                                 -- Kingsblood
    [2041] = 150,                                                                 -- Liferoot
    [2042] = 160,                                                                 -- Fadeleaf
    [2046] = 170,                                                                 -- Goldthorn
    [2043] = 185,                                                                 -- Khadgar's Whisker
    [2044] = 195,                                                                 -- Wintersbite
    [2866] = 205,                                                                 -- Firebloom
    [142140] = 210, [180165] = 210,                                               -- Purple Lotus
    [142141] = 220, [176642] = 220,                                               -- Arthas' Tears
    [142142] = 230, [176636] = 230, [180164] = 230,                               -- Sungrass
    [142143] = 235,                                                               -- Blindweed
    [142144] = 245,                                                               -- Ghost Mushroom
    [142145] = 250, [176637] = 250,                                               -- Gromsblood
    [176583] = 260, [176638] = 260, [180167] = 260,                               -- Golden Sansam
    [176584] = 270, [176639] = 270, [180168] = 270,                               -- Dreamfoil
    [176586] = 280, [176640] = 280, [180166] = 280,                               -- Mountain Silversage
    [176587] = 285, [176641] = 285,                                               -- Plaguebloom
    [176588] = 290,                                                               -- Icecap
    [176589] = 300,                                                               -- Black Lotus
}

-- Exact herb names (lower case) -> level
Data.herbNames = {
    ["silverleaf"] = 1, ["hojaplata"] = 1,
    ["peacebloom"] = 1, ["flor de paz"] = 1,
    ["earthroot"] = 15, ["raíz de tierra"] = 15,
    ["mageroyal"] = 50, ["marregal"] = 50,
    ["briarthorn"] = 70, ["brezospina"] = 70,
    ["stranglekelp"] = 85, ["alga estranguladora"] = 85,
    ["bruiseweed"] = 100, ["hierba cardenal"] = 100,
    ["wild steelbloom"] = 115, ["acérita salvaje"] = 115,
    ["grave moss"] = 120, ["musgo de tumba"] = 120,
    ["kingsblood"] = 125, ["sangrerregia"] = 125,
    ["liferoot"] = 150, ["vidarraíz"] = 150,
    ["fadeleaf"] = 160, ["pálida"] = 160,
    ["goldthorn"] = 170, ["espina de oro"] = 170,
    ["khadgar's whisker"] = 185, ["vibrisa de khadgar"] = 185,
    ["wintersbite"] = 195, ["ivernalia"] = 195,
    ["firebloom"] = 205, ["flor de fuego"] = 205,
    ["purple lotus"] = 210, ["loto cárdeno"] = 210,
    ["arthas' tears"] = 220, ["lágrimas de arthas"] = 220,
    ["sungrass"] = 230, ["solea"] = 230,
    ["blindweed"] = 235, ["carolina"] = 235,
    ["ghost mushroom"] = 245, ["champiñón fantasma"] = 245,
    ["gromsblood"] = 250, ["gromsanguina"] = 250,
    ["golden sansam"] = 260, ["sansam dorado"] = 260,
    ["dreamfoil"] = 270, ["hojasueño"] = 270,
    ["mountain silversage"] = 280, ["salviargenta de montaña"] = 280,
    ["plaguebloom"] = 285, ["flor de peste"] = 285,
    ["icecap"] = 290, ["setelo"] = 290,
    ["black lotus"] = 300, ["loto negro"] = 300,
}

-- Ore names: searched in order, first match wins ("veraplata" before "plata",
-- "hierro negro" before "hierro"). Ooze-covered variants contain the metal.
Data.orePatterns = {
    { "dark iron", 230 }, { "hierro negro", 230 },
    { "truesilver", 230 }, { "veraplata", 230 },
    { "rich thorium", 275 }, { "torio enriquecido", 275 },
    { "hakkari thorium", 250 }, { "torio de hakkari", 250 },
    { "thorium", 245 }, { "torio", 245 },
    { "mithril", 175 }, { "mitril", 175 },
    { "indurium", 150 }, { "indurio", 150 },
    { "gold vein", 155 }, { "filón de oro", 155 }, { "filon de oro", 155 }, { "oro cubierto", 155 },
    { "iron deposit", 125 }, { "hierro", 125 },
    { "lesser bloodstone", 75 }, { "petrosangre", 75 },
    { "silver vein", 75 }, { "plata", 75 },
    { "incendicite", 65 }, { "incendicita", 65 },
    { "tin vein", 65 }, { "estaño", 65 },
    { "copper vein", 1 }, { "cobre", 1 },
}

-- Words that only an ore node's name has, to classify a node when the cursor
-- can't be read.
Data.oreWords = { "vein", "deposit", "filón", "filon", "depósito", "deposito" }

function Data.NormalizeName(name)
    if type(name) ~= "string" then return nil end
    name = name:lower():gsub("\194\160", " "):gsub("\226\128\153", "'")
    return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- category, level for a node known by ID or name; nil when unknown
function Data.Lookup(objectID, name, category)
    if objectID then
        if category ~= "herb" and Data.oreIDs[objectID] then
            return "ore", Data.oreIDs[objectID]
        end
        if category ~= "ore" and Data.herbIDs[objectID] then
            return "herb", Data.herbIDs[objectID]
        end
    end
    local lname = Data.NormalizeName(name)
    if not lname then return nil end
    if category ~= "ore" and Data.herbNames[lname] then
        return "herb", Data.herbNames[lname]
    end
    if category ~= "herb" then
        local isOre = category == "ore"
        if not isOre then
            for _, word in ipairs(Data.oreWords) do
                if lname:find(word, 1, true) then isOre = true break end
            end
        end
        if isOre then
            for _, entry in ipairs(Data.orePatterns) do
                if lname:find(entry[1], 1, true) then
                    return "ore", entry[2]
                end
            end
            return "ore", nil
        end
    end
    return nil
end

-- What the node gives, for the alert's icon: item IDs by required level
-- (a few levels are shared and told apart by name).
local ORE_ITEMS = {
    [1] = 2770, [65] = 2771, [75] = 2775, [125] = 2772, [150] = 5833, [155] = 2776,
    [175] = 3858, [230] = 7911, [245] = 10620, [250] = 10620, [275] = 10620,
}
local HERB_ITEMS = {
    [1] = 2447, [15] = 2449, [50] = 785, [70] = 2450, [85] = 3820, [100] = 2453, [115] = 3355,
    [120] = 3369, [125] = 3356, [150] = 3357, [160] = 3818, [170] = 3821, [185] = 3358,
    [195] = 3819, [205] = 4625, [210] = 8831, [220] = 8836, [230] = 8838, [235] = 8839,
    [245] = 8845, [250] = 8846, [260] = 13464, [270] = 13463, [280] = 13465, [285] = 13466,
    [290] = 13467, [300] = 13468,
}
local NAME_ITEMS = {
    { "incendicit", 3340 }, { "bloodstone", 4278 }, { "petrosangre", 4278 },
    { "dark iron", 11370 }, { "hierro negro", 11370 },
    { "silverleaf", 765 }, { "hojaplata", 765 },
}
Data.CATEGORY_ICONS = {
    ore = "Interface\\Icons\\Trade_Mining",
    herb = "Interface\\Icons\\Trade_Herbalism",
    skin = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
}

local function ItemIcon(itemID)
    if not itemID then return nil end
    local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if not get then return nil end
    local ok, icon = pcall(get, itemID)
    if ok and icon then return icon end
end

function Data.IconFor(category, required, name)
    local item
    local lname = Data.NormalizeName(name)
    if lname and category ~= "skin" then
        for _, entry in ipairs(NAME_ITEMS) do
            if lname:find(entry[1], 1, true) then item = entry[2] break end
        end
    end
    if not item and required then
        if category == "ore" then item = ORE_ITEMS[required]
        elseif category == "herb" then item = HERB_ITEMS[required] end
    end
    return ItemIcon(item) or Data.CATEGORY_ICONS[category] or Data.CATEGORY_ICONS.ore
end

-- Skinning: what the classic formula asks for a corpse of that level.
function Data.SkinningLevel(level)
    if type(level) ~= "number" or level < 1 then return nil end
    if level <= 10 then return 1 end
    if level <= 20 then return (level - 10) * 10 end
    return level * 5
end

-- Gathering difficulty colour, like the game's: red can't, orange always a
-- skill-up, yellow often, green rarely, grey never.
function Data.DifficultyColor(required, skill)
    if not required then return 1, 0.82, 0 end
    if not skill or skill < required then return 1, 0.15, 0.12 end
    if skill < required + 25 then return 1, 0.5, 0.1 end
    if skill < required + 50 then return 1, 1, 0 end
    if skill < required + 100 then return 0.25, 1, 0.25 end
    return 0.6, 0.6, 0.6
end
