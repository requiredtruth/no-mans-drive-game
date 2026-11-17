# To do

What is still to be made. Finished work moves to `done.md`. Each item needs a real 3D model and texture, an entry in `game/scripts/data.gd`, a model in `game/scripts/items.gd` (or a structure in `structure.gd` for furniture), and a place in the loot tables, a recipe or a world drop. The full source lists are in `docs/item-backlog/`.

**Quality bar:** read `NOTES.md` before changing models, textures, the HUD, items or interactions. It lists the gap to the reference screenshots and the rules every new piece follows.

## Quality pass (see NOTES.md)

- [ ] Extend aim outlines to the remaining vehicle exterior hotspots and built-in house containers (van cupboard/fridge doors, cargo lids and placed furniture completed in 1.10).
- [ ] Liquids in litres for fuel, water and coolant, with a two-gauge transfer panel and a pump nozzle at fuel stations.
- [ ] Texture and bevel pass on the van interior (cab, dashboard, seats, cupboards, floor), then houses.
- [ ] Label remaining jars, chemistry containers and other packaging (16 food/drink/water/spray labels and slatted crates completed in 1.10).
- [ ] House cabinets and wardrobes as physical shelves with hinged doors.
- [ ] Detailed first-person hand and sleeve; bigger held items.
- [ ] Ambient occlusion and grime in interiors.

## Testing phase

- [ ] The test depot (every item at the start of a new game) stays on until everything has been checked; turn it off with `TEST_DEPOT` in `game/scripts/world.gd` for a normal start.
- [ ] Make the built-in house cabinets, wardrobes and fridges movable too (they are searchable containers today).

## Remaining gameplay expansion

- [ ] Vehicle performance parts and add-ons for the other cars (they take the turbo and ram plow at the hood today; the rest is van-only).
- [ ] Base building pieces: metal and concrete walls, metal floor, metal door with code lock, window barricades, weapon rack, mannequin, tanning rack, anvil bench, hydroponic tray, industrial crate.
- [ ] Power: generators, batteries, solar array, wind turbine, power hub, battery monitor, with lights and appliances that need power.
- [ ] Machines: smelter, crusher, chemistry station, coolant still, water filtration, 3D printer, fabricator.
- [ ] Remaining weapons: SMG, assault rifles, heavy rifle, bullpup, explosive arrows, flamethrower, and their ammo.
- [ ] Finish the visuals pass: every vehicle, building and animal to the same high-resolution standard as the nature and the new items.

## Remaining backlog items

### Raw Resources and Minerals

- [ ] metal (`metal`)
- [ ] metal ore (`metal_ore`)
- [ ] high-quality metal fragment (`hq_metal_fragment`)
- [ ] high-quality metal ore (`hq_metal_ore`)
- [ ] titanium scrap (`titanium_scrap`)
- [ ] explosives (`explosives`)
- [ ] c4 explosive charge (`c4_charge`)
- [ ] timed explosive charge (`timed_charge`)
- [ ] raw phosphate (`raw_phosphate`)
- [ ] smokeless propellant (`smokeless_propellant`)
- [ ] sleeping bag (`sleeping_bag`)
- [ ] hemp seeds (`hemp_seeds`)

### Chemistry and Fluid Synthesis (Coolants, Acids, Fuels)

- [ ] industrial chemical container (`chem_container_empty`)
- [ ] industrial acid (`industrial_acid`)
- [ ] sulfuric acid (`sulfuric_acid`)
- [ ] hydrogen peroxide (`hydrogen_peroxide`)
- [ ] low-grade fuel (`low_grade_fuel`)
- [ ] refined petrol (`refined_petrol`)
- [ ] bio-diesel (`bio_diesel`)
- [ ] rocket propellant (`rocket_propellant`)
- [ ] synthetic coolant base (`synthetic_coolant_base`)
- [ ] heavy-duty anti-boil coolant - tier 2 (`coolant_t2`)
- [ ] exotic cryogenic coolant - tier 3 (`coolant_t3`)
- [ ] hydraulic fluid (`hydraulic_fluid`)
- [ ] electrochemical cell solution (`electrolyte_solution`)

### Survival Consumables, Agriculture and Cooking

- [ ] canteen (empty) (`canteen_empty`)
- [ ] canteen (half) (`canteen_half`)
- [ ] canteen (full) (`canteen_full`)
- [ ] dead bird (`dead_bird`)
- [ ] rabbit food (`rabbit_food`)
- [ ] livestock feed mix (`livestock_feed`)
- [ ] green berry (`green_berry`)

### Medical and Biotech

- [ ] plaster cast (`plaster_cast`)
- [ ] blood bag (empty) (`blood_bag_empty`)
- [ ] blood bag (universal donor) (`blood_bag_full`)
- [ ] IV saline drip (`iv_saline_drip`)
- [ ] surgical kit (`surgical_kit`)

### Firearms, Ammunition and Explosives

- [ ] viper smg (`viper_smg`)
- [ ] storm tactical rifle (`storm`)
- [ ] thor heavy rifle (`thor`)
- [ ] ak-tactic assault rifle (`akt_assault_rifle`)
- [ ] gizmo pistol (`gizmo`)
- [ ] bullpup rifle (`bullpup`)
- [ ] rotary minigun (`minigun`)
- [ ] flame thrower (`flame_thrower`)
- [ ] rocket launcher rpg (`rocket_launcher`)
- [ ] ammo box 5.56mm (`ammo_box_5.56mm`)
- [ ] ammo box .338 lapua (`ammo_box_338`)
- [ ] explosive arrows (`explosive_arrows`)
- [ ] rocket projectile (`rocket_projectile`)
- [ ] fuel canister (flamethrower ammo) (`flamethrower_fuel`)

### Tools, Melee Weapons and Utility Gear

- [ ] pneumatic jackhammer (`pneumatic_jackhammer`)
- [ ] heavy axe (`heavy_axe`)
- [ ] katana (`katana`)
- [ ] heavy hydraulic crowbar (`hydraulic_crowbar`)
- [ ] chainsaw (`chainsaw`)
- [ ] electronic hacking device (`electronic_hacker`)
- [ ] geiger counter (`geiger_counter`)
- [ ] portable metal detector (`metal_detector`)
- [ ] night vision goggles (`night_vision_goggles`)

### Apparel, Armor and Tactical Gear

- [ ] hazmat suit (`hazmat_suit`)
- [ ] diving wetsuit (`diving_wetsuit`)
- [ ] ghillie suit (top & bottoms) (`ghillie_suit`)
- [ ] ghillie bottoms (`ghillie_bottoms`)
- [ ] riot police armor (`riot_armor`)
- [ ] black body armour (`black_body_armour`)
- [ ] ceramic plate carrier (`ceramic_plate_carrier`)
- [ ] welding mask (`welding_mask`)
- [ ] black rucksack (`black_rucksack`)
- [ ] grey rucksack (`grey_rucksack`)
- [ ] blue rucksack (`blue_rucksack`)
- [ ] waxed canvas field rucksack (`waxed_canvas_field_rucksack`)
- [ ] alpine trekking pack (`alpine_trekking_pack`)
- [ ] mr. bacon's meat sack (`mr_bacon_meat_sack`)
- [ ] kris kringle holiday sack (`kris_kringle_holiday_sack`)

### Mobile Base and Road-Trip Equipment (Packable)

- [ ] packable camp cot (`deployable_camp_cot`)
- [ ] compact folding table (`folding_workbench_compact`)
- [ ] portable field anvil (`portable_anvil`)
- [ ] portable chemistry mixing station (`portable_chem_lab`)
- [ ] portable induction cookstove (`portable_cookstove`)
- [ ] compact solar roll-out blanket (`rollout_solar_panel`)
- [ ] collapsible rain catcher barrel (`collapsible_rain_barrel`)
- [ ] portable water purifier pump (`portable_water_purifier`)
- [ ] heavy towing winch cable (`towing_winch_cable`)
- [ ] portable wildlife decoy speaker (`wildlife_decoy_speaker`)

### Heavy Machinery, Automation and Power Grids

- [ ] petrol combustion generator (`machine_petrol_generator`)
- [ ] heavy diesel industrial generator (`machine_diesel_generator`)
- [ ] nuclear micro-reactor core (`machine_nuclear_reactor`)
- [ ] wind turbine generator (`machine_wind_turbine`)
- [ ] water filtration plant module (`machine_water_filtration`)
- [ ] industrial water reservoir 1000l (`machine_water_reservoir_1000l`)
- [ ] fuel drum 100l (`mod_fuel_drum_100l`)
- [ ] coolant distillation still (`machine_coolant_still`)
- [ ] chemical synthesis reaction vessel (`machine_chem_synthesizer`)
- [ ] industrial arc furnace / smelter (`machine_arc_furnace`)
- [ ] automated mineral crushing mill (`machine_crusher`)
- [ ] alloy mixing centrifuge (`machine_alloy_centrifuge`)
- [ ] automated assembly fabricator (`machine_fabricator`)
- [ ] 3d parts printer (`machine_3d_printer`)
- [ ] heavy auto-turret defense system (`machine_auto_turret`)
- [ ] electric gate controller (`machine_gate_controller`)
- [ ] battery storage bank (`machine_battery_bank`)
- [ ] power distribution relay hub (`machine_power_hub`)
- [ ] trash crusher / recycler (`mod_trash_crusher`)
- [ ] spray booth rack (`mod_spray_rack`)
- [ ] mobile paint station (`mod_paint_station`)
- [ ] cassette wall display (`mod_cassette_wall_display`)
- [ ] cassette wire rack (`mod_cassette_wire_rack`)
- [ ] cassette rotating tower (`mod_cassette_rotating_tower`)
- [ ] modular storage sofa corner piece (`mod_storage_sofa_corner`)
- [ ] battery monitoring console (`mod_battery_monitor`)
- [ ] lighting pack (table lamp, ceiling light, string lights, camping lantern, neon signs) (`mod_lighting_pack`)

### Vehicle Simulator and Engine Parts

- [ ] canteen 2l (`mod_canteen_2l`)
- [ ] coffee flask 3l (`mod_coffee_flask_3l`)

### Base Building and Structural Components

- [ ] wooden foundation frame (`base_wood_foundation`)
- [ ] reinforced metal floor panel (`base_metal_floor`)
- [ ] wooden wall panel (`base_wood_wall`)
- [ ] corrugated sheet metal wall (`base_metal_wall`)
- [ ] reinforced concrete wall block (`base_concrete_wall`)
- [ ] wooden door frame (`base_wood_doorframe`)
- [ ] reinforced metal door (`base_metal_door`)
- [ ] combination code lock (`base_code_lock`)
- [ ] wooden window barricade (`base_wood_window`)
- [ ] iron barred window grate (`base_iron_grate`)
- [ ] large industrial shipping crate (`base_industrial_crate`)
- [ ] weapon mounting rack (`base_weapon_rack`)
- [ ] armor display mannequin (`base_armor_mannequin`)
- [ ] tanning rack for hides (`base_tanning_rack`)
- [ ] blacksmith anvil bench (`base_anvil_bench`)
- [ ] hydroponic crop growing tray (`base_hydroponic_tray`)

### Roadway Salvage and Vehicle Chassis Parts

- [ ] sedan chassis frame (`vehicle_chassis_sedan`)
- [ ] heavy utility truck frame (`vehicle_chassis_truck`)
- [ ] compact camper trailer shell (`vehicle_chassis_camper`)
- [ ] vehicle steering column assembly (`vehicle_steering_column`)
- [ ] dashboard instrument cluster (`vehicle_dashboard_cluster`)
- [ ] ignition switch and keys (`vehicle_ignition_switch`)
- [ ] vehicle windshield glass (`vehicle_windshield`)
- [ ] exhaust muffler pipe (`vehicle_exhaust_pipe`)
- [ ] catalytic converter (`vehicle_catalytic_converter`)
- [ ] heavy towing tow-rope (`vehicle_tow_rope`)

### Navigation, Maps and Communications

- [ ] shortwave radio transceiver (`nav_shortwave_radio`)
- [ ] handheld walkie-talkie pair (`nav_walkie_talkie`)
- [ ] emergency distress beacon transmitter (`nav_distress_beacon`)
- [ ] signal flare gun (`nav_flare_gun`)
- [ ] red emergency signal flare (`nav_signal_flare_red`)
- [ ] green navigation flare (`nav_signal_flare_green`)
- [ ] topographical survey map (`nav_topo_map`)

### Weather and Extreme Environment Gear

- [ ] winter snowshoes (`gear_snowshoes`)
- [ ] mountain climbing crampons (`gear_crampons`)
- [ ] collapsible emergency umbrella (`gear_umbrella`)
- [ ] ice scraper tool (`gear_ice_scraper`)
- [ ] snow shovel (`gear_snow_shovel`)

### Electronics, Wiring and Circuitry

- [ ] motion detector sensor (`elec_motion_sensor`)
- [ ] solar power inverter (`elec_solar_inverter`)
- [ ] electronic sensor array (`elec_sensor_array`)
- [ ] digital control interface panel (`elec_control_panel`)

### Specialized Vehicle Armor and Mod Add-Ons

