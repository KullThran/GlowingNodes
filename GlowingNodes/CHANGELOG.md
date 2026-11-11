# Glowing Nodes Changelog

## 1.2.0 (2026-11-11)
- Skinning zones on the Map page: purple areas where skinnable creatures roam, outlined the way the game marks a quest's area, each with the skinning it needs (its colour: how hard it is for you). Hover the label for the creatures' level and how many there are. They come from the 1.12 world database, so Forever may differ here and there. They show on the game's world map too. Off by default: the Skinning filter under the map (or on the filter button) shows them along with your hide areas. Labels that would cover each other are left out until you zoom in.
- Switch what the maps show from the map itself: a button on the Map page and one in the top right corner of the game's world map open the same little panel with ore veins, herbs and skinning (and, on the world map, its master switch).
- Works with Open Map. Its menu gets a Glowing Nodes section with the same switches (on the world map, ore, herbs, skinning), and our corner button stays away from its buttons. On its stitched map, the zones around the one you are looking at show too: their beads, hide areas and skinning zones, each in its place on the stitched world and above its art.
- The map zooms: mouse wheel over it (about the pointer) or the + and - buttons; drag to move a zoomed map.
- Back: the button (or a right-click on the map) goes to the map you saw before, or up to the continent. A continent shows a badge on every zone with points, names the zone under the pointer, and opens it with a click.
- Search box on the Map page: zones, nodes, creatures and drops. Results list the zones and where each match is logged; picking one opens its map with the matches standing out. A number (a skinning level) lights the skinning zones that need it.
- Fixed: a dark streak above the window's top left corner (and stray marks round the glow) came from specks left on the edges of the glow textures.

## 1.1.2 (2026-11-08)
- Chests glow too: treasure chests, lockboxes and other things you open in the world, in gold, with their own tab and alert. No level or number on them.
- New option, off by default: "Switch Find Herbs and Find Minerals". With both professions, the minimap tracks herbs and minerals by turns every 3 seconds while you move. Not in combat, towns or instances, never over another tracking you picked, and its sound is muted.
- When Mining or Herbalism goes up, the chat names the nodes you saw but couldn't gather yet that you now can: what, its level, how many and in which zones. It can be switched off on the Alert page.
- Fixed: in dungeons, where the game hides a node's name, identity and your position, a herb or vein picked from afar stayed "Level too low" with a "?" even once you stood at it. Its cursor is now read again as you walk up, so the glow turns to "in reach". The alert says "Name and level hidden here" instead of a blank name, and the glow shows no "?". Where the tooltip is readable, the name (and so the level) comes from it.
- Each node remembers what it dropped (ore, stones, gems, rare herbs): the map tooltip lists it, most often first, in the item's quality colour.
- New option, on by default: "Keep the Interact Key on the node". The game moves the Interact Key to whatever you have selected (the mob you just killed, an NPC), and the node next to you lost its glow; now the key stays on what's nearest. Switched off, or with the addon off, your own setting comes back.
- The window size ruler zooms the window as you drag it, about the mouse, so the ruler stays under it. Before, nothing changed until you let go, and then the window grew from its centre and ran off from under the mouse. The mouse wheel on the ruler also zooms about the mouse.
- Sliders fill up to the knob's centre, no longer past it.
- Fixed: a node first seen from far off left a "rough" point beside the real one on the map. The game picks nodes up to about 40 yards away, and the rough spot only merged within 25; it now merges from 45.
- Fixed: one vein mined in several pulls counted as several gathers. Pulls of the same vein within a minute are one gather.
- The maps are no longer redrawn every time the Interact Key comes back to a node it just held; only when a point is added, moves or counts up.
- A node is only placed exactly on the map when the game says you're in reach of it.
- Fixed: "Requires Skinning 105" learned on one mob made every mob of that name show that level. A corpse's level now follows its own mob level.
- Minimap points follow you into caves and towns with a map of their own, not only into a new zone.
- The Map page says your filters hide the points, instead of "Nothing gathered here yet", when they do.
- The texts now give the real reach (about 40 yards, not 15 or 20), and the help and About page list /gn range and /gn debug.
- The warning about other addons that use the same nameplate is gone: Glowing Nodes works on its own whatever else is installed.
- Steadier with targets whose identity the game keeps secret, and with secret error messages.
- Fixed: a node found from afar could say "Level too low" (and glow grey) even with your level well above what it needs, such as a level 1 Silverleaf at Herbalism 68. The game greys its cursor on a node out of reach too, and that was taken for "too low". A node's known level now decides, and the cursor is read again as you walk up to it.

## 1.1.1 (2026-11-07)
- Fixed: the glow could jump and flash wildly, worse the longer you played. Its pulse and turning ring leapt whenever it changed between out of reach, in reach and too low a level; they now move smoothly.
- Fixed: standing at the edge of a node's reach, the glow flared over and over as the game kept changing its mind. A change now shows once it holds for a moment.

## 1.1.0 (2026-11-07)
- Gathering map: every node you mine, pick or skin is logged on the zone's map, like GatherMate2. A node gathered again counts up instead of adding a point.
- Nodes are logged as soon as the glow finds them, even if you walk past: first roughly, where you stood, then on the spot once you're in reach of it. Their tooltip says "Seen, not gathered yet" and the level needed.
- Points in each kind's colour on the world map and the minimap, with a tooltip (name, times gathered, last time).
- Hides are areas, not points: mobs wander, so skinning marks a purple area (60 yards round) where skinnable creatures roam. Skinning inside it adds to it and moves it towards where you skin; its tooltip lists the creatures skinned there.
- New Map page in the options: the zone's map with your points, your position, filters per kind, the latest gathers, and buttons to clear a zone or the whole log. /gn map opens it.
- Window size, as in KullThranUI: zoom the options window from 50 % to 150 % with the ruler under the tabs, the mouse wheel, a typed percentage, or Ctrl + mouse wheel over the window.
- Language selector on the window's cover: any of the ten languages, whatever your client's.
- New look for the options window, in the alert card's materials: brown pebbled leather with a cream running stitch, bronze corner caps, the title on a bronze-rimmed chevron plate, a darker sunk page, leather plaques for tabs and buttons, dark wells in bronze rims for the controls, gems for colours. Much more contrast: cream text, warm gold headings.
- The window is 38 % bigger at 100 %.
- The glow previews show the node itself in 3D, turning slowly under its glow: a Tin vein, a Bruiseweed bush, a dead Timber Wolf. The Alert page's sample uses what you gather (Tin Ore, Bruiseweed, Light Leather) instead of the professions' icons, with the herb's real name.
- Map page: the zone's map fills the page; the latest gathers and the map options open as panels over it.
- The glow keeps its full size, column of light included, on a node the game picks far off (up to about 40 yards, the game's own limit), whatever the game does with the nameplate's scale; only its drop to the ground follows perspective.
- The glow finds the node's nameplate among all the game's nameplates when the game doesn't hand it over by name.
- Far off, the game can drop a node and pick it again a moment later: the glow now comes straight back, without fading in from nothing each time.
- Fixed: the glow could stay off on a node the game had already picked (its outline showing) when something else, another addon or the game's options, closed the nameplate setting the glow needs. The setting is now read as it really is, not as last left.
- Fixed: "You're doing that too fast" every little while. The nameplate switch the glow needs is a setting the game keeps on the server; it is now written at most once a second and stays on a moment after the glow goes, instead of flipping as the Interact Key hops between mobs, corpses and nodes.
- Fixed: a "Lua Taint: GlowingNodes" error repeating near corpses. Corpses are read with the game's tooltip data only, never through a hidden tooltip.

## 1.0.1 (2026-11-06)
- First release for WoW Forever.
- Ore veins, herbs and skinnable corpses glow in the world, in a colour of your choice for each kind, with the profession level they need on top.
- A soft sound for each kind and a RareScanner-style alert card with the node's icon, name and level.
- Options window (/gn): colours, intensity, size, pulse, light pillar, sounds, alert, and a live preview.
- Learns the level of nodes it doesn't know yet from the game's own messages.
- Nine languages: English, Spanish, German, French, Italian, Portuguese, Russian, Korean and Chinese.
