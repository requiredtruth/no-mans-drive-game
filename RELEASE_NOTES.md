# No Man's Drive 1.15.0 — Dedicated multiplayer, dress-up and gardening

- New `./server.sh` boots a headless Godot ENet server on Linux, downloading the matching engine once if necessary. Use `PORT=24680 SEED=4242 MAP=everything ./server.sh`. Persistent server saves go to `server-data/`.
- Join friends from Android with a server domain or IP, optionally followed by a UDP port. Forward the port on the server/router; the server script does not open your firewall itself.
- Reliable host relay for player positions and character looks, and for world construction/plant edits. No longer dependent on direct client RPCs for seeing other players.
- Create a persistent name (`Human 1`–`Human 999` randomized on first run). Change your username or character from the main menu and pause screen.
- Original live 3D character creator with gender choices, many hairstyles and colors, shirts and dresses, trousers and skirts, footwear, hats, glasses, bags, jewelry, makeup, and skin palettes. Your visible multiplayer puppet reflects your choices.
- 32 additional seed/crop pairs: vegetables, herbs, berries and ornamental flowers including roses, daisies, lavender, sunflowers and orchids. Raised garden bed is buildable, waterable and harvestable.
- Existing vehicle repair, survival, world generation, saves, and full Everything start map retained.

**Known limits:** The original world network code was basic; this is its first dedicated-server expansion. Shared world changes are relayed but the server is not a secure public MMO, and 15-peer capacity is a configured limit, not a benchmark. On-device multiplayer performance and reliability still need testing.
