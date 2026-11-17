# No Man's Drive — required features

Every user requirement for this project, kept up to date. Items marked ✅ are in the current build. Items marked 🔄 are in progress for the next version.

## User requests (verbatim intent)

- Build the full game in `requiredtruth/no-mans-drive-game`. Posting directly to `main` is approved.
- Publish a GitHub **release with an installable Android APK** for each version. **Post a release of the current version before starting the next one.**
- A very high quality game in the style of the RV road-trip survival genre (the user referenced *Nomad Drive*). It must be an **original game** with its own name, art, world and content, but include **every kind of feature that genre offers**.
- High-resolution visuals. Use free online textures, shaders and models where possible, and record their licenses.
- **Wandering wildlife the player can hunt.**
- **Make a camp with a campfire.**
- **Build full houses.**
- **All items need real 3D models and textures ("models and textures galore").** The nature already looks good, and everything else (items, tools, weapons, RV, buildings, furniture, animals, props) must match that quality. 🔄
- Save all user requirements to this file.

### Feedback on 1.0 (all addressed in 1.1)

- ✅ No rain inside buildings or the RV.
- ✅ No grass growing through floors of buildings or placed foundations.
- ✅ Less "squares everything": bevelled, rounded edges on all built geometry, and real 3D models for items.
- ✅ The build dialog must be easy to dismiss: build mode is a toggle (B / BUILD), and tapping outside any dialog closes it.
- ✅ Don't start with a fully equipped RV: you start with a rundown RV and a pocket knife, flashlight and a few supplies.
- ✅ A cheat / testing menu (Pause → Cheats / testing).
- ✅ Physically pick up and place objects: loot drops as items you pick up, loose sticks and stones lie on the ground, items can be dropped, and placed objects (crates, campfires, beds, chairs, tables…) can be picked back up (G / GRAB) and moved.
- ✅ Build on the RV: place furniture inside or on the roof; loose items left in the RV ride along.
- ✅ Easier driving: stronger engine, quicker steering, stability assist, auto-righting, a third-person camera by default, and GAS/REV pedals on touch.
- ✅ More natural world generation: groves and clearings, single-species stands, larger and gentler biomes, no trees on cliffs, grass in natural patches.

### Requests after 1.1

- 🔄 Finish **all visuals** before a version release: high-res models and textures that match the nature quality on every item, vehicle, building and animal. Regular releases are fine along the way.
- ✅ **Multiple vehicle types and modularity**: a motorhome, pickup truck, sedan, box truck and off-roader, plus hitchable trailers (walk-in camper, flatbed, fuel tanker). Every vehicle has repairable parts, upgrades, paint, cargo that rides along, and furniture you can place on trailers.
- ✅ **Random houses along the road**: procedurally generated cottages, brick and log houses, cabins, hamlets and truck stops, with furnished interiors.
- ✅ **Varied ambience**: no looping birdsong. Dozens of randomized bird, owl, crow, woodpecker, frog, coyote, wind and thunder one-shots, chosen by biome and time, with dawn/dusk choruses and call-and-answer.
- Quality and detail bar: Nomad Drive, plus all of our extra additions.

### Requests after 1.2 (addressed in 1.3)

- ✅ **Physical items, Nomad Drive style. No boxed inventory.** Pick up each individual item. You can carry only a few (two hands, plus two backpack slots). Place items in exact spots with a preview and rotation, and placed items stay glued in place in the RV and every vehicle while driving.
- ✅ **Open boxes to find items inside** them (cardboard boxes, open-top crates, RV fridge and cupboards with doors and shelves). Clicking an item never sends it to an inventory screen.
- ✅ **Replace parts by hand**: pull out the worn battery or tire, carry the new one over and fit it. Engine parts and scrap go in at the hood.
- ✅ **Items easier to see**: small items are drawn larger in the world, and the targeted item is highlighted with its name shown.
- ✅ **Truck cabs are real interiors** (headliner, door panels, pillars, dash gauges), not just windows.
- ✅ **The RV interior should not look like wood**: wall board, vinyl floor, laminate cabinets, fabric seats.
- Keep imitating Nomad Drive as closely as possible, plus our added features. Sound and driving are approved as-is.

### Requests after 1.3 (addressed in 1.4)

- ✅ **Assemble the whole vehicle from the start, Nomad Drive style.** Start with a very broken, unassembled van, not an RV. The doors, seats, radio, engine, steering wheel, wheels and battery all have to be fitted by hand. The interior starts empty: bed, fridge, kitchen and the rest are fitted manually.
- ✅ **More items, modules and textures**: 28 fittable van modules, new materials (wire, bolts, pipe, foam, glass), empty bottles and fuel cans, spray paint, and six new textures.
- ✅ **Avoid little crafting menus.** Crafting happens on a workbench: lay the items on it and put them together. Cooking happens on a campfire grill or the van stove. Drinking, refilling, refuelling and fitting parts are all done with items in your hands. The old crafting, cooking, sink and RV workshop menus are gone. Tab is now a read-only notebook.
- Posting directly to `main` and publishing a new APK release are approved.

### Requests after 1.4 (addressed in 1.5)

- ✅ **No "walk into a room with E".** Get into the van by walking in through the doorway, as in Nomad Drive. With no door fitted the doorway is open; a fitted sliding door opens and closes with E. The camper trailer works the same way. No teleporting in or out.
- ✅ **You can see into and out of the vehicle**: every window and the doorway are real openings with see-through glass.
- ✅ **The van must look as real as possible**, with the same feel as Nomad Drive: real body details, lights, bumpers, trim, chassis and underside.
- Posting directly to `main` and publishing a new APK release are approved.

## Core RV road-trip features

- ✅ Drivable motorhome with physics (throttle, brake/reverse, steering, handbrake), first- and third-person cameras, headlights, engine sound.
- ✅ Walk-in RV interior: driver and passenger seats, kitchen counter with stove and sink, coffee maker, fridge, storage cabinet, dinette, bathroom with toilet, rear bed, interior lights, plant pots.
- ✅ RV parts that wear and break (engine, tires, battery, body), repairs with parts and a toolkit, fuel and water tanks, battery charging, crash damage.
- ✅ RV upgrades (engine tune, off-road tires, extended tank, solar panel, bull bar, heater, large water tank) and paint jobs.
- ✅ Endless procedurally generated world with a winding highway, distinct biomes (forest, grassland, desert, snowy tundra), lakes, mountains and climates.
- ✅ Abandoned roadside locations with loot: gas stations with working pumps, houses, farms with wells, car wrecks and camp ruins.
- ✅ Survival needs: health, food, water, energy and warmth (temperature by biome, time, weather, shelter, fire, jacket).
- ✅ Gathering (wood, stone, fiber, berries, mushrooms, scrap), crafting, workbench recipes, cooking at campfires and the RV stove, coffee brewing, boiling water.
- ✅ Fishing in lakes with a bite-and-reel minigame.
- ✅ Gardening: plant tomato, potato and coffee seeds in planters or the RV pots, water them, and harvest crops and seeds.
- ✅ Day and night cycle, dynamic sky with clouds, stars, sun and moon, weather (clear, cloudy, rain, snow, lightning).
- ✅ Online co-op for up to 4 players (direct IP / LAN): shared world, structures, loot, RV driving and time/weather sync.
- ✅ Save any time, autosave, continue from the main menu.
- ✅ Difficulty levels (Relaxed, Normal, Hard), settings for audio buses (master, effects, ambience, vehicle, UI), sensitivity, FOV, invert Y, head bob, view distance, shadows, grass, render scale.
- ✅ Keyboard and mouse, game controller, and Android touch controls (joystick, drag-look, action buttons, tappable hotbar).

## Added gameplay

- ✅ Wildlife with biome-appropriate behavior: deer, rabbits, boar, turkeys, foxes (flee), wolves in packs and bears (attack), sneaking, gunshots that scare animals.
- ✅ Hunting with knife, bow (ballistic arrows) and rifle (scope zoom). Butcher carcasses for meat, hide and feathers.
- ✅ Camps: campfire (light, heat, cooking, burns wood, rain wears it down), tent and bed (sleep, set respawn, save), storage crates, rain collectors, lantern posts, workbench.
- ✅ Full houses: foundations, floors and ceilings, walls, door walls with opening doors, window walls, flat and sloped roofs, stairs and fences, all with a grid-snapped placement preview, rotation, resource costs, 50% refunds on demolish, and shelter warmth.

## Quality pass (1.1)

- ✅ Detailed 3D models with PBR textures for every item and tool: hatchet, pickaxe, knife, hammer, bow, arrows, rifle, fishing rod, flashlight, food, cans, bottles, fuel cans, parts, seeds.
- ✅ First-person hands and held-item models.
- ✅ Higher-detail RV: a smooth Class-C shell with over-cab nose, wheel arches, inset windows, decals, trim and real tires.
- ✅ Log-cabin walls, shingle roofs, stone foundations, and window and door trim.
- ✅ Better animal models: smooth lofted bodies with jointed legs and fur textures (more detail and animation still welcome).
- ✅ Rendered 3D item icons in the inventory and hotbar.

## Release acceptance

- Use original or properly licensed assets, and record their attribution (see the in-game Credits and `ASSETS.md`).
- Verify gameplay, save/load and controls with the automated tour (`game/scripts/devtest.gd`). Verify on Android. Test co-op with multiple clients.
- Tag each version on `main` and publish a GitHub release with the signed APK.
