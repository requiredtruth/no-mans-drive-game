# Quality notes: where No Man's Drive is and where it needs to be

**Read this before any change to models, textures, the HUD, items or interactions.** In November 2026 the owner shared five reference screenshots as the quality and detail bar for the game. They show a first-person van survival game with realistic textured models, liquids measured in litres, item cupboards with doors, and a clean context-action HUD. This file lists the gap between those screenshots and No Man's Drive 1.8.0, and the rules that close it.

The target is the **level of quality and detail**, not a copy. Never copy another game's name, logos, characters, UI artwork, product labels (for example its baked-beans brand) or levels. Use our own designs, brands and layout. The reference screenshots are not committed to the repo; the descriptions below stand in for them.

## What the reference screenshots show

1. **Refuelling at the fuel cap.** You hold a pump nozzle on a hose up to the van's fuel filler. A panel shows both containers side by side, each with a level gauge: "Nozzle, Gasoline 27.52/50.00 L" and "Fuel Tank, Gasoline 26.19/50.00 L", with "Ready for transfer!" underneath. The filler has a hinged flap and a round cap. Behind it, the van's white body has visible grime and texture. Right-hand action hints read "Transfer [E]", "Throw [Q]", "Placement Mode [R]".
2. **Coolant in a crate.** A slatted wooden crate (real gaps between the planks) sits on a cracked, tiled concrete floor. A green coolant bottle and a water bottle stand inside it. Hovering the bottle shows a tooltip with a liquid-level icon: "Coolant, 3.81/5.00 L". Objects you can grab get a small label and a hand cursor.
3. **Pantry cupboard, holding a can.** A wooden cabinet with an open door has cans and jars on its shelf; water bottles, an orange, a soda can, spanners and chocolate bars stand on top. The held can is large and detailed in the right hand, with a printed label and a ribbed lid, and the sleeve and hand are textured. Hints read "Eat [E]", "Throw [Q]", "Placement Mode [R]", "Take Off Backpack [B]". The hotbar shows real item icons (a spanner, a can).
4. **The same cupboard with both doors open.** Each hinged door turns on its own hinge and shows a white outline when you aim at it. Inside are shelves, a divider, and jars and cans with labels. Wood grain runs the right way on every panel, and the wall has dirt and stains near the floor.
5. **Inside the van, the living area and cab.** A big window looks out on grass. There's a potted palm, wooden bedside cabinets, corner shelves holding a battery, a flashlight and a camera, a shovel leaning upright, and a crate holding a dozen spray-paint cans in different colours. Past them are textured cab seats, a steering wheel with a gauge cluster, and a loft bed over the cab. The floor is warm wood planking. A white outline and a "Shovel" label mark what you're aiming at.

## Progress through 1.10.0

The comparison below describes the original 1.8 baseline, not the current implementation. Version 1.9 added loose-item outlines, action rows and cab materials. Version 1.10 adds cupboard/fridge-door and cargo-lid outlines, placed-furniture outlines, 16 original printed labels with paper normals, detailed can lids, slatted crates, and a nine-stop route card/notebook. Reference targets still outstanding include litre-based transfers, house cabinet doors, broader bevel/material work and interior grime/contact lighting. The `--v110` devtest captures the new presentation for review; `--v18` retains vehicle regression coverage.

## The differences (historical 1.8 baseline)

### Models and materials
| Reference | No Man's Drive 1.8.0 |
|---|---|
| Realistic shapes with bevelled edges, wear on the edges and accurate proportions (can lids, nozzle grips, hinged doors) | Procedural meshes made mostly of boxes, tubes and lathes, with hard, sharp edges. Many items still read as blocky (crates, cabinets, the windshield guard, panniers) |
| Every surface has a texture: wood grain, grimy painted metal, cracked concrete tiles, fabric seats | Many parts use flat `color_mat` colours (cab interior, dashboard, plastics, the new cargo box) with no texture or normal map |
| Printed labels on cans, jars, bottles and spray cans | Cans and bottles are plain coloured cylinders, at most with a coloured band |
| Grime, dirt and wear in corners and along floor edges | Only the van body and primer have rust or grime. Interiors are clean, single-tone surfaces |
| Slatted crates with real gaps; jars with lids and contents | Crates are solid boxes or simple frames |
| Plants with leaf cards (potted palm), detailed props (camera, flashlight) | Potted plant and decor are coarse |

### Interaction and feedback
| Reference | No Man's Drive 1.8.0 |
|---|---|
| A white **outline** on the object you aim at, plus a small floating name label at the cursor | No outline. One centred prompt line at the bottom ("[E] …   [G] …") |
| **Context hints on the right**: one row per action with a key cap ("Transfer [E]", "Eat [E]", "Throw [Q]", "Placement Mode [R]") | Every action is packed into one prompt string |
| **Liquids measured in litres** on every container (coolant 3.81/5.00 L, nozzle 27.52/50.00 L) | Containers are whole items: full fuel can, empty fuel can, water bottle. The van tank shows litres, nothing else does |
| **Transfer panel** between two containers, with two gauges and a "Ready for transfer!" state; you hold the nozzle at the filler | A fuel can pours a fixed 10 L at the fuel cap with [E] |
| Cupboard doors on hinges, one door at a time, shelves you can fill and see into | Van cupboards and the new lidded boxes open, but house cabinets are still loot containers you search through a menu |
| Held item shown large and detailed in the right hand, with a textured sleeve | The viewmodel arm is a plain skin-coloured shape; held items are small |
| Hotbar slots show rendered item icons | Hotbar slots show rendered icons (good) but the slots themselves are plain dark boxes |

### HUD and presentation
| Reference | No Man's Drive 1.8.0 |
|---|---|
| Minimal HUD: one green health or stamina bar bottom-left, an objective card top-right ("Main Objective: Reach the Winterland, 5/9" with progress pips) | Five stat bars top-left, a compass strip, a clock and weather top-right, plus a notification log on the left |
| A clear goal shown at all times | No objective or progression system; the open road has no destination |
| Lighting with soft ambient occlusion in corners and warm interior bounce | Interiors are evenly lit, with no contact shadows in corners |

## Rules for future changes

1. **Texture everything you add.** No new flat `color_mat` surfaces on anything bigger than a screw. Use or add a texture in `tools/gen_textures.py` (wood grain, painted metal with grime, plastic, fabric, rubber, concrete tile) with a normal map.
2. **Bevel and wear.** Give boxes rounded or bevelled edges (`Lib.box(..., bevel)` or a bevelled surface-tool helper), and use slightly worn edges on painted metal and wood.
3. **Labels on consumables.** Cans, jars, bottles and spray cans get a label texture band with our own made-up brands, never real or borrowed ones.
4. **Real construction.** Crates have slats with gaps, cupboards have hinged doors and shelves, and jars have lids. Things that open open physically, never through a menu.
5. **Liquids in litres.** Moving toward this: fuel, water, coolant and other fluids live in containers with a capacity and a current amount, shown as "x.xx/y.yy L". Transfers between containers (a can to the van tank, a pump nozzle to the tank, a jug to the radiator) show a two-gauge panel.
6. **Aim feedback.** Loose items have an outline and crosshair label. Key-first prompts have right-side action rows with one key cap per row. Extend the outline and label to other interactable props.
7. **Check in screenshots.** Every visual change gets a devtest screenshot (see `game/scripts/devtest.gd`, for example `--v18`) and is compared against the descriptions above before it ships.

## Priority list toward the bar

These are also tracked in `todo.md` under "Quality pass".

1. Aim outline, floating name label and right-hand action hints.
2. Litre-based liquids for fuel, water and coolant, with the transfer panel and a pump nozzle at fuel stations.
3. Texture and bevel pass on the van interior (cab, dashboard, seats, cupboards, floor), then on houses.
4. Labelled consumables (cans, jars, bottles, spray paint) and slatted crates.
5. House cabinets and wardrobes become physical shelves with doors (moves the existing "make the built-in house cabinets movable" item forward).
6. Detailed first-person hand and sleeve; bigger held items.
7. Ambient occlusion (SSAO or SDFGI on desktop, baked corner darkening on phones) and grime decals in interiors.
8. A light objective track (destinations along the road) shown in a top-right card.
