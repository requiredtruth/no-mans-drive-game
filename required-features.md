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

## Next version (1.1) — quality pass 🔄

- Detailed 3D models with PBR textures for every item and tool: hatchet, pickaxe, knife, hammer, bow, arrows, rifle, fishing rod, flashlight, food, cans, bottles, fuel cans, parts, seeds.
- First-person hands and held-item models with animations.
- Higher-detail RV (rounded shell, trim, decals, detailed interior props).
- Detailed buildings and furniture, with textured logs for walls and shingles for roofs.
- Better animal models (fur shading, proper anatomy, animations).
- Rendered item icons in the inventory instead of text tiles.

## Release acceptance

- Use original or properly licensed assets, and record their attribution (see the in-game Credits and `ASSETS.md`).
- Verify gameplay, save/load and controls with the automated tour (`game/scripts/devtest.gd`). Verify on Android. Test co-op with multiple clients.
- Tag each version on `main` and publish a GitHub release with the signed APK.
