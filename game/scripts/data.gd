extends RefCounted
## Static game data: items, workbench and heat recipes, van modules, build pieces, parts.

const ITEMS := {
	# Materials
	"wood": {"name": "Wood", "color": Color("8a6440"), "kind": "material"},
	"stone": {"name": "Stone", "color": Color("8c8c88"), "kind": "material"},
	"scrap": {"name": "Scrap Metal", "color": Color("8e5c3c"), "kind": "material"},
	"fiber": {"name": "Plant Fiber", "color": Color("8aa05a"), "kind": "material"},
	"rope": {"name": "Rope", "color": Color("c4a86c"), "kind": "material"},
	"cloth": {"name": "Cloth", "color": Color("8c9cb0"), "kind": "material"},
	"hide": {"name": "Animal Hide", "color": Color("9a6d4a"), "kind": "material"},
	"feather": {"name": "Feather", "color": Color("e8e2d0"), "kind": "material"},
	"engine_parts": {"name": "Engine Parts", "color": Color("6a7480"), "kind": "material"},
	"tire": {"name": "Spare Tire", "color": Color("2a2a2a"), "kind": "material"},
	"car_battery": {"name": "Car Battery", "color": Color("3b6ea8"), "kind": "material"},
	"toolkit": {"name": "Toolkit", "color": Color("c0392b"), "kind": "material"},
	"worn_tire": {"name": "Worn Tire", "color": Color("3a3a3a"), "kind": "material"},
	"worn_battery": {"name": "Dead Battery", "color": Color("4a4a4a"), "kind": "material"},
	"wire": {"name": "Copper Wire", "color": Color("c87a3a"), "kind": "material"},
	"bolts": {"name": "Nuts & Bolts", "color": Color("9a9a9a"), "kind": "material"},
	"pipe": {"name": "Metal Pipe", "color": Color("8a9096"), "kind": "material"},
	"foam": {"name": "Foam Padding", "color": Color("d8c890"), "kind": "material"},
	"glass": {"name": "Glass Pane", "color": Color("a8d0d8"), "kind": "material"},
	"duct_tape": {"name": "Duct Tape", "color": Color("a0a4a8"), "kind": "material"},
	# Empty containers: drink a bottle and you keep the bottle; fill it at a sink, lake, well or rain collector
	"bottle_empty": {"name": "Empty Bottle", "color": Color("c8e0f0"), "kind": "container"},
	"fuel_can_empty": {"name": "Empty Fuel Can", "color": Color("903028"), "kind": "container"},
	"paint_can": {"name": "Spray Paint", "color": Color("4f8fbf"), "kind": "paint"},
	# Van modules: carry them to their spot on the van and press [E] to fit them. [G] takes them out again.
	"engine_block": {"name": "Engine Block", "color": Color("5a5e64"), "kind": "module"},
	"steering_wheel": {"name": "Steering Wheel", "color": Color("2a2a2a"), "kind": "module"},
	"car_seat": {"name": "Car Seat", "color": Color("4a4e58"), "kind": "module"},
	"van_door": {"name": "Side Door", "color": Color("a0a29e"), "kind": "module"},
	"headlight": {"name": "Headlight", "color": Color("e0e4e8"), "kind": "module"},
	"radio": {"name": "Car Radio", "color": Color("303236"), "kind": "module"},
	"floor_kit": {"name": "Vinyl Flooring", "color": Color("b09a7e"), "kind": "module"},
	"wall_panels": {"name": "Insulated Wall Panels", "color": Color("e0ddd6"), "kind": "module"},
	"kitchen_unit": {"name": "Kitchen Counter", "color": Color("d2b68e"), "kind": "module"},
	"stove_unit": {"name": "Gas Stove", "color": Color("2a2a2c"), "kind": "module"},
	"sink_unit": {"name": "Sink & Tap", "color": Color("c0c4c8"), "kind": "module"},
	"coffee_maker": {"name": "Coffee Maker", "color": Color("1e1e20"), "kind": "module"},
	"fridge_unit": {"name": "Fridge", "color": Color("ececea"), "kind": "module"},
	"cupboard_unit": {"name": "Storage Cupboard", "color": Color("d2b68e"), "kind": "module"},
	"overhead_unit": {"name": "Overhead Cabinet", "color": Color("d2b68e"), "kind": "module"},
	"dinette_kit": {"name": "Dinette (table & benches)", "color": Color("6a7080"), "kind": "module"},
	"toilet_unit": {"name": "Cassette Toilet", "color": Color("f2f2f2"), "kind": "module"},
	"bed_frame": {"name": "Bed Frame", "color": Color("d2b68e"), "kind": "module"},
	"mattress": {"name": "Mattress", "color": Color("e8e6e0"), "kind": "module"},
	"ceiling_light": {"name": "Ceiling Light", "color": Color("f0e8c8"), "kind": "module"},
	"water_tank": {"name": "Water Tank (60 L)", "color": Color("e0e0e0"), "kind": "module"},
	"solar_panel": {"name": "Solar Panel", "color": Color("1e2a50"), "kind": "module"},
	"bull_bar": {"name": "Bull Bar", "color": Color("b8bcc0"), "kind": "module"},
	"heater_unit": {"name": "Cabin Heater", "color": Color("8a3a2a"), "kind": "module"},
	"fuel_tank_xl": {"name": "Long-Range Fuel Tank", "color": Color("3a3a3a"), "kind": "module"},
	"tune_kit": {"name": "Engine Tune Kit", "color": Color("c0392b"), "kind": "module"},
	"offroad_tire": {"name": "Off-Road Tire", "color": Color("1a1a1a"), "kind": "module"},
	# Food & drink
	"raw_meat": {"name": "Raw Meat", "color": Color("c0504d"), "kind": "food", "food": 8, "water": 0, "health": -6, "cook": "cooked_meat"},
	"cooked_meat": {"name": "Cooked Meat", "color": Color("8b4a2b"), "kind": "food", "food": 35, "water": -2, "health": 4},
	"raw_fish": {"name": "Raw Fish", "color": Color("8fb3c4"), "kind": "food", "food": 6, "water": 0, "health": -4, "cook": "cooked_fish"},
	"cooked_fish": {"name": "Grilled Fish", "color": Color("c48f4f"), "kind": "food", "food": 28, "water": 0, "health": 4},
	"berries": {"name": "Wild Berries", "color": Color("7b3f8c"), "kind": "food", "food": 6, "water": 4},
	"mushroom": {"name": "Mushroom", "color": Color("d8c7a8"), "kind": "food", "food": 7, "water": 1, "cook": "roast_mushroom"},
	"roast_mushroom": {"name": "Roasted Mushroom", "color": Color("9c7c56"), "kind": "food", "food": 14, "water": 0, "health": 2},
	"canned_food": {"name": "Canned Beans", "color": Color("b0b4b8"), "kind": "food", "food": 30, "water": 4},
	"tomato": {"name": "Tomato", "color": Color("d6402f"), "kind": "food", "food": 8, "water": 8},
	"potato": {"name": "Potato", "color": Color("b89060"), "kind": "food", "food": 6, "water": 0, "cook": "baked_potato"},
	"baked_potato": {"name": "Baked Potato", "color": Color("a0703c"), "kind": "food", "food": 22, "water": 0, "health": 2},
	"stew": {"name": "Hearty Stew", "color": Color("9a5a2a"), "kind": "food", "food": 60, "water": 15, "health": 15},
	"water_dirty": {"name": "Dirty Water", "color": Color("7f8f6a"), "kind": "food", "food": 0, "water": 22, "health": -8, "cook": "water_clean"},
	"water_clean": {"name": "Clean Water", "color": Color("5aa0d8"), "kind": "food", "food": 0, "water": 35},
	"coffee_beans": {"name": "Coffee Beans", "color": Color("4a2c1a"), "kind": "material"},
	"coffee": {"name": "Hot Coffee", "color": Color("3a2416"), "kind": "food", "food": 2, "water": 18, "energy": 35, "warmth": 15},
	"soda": {"name": "Flat Soda", "color": Color("d84a4a"), "kind": "food", "food": 4, "water": 20, "energy": 10},
	"chips": {"name": "Bag of Chips", "color": Color("e0b030"), "kind": "food", "food": 12, "water": -3, "energy": 4},
	"energy_bar": {"name": "Energy Bar", "color": Color("3070c0"), "kind": "food", "food": 14, "water": -1, "energy": 22},
	"jerky": {"name": "Beef Jerky", "color": Color("7a3a1a"), "kind": "food", "food": 24, "water": -5, "health": 2},
	"apple": {"name": "Apple", "color": Color("c02a24"), "kind": "food", "food": 9, "water": 7},
	"bread": {"name": "Loaf of Bread", "color": Color("c8904a"), "kind": "food", "food": 26, "water": -2},
	"instant_noodles": {"name": "Instant Noodles", "color": Color("e8e0d0"), "kind": "food", "food": 6, "water": -4},
	"tinned_hotdogs": {"name": "Tinned Hotdogs", "color": Color("c86a3a"), "kind": "food", "food": 28, "water": 2},
	"can_of_cashews": {"name": "Can of Cashews", "color": Color("d8b070"), "kind": "food", "food": 20, "water": -4, "energy": 6},
	"peaches_oreilly": {"name": "Peaches O'Reilly", "color": Color("f0a050"), "kind": "food", "food": 16, "water": 14},
	"berry_juice": {"name": "Berry Juice", "color": Color("8a2a6a"), "kind": "food", "food": 4, "water": 30, "energy": 4},
	"mocha_cola": {"name": "Mocha Cola", "color": Color("5a3220"), "kind": "food", "food": 3, "water": 22, "energy": 18},
	"emergency_ration_pack": {"name": "Emergency Ration Pack", "color": Color("6a7a40"), "kind": "food", "food": 45, "water": 5, "health": 5},
	"jason_s_choccy_block": {"name": "Jason's Choccy Block", "color": Color("4a2a18"), "kind": "food", "food": 16, "energy": 14},
	"hot_noodles": {"name": "Hot Noodles", "color": Color("e8c070"), "kind": "food", "food": 32, "water": 12, "warmth": 12},
	# Medical
	"bandage": {"name": "Bandage", "color": Color("efefef"), "kind": "medical", "health": 25},
	"medkit": {"name": "First Aid Kit", "color": Color("d03030"), "kind": "medical", "health": 70},
	"painkillers": {"name": "Painkillers", "color": Color("e07a20"), "kind": "medical", "health": 15, "energy": 5},
	# Seeds
	"seeds_tomato": {"name": "Tomato Seeds", "color": Color("e07050"), "kind": "seed", "grows": "tomato"},
	"seeds_potato": {"name": "Seed Potato", "color": Color("c0a070"), "kind": "seed", "grows": "potato"},
	"seeds_coffee": {"name": "Coffee Seedling", "color": Color("5a8040"), "kind": "seed", "grows": "coffee_beans"},
	# Fuel & ammo
	"fuel_can": {"name": "Fuel Can (10L)", "color": Color("d0302a"), "kind": "fuel", "fuel": 10.0},
	"ammo": {"name": "Rifle Rounds", "color": Color("c8a03c"), "kind": "ammo"},
	"arrow": {"name": "Arrow", "color": Color("a08060"), "kind": "ammo"},
	# Tools & weapons (equippable)
	"knife": {"name": "Hunting Knife", "color": Color("b8c0c8"), "kind": "tool", "damage": 22, "reach": 2.2},
	"axe": {"name": "Hatchet", "color": Color("a85a3a"), "kind": "tool", "damage": 28, "reach": 2.6},
	"pickaxe": {"name": "Pickaxe", "color": Color("7a7a8a"), "kind": "tool", "damage": 24, "reach": 2.6},
	"hammer": {"name": "Builder's Hammer", "color": Color("c8913a"), "kind": "tool", "damage": 15, "reach": 2.2},
	"bow": {"name": "Hunting Bow", "color": Color("7b5232"), "kind": "tool", "damage": 65},
	"rifle": {"name": "Bolt Rifle", "color": Color("3a3a3a"), "kind": "tool", "damage": 120},
	"fishing_rod": {"name": "Fishing Rod", "color": Color("4f7f5f"), "kind": "tool"},
	"flashlight": {"name": "Flashlight", "color": Color("e8d36a"), "kind": "tool"},
	"crowbar": {"name": "Crowbar", "color": Color("b02a20"), "kind": "tool", "damage": 20, "reach": 2.4},
	"binoculars": {"name": "Binoculars", "color": Color("2a2c30"), "kind": "tool"},
	"jacket": {"name": "Hide Jacket", "color": Color("6f4a2f"), "kind": "wear", "insulation": 12},
	"backpack": {"name": "Backpack (+2 carry slots)", "color": Color("5a6a4a"), "kind": "wear"},
	# Carried objects you can place, pick up and move (also built from the build menu)
	"campfire": {"name": "Campfire", "color": Color("b05a30"), "kind": "placeable"},
	"tent": {"name": "Tent", "color": Color("7b8a5c"), "kind": "placeable"},
	"crate": {"name": "Storage Crate", "color": Color("8a6440"), "kind": "placeable"},
	"planter": {"name": "Garden Planter", "color": Color("6a5030"), "kind": "placeable"},
	"bed": {"name": "Bed", "color": Color("5a6a8a"), "kind": "placeable"},
	"workbench": {"name": "Workbench", "color": Color("7a5a3a"), "kind": "placeable"},
	"rain_collector": {"name": "Rain Collector", "color": Color("5a7090"), "kind": "placeable"},
	"lantern": {"name": "Lantern Post", "color": Color("c8a040"), "kind": "placeable"},
	"chair": {"name": "Camp Chair", "color": Color("4f7f5f"), "kind": "placeable"},
	"table": {"name": "Wooden Table", "color": Color("8a6440"), "kind": "placeable"},
	"sofa": {"name": "Sofa", "color": Color("6a7a9a"), "kind": "placeable"},
	"floor_lamp": {"name": "Floor Lamp", "color": Color("e8d8a0"), "kind": "placeable"},
	"rug": {"name": "Rug", "color": Color("a04a3a"), "kind": "placeable"},
	"potted_plant": {"name": "Potted Plant", "color": Color("4a8a3a"), "kind": "placeable"},
	"shelf_unit": {"name": "Shelf Unit", "color": Color("9a7a50"), "kind": "placeable"},
}

## How many of an item fit in one hand/backpack slot. Anything not listed is carried one at a time.
const STACK := {
	"wood": 3, "stone": 4, "scrap": 4, "fiber": 6, "rope": 3, "cloth": 4, "hide": 2, "feather": 12,
	"berries": 8, "mushroom": 6, "tomato": 4, "potato": 4, "coffee_beans": 3, "raw_meat": 2, "cooked_meat": 2,
	"bandage": 4, "seeds_tomato": 6, "seeds_potato": 6, "seeds_coffee": 3, "ammo": 30, "arrow": 12, "soda": 2,
	"roast_mushroom": 4, "baked_potato": 3, "wire": 4, "bolts": 8, "pipe": 2, "foam": 3, "glass": 2,
	"bottle_empty": 3, "water_clean": 2, "water_dirty": 2,
	"tinned_hotdogs": 2, "can_of_cashews": 3, "peaches_oreilly": 2, "berry_juice": 2, "mocha_cola": 2, "emergency_ration_pack": 2, "jason_s_choccy_block": 4,
	"chips": 3, "energy_bar": 4, "jerky": 3, "apple": 4, "bread": 2, "instant_noodles": 3, "painkillers": 2, "duct_tape": 2,
}

static func stack(id: String) -> int:
	return int(STACK.get(id, 1))

## Workbench recipes. Lay the ingredients on top of a workbench, look at the bench and press
## [E] to put them together; [R] picks between several matching recipes. The result appears on
## the bench (big things are set down in front of it).
const RECIPES := [
	# basics
	{"out": "rope", "n": 1, "cost": {"fiber": 3}},
	{"out": "arrow", "n": 4, "cost": {"wood": 1, "feather": 1, "stone": 1}},
	{"out": "bandage", "n": 2, "cost": {"cloth": 1}},
	{"out": "axe", "n": 1, "cost": {"wood": 2, "stone": 2, "rope": 1}},
	{"out": "pickaxe", "n": 1, "cost": {"wood": 3, "stone": 3, "rope": 1}},
	{"out": "knife", "n": 1, "cost": {"stone": 2, "wood": 1, "rope": 1}},
	{"out": "bow", "n": 1, "cost": {"wood": 4, "rope": 2}},
	{"out": "fishing_rod", "n": 1, "cost": {"wood": 2, "rope": 2}},
	{"out": "hammer", "n": 1, "cost": {"wood": 2, "stone": 1, "rope": 1}},
	{"out": "jacket", "n": 1, "cost": {"hide": 4, "rope": 2}},
	{"out": "backpack", "n": 1, "cost": {"hide": 2, "cloth": 2, "rope": 2}},
	{"out": "medkit", "n": 1, "cost": {"bandage": 2, "water_clean": 1, "fiber": 2}},
	{"out": "duct_tape", "n": 1, "cost": {"cloth": 1, "fiber": 2}},
	{"out": "crowbar", "n": 1, "cost": {"pipe": 1, "scrap": 1}},
	{"out": "binoculars", "n": 1, "cost": {"glass": 2, "pipe": 1, "scrap": 1}},
	# metalwork
	{"out": "bolts", "n": 6, "cost": {"scrap": 2}},
	{"out": "pipe", "n": 2, "cost": {"scrap": 2, "bolts": 1}},
	{"out": "ammo", "n": 6, "cost": {"scrap": 2, "bolts": 2}},
	{"out": "engine_parts", "n": 1, "cost": {"scrap": 4, "bolts": 2}},
	{"out": "toolkit", "n": 1, "cost": {"scrap": 3, "wood": 1, "bolts": 2}},
	{"out": "tire", "n": 1, "cost": {"hide": 3, "scrap": 3, "rope": 2}},
	{"out": "rifle", "n": 1, "cost": {"pipe": 1, "wood": 3, "engine_parts": 1}},
	{"out": "scrap", "n": 3, "cost": {"worn_tire": 1}},
	{"out": "scrap", "n": 2, "cost": {"worn_battery": 1}},
	{"out": "wire", "n": 2, "cost": {"worn_battery": 1, "scrap": 1}},
	{"out": "foam", "n": 2, "cost": {"fiber": 4, "cloth": 1}},
	{"out": "bottle_empty", "n": 2, "cost": {"glass": 1}},
	# van modules
	{"out": "engine_block", "n": 1, "cost": {"engine_parts": 3, "pipe": 1, "bolts": 4}},
	{"out": "steering_wheel", "n": 1, "cost": {"pipe": 1, "rope": 1, "bolts": 1}},
	{"out": "car_seat", "n": 1, "cost": {"foam": 2, "cloth": 2, "pipe": 1}},
	{"out": "van_door", "n": 1, "cost": {"scrap": 4, "glass": 1, "bolts": 2}},
	{"out": "headlight", "n": 1, "cost": {"glass": 1, "wire": 1}},
	{"out": "radio", "n": 1, "cost": {"wire": 2, "scrap": 1, "worn_battery": 1}},
	{"out": "floor_kit", "n": 1, "cost": {"wood": 3, "cloth": 1}},
	{"out": "wall_panels", "n": 1, "cost": {"wood": 3, "foam": 2}},
	{"out": "kitchen_unit", "n": 1, "cost": {"wood": 4, "bolts": 2}},
	{"out": "stove_unit", "n": 1, "cost": {"scrap": 3, "pipe": 1, "wire": 1}},
	{"out": "sink_unit", "n": 1, "cost": {"scrap": 2, "pipe": 2}},
	{"out": "coffee_maker", "n": 1, "cost": {"scrap": 1, "glass": 1, "wire": 1}},
	{"out": "fridge_unit", "n": 1, "cost": {"scrap": 4, "wire": 2, "foam": 1}},
	{"out": "cupboard_unit", "n": 1, "cost": {"wood": 3, "bolts": 1}},
	{"out": "overhead_unit", "n": 1, "cost": {"wood": 2, "bolts": 2}},
	{"out": "dinette_kit", "n": 1, "cost": {"wood": 3, "foam": 1, "cloth": 1}},
	{"out": "toilet_unit", "n": 1, "cost": {"scrap": 2, "pipe": 1, "stone": 1}},
	{"out": "bed_frame", "n": 1, "cost": {"wood": 4, "bolts": 1}},
	{"out": "mattress", "n": 1, "cost": {"foam": 3, "cloth": 2}},
	{"out": "ceiling_light", "n": 1, "cost": {"wire": 1, "glass": 1, "scrap": 1}},
	{"out": "water_tank", "n": 1, "cost": {"scrap": 3, "pipe": 1, "bolts": 1}},
	{"out": "solar_panel", "n": 1, "cost": {"glass": 2, "wire": 2, "scrap": 2}},
	{"out": "bull_bar", "n": 1, "cost": {"pipe": 2, "bolts": 2}},
	{"out": "heater_unit", "n": 1, "cost": {"scrap": 3, "wire": 1, "engine_parts": 1}},
	{"out": "fuel_tank_xl", "n": 1, "cost": {"scrap": 4, "pipe": 1, "bolts": 2}},
	{"out": "tune_kit", "n": 1, "cost": {"engine_parts": 2, "wire": 1, "bolts": 2}},
	{"out": "offroad_tire", "n": 1, "cost": {"tire": 1, "hide": 1, "bolts": 1}},
	{"out": "paint_can", "n": 1, "cost": {"berries": 3, "scrap": 1}},
]

## Heat recipes: set the ingredients on a burning campfire or a lit stove and they cook on
## their own. Multi-ingredient dishes (stew, coffee) cook when everything sits on the heat.
const COOK_TIME := 14.0
const COOKING := [
	{"out": "stew", "n": 1, "cost": {"raw_meat": 1, "potato": 1, "tomato": 1, "water_clean": 1}},
	{"out": "coffee", "n": 1, "cost": {"coffee_beans": 1, "water_clean": 1}},
	{"out": "hot_noodles", "n": 1, "cost": {"instant_noodles": 1, "water_clean": 1}},
	{"out": "cooked_meat", "n": 1, "cost": {"raw_meat": 1}},
	{"out": "cooked_fish", "n": 1, "cost": {"raw_fish": 1}},
	{"out": "roast_mushroom", "n": 1, "cost": {"mushroom": 1}},
	{"out": "baked_potato", "n": 1, "cost": {"potato": 1}},
	{"out": "water_clean", "n": 1, "cost": {"water_dirty": 1}},
]

## What a drink leaves behind in your hand.
const LEAVES := {"water_clean": "bottle_empty", "water_dirty": "bottle_empty", "fuel_can": "fuel_can_empty"}

## Van module slots. Each slot takes one item. "needs": slots that must be fitted first.
## "toolkit": a Toolkit must be in hand or within reach. "drive": required to drive.
const VAN_SLOTS := {
	"engine": {"item": "engine_block", "name": "Engine", "toolkit": true, "drive": true},
	"steering": {"item": "steering_wheel", "name": "Steering wheel", "toolkit": true, "drive": true},
	"seat_driver": {"item": "car_seat", "name": "Driver's seat", "drive": true},
	"seat_passenger": {"item": "car_seat", "name": "Passenger seat"},
	"door": {"item": "van_door", "name": "Side door", "toolkit": true},
	"headlight_l": {"item": "headlight", "name": "Left headlight"},
	"headlight_r": {"item": "headlight", "name": "Right headlight"},
	"radio": {"item": "radio", "name": "Radio", "needs": ["steering"]},
	"floor": {"item": "floor_kit", "name": "Flooring"},
	"walls": {"item": "wall_panels", "name": "Wall panels"},
	"kitchen": {"item": "kitchen_unit", "name": "Kitchen counter"},
	"stove": {"item": "stove_unit", "name": "Stove", "needs": ["kitchen"]},
	"sink": {"item": "sink_unit", "name": "Sink", "needs": ["kitchen"]},
	"coffee": {"item": "coffee_maker", "name": "Coffee maker", "needs": ["kitchen"]},
	"overhead": {"item": "overhead_unit", "name": "Overhead cabinet", "needs": ["walls"]},
	"fridge": {"item": "fridge_unit", "name": "Fridge"},
	"cupboard": {"item": "cupboard_unit", "name": "Cupboard"},
	"dinette": {"item": "dinette_kit", "name": "Dinette"},
	"toilet": {"item": "toilet_unit", "name": "Toilet"},
	"bed": {"item": "bed_frame", "name": "Bed frame"},
	"mattress": {"item": "mattress", "name": "Mattress", "needs": ["bed"]},
	"light": {"item": "ceiling_light", "name": "Ceiling light"},
	"water_tank": {"item": "water_tank", "name": "Water tank", "toolkit": true},
	"solar": {"item": "solar_panel", "name": "Solar panel", "toolkit": true},
	"bullbar": {"item": "bull_bar", "name": "Bull bar", "toolkit": true},
	"heater": {"item": "heater_unit", "name": "Heater"},
	"big_tank": {"item": "fuel_tank_xl", "name": "Long-range tank", "toolkit": true},
	"engine_tune": {"item": "tune_kit", "name": "Engine tune", "toolkit": true, "needs": ["engine"]},
}

## Upgrades that cars accept at the hood (carry the part there and press [E]).
const CAR_UPGRADE_ITEMS := {"tune_kit": "engine_tune", "bull_bar": "bullbar", "fuel_tank_xl": "big_tank"}

## Buildable pieces. "snap": grid snapping mode.
const PIECES := {
	"foundation": {"name": "Foundation", "cost": {"wood": 4, "stone": 2}, "snap": "cell"},
	"floor": {"name": "Floor / Ceiling", "cost": {"wood": 3}, "snap": "cell_level"},
	"wall": {"name": "Wall", "cost": {"wood": 4}, "snap": "edge"},
	"doorway": {"name": "Wall with Door", "cost": {"wood": 6}, "snap": "edge"},
	"window": {"name": "Wall with Window", "cost": {"wood": 4, "cloth": 1}, "snap": "edge"},
	"roof": {"name": "Flat Roof", "cost": {"wood": 3}, "snap": "cell_level"},
	"roof_slope": {"name": "Sloped Roof", "cost": {"wood": 4}, "snap": "cell_level"},
	"stairs": {"name": "Stairs", "cost": {"wood": 5}, "snap": "cell"},
	"campfire": {"name": "Campfire", "cost": {"wood": 3, "stone": 3}, "snap": "free"},
	"tent": {"name": "Tent", "cost": {"cloth": 4, "wood": 3, "rope": 1}, "snap": "free"},
	"crate": {"name": "Storage Crate", "cost": {"wood": 6}, "snap": "free"},
	"planter": {"name": "Garden Planter", "cost": {"wood": 4, "fiber": 2}, "snap": "free"},
	"bed": {"name": "Bed", "cost": {"wood": 4, "cloth": 3}, "snap": "free"},
	"workbench": {"name": "Workbench", "cost": {"wood": 6, "scrap": 2}, "snap": "free"},
	"rain_collector": {"name": "Rain Collector", "cost": {"wood": 3, "cloth": 2}, "snap": "free"},
	"lantern": {"name": "Lantern Post", "cost": {"wood": 2, "scrap": 2}, "snap": "free"},
	"fence": {"name": "Fence", "cost": {"wood": 2}, "snap": "edge"},
	"chair": {"name": "Camp Chair", "cost": {"wood": 2, "cloth": 1}, "snap": "free"},
	"table": {"name": "Wooden Table", "cost": {"wood": 4}, "snap": "free"},
	"sofa": {"name": "Sofa", "cost": {"wood": 3, "cloth": 3, "foam": 2}, "snap": "free"},
	"floor_lamp": {"name": "Floor Lamp", "cost": {"scrap": 1, "wire": 1, "glass": 1}, "snap": "free"},
	"rug": {"name": "Rug", "cost": {"cloth": 3}, "snap": "free"},
	"potted_plant": {"name": "Potted Plant", "cost": {"stone": 1, "fiber": 2}, "snap": "free"},
	"shelf_unit": {"name": "Shelf Unit", "cost": {"wood": 4, "bolts": 1}, "snap": "free"},
}

const PIECE_ORDER := ["foundation", "floor", "wall", "doorway", "window", "roof", "roof_slope", "stairs",
	"fence", "campfire", "tent", "crate", "planter", "bed", "workbench", "rain_collector", "lantern", "chair", "table",
	"sofa", "floor_lamp", "rug", "potted_plant", "shelf_unit"]

## RV parts (condition 0..100).
## Vehicle parts (condition 0..100). Parts are replaced physically: carry the part in your hands
## to where it fits on the vehicle ("where") and install it there.
const RV_PARTS := {
	"engine": {"name": "Engine", "repair": {"engine_parts": 1}, "amount": 50, "needs_toolkit": true, "where": "Fit an Engine Block at the hood, then hold Engine Parts there to rebuild it (toolkit nearby)"},
	"tires": {"name": "Tires", "repair": {"tire": 1}, "amount": 25, "needs_toolkit": true, "where": "Pull a worn tire off a wheel, then fit a Spare Tire there (toolkit nearby)"},
	"battery": {"name": "Battery", "repair": {"car_battery": 1}, "amount": 100, "needs_toolkit": false, "where": "Pull the old battery out of the battery box, then fit a Car Battery"},
	"body": {"name": "Body & Chassis", "repair": {"scrap": 1}, "amount": 12, "needs_toolkit": true, "where": "Hold Scrap Metal at the hood to weld patches (toolkit nearby)"},
}

const RV_UPGRADES := {
	"engine_tune": {"name": "Engine Tune-Up (+35% power)"},
	"offroad_tires": {"name": "Off-Road Tires (+grip, less wear)"},
	"big_tank": {"name": "Long-Range Fuel Tank (140 L)"},
	"solar": {"name": "Roof Solar Panel (charges battery)"},
	"bullbar": {"name": "Bull Bar (-60% crash damage)"},
	"heater": {"name": "Cabin Heater"},
	"water_tank": {"name": "Water Tank (60 L)"},
}

const RV_PAINTS := [Color("e9e2cf"), Color("7d9a6a"), Color("c26b3c"), Color("4f6f8f"), Color("d9b44a"), Color("8f3b3b"), Color("3d3d3d"), Color("9a9c98")]
const PRIMER := 7 # the bare primer-and-rust look the van starts with

const ANIMALS := {
	"deer": {"hp": 60, "walk": 1.6, "run": 9.5, "flee": 26.0, "aggro": 0.0, "dmg": 0, "drops": {"raw_meat": 4, "hide": 2}, "color": Color("8a6440"), "size": 1.0},
	"rabbit": {"hp": 14, "walk": 1.2, "run": 7.5, "flee": 12.0, "aggro": 0.0, "dmg": 0, "drops": {"raw_meat": 1, "hide": 1}, "color": Color("9c8a74"), "size": 0.3},
	"boar": {"hp": 90, "walk": 1.4, "run": 7.0, "flee": 16.0, "aggro": 0.0, "dmg": 14, "drops": {"raw_meat": 5, "hide": 2}, "color": Color("4a3a30"), "size": 0.75},
	"wolf": {"hp": 70, "walk": 1.8, "run": 8.6, "flee": 0.0, "aggro": 26.0, "dmg": 11, "drops": {"raw_meat": 2, "hide": 2}, "color": Color("6f6a64"), "size": 0.75},
	"bear": {"hp": 230, "walk": 1.4, "run": 8.2, "flee": 0.0, "aggro": 18.0, "dmg": 28, "drops": {"raw_meat": 8, "hide": 5}, "color": Color("3b2a1f"), "size": 1.4},
	"fox": {"hp": 25, "walk": 1.5, "run": 8.0, "flee": 14.0, "aggro": 0.0, "dmg": 0, "drops": {"raw_meat": 1, "hide": 1}, "color": Color("c06a30"), "size": 0.5},
	"turkey": {"hp": 18, "walk": 1.0, "run": 5.5, "flee": 11.0, "aggro": 0.0, "dmg": 0, "drops": {"raw_meat": 2, "feather": 4}, "color": Color("3f3328"), "size": 0.45},
}

const DIFFICULTY := {
	"Relaxed": {"drain": 0.5, "damage": 0.5, "fuel": 0.6, "loot": 1.5},
	"Normal": {"drain": 1.0, "damage": 1.0, "fuel": 1.0, "loot": 1.0},
	"Hard": {"drain": 1.5, "damage": 1.6, "fuel": 1.4, "loot": 0.7},
}

static func item_name(id: String) -> String:
	return ITEMS[id]["name"] if ITEMS.has(id) else id.capitalize()

static func cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d %s" % [cost[k], item_name(k)])
	return ", ".join(parts)
