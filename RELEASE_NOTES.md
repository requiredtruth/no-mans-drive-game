# No Man's Drive v1.15.5 — True Starter survival map

- **Starter is the default new-game map**, with only **one randomly chosen four-wheel vehicle** at the initial site. Choices: van, sedan, pickup, utility work truck, off-roader, compact RV, touring RV and box truck. Six-wheel trucks and double-long RVs remain discoverable later, not starting vehicles.
- The single starting vehicle has a fitted engine, working battery, steering, driver seat and all four tires, but randomized **medium/worn condition** (roughly 38–74% for engine/tires/battery/body), limited gasoline (12–27 L), and no upgrades.
- Only **3–5 random loose items** appear close to the vehicle; no free extra cars, assembly workbench, trailer, huge item depot, or artificial depot clearing. Local roadside POI vehicles are suppressed near the first 360 m, preserving discoveries farther down the highway.
- World seed determines the initial vehicle type, condition and handful of supplies. Saves store the exact primary vehicle kind, wear, location and cargo, so continuing a game does not reroll them.
- **Regular** remains the prior broken-van assembly-lot mode with its supplies and starter traffic; **Everything** retains the fully fitted flagship RV, all vehicle types, trailers and item depot. Existing saves continue to load in their original mode.
- The single starter vehicle uses the game's primary save slot, compass and multiplayer synchronization, including when it is not a van. The notebook and cheats handle other vehicle types safely.
- The Linux server's default map is now Starter; set MAP=regular or MAP=everything for the original modes. No change to UDP port or server requirements.
