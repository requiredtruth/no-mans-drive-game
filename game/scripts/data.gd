extends RefCounted
## Static game data: items, recipes, cooking, build pieces, RV parts and upgrades.

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
	# Medical
	"bandage": {"name": "Bandage", "color": Color("efefef"), "kind": "medical", "health": 25},
	"medkit": {"name": "First Aid Kit", "color": Color("d03030"), "kind": "medical", "health": 70},
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
	"jacket": {"name": "Hide Jacket", "color": Color("6f4a2f"), "kind": "wear", "insulation": 12},
}

## Crafting recipes. "station": "" (hands), "workbench", "fire".
const RECIPES := [
	{"out": "rope", "n": 1, "cost": {"fiber": 3}, "station": ""},
	{"out": "arrow", "n": 4, "cost": {"wood": 1, "feather": 1, "stone": 1}, "station": ""},
	{"out": "bandage", "n": 1, "cost": {"cloth": 2}, "station": ""},
	{"out": "axe", "n": 1, "cost": {"wood": 2, "stone": 2, "rope": 1}, "station": ""},
	{"out": "pickaxe", "n": 1, "cost": {"wood": 3, "stone": 3, "rope": 1}, "station": ""},
	{"out": "knife", "n": 1, "cost": {"stone": 2, "wood": 1, "rope": 1}, "station": ""},
	{"out": "bow", "n": 1, "cost": {"wood": 4, "rope": 2}, "station": ""},
	{"out": "fishing_rod", "n": 1, "cost": {"wood": 2, "rope": 2}, "station": ""},
	{"out": "hammer", "n": 1, "cost": {"wood": 2, "stone": 1, "rope": 1}, "station": ""},
	{"out": "jacket", "n": 1, "cost": {"hide": 4, "rope": 2}, "station": ""},
	{"out": "ammo", "n": 6, "cost": {"scrap": 3}, "station": "workbench"},
	{"out": "engine_parts", "n": 1, "cost": {"scrap": 6, "rope": 1}, "station": "workbench"},
	{"out": "toolkit", "n": 1, "cost": {"scrap": 4, "wood": 2}, "station": "workbench"},
	{"out": "tire", "n": 1, "cost": {"hide": 3, "scrap": 4, "rope": 2}, "station": "workbench"},
	{"out": "medkit", "n": 1, "cost": {"bandage": 2, "water_clean": 1, "fiber": 2}, "station": "workbench"},
	{"out": "rifle", "n": 1, "cost": {"scrap": 12, "wood": 4, "engine_parts": 1}, "station": "workbench"},
]

## Cooking at a campfire or the RV stove.
const COOKING := [
	{"out": "cooked_meat", "n": 1, "cost": {"raw_meat": 1}},
	{"out": "cooked_fish", "n": 1, "cost": {"raw_fish": 1}},
	{"out": "roast_mushroom", "n": 1, "cost": {"mushroom": 1}},
	{"out": "baked_potato", "n": 1, "cost": {"potato": 1}},
	{"out": "water_clean", "n": 1, "cost": {"water_dirty": 1}},
	{"out": "coffee", "n": 1, "cost": {"coffee_beans": 1, "water_clean": 1}},
	{"out": "stew", "n": 1, "cost": {"raw_meat": 1, "potato": 1, "tomato": 1, "water_clean": 1}},
]

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
}

const PIECE_ORDER := ["foundation", "floor", "wall", "doorway", "window", "roof", "roof_slope", "stairs",
	"fence", "campfire", "tent", "crate", "planter", "bed", "workbench", "rain_collector", "lantern"]

## RV parts (condition 0..100).
const RV_PARTS := {
	"engine": {"name": "Engine", "repair": {"engine_parts": 1}, "amount": 50, "needs_toolkit": true},
	"tires": {"name": "Tires", "repair": {"tire": 1}, "amount": 40, "needs_toolkit": false},
	"battery": {"name": "Battery", "repair": {"car_battery": 1}, "amount": 100, "needs_toolkit": false},
	"body": {"name": "Body & Chassis", "repair": {"scrap": 3}, "amount": 30, "needs_toolkit": true},
}

const RV_UPGRADES := {
	"engine_tune": {"name": "Engine Tune-Up (+35% power)", "cost": {"engine_parts": 2, "scrap": 4}},
	"offroad_tires": {"name": "Off-Road Tires (+grip, less wear)", "cost": {"tire": 4, "scrap": 2}},
	"big_tank": {"name": "Extended Fuel Tank (140L)", "cost": {"scrap": 10, "rope": 1}},
	"solar": {"name": "Roof Solar Panel (charges battery)", "cost": {"scrap": 6, "car_battery": 1}},
	"bullbar": {"name": "Bull Bar (-60% crash damage)", "cost": {"scrap": 8}},
	"heater": {"name": "Cabin Heater", "cost": {"scrap": 5, "engine_parts": 1}},
	"water_tank": {"name": "Large Water Tank (80L)", "cost": {"scrap": 5, "rope": 1}},
}

const RV_PAINTS := [Color("e9e2cf"), Color("7d9a6a"), Color("c26b3c"), Color("4f6f8f"), Color("d9b44a"), Color("8f3b3b"), Color("3d3d3d")]

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
