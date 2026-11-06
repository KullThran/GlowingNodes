-- Sounds.lua
-- Short cues, one per node kind by default (anvil for ore, leaves for herbs,
-- a drum for hides), synthesised by tools/sounds/make_sounds.py at three
-- volumes each.
local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

Sounds.LIST = { "none", "ore_ping", "herb_chime", "skin_thump", "crystal", "drop", "bell" }
Sounds.CHANNELS = { "Master", "SFX", "Ambience", "Dialog" }
Sounds.VOLUMES = { 1, 2, 3 }

local DIR = ns.MEDIA .. "Sounds\\"
local COOLDOWN = 0.6
local last = 0

function Sounds.Play(key, volume, channel, force)
    if not key or key == "none" then return end
    local now = GetTime()
    if not force and now - last < COOLDOWN then return end
    last = now
    local file = DIR .. key .. "_" .. (tonumber(volume) or 2) .. ".ogg"
    pcall(PlaySoundFile, file, channel or (ns.db and ns.db.channel) or "SFX")
end

function Sounds.PlayCategory(category, force)
    local cfg = ns.db and ns.db[category]
    if not cfg or (not force and not cfg.soundOn) then return end
    Sounds.Play(cfg.sound, cfg.volume, ns.db.channel, force)
end
