# Done

Everything finished and in the game, newest first. Work in progress lives in `todo.md`. When something is finished, it moves from `todo.md` to here.

## Version 1.11.0: silent nights, sleep at 05:00 and first-person sitting

- [x] No nighttime cricket loop; wind, weather and non-cricket animal ambience remain.
- [x] Night sleep on beds, tents, bedrolls and van bunks immediately advances to 05:00 with correct day rollover; daytime naps still advance three hours.
- [x] Chairs, sofas and folding camp chairs physically seat the first-person player with seated eye height, free camera look, continuous energy recovery, standing via E/Jump, and return to the original entry point even if furniture moves.
- [x] Automated quality assertions and a seated-view screenshot gate the new APK.

## Version 1.10.0: roadside details and saved journey

- [x] Nine deterministic roadside destinations, visited in order, with saved progress, distance/bearing, a top-right card and a notebook route list. Existing saves begin with an unstarted journey.
- [x] White aim outlines and names for van cupboard/fridge doors, cargo lids, and placed furniture; outline clears on target change.
- [x] Sixteen original printed food/drink/water/spray labels, paper normal map, and rolled lid ridges/pull rings on cans.
- [x] Slatted wooden storage crate with gaps, corner posts and fasteners; retaining collision walls preserve its storage behavior.
- [x] Checked temporary save replacement, previous-valid-save backup, and recovery if the main save is damaged.
- [x] Automated route progression, save recovery and interaction tests in `--v110`, plus a rendered screenshot tour. Publication is gated by these and the existing `--v18` regression tour.

## Version 1.9.0: interaction and cab detail

- [x] Loose items show a white outline and a name with stack count at the crosshair.
- [x] Key-first interaction prompts appear as individual right-side action rows with touchscreen button names where available.
- [x] Van dashboard, door cards and console have textured trim, with textured laminate wall panels and fabric headliner.

## Version 1.8.0: van performance parts and body add-ons

### Performance parts (fitted at the open hood with a toolkit nearby; [G] with empty hands takes them out again, last one first)
- [x] Tier 2 high-compression engine and tier 3 supercharged V8 fit the engine bay in place of the stock block: more power and top speed, more fuel and heat.
- [x] Turbocharger (+25% power, +8% top speed, more heat) and supercharger (strong low-speed pull, a bit more fuel).
- [x] Nitrous kit: hold Shift (NOS on touch) while accelerating for a big boost; the bottle refills slowly when not in use.
- [x] Engine heat and coolant: the engine warms toward a temperature set by load against cooling. Above 100°C it wears; at 118°C it seizes and won't restart until it cools. Coolant boils off when hot and drains in crashes; top it up at the hood with Engine Coolant (+50%) or a Coolant Jug (+100%).
- [x] Radiators: stock, dual-fan (best cooling) and armored (good cooling, never leaks in a crash, halves crash damage to the engine).
- [x] Alternator (battery charges 3× faster while driving) and starter motor (no more sputtering starts, uses less battery).
- [x] Suspension: independent kit (stiffer, less body roll, +8% grip) or heavy-duty leaf springs (more ground clearance and load).
- [x] Lithium deep-cycle battery for the battery tray: lights drain it half as fast, solar charges it faster, and it comes out as good as it went in.
- [x] Sand dune tires (much more grip off the road) and solid puncture-proof tires (never wear, a little less grip), fitted wheel by wheel like the off-road tire.

### Body add-ons (fitted on the outside of the van)
- [x] Roof rack over the front of the roof; on it a lockable roof cargo box (things inside ride along), a roof tent you can sleep in, and a spare tire mount that holds any tire.
- [x] Side panniers: a lidded storage box on each flank.
- [x] Jerry can holder: +40 L fuel range.
- [x] Snorkel: driving into deep water drowns the engine (-15%) unless a snorkel keeps the intake above it.
- [x] Winch on the front bumper: hauls a ditched or flipped van back toward the road (uses battery).
- [x] Steel ram plow (-50% crash damage), door armor plates (-30%), windshield mesh (halves crash injuries).
- [x] Mud flaps (30% less tire wear off the road), underglow neon (lights up under the van with the headlights).
- [x] Tow hitch: the van needs one to tow trailers. Vans from older saves keep theirs.
- [x] Cars take the turbo and the ram plow at the hood too.

## Version 1.7.2

- [x] Starting steering wheel lies on top of the tires next to the van.
- [x] No trees, bushes, rocks, sticks or grass where the test items are laid out.

## Version 1.7.1: playtest fixes

- [x] Steering wheel raised into the driver's view; driving readout moved to the top of the screen.
- [x] Van barn doors open and close (E) and you can walk in at the back; two rear steps; ladder on the right door.
- [x] Climb onto vehicles, trailers, crates and walls with Jump (up to 3.7 m).
- [x] House roofs no longer upside down.
- [x] Bookshelf moved away from the front door.
- [x] House furniture (sofa, armchair, rug, table, chairs) is movable and stays where you put it.
- [x] Sharper, smoother shadows (bigger shadow maps, 4 cascades, soft filtering).
- [x] Sedan, pickup truck and box truck parked at the start.
- [x] Test depot: every item laid out at the start of a new game (and on the cheats menu).
- [x] No red placement ghost on walls.

## Version 1.7.0: item backlog batch 1

### Gameplay systems added for the new items
- [x] Wearables have body slots (body, head, back, wrist). Putting something on swaps out what was in that slot. Warmth adds up across everything you wear.
- [x] Backpacks of different sizes: burlap bag +1, rucksacks +2, hiking pack +3, military pack +4, expedition pack +5 hand slots.
- [x] Armor: helmet, leather vest and work clothes reduce damage from animals.
- [x] Rain poncho keeps you warmer in the rain.
- [x] Watches: without one the HUD only shows the rough time of day ("Morning", "Dusk"). New games start with a wristwatch. The survival watch also shows altitude.
- [x] Guns use their own ammunition (9mm, .25 ACP, .44, 12 gauge, rifle rounds). The shotgun fires a spread of pellets. Each gun has its own rate of fire and zoom.
- [x] Melee tools are defined by their data: anything with `chop` fells trees, anything with `mine` breaks rock, and stronger tools need fewer swings (fire axe and saw: 2 swings).
- [x] Any knife or machete can butcher. A multi-tool counts as a toolkit. Any hammer can open the build menu.
- [x] Hand-held lights: torch and road flare (flickering, with flames), chemical light stick, folding camp lantern. The tactical headlamp works like the flashlight with your hands free (F).
- [x] Pocket compass (bearing and distance to the van), paper roadmap (the next stops along the highway), retro GPS (nearest fuel), hand-crank radio (plays music anywhere).
- [x] Water purification tablets turn up to 3 bottles of dirty water into clean water.
- [x] Camp cooking gear: a cast iron skillet, pot or percolator on the fire or stove makes everything on the heat cook up to twice as fast.
- [x] Thermos: cook it with hot coffee to make a thermos of coffee that keeps you warm.
- [x] Campfires burn hardwood, charcoal, sticks, driftwood and old magazines, not only logs. Hardwood and charcoal burn longest.
- [x] Smelting on the fire: wood into charcoal, copper ore and lead ore into ingots, animal fat into grease.
- [x] Rocks give ore when broken: copper, lead, sulphur (more in the desert), saltpeter, sometimes obsidian.
- [x] Trees drop sticks, seasoned hardwood (dead trees especially) and sometimes raw rubber.
- [x] Driftwood washes up on lake shores. Fallen sticks and loose rocks lie in the woods.
- [x] Berry bushes grow red, yellow or purple berries, and very rarely a golden mystic berry.
- [x] Each animal now gives its own meat and byproducts: venison, sinew, bones and antlers from deer; pelts, claws, sinew and skulls from wolves; fat and claws from bears; bird meat from turkeys.
- [x] Planters grow any seed, including the new carrots and corn.
- [x] Cab decor hangs from the van ceiling: aim at the ceiling with a hanging piece and place it. Hanging decor sways as the van drives.
- [x] Salvage and junk break down at the workbench into scrap, wire, glass, bolts, microchips and more.
- [x] Over 80 new workbench recipes (leatherwork, backpacks, clothing, stone tools, ammunition, gunpowder, camp gear, electronics, junk recycling).

### New furniture
- [x] Five rugs with their own high-resolution patterns (Persian, braided, Japanese wave, cowhide, woven).
- [x] Folding camp chair, canvas bedroll (sleep on it), shade tarp (keeps the rain off), retro TV (switch on, flickering screen), LED clock (shows the time), weather station (temperature, conditions, spinning anemometer), cassette travel case (plays a tape on the van radio).

### Backlog items now in the game
Each has its own 3D model, an entry in `data.gd`, and a place in loot, a recipe or a world drop. Items already in the game under an older id are marked with →.

### Raw Resources and Minerals

- [x] wood (`wood`)
- [x] seasoned hardwood (`seasoned_hardwood`)
- [x] drift wood (`drift_wood`)
- [x] resource scrap metal (`resource_scrap_metal`) → in game as `scrap`
- [x] copper ore (`copper_ore`)
- [x] copper ingot (`copper_ingot`)
- [x] lead ore (`lead_ore`)
- [x] lead ingot (`lead_ingot`)
- [x] raw rubber (`raw_rubber`)
- [x] cured rubber sheet (`cured_rubber_sheet`)
- [x] glass pane / shard (`glass_shard`) → in game as `glass`
- [x] stone (`stone`)
- [x] obsidian chunk (`obsidian_chunk`)
- [x] charcoal (`charcoal`)
- [x] sulphur (`sulphur`)
- [x] sulphur ore (`sulphur_ore`)
- [x] saltpeter (`saltpeter`)
- [x] gunpowder (`gunpowder`)
- [x] cloth (`cloth`)
- [x] heavy canvas (`heavy_canvas`)
- [x] leather hide (`leather_hide`) → in game as `hide`
- [x] cured leather (`cured_leather`)
- [x] animal fat (`animal_fat`)
- [x] sinew / tendon (`sinew`)
- [x] bone fragments (`bone_fragments`)
- [x] carrot seeds (`carrot_seeds`)
- [x] potato seeds (`potato_seeds`) → in game as `seeds_potato`
- [x] tomato seeds (`tomato_seeds`) → in game as `seeds_tomato`
- [x] corn seeds (`corn_seeds`)
- [x] empty bottle (`empty_bottle`) → in game as `bottle_empty`
- [x] empty glass jar (`empty_glass_jar`)

### Chemistry and Fluid Synthesis (Coolants, Acids, Fuels)

- [x] industrial solvent (`industrial_solvent`)
- [x] crude oil (`crude_oil`)
- [x] high-performance engine coolant - tier 1 (`coolant_t1`)
- [x] brake fluid (`brake_fluid`)
- [x] water purification tablets (`water_purification_tablets`)

### Survival Consumables, Agriculture and Cooking

- [x] purified water (`purified_water`) → in game as `water_clean`
- [x] river water (`river_water`) → in game as `water_dirty`
- [x] stagnant swamp water (`stagnant_water`) → in game as `water_dirty`
- [x] crimson chaos energy (`crimson_chaos_energy`)
- [x] mocha cola (`mocha_cola`)
- [x] digital soda (`digital_soda`)
- [x] matrix cola (`matrix_cola`)
- [x] zap power juice (`zap_power_juice`)
- [x] berry juice (`berry_juice`)
- [x] sterling organic milk (`sterling_organic_milk`)
- [x] spoiled milk (`spoiled_milk`)
- [x] tin of beanz (`tin_of_beanz`) → in game as `canned_food`
- [x] tinned hotdogs (`tinned_hotdogs`)
- [x] can of cashews (`can_of_cashews`)
- [x] peaches o'reilly (`peaches_oreilly`)
- [x] emergency ration pack (`emergency_ration_pack`)
- [x] raw bird meat (`raw_bird_meat`)
- [x] cooked bird meat (`cooked_bird_meat`)
- [x] raw rabbit meat (`raw_rabbit_meat`)
- [x] cooked rabbit meat (`cooked_rabbit_meat`)
- [x] raw venison (`raw_venison`)
- [x] cooked venison (`cooked_venison`)
- [x] raw wolf meat (`raw_wolf_meat`)
- [x] cooked wolf meat (`cooked_wolf_meat`)
- [x] feline feast cat food (`feline_feast_cat_food`)
- [x] canine chow dog food (`canine_chow_dog_food`)
- [x] tommy's crunch (`tommy_s_crunch`)
- [x] jason's choccy block (`jason_s_choccy_block`)
- [x] potato (`potato`)
- [x] baked potato (`baked_potato`)
- [x] tomato (`tomato`)
- [x] carrot (`carrot`)
- [x] corn cob (`corn_cob`)
- [x] roasted corn (`roasted_corn`)
- [x] purple berry (`purple_berry`) → in game as `berries`
- [x] yellow berry (`yellow_berry`)
- [x] red berry (`red_berry`)
- [x] golden mystic berry (`golden_mystic_berry`)

### Medical and Biotech

- [x] medical pack (`medical_pack`) → in game as `medkit`
- [x] advanced trauma kit (`advanced_trauma_kit`)
- [x] bandage (`bandage`)
- [x] sterile gauze roll (`sterile_gauze`)
- [x] painkillers (`painkillers`)
- [x] morphine injector (`morphine_injector`)
- [x] adrenaline auto-injector (`adrenaline_injector`)
- [x] splint (`splint`)
- [x] antidote (`antidote`)

### Firearms, Ammunition and Explosives

- [x] combat 19 pistol (`combat_19_pistol`)
- [x] bolt action rifle (`bolt`) → in game as `rifle`
- [x] magnum revolver (`magnum`)
- [x] hunting bow (`hunting_bow`) → in game as `bow`
- [x] compound bow (`compound_bow`)
- [x] pocket pistol (`pocket_pistol`)
- [x] double barrel shotgun (`double_barrel_shotgun`)
- [x] ammo box 9mm (`ammo_box_9mm`)
- [x] ammo box 7.62mm (`ammo_box_7.62mm`) → in game as `ammo`
- [x] ammo box .44 magnum (`ammo_box_44`)
- [x] ammo box 12 gauge buckshot (`ammo_box_12_gauge`)
- [x] ammo box .25 acp (`ammo_box_25_acp`)
- [x] standard arrows (`arrows`) → in game as `arrow`

### Tools, Melee Weapons and Utility Gear

- [x] bare hands (`hands`) → in game as `(bare hands)`
- [x] fire axe (`fire_axe`)
- [x] torch (`torch`)
- [x] wooden hammer (`hammer`)
- [x] metal framing hammer (`metal_hammer`)
- [x] heavy-duty flashlight (`flashlight`)
- [x] tactical headlamp (`tactical_headlamp`)
- [x] stone pickaxe (`stone_pickaxe`)
- [x] metal pickaxe (`pickaxe`)
- [x] heavy pickaxe (`heavy_pickaxe`)
- [x] stone hatchet (`stone_hatchet`)
- [x] steel hatchet (`steel_hatchet`) → in game as `axe`
- [x] spiked bat (`spiked_bat`)
- [x] machete (`machete`)
- [x] tactical combat knife (`combat_knife`)
- [x] kitchen knife (`kitchen_knife`)
- [x] sledge hammer (`sledge_hammer`)
- [x] crowbar (`crowbar`)
- [x] mechanical hand saw (`saw`)
- [x] multi-tool wrench (`multi_tool_wrench`)
- [x] field binoculars (`binoculars`)
- [x] rock (`rock`)
- [x] stick (`stick`)

### Apparel, Armor and Tactical Gear

- [x] ripped t-shirt (`ripped_t_shirt`)
- [x] survivor clothes (`survivor_clothes`)
- [x] red jacket (`red_jacket`)
- [x] blue jacket (`blue_jacket`)
- [x] construction clothes (`construction_clothes`)
- [x] leather vest (`leather_vest`)
- [x] military tactical helmet (`tactical_helmet`)
- [x] brown rucksack (`brown_rucksack`)
- [x] military tactical backpack (`military_backpack`)
- [x] hiking backpack (`hiking_backpack`)
- [x] heavy expedition hiking pack (`expedition_pack`)
- [x] makeshift burlap bag (`makeshift_bag`)

### Mobile Base and Road-Trip Equipment (Packable)

- [x] deployable shade tarp (`deployable_tarp`)
- [x] road flare (`road_flare`)
- [x] chemical light stick (`chem_light_stick`)
- [x] emergency roadside hazard triangle (`hazard_triangle`)

### Heavy Machinery, Automation and Power Grids

- [x] stationary solar panel array (`machine_solar_array`) → in game as `solar_panel`
- [x] large rain collector / 400l caged tank (`mod_rain_collector`) → in game as `rain_collector`
- [x] water tank 50l (`mod_water_tank_50l`) → in game as `water_tank`
- [x] portable campfire (`mod_portable_campfire`) → in game as `campfire`
- [x] retro tv entertainment unit (`mod_retro_tv`)
- [x] cassette travel case (`mod_cassette_travel_case`)
- [x] modular storage sofa (`mod_storage_sofa`) → in game as `sofa`
- [x] persian rug (`mod_rug_persian`)
- [x] braided rag rug (`mod_rug_braided`)
- [x] japanese wave rug (`mod_rug_japanese_wave`)
- [x] cowhide rug (`mod_rug_cowhide`)
- [x] woven floor rug (`mod_rug_woven`)
- [x] led wall clock (`mod_led_wall_clock`)
- [x] weather forecasting station (`mod_weather_station`)

### Vehicle Simulator and Engine Parts

- [x] vehicle engine block tier 1 (`vehicle_engine_block_t1`) → in game as `engine_block`
- [x] standard road tire (`vehicle_tire_standard`) → in game as `tire`
- [x] heavy off-road mud tire (`vehicle_tire_mud`) → in game as `offroad_tire`
- [x] vehicle fuel canister (`vehicle_fuel_canister`) → in game as `fuel_can`
- [x] auxiliary long-range fuel tank (`vehicle_aux_fuel_tank`) → in game as `fuel_tank_xl`
- [x] standard lead-acid vehicle battery (`vehicle_battery`) → in game as `car_battery`
- [x] radiator - standard core (`vehicle_radiator`)
- [x] armored front bull bar (`vehicle_bull_bar`) → in game as `bull_bar`
- [x] retro dashboard gps unit (`mod_retro_gps`)
- [x] cab decor: fuzzy dice (`mod_decor_fuzzy_dice`)
- [x] cab decor: cactus air freshener (`mod_decor_cactus_freshener`)
- [x] cab decor: crystal sun catcher (`mod_decor_suncatcher`)
- [x] cab decor: brass bells (`mod_decor_brass_bells`)
- [x] cab decor: dreamcatcher (`mod_decor_dreamcatcher`)
- [x] cab decor: mini mirror ball (`mod_decor_mirror_ball`)
- [x] cab decor: wind spinner (`mod_decor_wind_spinner`)
- [x] cab decor: spring palm (`mod_decor_spring_palm`)
- [x] cab decor: mini globe (`mod_decor_mini_globe`)
- [x] cab decor: hourglass (`mod_decor_hourglass`)
- [x] coolant jug 20l (`mod_coolant_jug_20l`)

### Base Building and Structural Components

- [x] small wooden storage box (`base_small_storage_box`) → in game as `crate`

### Roadway Salvage and Vehicle Chassis Parts

- [x] vehicle alternator unit (`vehicle_alternator`)
- [x] engine starter motor (`vehicle_starter_motor`)
- [x] side view mirror (`vehicle_side_mirror`)
- [x] headlight assembly (`vehicle_headlight`) → in game as `headlight`
- [x] taillight assembly (`vehicle_taillight`)
- [x] rusted hubcap (`vehicle_hubcap`)

### Navigation, Maps and Communications

- [x] paper regional roadmap (`nav_paper_roadmap`)
- [x] magnetic pocket compass (`nav_pocket_compass`)
- [x] analog wristwatch (`nav_wristwatch`)
- [x] digital survival watch with altimeter (`nav_survival_watch`)

### Weather and Extreme Environment Gear

- [x] heavy wool poncho (`gear_wool_poncho`)
- [x] thermal emergency space blanket (`gear_space_blanket`)
- [x] sandstorm protective goggles (`gear_sandstorm_goggles`)
- [x] heavy-duty rain poncho (`gear_rain_poncho`)
- [x] hand warmer chemical packet (`gear_hand_warmer`)

### Electronics, Wiring and Circuitry

- [x] copper wire coil (`elec_copper_wire`) → in game as `wire`
- [x] printed circuit board (`elec_circuit_board`)
- [x] microchip processor (`elec_microchip`)
- [x] electrical relay switch (`elec_relay_switch`)
- [x] heavy electrical fuse (`elec_fuse`)
- [x] incandescent light bulb (`elec_light_bulb`)
- [x] copper spool (`elec_copper_spool`)

### Salvage, Trash and Junk Curiosities

- [x] rusted license plate (`salvage_license_plate`)
- [x] bent silverware (`salvage_bent_spoon`)
- [x] vintage tin can (`salvage_vintage_can`)
- [x] waterlogged magazine (`salvage_old_magazine`)
- [x] broken pocket watch (`salvage_broken_watch`)
- [x] shattered glass bottle (`salvage_shattered_glass`)
- [x] rusted spring (`salvage_rusted_spring`)
- [x] discarded wire hanger (`salvage_wire_hanger`)
- [x] empty aerosol can (`salvage_empty_aerosol`)
- [x] old battery core (`salvage_dead_battery`) → in game as `worn_battery`

### Wilderness Wildlife and Hunting Byproducts

- [x] deer antlers (`hunt_deer_antlers`)
- [x] raw wolf pelt (`hunt_wolf_pelt`)
- [x] cured wolf pelt (`hunt_cured_pelt`)
- [x] bird feathers (`hunt_bird_feathers`) → in game as `feather`
- [x] predator claws (`hunt_predator_claws`)
- [x] animal sinew cord (`hunt_sinew_cord`)
- [x] rendered animal grease (`hunt_animal_grease`)
- [x] bone sewing needle (`hunt_bone_needle`)
- [x] raw leather hide strip (`hunt_hide_strip`)
- [x] predator skull trophy (`hunt_predator_skull`)

### Camping, Cooking Utensils and Comfort Gear

- [x] cast iron skillet (`camp_cast_iron_skillet`)
- [x] camping cooking pot (`camp_cooking_pot`)
- [x] manual coffee percolator (`camp_coffee_percolator`)
- [x] titanium camping spork (`camp_spork`)
- [x] collapsible folding camp chair (`camp_folding_chair`)
- [x] insulated thermos flask (`camp_insulated_thermos`)
- [x] canvas bedroll (`camp_canvas_bedroll`)
- [x] portable hand-crank radio (`camp_handcrank_radio`)
- [x] portable folding camp lantern (`camp_folding_lantern`)
- [x] waterproof matchbox (`camp_waterproof_matches`)

## Earlier versions

- 1.6.0: van furniture placed anywhere with a preview, five hand slots, better start, first backlog foods and items.
- 1.5.0: walk into the van and camper through real doorways, realistic van body with see-through windows.
- 1.4.0: build the van from a stripped shell, workbench crafting, hands-on cooking.
- 1.3.0: physical hands-on items, exact placement, part swaps, real interiors.
- 1.2.0: multiple vehicles and trailers, roadside houses, varied ambience.
- 1.1.0: item models, physical items, RV furniture, cheats, driving and worldgen fixes.
- 1.0.0: the full open-road survival game.
