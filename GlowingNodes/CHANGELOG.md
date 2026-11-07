# Glowing Nodes Changelog

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
