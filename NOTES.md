# Quality notes: where No Man's Drive is and where it needs to be

**Read this before any change to models, textures, the HUD, items or interactions.** In November 2026 the owner shared five reference screenshots as the quality and detail bar for the game. They show a first-person van survival game with realistic textured models, liquids measured in litres, item cupboards with doors, and a clean context-action HUD. This file lists the gap between those screenshots and the game (first written for 1.8.0, updated for 1.9.0), and the rules that close it.

The target is the **level of quality and detail**, not a copy. Never copy another game's name, logos, characters, UI artwork, product labels (for example its baked-beans brand) or levels. Use our own designs, brands and layout. The reference screenshots are not committed to the repo; the descriptions below stand in for them.

## What the reference screenshots show

1. **Refuelling at the fuel cap.** You hold a pump nozzle on a hose up to the van's fuel filler. A panel shows both containers side by side, each with a level gauge: "Nozzle, Gasoline 27.52/50.00 L" and "Fuel Tank, Gasoline 26.19/50.00 L", with "Ready for transfer!" underneath. The filler has a hinged flap and a round cap. Behind it, the van's white body has visible grime and texture. Right-hand action hints read "Transfer [E]", "Throw [Q]", "Placement Mode [R]".
2. **Coolant in a crate.** A slatted wooden crate (real gaps between the planks) sits on a cracked, tiled concrete floor. A green coolant bottle and a water bottle stand inside it. Hovering the bottle shows a tooltip with a liquid-level icon: "Coolant, 3.81/5.00 L". Objects you can grab get a small label and a hand cursor.
3. **Pantry cupboard, holding a can.** A wooden cabinet with an open door has cans and jars on its shelf; water bottles, an orange, a soda can, spanners and chocolate bars stand on top. The held can is large and detailed in the right hand, with a printed label and a ribbed lid, and the sleeve and hand are textured. Hints read "Eat [E]", "Throw [Q]", "Placement Mode [R]", "Take Off Backpack [B]". The hotbar shows real item icons (a spanner, a can).
4. **The same cupboard with both doors open.** Each hinged door turns on its own hinge and shows a white outline when you aim at it. Inside are shelves, a divider, and jars and cans with labels. Wood grain runs the right way on every panel, and the wall has dirt and stains near the floor.
5. **Inside the van, the living area and cab.** A big window looks out on grass. There's a potted palm, wooden bedside cabinets, corner shelves holding a battery, a flashlight and a camera, a shovel leaning upright, and a crate holding a dozen spray-paint cans in different colours. Past them are textured cab seats, a steering wheel with a gauge cluster, and a loft bed over the cab. The floor is warm wood planking. A white outline and a "Shovel" label mark what you're aiming at.

## The differences

1.9.0 worked through the whole first priority list. The tables show where each point stands now.

### Models and materials
| Reference | No Man's Drive 1.9.0 |
|---|---|
| Realistic shapes with bevelled edges, wear on the edges and accurate proportions (can lids, nozzle grips, hinged doors) | Cans have rolled seams, ribbed lids and pull tabs; the pump nozzle has a rubber grip, trigger guard and swivel; cupboards have hinged raised-panel doors. Older procedural items are still mostly boxes, tubes and lathes |
| Every surface has a texture: wood grain, grimy painted metal, cracked concrete tiles, fabric seats | The van interior material set is fully textured (wall board, plastic, metal, seat fabric). New textures: wood grain, grimy paint, cracked tiles, crate wood, plastic, seat fabric. Exterior trim, house fixtures and the gas-station shop still have flat colours |
| Printed labels on cans, jars, bottles and spray cans | Done for 16 products with our own brands (`labels.png`). Jars don't exist yet |
| Grime, dirt and wear in corners and along floor edges | Baked grime and contact-shadow strips along floor edges in the van and every house room |
| Slatted crates with real gaps; jars with lids and contents | Slatted crates everywhere a crate appears. No jars yet |
| Plants with leaf cards (potted palm), detailed props (camera, flashlight) | Not done: the potted plant and decor are still coarse |

### Interaction and feedback
| Reference | No Man's Drive 1.9.0 |
|---|---|
| A white **outline** on the object you aim at, plus a small floating name label at the cursor | Done: white outline, name and litres under the cursor |
| **Context hints on the right**: one row per action with a key cap | Done: one row per action, key caps (button names on touch) |
| **Liquids measured in litres** on every container | Done for fuel, coolant, canteens, the coffee flask and the pump nozzle. Water bottles, juice and milk are still whole items |
| **Transfer panel** between two containers, "Ready for transfer!"; you hold the nozzle at the filler | Done at the fuel cap, radiator, sink and pump, with a nozzle on a hose. The transfer is instant rather than poured over time |
| Cupboard doors on hinges, one door at a time, shelves you can fill and see into | Done for house kitchens, fridges, wardrobes and medicine cabinets. Van cupboards open too but have plainer doors |
| Held item shown large and detailed in the right hand, with a textured sleeve | Done: jointed hand with nails and a watch, a sleeve that matches your jacket, held items bigger |
| Hotbar slots show rendered item icons | Icons and a litre gauge; the slots themselves are still plain dark boxes |

### HUD and presentation
| Reference | No Man's Drive 1.9.0 |
|---|---|
| Minimal HUD: one bar bottom-left, an objective card top-right with progress pips | Objective card with pips, done. The five stat bars, compass, clock and notification log are still there (a minimal-HUD option is planned) |
| A clear goal shown at all times | Done: nine road-trip stops with signs and supply crates |
| Lighting with soft ambient occlusion in corners and warm interior bounce | The Compatibility renderer has no SSAO, so corners get baked contact-shadow strips. No light bounce yet |

## Rules for future changes

1. **Texture everything you add.** No new flat `color_mat` surfaces on anything bigger than a screw. Use or add a texture in `tools/gen_textures.py` (wood grain, painted metal with grime, plastic, fabric, rubber, concrete tile) with a normal map.
2. **Bevel and wear.** Give boxes rounded or bevelled edges (`Lib.box(..., bevel)` or a bevelled surface-tool helper), and use slightly worn edges on painted metal and wood.
3. **Labels on consumables.** Cans, jars, bottles and spray cans get a label texture band with our own made-up brands, never real or borrowed ones.
4. **Real construction.** Crates have slats with gaps, cupboards have hinged doors and shelves, and jars have lids. Things that open open physically, never through a menu.
5. **Liquids in litres.** Every fluid container is listed in `Data.LIQUID` with a capacity, and its current amount travels with it (the `l` key on a hand slot, `litres` on a world item, `l` in saves). Moving liquid goes through `Game.pour_held_into` / `Game.fill_held_from`, and every place you can pour gets a `transfer_info()` that returns `Game.transfer_panel(...)` so the two-gauge panel shows. Show amounts as "x.xx/y.yy L".
6. **Aim feedback.** Anything you can interact with gets the outline automatically (`Items.set_outline`). Give new interactables a short name (`player._target_name`) and write prompts as "Name — info   [Key] Action   [Key] Action" so the HUD can split them into the cursor label and the action rows. Don't put the key in the middle of a sentence unless it really is a sentence.
7. **Check in screenshots.** Every visual change gets a devtest screenshot (see `game/scripts/devtest.gd`, for example `--v19`) and is compared against the descriptions above before it ships.

## Priority list toward the bar

The first list (aim feedback, litres, interior textures, labels and crates, physical cupboards, the hand, contact shadows, the objective track) shipped in 1.9.0. The next round is tracked in `todo.md` under "Quality pass, round two":

1. Hold-to-pour transfers with sound and moving gauges.
2. Litres for water bottles, juice and milk; can-to-can transfers.
3. Jars with lids and visible contents; potted palm with leaf cards; detailed shelf decor.
4. Texture and bevel pass on the remaining flat-coloured surfaces (exterior trim, house fixtures, the gas-station shop).
5. Reference-style hotbar slots and a minimal-HUD option.
6. A left hand for two-handed items, and pick-up and put-down animations.
7. The van's cupboards with the house cupboards' panelled doors.
