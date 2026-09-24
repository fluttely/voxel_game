# Roadmap — stages and status (Flutter port)

One stage = one commit or a few. A stage is DONE only when it was seen running (screenshot
probe or interactive run). Status: ☐ todo · ◐ in progress · ✅ done. The stage numbers are
the Godot POC's, so the two roadmaps line up.

## Design decisions (settled, do not re-litigate)

- **Look**: flat vertex colours, per-voxel ±5% colour noise, baked AO (4-level) in
  the vertex colour; since stage 31 sky + block light ride the second UV set and the terrain
  shader (`shaders/terrain.frag`, flutter_scene's standard lit shader plus the voxel light term)
  scales the sky half by the time of day. PBR roughness 1, specular 0, lit by one sun (Godot's
  0.6) with cascaded shadows and a constant-diffuse ambient. No textures. Sun scale 0.6,
  ambient 0.6, ACES; distance fog exponential-squared in the horizon colour, from 72% of the
  render distance to full at 97%, so the last loaded chunks dissolve into the sky and the
  rest stays clear (s7, s29). In first person the walk is
  carried by the hand in the corner of the screen (`HandView`, s9), not by the eye, which only
  nudges.
- **World**: dense chunks 16×128×16 (`Uint8List`, byte = block index), sea level 46, radius 8
  streamed, 3×3 neighbour ring generated before a chunk meshes. Generation + meshing on a
  pool of 3 isolates; one `Node` per chunk with up to three mesh children (solid, cutout,
  liquid), `shadowStatic`, replaced whole on remesh.
- **Block table is code** (`lib/src/core/blocks.dart`), index order is the save contract —
  append only, identical to the Godot table.
- **Player / RPG / Survival / Save**: as the Godot POC (see its ROADMAP). Save bytes and JSON
  keys are the same, so a `worlds/<name>` folder is interchangeable between the two.
- **Verification without a screen**: `--screenshot=<png> --frames=N` renders and quits; the
  PNG is read back. Never screencapture the desktop.

## Stages

| # | Stage | Status | Notes |
|:--|:---|:---|:---|
| 0 | Worktree + project skeleton (`flutter create`, `flutter_scene`, Flutter GPU on, args forwarded) | ✅ | |
| 1 | Block/item/recipe/species tables | ✅ | `lib/src/core/`, unit-tested |
| 2 | `TerrainGenerator` + `ChunkMesher` in pure Dart on isolates | ✅ | `lib/src/world/`, unit-tested |
| 3 | Streaming world + delta save + screenshot probe; first screenshot | ✅ | 225 chunks in ~1 s |
| 4 | Player: body, third-person camera, voxel model, mine/place, highlight, swim/climb/glide/ladders | ✅ | `lib/src/player/` |
| 5 | HUD, hotbar, inventory + crafting UI, drops and pickups, chests with loot | ✅ | `--open-inventory` seen |
| 6 | Mobs (17 species), AI, melee/bow/staff combat, abilities, XP, levels, classes, boss troll | ✅ | `--strike`: zombie 18 → 8 hp |
| 7 | Day/night, spawn manager, hunger, fall/lava/drowning damage, death + respawn | ✅ | `--time=0.9` seen |
| 8 | Main menu (new world: seed + class, continue), pause menu, save/load (autosave 60 s) | ✅ | Flutter widgets |
| 9 | Dungeons, towers, camps with loot chests; boss in the dungeon | ✅ | generator port |
| 10 | Armor from inventory; glider; ranged classes | ✅ | |
| 11 | Quests, minimap, wolf companions, villages + traders, procedural SFX (SoLoud), debris, mob levels | ✅ | `--map` seen |
| 12 | Rivers, falling sand, beds, farming, fly mode F5, boss bar, F2 screenshot, footsteps, pause settings | ✅ | `--fly` aerial probe |
| 13 | **Play it by hand** — mining feel, combat feel, inventory clicks, trading, sleeping, farming | ☐ | needs a human at the keyboard; pointer lock only verified by code |
| 14 | Weapon rarity + random bonuses, spawner blocks, TNT chains, the Boomer, roaming bosses | ✅ | |
| 13b | Ranged combat: simulation-owned projectiles, staff spray / arc, bow / fan, 8-way volley | ✅ | `--fire=secondary` with `--class=mage` seen |
| 16 | Doors, wall torches, boats, enchanting table, sleeping animation | ✅ | `--stage16` seen |
| 17 | **Close the stage 15 gaps.** Melee hit owned by the simulation: `meleeStrike(dir, dmg, followUp, attacker)` runs the reach check from the attacker's own centre; a client sends `melee` and the host resolves it against the puppet it owns. Mobs hunt the nearest body in `targets()` (the local player + `puppetBodies()` on the host); a `RemotePlayer` answers `centre()` / `isDead` / `takeDamage()` through the `Target` interface and forwards the damage to its peer as `hurt`; damage numbers reach clients as `dmg`. Probe flag `--strike`. | ✅ | re-verified 2026-09-14: solo zombie 18 → 8 at 2.01 m, the Godot figure; the host-side resolve and `hurt` were seen in the stage 15 two-process run. Engine difference: Godot splits mob packets into ≤6-row unreliable ENet packets with an epoch to stay under the MTU; TCP + JSON lines is a stream, so one `mobs` line carries every row and needs no split |
| 18 | **RPG depth + weather.** Status effects (poison, burning, slow, regen, speed, strength, resistance, haste, well fed; chips on the HUD, ticks as coloured damage numbers), potions brewed at the brewing stand, talents (six shared + one signature per class, three ranks) spent in the journal (J), elite mobs (8% of hostiles: Swift / Sturdy / Venomous / Burning / Chilling / Giant, an aura light, ×2.5 XP), dodge roll (Left Alt, 0.4 s invulnerable), 20 achievements, waypoint blocks that teleport, a bestiary, and weather (rain / storm / snow on `flutter_scene`'s `ParticleEmitterComponent`, overcast sky, lightning flash + thunder). Probe flags `--stage18`, `--weather=`, `--journal=`. | ✅ | seen: storm with rain streaks, effect chips, the journal's talent tab; headless: 2 effects, Venomous elite spider, a talent spent, 2 waypoints + travel, dodge invulnerable |
| 19 | **Sub-block shapes in the mesher.** `slab` (bottom half), `fence` (post plus rails toward every fence or opaque neighbour, across chunk borders through the padded fill), `stairsN/E/S/W` (low step in front, high step behind, four ids behind one item, orientation from the placer's yaw). Blocks oak/stone/cobblestone slab, oak fence, oak/stone stairs, and their recipes. Probe flag `--stage19`. | ✅ | face counts unit-tested; bodies collide with all three as a full block (`VoxelBody` knows no sub-shapes) → stage 22 |
| 20 | **Fishing, horses, shears, buckets.** Fishing rod: right click casts a `Bobber` at the first water cell along the aim ray (a liquid raycast beside the solid one), a line runs from the hand, the bobber dips after 3–8 s and a second right click inside 1.5 s catches 70% raw fish / 10% salmon / 15% junk / 5% treasure. Horse (plains + forest, `mount`), tamed with wheat or an apple, F mounts within 3.5 m and WASD drives it at 8.5 m/s (sprint ×1.4, Space jumps); a ridden mob skips its AI and a tamed mount follows without fighting. Shears drop 1–3 wool and shrink the sheep for 120 s, and break leaves instantly into themselves. Buckets scoop and pour water or lava, and milk a cow. Probe flags `--stage20`, `--ride`. | ✅ | seen: the rider on the horse's back, the line down to the bobber on a fresh water block, the sheared sheep beside them; `--ride` moved the horse 0.85 m in ten frames at -8.6 m/s, the same figures the Godot POC reported |
| 21a | **Four more world structures** in the generator, on a second 4x4-chunk grid with its own hash; a candidate is dropped within 48 blocks of any primary structure so the two layers never overwrite each other. **5 ruin** (broken stone/mossy-brick walls 2-4 high around a cracked cobblestone floor, a chest half the time), **6 well** (3x3 cobblestone ring, water 4 deep, two fence posts, plank roof), **7 abandoned mine** (fenced head frame, ladder shaft to y 24, a 3x3 corridor 20-30 long with log-and-plank beams every 4 and torches on every second, iron/gold veins in the walls, a chest at the end, a spawner a third of the time), **8 desert temple** (sandstone step pyramid 9x9, a hollow chamber with two chests and a lamp, TNT under its floor, a south entrance). Probe `--stage21a` (`--kind=5..8`, `--biome=N`, `--fp`). | ✅ | seed 42 has a ruin 29 m from spawn, the same as the Godot POC; the temple and the mine corridor (beams, torch glow, a gold vein, the spawner at the end) both captured |
| 15 | **Multiplayer probe** (TCP + JSON lines on 7777, host-authoritative, puppets, replicas, host clock) | ✅ | two processes: the host captured peer 2's puppet beside it, the client got `hello` (seed + 20 edit bytes), 6 mob puppets, the host clock and the host's puppet; a zombie spawned beside the puppet hit the client (HP 26/30) through `hurt`. Since `CL-001` the sockets themselves are `voxel_engine`'s `NetHost` / `NetConnection`; the Dawnforge protocol above them is unchanged |

| 21b | **Replicate what stage 15 left local.** Drops: the host owns every `ItemDrop`, a client's spawn becomes a request, a client draws replicas that only fall and spin, and a drop pulled to a peer's puppet is handed over into that peer's own bag. Chests: the inventory lives on the host, a client opens a view and every grid click travels as the whole grid (last writer wins). Weather: the host broadcasts its roll on change and every 10 s. Mounts: mob rows carry `tamed` and `riddenBy`, a puppet copies both, a rider's puppet sits on that horse's puppet, and a client's ride input travels inside its pose. Effects: a mob's species or affix effect on a puppet reaches the peer's own player. Probe `--stage21b` (with `--wait-peer`). | ✅ | two processes: the host gave peer 2 iron_ingot x2 and reported it picked up; the client's capture shows the host puppet riding its horse puppet on the stone pad in a storm, poisoned, with the two ingots in its bag and the host's chest read as 3 apples |
| 22 | **Sub-block collision + liquid flow.** `Blocks.collisionBoxes(index)` gives every solid block its boxes in 0..1 space (slab = bottom half, fence = the 6/16 post 1.5 tall, stairs = bottom half + the mesher's back half); `VoxelBody` sweeps its AABB against those boxes instead of whole cells (`_solidBoxesAt` scans one row below the feet for the fence's extra half, `_resolveAxis` lands on the face of the box that was entered) and `tryStepUp` tries 0.52 then 1.02, each also nudged 0.05 into the blocked direction so a half step never beats a wall. `wallAhead` / `overlapsBlock` stay cube-based. **Liquids**: two appended ids `water_flow` / `lava_flow` (`Blocks.liquidKind` answers water / lava for both forms, `isLiquidSource` tells them apart); `VoxelWorld.tickFlow` runs on the host / solo only (`flowEnabled`), every 0.25 s for water and 0.6 s for lava, at most 400 cells a tick, over a queue only `setBlock` feeds. A cell falls first, spreads sideways only on a solid or a source (water 4 steps, lava 2), a flowing cell with no strictly closer feeder becomes air, lava touching water hardens to cobblestone. Buckets scoop sources only; every flow edit rides the existing per-block `block` message. Probe flag `--stage22`. | ✅ | seed 42, same site as Godot (x0 11, y0 66, z0 8): slab top 67.501, stairs top 68.001 with max vy 0 (no jump), fence stopped at 20.074 against the 20.375 post face with a jump peaking 1.35 m, water 43 cells at max dist 4 (42 flow writes), 0 after the source went, lava + water → 7 cobblestone: every figure inside Godot's. The capture shows the pad, the second puddle, the cobblestone crust, the slab, the stairs against its plank and the fence post. Unit-tested headless in `test/stage22_test.dart` (boxes, the three walks, a two-plank wall that a half step must not beat, 43 cells / drain / hardening, a client world that never flows) |
| 23 | **Temple boss + trap, loot tables, second abilities, three mobs, durability.** **Mummy King** (`mummy_king`, boss, 120 hp, speed 1.8, hits apply `slow`, XP 48, drops 2–5 gold + a guaranteed `ancient_blade`, a tier-4 14-damage sword) wakes once per temple when the player is within 6 m of the chamber centre (`Game._checkStructures`, key = chamber + `templeBossKeyY` 1000 in `_bossesSpawned`, so it rides the save). **Pressure plate** (appended id after `lava_flow`, dark `slab`, passed through `generatorIds()` last; the generator sets the temple chamber floor centre to it over the buried TNT): `Game._tick` checks the feet cell of the player, every mob and every pet each simulation tick on host / solo and, on `overlapsBlock`, clicks once per visit and lights the TNT below through `igniteTnt`; `litTntCount` / `probeDefuseTnt` read and undo the fuses. **Loot tables** in `lib/src/game/loot.dart` (`LootTables.tables` temple / mine / ruin / well / dungeon / camp as `LootEntry(item, min, max, chance)`, `roll(table, Random)`, `tableNear` = the nearest structure within 48 m, else camp); dungeon and temple chests keep the 45% bonus weapon. **Q abilities** (`GameAction.ability2`, `PlayerClass.ability2` / `mana2` through `manaCost`): Warrior *Shield Bash* (12 m/s lunge, every mob in the 3.5 m half-space ahead takes 0.8x melee and `Mob.stun(2)`: AI frozen, model tinted yellow), Ranger *Volley* (5 arrows over 40°), Mage *Frost Nova* (4 damage + `slow` 4 s within 5 m, half speed), Rogue *Smoke Bomb* (3 s invulnerable + Swiftness, mobs within 12 m `loseTarget(3)` and cannot aggro); the HUD stacks `[Q]` under `[R]`. **Mobs**: `bat` (cave only, `maxY` 50 through `Species.candidates(..., y)`; `flying`: no gravity, a new random 3D heading every 0.2–0.6 s, dives when nothing solid is 3 m below, steers at the target's centre when chasing), `bear` (forest, neutral, 40 hp, hits 6), `ghost` (ruins at night only through `_tickRuinGhosts`, at most two per ruin; `VoxelBody.noclip` skips the sweep, 45% alpha tint, slow flier, `slow` on hit); weight 0 keeps structure-only rows out of the spawner, `Spawner.forceSpawn` places one. **Durability**: weapons get `durability` 40 + 50 x tier (tools already 60 x tier²), the live count is `ItemStack.dur` (-1 = never worn, saved as `dur` only when set), `Player._wearHeld` takes one per melee swing, arrow, fan and tool-broken block, at 0 the slot empties with a break sound and a notice; the hotbar draws a green→red bar under a worn icon. Probe flag `--stage23` (with `--kind=8`; builds a 5x5x3 chamber beside the player if no temple is within 48 chunks). | ✅ | seed 42, same temple as Godot, 494 m out at (414, 54, -274): `Mummy King Lv 3 hp=163` (path temple, plate (414, 54, -274)), `tnt lit=true` after three ticks on the plate, Shield Bash 3/3 stunned, Volley 2/3 hit, Frost Nova 3/3 slowed, Smoke Bomb 3/3 lost the player, bat / bear / ghost alive after 60 ticks and the ghost drifted 2.04 m out of solid stone, iron sword 190 → 185 over five swings and the slot emptied from `dur` 1: every figure Godot's. The loot lines are seeded but not Godot's (Dart's `Random(23)` is not Godot's RNG). The capture, first person in the south corridor: the Mummy King between the two chests under the lamp, its boss bar on top, `[Q] Shield Bash (10s)` under `[R] Whirlwind`, "Your Iron Sword broke!" in the notices. `--strike` unchanged (18 → 8). Unit-tested in `test/stage23_test.dart` (plate id, durability numbers, wear + save round trip + break, loot ranges / determinism / real items, spawn filter, noclip) |
| 24 | **Save what lived outside the save, maps with markers, the quest tab, a settings screen, the bed checked.** **Persistence**: `saveGame` also writes Godot's keys `boats` (`pos`, `yaw`), `pets` (every tamed `Mob`: `species`, `pos`, `hp`, `max_hp`, `level`, `affix`, `tamed`, `name`, `yaw` through `Mob.toJson` / `fromJson` / `restoreTamed`), `mount` (the index of the ridden pet, restored through `Player.mountHorse`, so the rider boots seated), `drops` (`item`, `count`, `bonus`, `pos`), `visited` (`"x,z"` for every chunk the player stood in, marked once a second) and `structures` (`"x,y,z"` → kind for anything within 48 m of the once-a-second `_checkStructures` pass); a restored boat, drop or mob waits for its chunk before its physics run; the save's seed wins over the menu default unless `--seed=` is given. `--slot=<name>` points a run at `worlds/<name>`. **Maps**: M cycles minimap → world map → off (`Game.cycleMap`); both draw markers (`HudPainter._drawMarkers`): cyan diamond waypoints, a coloured square per structure kind 1–8, brown dots for tamed mounts, a white dot for the spawn; the world map (`WorldMap`, one pixel per block, rebuilt every 2 s through `decodeImageFromPixels`) covers every loaded chunk plus every visited one (flat grey out of the window), with labels, a "You" arrow and a legend. **Journal**: a fifth tab `Quests` (`JournalTabs.questEntries`): done greyed with a tick, the active one lit with a progress bar, the rest dim. **Settings** (`lib/src/game/settings.dart`, `settings.cfg` beside `worlds/` in Godot's `ConfigFile` text, loaded in `main`): the Escape menu holds render distance 4–10 (`Game.applyRenderDistance` + `VoxelWorld.trimWindow`), mouse sensitivity, FOV, master volume (`SoLoud.setGlobalVolume`), weather on/off (`Weather.setEnabled`: off forces Clear), an FPS overlay (when F1 text is hidden), Resume / Save / Save & Quit; the world never pauses. **Bed respawn** was already right; the probe proves it. Probe `--stage24` (with `--slot=probe24`): the first session builds the scene, saves, writes `probe24.flag` and asks the view for a fresh session; the second sees the flag, loads that save and prints the verify half. `--open-map` / `--open-settings`. | ✅ | seed 42: pre-save and post-load both `boats=1 tamed=2 drops=2 mounted=true waypoints=1 visited=3`, `horse pos delta=0.00`, `markers: waypoints=1 structures=1 mounts=1` (the ruin at (19, 56, 36), 30 m off spawn), `quests tab entries=12 active=Gather wood`, `radius 8->6 chunks loaded before=289 after=169`, `weather off -> Clear`, `settings.cfg written=true` (to `settings_probe24.cfg`), `respawn at bed … delta=0.00`: every line Godot's. Seen: the world map with You / Spawn / Horse / Waypoint 1 / Ruin labelled over the coast, the legend under it, the minimap beside it with the same markers; the menu (`--slot=probe24 --open-settings`) with four sliders, two switches and four buttons over the running world, the restored horse and boat behind it; the journal's Quests tab (`--journal=4`). `--strike` unchanged (18 → 8 at 2.02 m). Unit-tested in `test/stage24_test.dart` (boat / drop / tamed-mob keys and round trip, visited + structures codec, settings file + clamps, quest entries, trim) |
| 25 | **The host owns what moved on its own; the client predicts what it touches.** **Drop poses**: the host streams `drop_poses` (10 Hz, only drops that moved > 0.05 m, ≤40 rows a message) and an `ItemDrop.replica` no longer simulates — it lerps to the streamed pose (`setNetPose`, snaps beyond 8 m). **Bag overflow**: `Inventory.roomFor(item, count)`; the client's `give` answers `give_rest` for what did not fit and the host drops it at the puppet's feet (2 s pickup delay); a client re-declares its bag as `bag` 0.2 s after any change (`Player.bagDirty`) and the host pulls a drop toward a puppet only when that declared bag has room (`Net.peerHasRoom`). **Chests**: `chest_set` is one slot (`slot`, `stack`, `from_bag`), accepted only from a peer that has the chest open on the host and only when what enters is paid for — from the declared bag (debited) or from the escrow of what that peer took out and still holds (`Net.chestEditVerdict`, pure); a refused edit gets the standing state re-sent; `InventoryScreen` tracks `_cursorFromChest`. **Boats**: host-owned like drops (`Boat.netId` / `replica`, `boat` / `boat_poses` (10 Hz, moved > 0.02 m or turned) / `boat_free`, late joiners get the list after `hello`); a client's `spawnBoat` is `boat_req`; boarding a replica is `board_req` (`Player.boardBoat` / `leaveBoat`), the steer rides in the pose's `ride` field (x = steer, z = throttle) and the host's boat carries the puppet; breaking one is `break_boat_req`. **Crops**: a client no longer runs `_growCrops`; the host registers a `wheat_0` a client placed. **Bobber**: every peer streams its own bobber at 5 Hz (`bobber`, `bobber_gone`); the others draw a `Bobber.replica` hanging from that peer's puppet hand. **Flow batch**: `Game._tick` wraps `tickFlow` in `Net.beginBlockBatch` / `endBlockBatch`, so a tick's cells leave as one `blocks` message (flat x, y, z, id, ≤200 cells a message); single edits stay on `block`. **Prediction**: a client's edit is applied at once and sent as `block_req` with a `seq` (`BlockPrediction`); the host answers `block_ack` with the id that stands and the client rolls back when it differs; a host `block` / `blocks` for a cell with a pending prediction waits for the ack. Host flag `--reject-one` refuses the first client edit. Probe `--stage25` (host + client, `--wait-peer`; the host takes `--reject-one`). | ✅ | two processes, seed 42, Godot's site cells: host `drop poses sent=9` (Godot 10), `give rest spawned=1`, `chest edit rejected(not open)=1 accepted=1`, `boat spawned net_id=1 client aboard=true`, `flow batch rpcs=4 cells=24`, `rejected client edit seq=1`, `crop (5, 50, 8) grew to wheat_1 through setBlock`; client `bag got=1 rest dropped seen=true`, `chest state slots=3` (Godot 2: the loot roll is Dart's RNG), `aboard boat net_id=1 moved=1.95` (Godot 1.95), `predicted=1 rollbacks=1 (cell a back to stone: true, cell b oak_planks)`, `replica drop delta to host pose=0.000 (replicas 2)`, `flow cells seen=24`, `bobber replica of host seen=true`, `crop reads wheat_1`. The client's capture: the host puppet on the pad with its line down to the replica bobber in the basin, the boat the client rowed, the apple replica on the basin wall. `--stage21b` pair and `--strike` (18 → 8 at 2.02 m) unchanged. Unit-tested in `test/stage25_test.dart` (`roomFor`, prediction bookkeeping, chest accounting, the walled pool as 24 cells in 4 batches, the 200-cell split, replica lerps). Simplifications are Godot's (per-slot chest check with escrow, a trusted bag snapshot, prediction covers `setBlock` only, boat poses carry no velocity). s31: an edit from the other side is never dropped in a chunk the receiver has not loaded; it waits in the delta (`VoxelWorld.storeEdit`), and a `--radius=2` client that joined mid-build held the host's 9830 cells (7675 before) |
| 26 | **Swamp and jungle, villages with traders, ambient music.** **Swamp** (biome 7, now low and flat: `surfaceHeight` presses the swamp climate band to two blocks over the sea): one-deep pools (`_swampPool`, a new `_detail` noise → water over `mud`), mud / clay / grass top patches, willows (`_placeWillow`), `reeds` on every pool edge. **Jungle** (biome 8, `t > 0.22 && hum > 0.28`): `jungle_log` trees 8–14 tall under a radius-3 canopy with `vines` hanging 2–5 below the rim, dense `fern`, `melon` patches (breaks into 3–5 `melon_slice`, food). Six blocks appended after `pressure_plate` (`mud reeds jungle_log vines fern melon`), `generatorIds()` extended at the end (+ `bed farmland wheat_2 oak_slab`). Maps tint the two biomes (`Hud.mapPixel`, biome sampled per 4×4 cell, shared by the minimap and the world map). **Spawns**: `slime` (12 hp, `splits` into two `slime_small` on death), spider and slime ×2.5 in the swamp (`SpeciesDef.biomeWeight`, `Species.weightIn`), `parrot` (passive flier, tamed with wheat seeds, hovers over its owner) and `ocelot` (neutral, 6.8 m/s) in the jungle. **Village** (kind 4, plains / forest only, trees felled in a radius 19): 4–7 huts (`_hutCount` / `_hutAt` ring) with a cobblestone floor, plank walls, slab roof, door gap, torch, bed and chest (`LootTables.tables['village']`, `tableByKind[4]`), gravel paths to the well, a fenced wheat plot; 3–5 `villager`s (`persistent`: never despawn, saved in `pets` with `trades` and `home`, turn back beyond `Mob.homeRadius` 16). **Trade**: each villager rolls 3 offers from `Mob.tradePool` (`TradeOffer`); F opens `ScreenKind.trade` (`TradeScreen`, a row per offer, click to trade through `Game.tradeRow`, Esc / F closes). **Music** (`lib/src/game/music.dart`): moods Meadow / Dunes / Jungle / Frost / Marsh / Deep (+ " Night": minor pentatonic, 0.8× tempo), picked once a second by `Game._updateMusic`, a `♪ <mood>` notice on change. Probe `--stage26` (`--shot=biome|village|trade`, `--kind=4` reaches a village through the 21a helper). | ✅ | seed 42, every generator figure Godot's: `swamp=48 jungle=44` chunks in the window; swamp `mud=768 pools=391 reeds=110` at chunk (-3, 3); jungle `jungle_log=458 vines=1413 fern=335 melon=20` at (2, 5); village at (-165, 152) `huts=4 chests=4 beds=4`. Random rolls are Dart's: villagers 4 or 5 (Godot 5), the probe's first offer `gold_ingot x1 -> bread x4` (Godot `gem_shard x3 -> diamond x1`), traded through the screen; slime split children=2; parrot tamed after 1–6 seeds (Godot 2); ocelot 6.8; moods Meadow → Meadow Night → Jungle → Deep, loops rendered and live on SoLoud (`playing=true`). Seen: the jungle (tall trunks, ferns, canopy, `♪ Jungle`), a swamp pool with reeds and willows (`♪ Marsh`), the village from a hover (four huts with slab roofs, gravel paths, villagers, `A village! F on a villager to trade`), the trade screen with three rows. `--strike` unchanged (18 → 8 at 2.02 m). Unit-tested in `test/stage26_test.dart` (block order, seed 42 swamp / jungle counts, village ring + a chest and bed per hut, offers + trade, villager save, weights, moods + a rendered loop) |
| 27 | **Redstone-lite.** `Circuits` (`lib/src/game/circuits.dart`, owned by `VoxelWorld`, host-only through the `flowEnabled` gate the flow already uses, ticked every simulation step inside the flow's `blocks` batch, recompute at most every 0.1 s): every state is a block id appended after the melon in Godot order (`redstone_ore`, `lever_off/on`, `button/_on`, `wire_off/on` — new `BlockShape.wire`, a 1/8 slab through the mesher's `_subBox` —, `redstone_lamp_off/on` (light 14), `iron_door_z/x` + `_open` mirroring the wooden door, `piston_n/e/s/w` + `_on`), so a flip is a plain `setBlock` and meshing, the save and the network batch come free. Sources: a lever on, a button for 1 s (`touch` starts the timer when `button_on` lands, from any side), a pressure plate while a body stands on it (`Game`'s plate check now collects the pressed set and hands it to `setPressedPlates`; the temple's TNT ignites through `onTntPowered` -> `igniteTnt`). Power runs along wires at strength 15 beside a source, one less per cell (15 cells reach, `strengthAt`); wires link on the same plane plus one step up/down along a block edge (the staircase rule). A live wire or a source powers its six neighbours: lamp on, iron door open (both halves), piston extends (pushes the block in front one cell when the cell past it gives way; the pushed block stays on retract), TNT ignites. An edit on or beside a circuit block marks its cell dirty; the tick floods every wire network the dirty cells touch (capped at 400) and recomputes it from scratch. Items: `redstone_dust` from the ore (veins below y 30 at about a third of coal's share), recipes for lever, button, wire x4, lamp, iron door, piston; RMB toggles a lever or presses a button (`click`), doors creak (new `door` voice); pistons and iron doors take the placer's facing like stairs; a wire needs a solid below like a plant. Strong emitters (light >= 10) draw on a fourth `glow` surface with an `UnlitMaterial` so a lamp reads at night. Probe `--stage27 --slot=probe27` (two boots like stage 24; `--time=0.05` for the night capture). Unit tests `test/stage27_test.dart`. | ✅ | seen on seed 42, same site as Godot (x0 11, y 67, z0 8), every line green and matching Godot's session log: lamp on/off through the lever (wire x5 `wire_on` while on), button lamp on at t=0.02 off at t=1.00 (simulation ticks), plate lamp on while standing / off after leaving, iron door closed-solid -> powered open (upper half too) -> walked through to x 16.29, wooden door by hand, strength 1 at 15 cells / 0 at 16, TNT under a live wire lit then defused, piston pushed a cobblestone from x 12 to 13, **3531 redstone ore below y 30 in 49 chunks (Godot: 3531)**, 21 recomputes, and after the reload lamp + wire on, door `iron_door_x_open`, lever `lever_on`. Captures: `stage27_day.png` (the bright 15-cell run with its dark 16th cell, the dark TNT run after the lever went off, the lit lamp, the grey iron door and the brown wooden door open, the extended piston with the gap before the pushed cobblestone) and `stage27_night.png` (the lamp glowing cream on the unlit surface, the rest dim). Simplifications as Godot: power to all six neighbours (no wire pointing), no sticky piston, `_power` rebuilt per tick and not saved. `--stage22` (same numbers as its row), `--stage23 --kind=8` (trap lit through the powered path) and `--strike` (18 -> 8) unchanged. |
| 28 | **Rails and minecarts.** Fourteen rail ids appended after `piston_w_on` in Godot order behind two items (`rail`: straights `rail_ns/ew`, curves `rail_ne/nw/se/sw`, slopes `rail_slope_n/e/s/w`; `powered_rail_ns/ew` + `_on` twins, light 4), each its own `BlockShape.rail*` (enum 15–24), so the mesher's `_subBox` draws two thin bars over wooden ties (tie colour × the cell noise), a curve as the two half-axes it joins, a slope as four rising steps; non-solid, a solid below needed like a wire, `rail_ew` last in `generatorIds()`. **`Rails`** (`lib/src/game/rails.dart`, static, pure over `VoxelWorld`): `connections(id)` (a slope's high end steps up), `orient(world, cell, base)` (a rail one up on a side over a solid makes a slope toward it, two sides a straight or a corner with the rails that face this cell first, one side a straight along it, none keeps the axis), `place` (orient, set, refresh the twelve neighbours, refresh itself once more), `removed`, `nextCell` / `endToward` (a flat end also finds a slope one cell down that climbs back). RMB with the rail item goes through `Rails.place`; `Game.onBlockBroken` calls `Rails.removed`. **Powered rails** are a circuit reactor: `Circuits._reactPoweredRails` floods the run of powered rails (four sides, cap 64) and lights every cell within eight of one that is directly powered. **`Minecart`** (`lib/src/entities/minecart.dart`, a plain object with a `Node`, no `VoxelBody`, `Game.carts`, stepped in `_tick` after the boats): `cell`, the entry / exit ends, `t` 0..1, a scalar `speed` (max 8); per tick 4 m/s² down a slope and against it up, 0.4 m/s² friction, +6 on a powered rail that is on and a 12 brake on one that is off, ±2 from the rider's push; a crossing takes the next rail, a line that ends stops and turns the cart round; a curve is two half segments through the centre, a slope the line between its end heights. `minecart` (5 iron) and `chest_minecart` (minecart + chest, an `Inventory`) are placed with RMB on an aimed rail; F within 2 m boards a plain cart or opens a chest cart's slots on the chest screen (`Game.openCartCargo`, host / solo only), F leaves, a melee swing at an empty cart drops it as its item (a chest cart spills). **Network**, host-owned like the stage 25 boats: `cart` / `cart_poses` (10 Hz with the boat poses, moved > 0.02 m or turned) / `cart_free`, late joiners get the list, `cart_req`, `cart_board_req`, `cart_unboard_req`, `break_cart_req`, the push rides in the pose's `ride.z`; replicas lerp. **Save**: `carts` rows (`kind`, `cell`, `from`, `to`, `t`, `speed`, `cargo`) beside the boats. **Mines**: `_mine` lays `rail_ew` from x 1 to len − 1 on the corridor's centre line before the chest (the spawner, a third of the time, overwrites one), and the first visit within 48 m spawns a chest minecart with `mine` loot at the corridor's last rail (`_checkStructures`, key `mineCartKeyY` 2000, set only once both corridor ends are loaded). Recipes: rail x16, powered rail x6, minecart, chest minecart. Probe `--stage28 --kind=7 --slot=probe28` (two boots like stage 27). Unit tests `test/stage28_test.dart`. | ✅ | seen on seed 42, same site as Godot (x0 11, y 59, z0 8), every line Godot's session log: `placed 24 rails: ns=6 ew=15 curves=1 slopes=2`; coasting from 6 m/s reached the west end (x 11.00) and stopped; **uphill 6 -> 3.93 m/s at the top, 3.07 m/s back down from rest (Godot 3.93 / 3.07)**; entered the corner heading +x and left heading +z; stopped dead on the unpowered rail, **peak 5.23 m/s within 2 s of the lever (Godot 5.23)**, both ends of the leg `powered_rail_ns_on`; F boarded, the push carried the player 0.86 m (Godot 0.89), F left; three apples through the chest cart's screen; **the mine at (-111, 53, -344) with 22 rails and its chest cart (Godot: the same mine, 22)**; after the reload `carts=3 rails intact=24`, lever on, leg lit, hp 30/30. Captures: `ride.png` (the player seated in the cart on the straight, ties and bars readable, the chest cart ahead, the stepped slope and plateau leading to the corner) and `mine.png` (`--stage21a --kind=7 --fp --look=-90,-20`: the rail down the corridor under the beams, the loot cart at the far end). Simplifications as Godot (no arcs, no rider on a chest cart, chest cart slots host-only, no power across a gap, the cart RPCs mirror the boat path without a paired probe). `--stage27` (every line of its row, 3531 ore) and `--strike` (18 -> 8 at 2.01 m) unchanged. |
| 29 | **The Underworld, a second dimension.** Eight blocks appended after `powered_rail_ew_on` in Godot order (`obsidian` tier 4, `portal` non-solid translucent light 11 and never an item, `hellstone`, `soul_sand` with the new `BlockDef.speedMult` 0.5, `glowstone` light 15 dropping 2–4 `glowstone_dust`, `nether_quartz_ore` → `quartz`, `nether_brick`, `fortress_core` light 8 → `underworld_heart`), six of them at the end of `generatorIds()`. **Generator** (`lib/src/world/terrain_generator.dart`): `generateIn(cx, cz, dimension)` beside `generate`, `setDimension` picks what `biomeAt` / `structuresNear` answer, dimension 1 is the cavern slab between bedrock at y 0 / 7 / 100 carved by the `_hell` 3D noise with edge bias, lava in every open cell at y ≤ 28, soul sand patches (`_hellPatch`), glowstone clusters from the ceilings and quartz veins by the integer hash, biome 9; the **fortress** (kind 9, `_fortressAt` per 8×8-chunk region, 60%) with the hall, pillars, windows and sconces, two side rooms with a chest each, the 9×9×7 throne room with the sunk lava moat and the core, and `fortressLayout` as a record (`length`, `hallEnd`, `throne`, `core`, `blaze`, `chestA`, `chestB`). **Isolates**: the `gen` job carries the dimension (`ChunkWorkerPool.generate(cx, cz, dimension)` → `generateIn`), and `VoxelWorld` stamps each gen / mesh future with `_genEpoch`, so a result that lands after a travel is dropped. **VoxelWorld**: one `dimension` at a time, `switchDimension` (keeps the live delta under `_editsByDimension`, bumps the epoch, clears in-flight, flow queue and circuits — the TNT callback carried over — and resets), `storeEdit` for a dimension not loaded, `editCountIn(d)`, `blocks.bin` **version 2** (both deltas after the seed; version 1 still loads as dimension 0). **Portal** (`lib/src/game/portals.dart`, static like `rails.dart`; Godot keeps them in `main.gd`): `light` (the hollow in either vertical plane), `buildAt` (frame, hollow, cleared front and a floor), `near`, `findSafeY` (y 30..90 outward from 64, the ring of columns with a bridge, a carved pocket); `Game.tryLightPortal` from the flint and steel (iron + flint), `_portalTick` (2 s in a portal, `_portalHold` until the body steps out; a client sends `travel_req`), `travelToDimension` (wild mobs freed, pets / villagers / drops / boats / carts tagged with their dimension through an `Expando` — Godot's `dim` meta — hidden and not stepped while elsewhere, rides dropped, weather suppressed) and `_arriveTick` (holds the player until the 3×3 ring is generated, then the safe spot and a return frame 2 north when no portal is within 16). **Fortress**: `_checkFortress` (announced within 48 m + *Into the Fire*, two blazes at the hall's middle within 20 m, the Underworld Lord within 14 m of the core, keys lifted by 5000 / 3000), `coreLocked` refuses the core until the lord's death sets the 4000 key (`onUnderworldLordDied` from `Mob._die`), the heart unlocks *Heart of the Underworld* on pick-up; `fortress` loot table (kind 9). **Mobs**: `blaze`, `dark_skeleton` (`wither` effect), `magma_cube`, `underworld_lord` (200 hp boss) with `projectile` / `volley` as data (as in Godot, the ranged AI still picks arrow / frost by body); a `fire` projectile sets the player burning 4 s; soul sand scales a walker's speed under the player's and a mob's feet; the spawner searches an air-over-solid pocket in the underworld and picks from biome 9. **Player**: waits for its chunk like a mob; beds refuse and a water bucket hisses away in the underworld. **Sky**: sun 0, sun disc colour 0, a dark red gradient, a warm constant-diffuse ambient, fog 0.014 red — set in `Game._updateSky` and left the moment the dimension is 0 again; `Weather.suppressed`; `Music` mood **Underworld**; the clock label reads *Underworld*; debug line shows `dim`. **Net**: `block` / `block_req` / `blocks` carry `dim` (an edit for another dimension waits via `storeEdit`, the host stores and relays a client's unchecked), the pose carries `dim` and a `RemotePlayer` in another dimension is hidden, `mobs` carries the host's `dim` (parked mobs are not sent, puppets hidden across dimensions), `travel_req` → the host checks the puppet's feet when they share a dimension → `set_dim`. HUD: Fortress marker and underworld map tint. Probe `--stage29 --kind=9 --slot=probe29` (two boots); windowed `--shot=portal --time=0.745` / `--shot=fortress`, plus a Flutter-only `--shot=cavern`. Unit tests `test/stage29_test.dart`. | ✅ | seen on seed 42, every line Godot's session log: site x0 11 y 66 z0 8; obsidian=true, cobblestone=true (lava_flow=true); 6 portal blocks lit; **travelled to dimension 1 at (19,63,11) on hellstone after 2 s in the portal (Godot the same cell)**; **hellstone 378100 / lava 43743 / glowstone 1604 / quartz 13947 / soul sand 2450 over the 5×5 core — identical to Godot** (the 3D noise ported unchanged; the unit test's raw generator reads hellstone 378101, one less edit); return portal at (19,63,9); **fortress at (34,27): 1557 bricks, 2 chests, 2 blazes, Underworld Lord hp 308 (Godot the same)**, origin y 56, length 45, core (84,56,27); core refused before the kill, heart ×1 after, both achievements; soul sand 2.30 m/s under a 4.6 walk (Godot 2.30); fireball → burning (hp 37/39); back home at (19,66,9) on the surface, weather Clear, clock label back; saved in dimension 1 with edits 436 / 59 (Godot 436 / 59); after the reload dimension 1, edits 436 / 59, the return portal's 6/6 cells intact, label *Underworld*, mood *Underworld*. Captures: `portal.png` (the obsidian frame on the pad at dusk, the hollow lit — only faintly purple: the portal draws on the translucent PBR liquid surface and the low sun washes its colour out; in the underworld it reads purple), `fortress.png` (the throne room from its door: the lord under its boss bar, glowstone sconces and ceiling lights, the orange lava moat along the walls, the purple core), `cavern.png` (hellstone walls, the lava sea below, a glowstone block), and the reload boot's capture (dark red hellstone, the return portal's purple glow). Simplifications as Godot (a client in a dimension the host does not hold sees no mobs and its edits are stored unchecked; the puppet's portal timer is the client's; parked drops and boats frozen; a fireball burns only the player; the probe's blaze fires through `spawnProjectile`; `deep` also fires under y 20 in the underworld; no ghast; no volley AI), plus: puppet mobs are not tagged on a travel (the `mobs` message hides them), and parked villagers stay in `Game.mobs` for aim and projectile tests (hidden, not stepped). `--strike` (18 -> 8 at 2.03 m), `--stage28 --kind=7` (every line of its row, 22 mine rails, 3 carts / 24 rails after the reload) and the `--stage25` pair (host `--reject-one`: drop poses 8, give rest 1, chest 1 / 1, boat aboard, flow 4 / 24, rollback seq 1, flow cells seen 24, bobber, wheat_1) unchanged. |
| 30 | **Title screen, world list, creative mode, tutorial, credits, stats.** The launcher in `main.dart` now shows `TitleScreen` (`lib/src/ui/title_screen.dart`; `main_menu.dart` is gone): Play / Multiplayer / Settings / Credits / Quit over a slowly orbiting vista — a second `VoxelWorld` (radius 3, seed 42) in its own `Scene` + `SceneView` with its own sky and sun, the Meadow mood once SoLoud is up; leaving for a world disposes the vista's isolate pool first. A probe boot (`--new`, `--slot=`, `--seed=`, `--continue`, `--screenshot=`, `--host`, `--join=`) still skips it, `--title-probe` forces it. **Worlds** (`lib/src/game/worlds.dart`): `worlds/<slot>/world.json` (name, seed, mode, class, created — Godot's keys) beside `player.json`; `list()` overlays the save's seed, dimension, play time, class / creative and mtime, newest first; `create` (slug = lower-case `validate_filename` with underscores, `_2`… when taken) / `rename` / `delete` / `start`; `WorldList` (`lib/src/ui/world_list.dart`): the rows, Play (or double-click), Rename, Delete behind an `AlertDialog`, and the New World form (name, seed text — a number as itself, other text FNV-1a hashed, empty random —, Survival / Creative, the four classes). `Worlds.start` fills `GameState` (`worldName` = the slot, seed, class, `creative`, `freshWorld` when no save exists) and the game boots from it as it did from `--slot=`. **Creative** (`GameState.creative`, saved in the stats block): `Player.takeDamage` returns, hunger never drains, every placement path goes through `Player._consumeHeld()` which costs nothing, and F5 flies only when `Game.flyAllowed()` (creative or `--fly`; survival says so). **Tutorial** (`lib/src/game/tutorial.dart`, a `ChangeNotifier` singleton drawn by `TutorialCard` over the HUD): ten steps (move, look, jump, break, inventory, craft a tool, place, eat, sleep or survive to sunrise, journal); `Tutorial.instance.event(id)` is called where the game does the thing (the walk vector, the look delta / `setLook`, `Player._jump`, `onBlockBroken`, `openStation`, `Player.craft` — the inventory click moved there —, `onBlockPlaced`, `_eatHeld`, `sleepInBed` or the 0.25 sunrise crossing, `openJournal`) and only the current step's event advances; Skip is the card's button or F6 (`GameAction.skipTutorial`); `Settings.tutorialDone` persists as `[tutorial] done` in `settings.cfg` (a switch in Settings re-arms it); it begins on a world the title just created (or under `--stage30`), never on a bare `--new`, a client or `--no-tutorial`. **Credits** (`CreditsScreen`): engine, fonts, the procedural audio, the lineage, then every `\| N \| title` row of this file — declared as a plain asset in `pubspec.yaml` and read with `rootBundle.loadString`, no build hook — scrolling up at 42 px/s; Esc closes. **Settings** are one `SettingsPanel` widget used by the pause menu (live) and the title (`game` null). **Stats**: the pause menu's Stats button unfolds play time, metres walked (`GameState.distanceWalked`, the ground displacement per tick), blocks broken / placed, mobs killed, deaths and dimension trips (`GameState.dimensionVisits`, counted in `travelToDimension`); the pause menu also gained Save & back to title in solo. Probe `--stage30 --title-probe` (two sessions, slot `probe30_stats`, removed at the end); `--title-probe` captures with `--open-worlds` / Flutter-only `--open-credits`; `--new --seed=42 --stage30 --shot=tutorial`. Unit tests `test/stage30_test.dart`. | ✅ | `--stage30 --title-probe`, every line green and matching Godot's session log: buttons=5, 'Probe World' seed 4242 created / listed / renamed / deleted (slot `probe30_probe_world`), **33 credits rows (Godot 33)**, creative damage ignored + block placed without consuming + fly, tutorial 7/10 by events (move … place, next eat) then skipped and read back from the file (`settings_probe30.cfg`), the stats saved and equal after the session rebuild (broken 1, placed 2, play 2.1 s → 3.5 s, still creative, no card), `probe30_ slots removed=1`. Seen: `stage30_title.png` (the vista from 16 m over the coast — trees, cliffs, the sea — behind the five buttons), `stage30_worlds.png` (`--open-worlds`: the developer's nine slots with mode, class, seed, dimension, play time and last played, and the New World form), `stage30_credits.png` (`--open-credits`: the engine / fonts / audio / lineage block, then stages 0–18 scrolling), `stage30_tutorial.png` (the gold card "Step 4/10 Break a block" with its skip button over the world), and the rebuilt session's capture of the creative mage world (HP 18/18, the stone still in slot 1). `--strike` (18 → 8 at 2.02 m), a plain `--screenshot` boot (straight into the world, no title) and `--stage29 --kind=9 --slot=probe29` unchanged — every figure of its row except `blazes=3` against the row's 2, a count of every blaze in `mobs` near the hall that this run did not explain (not a stage 30 path). |
| 31 | **Voxel lighting with AO in the shader, light-gated spawns, A* for walkers.** The mesher stops baking the light into the vertex colour: the colour keeps block tint x face tint x AO (the 4-level corner count, the diagonal flipped when anisotropic, mirrored for CCW winding) and `MeshSurface.light` (the second UV set, `texCoords1`) carries `(sky / 15, block / 15)` of the cell the face points into (a plant, a door, a torch stick read their own cell; a flame is full bright). Skylight floods each column from the top and spreads sideways at -1 per step, block light spreads from every emitter (`Blocks.emission()`), both inside the padded 18x18x128 volume of the job, and the two chunk-sized volumes ride `ChunkMeshResult` (with `aoVerts` and the job's own `ms`) back from the isolate so `VoxelWorld.lightAt(cell)` answers `(sky, block)`. **Shader**: `TerrainMaterial` (`lib/src/world/terrain_material.dart`) is a `PhysicallyBasedMaterial` whose fragment shader is `shaders/terrain.frag` — flutter_scene's standard lit shader with Godot's `terrain_light` folded into the albedo (`level = max(sky * sky_intensity, block)`, `0.02 + 0.98 * level^4`) and `emission_mix` 0.5 of the lit albedo added as emission — plus a cube-radiance twin, compiled by `dart tool/build_shaders.dart` (SDK impellerc) into the committed asset `assets/shaders/terrain.shaderbundle`; the only extra input is a `TerrainInfo` uniform block bound in `bind`. Solid, cutout and liquid use it (specular 0 on solid / cutout: Godot's `specular_disabled` and no sky reflection); the stage 27 glow surface stays `UnlitMaterial`. `Game._updateSky` sets `skyIntensity` (1.0 noon, 0.35 night, 0.0 underworld, storms dim it) through `VoxelWorld.setSkyIntensity`, and the sun drops from Godot's 0.85 to 0.6. The title vista loads the library too. A placed or removed block that is opaque or emits remeshes the whole 3x3 ring (`VoxelWorld.setBlock`). **Spawns**: `Spawner.hostileAllowedAt(cell)` is `block + sky * Game.dayFactor < 7` (`lightAllowsHostile`, pure); `Species.candidates(biome, night, cave, dark, rng)` drops the height, and the bat's `maxY` is gone. **Pathfinding** (`Pathfinder`, `lib/src/game/pathfinder.dart`): A* on feet cells, 4 horizontal moves, a step up with head room, a drop of up to 3 onto a landing, lava never, water x3, soul sand x2, Manhattan heuristic, 600 expansions then the best partial path, a binary heap on f then deeper g; `Mob._steer` follows the waypoints for a chasing or homing walker (replan every 0.6 s or when the next waypoint got blocked, three partial paths in a row fall back to the straight chase for 3 s); fliers and puppets untouched. Probe `--stage31` (`--no-light` for the cost comparison, `--shot=room|cave` for the captures). Unit tests `test/stage31_test.dart`. | ✅ | seen on seed 42, every probe line Godot's: site chunk (1, 0), walk floor y 67; **outside sky 15 / block 0, room centre sky 1 / block 10, under the overhang sky 7 (Godot the same)**; torch removed -> block 0 after **9 chunks remeshed**; **4107 AO vertices** in the room chunk; spawn gate dark=true / lit=false (day factor 0.35 at night, 1.00 by day); **the zombie reaches the player through the S maze in 9.7 s along a 28-cell path (straight line 10), 17 replans; the no-path control stays stuck (closest 7.2 m in 6 s)** — all Godot's figures; A* on that maze 0.4–1.6 ms; mesh time **6.5 / 7.4 / 7.7 ms per chunk lit** over 341–353 jobs against **6.2 ms with `--no-light`** (Godot 7.5–13.8 lit, 5.5–17.3 unlit on a busier pool). Plain boot seed 42: window 361 chunks / 649942 faces in 1.65–1.70 s at 86–87 fps against 1.58–2.40 s at 94–102 fps for the stage 30 build on this machine (the terrain shader is the standard one plus a few ops; the spread between runs is about as large). Captures: `stage31_room.png` (night, the torch wall bright around the torch, the far corners and edges dark, every face flat-lit from its cell), `stage31_cave.png` (the pit's mouth bright by day fading to grey at the back), the plain day boot (the same coast as stage 30, lighter and a little paler: the emission share adds to the lit albedo), the plain night boot (darker than stage 30: the field near black away from the moonlit sky), the title vista (trees, grass, water, readable), `--stage29` (underworld: hellstone dark, the portal's purple glow and glowstone lit), `--stage27 --time=0.05` (the lamp throws a pool of block light on the dark pad). Regression: `--stage29 --kind=9 --slot=probe29` (hellstone 378100, fortress 1557 bricks / lord 308, edits 436 / 59 after the reload), `--stage27 --slot=probe27` (3531 ore, reload lamp + wire on), `--strike` (18 -> 8 at 2.01 m) and `--title-probe` (81 vista chunks, 5 buttons) unchanged. Engine differences: Godot's `ShaderMaterial` + `EMISSION`/`ALBEDO` keeps the engine's lighting; flutter_scene's raw `ShaderMaterial` binds no sun, shadow, ambient or fog, so the terrain shader is the standard PBR fragment shader with the light term folded in and the material subclasses `PhysicallyBasedMaterial` (sun, cascaded shadows, ambient and sky fog all kept); it keeps every sampler of the standard shader because the material binds them by name. The bundle is built by hand (no app hook) with `--gles-language-version=300`, is tied to the engine and holds every backend (1.7 MB). Under ACES the 0.35 night with the fourth power reads darker than Godot's filmic tonemapper made it; the numbers are Godot's. Simplifications as Godot (~~the light BFS inside the one-cell pad, so a torch across a chunk border does not light the neighbour~~ → stage 32, the pad is the whole 3x3 ring; the fourth-power curve; `--no-light` still pays the AO pass). Fixed on the way: a remesh requested while that chunk's job was already in flight was dropped when the stale result landed (`VoxelWorld._remeshAgain`), which let a probe read pre-edit light. |
| 32 | **Polish: seam-free light, combat feel, breaking feel, mob life, HUD.** **Light** — `ChunkMesher.pad` = 16: the padded volume is the whole 3x3 ring (48x48x128, filled chunk by chunk by `_copyChunk`), so the skylight and block BFS see every emitter up to 15 cells past a border; the four buffers are static (one set per worker isolate, Godot's `[ThreadStatic]`, the queue sized 2x the volume); the sky BFS is seeded only from cells with a darker side neighbour (`ChunkMesher.fullSkySeed` keeps stage 31's rule for the equivalence test); Flutter-only and result-identical, the layers above the volume's highest block are filled with 15 at once so neither the column pass nor the seeding scan walks them. **Combat** — every hit adds `Mob.knockbackVelocity` (4 m/s away on the ground plane, a projectile's or explosion's larger push wins, + 3 m/s up) and a 0.3 s stagger the steering lerp does not brake (`Mob._moveAndAnimate`, `Player` on foot and flying; a puppet rides the host's pose), a 60 ms hit-stop on the victim's model (`Mob._freeze`, `PlayerModel.freeze`: the pose holds, the body and the clock keep going), a 100 ms white flash through one shared `UnlitMaterial` (`PlayerModel.flashMaterial`, `vertexColorWeight` 0), a hurt voice per group (`Mob.hurtGroup`: small / large / undead / flying), the player's camera shake (0.15 s, damage / 10 capped at 0.3 m, added to the camera only, never the aim) and the HUD's radial red vignette (1 -> 0 over 0.4 s); damage numbers read `-N`, rise 1 m over 0.8 s and fade from 0.2 s to 1 s; one melee hit or arrow in ten is a critical (`Game.rollCrit`, `critChance` 0.1, x`critMult` 1.5 rounded, yellow `-N!`; the `dmg` message carries `crit`); the held item pivots 60 degrees over 120 ms on every swing and every 0.35 s mining tick (`PlayerModel.hand`). **Breaking** — four crack stages (`Player._buildCrackStages`: a box darkening 0.16 a stage plus two jagged four-segment polylines per face per stage from `Random(32)`, one `LineSegmentsGeometry` node per stage and face built once, a face turned away from the camera hidden), `Game.spawnDebris(at, colour, count, speed)` with one shared unit cube (12 on a break, 2 per mining tick at 0.7, 8 white at 0.5 for a spawn poof, 1 ember for a burning mob), and `Blocks.materialFamily` (metal / glass / stone / plant / wood / earth by id substring in that order, liquid by shape, stone otherwise) picks the `break_` / `place_` / `step_` voice (21 new SoLoud voices, plus `hurt_*` x4 and `heartbeat`); footsteps every 0.45 m (0.3 m sprinting), softer on sand and soul sand (`Player.stepsTaken`). **Mobs** — breathing (2% on the height, not blobs or creepers), a passive mob's head turns to the player within 6 m (clamped to 1.2 rad), `Spawner` spawns in a poof, death = topple 90 degrees over 0.4 s, fade over 0.3 s, removed (drops at t = 0), and the classic rule (`Mob.burnsInDaylight`: zombie / skeleton / dark_skeleton whose head cell reads sky 15 while `dayFactor >= 0.9`, not in water, not tamed; checked every 0.5 s, 0.5 HP each, orange tint, an ember). **HUD** — `HudState` (`lib/src/ui/hud_state.dart`, advanced by `Game.onFrame`, Godot's `hud._process`): the selected hotbar slot tweens to 1.1 over 80 ms, pickups are toasts bottom-right that merge a repeat within 1 s (`Player.pickUp` calls `hud.addPickup` instead of a note), under 25% HP the vignette pulses and a heartbeat plays every 0.9 s, the XP fill tweens, the boss bar carries a portrait block in the species colour and shakes 0.25 s on a hit. Probe `--stage32` (`--shot=combat|mining` as Godot, Flutter-only `--shot=seam`). Unit tests `test/stage32_test.dart`. | ✅ | seen on seed 42, every probe line Godot's: site chunk (1, 0), border at x 16; **a torch 5 steps from the west chunk lights its first cell to 8 and the third to 6 (Godot 8 / 6), the same 5 steps inside the torch's chunk 8**, the west chunk remeshed with the ring of 9; **the zombie moved 1.62 m and rose (Godot 1.62)**, flash + hit-stop on, the player's hit shook the camera with **vignette 0.90 (Godot 0.90)** and a model flash; crits 17 / 16 / 23 / 31 / 25 / 15 over 200 swings across six runs (Godot 24-25), 200 numbers; **crack alpha 0.48 at progress 0.5 (Godot 0.48)**, stage 2 with 9 face nodes shown, 12 cubes and the stone voice on the break; **12 steps over 5.3 m (Godot 12 over 5.3)**; **sun zombie burning, roofed one (head sky 13) and pooled one (in water) not (Godot the same)**, day factor 1.00; the kill freed the body after 0.72 s (43 ticks; Godot 0.70 wall time) with the drops at t = 0; `+3 Apple` twice -> `+6 Apple`, low HP pulsing. **Mesh time**: the in-app job clock (24 jobs in flight on the isolate pool) read 8.6-10.2 ms per chunk over 315-327 jobs in nine `--stage32` runs and 9.9 / 11.0 ms in two `--stage31` runs of this build, against stage 31's 6.5-7.7 ms; single-threaded on the same 49 seed-42 chunks (no pool contention) the stage 31 mesher takes 3.0-3.2 ms and this one 4.5-4.75 ms (5.0 before the empty-layer shortcut), so the 3x3 pad costs about 1.5 ms per chunk here where Godot's C# measured it as about the same. **Window fill** (plain boot seed 42, 361 chunks / 649942 faces): 1.91 / 2.12 / 2.36 s at 76-82 fps against stage 31's 1.65-1.70 s at 86-87 fps (these runs shared the machine with another session's headless Godot test run at ~97% CPU). Captures: `stage32_combat.png` (the player and the zombie both white mid-flash, the zombie shoved back with its health bar over it, `-1` yellow on it and `-3` red on the player, the red vignette, a `+6 Apple` toast), `stage32_mining.png` (first person, a raised stone block darkened with cracks on its top and front faces, a chip in the air, the progress ring), Flutter-only `stage32_seam.png` (`--shot=seam`: the torch back at midnight seen from 7 m above the border, its diamond of light fading a step a cell straight across the border column into the west chunk with no cut; the probe's row along the torch reads 3 4 5 6 7 8 | 9 10 11 12 13 12 11 ... across the border at x 16). Regression: `--stage31` (sky 1 / block 10 at the room centre, sky 7 under the overhang, 9 remeshed, 4107 AO, the maze in 9.7 s along 28 cells, the control stuck at 7.2 m), `--stage29 --kind=9 --slot=probe29` (hellstone 378100, fortress 1557 bricks / lord 308, soul sand 2.30, edits 436 / 59 after the reload), `--strike` (10 damage at 2.01 m: 17.5 -> 7.5, the zombie now burning in the morning sun before the swing, where stage 31 read 18 -> 8) and `--title-probe` (81 vista chunks, 5 buttons) unchanged; the `--stage21b` pair was not run. Engine differences: a material swap in flutter_scene 0.23 only reaches the renderer when the mesh is re-assigned (`refreshMeshMaterials`, used by the flash, the burn tint and the death fade); the crack lines draw over the terrain, so faces turned away are hidden per node where Godot's depth test hides them; the vignette is a canvas radial gradient stretched to the screen like Godot's `GradientTexture2D`, over Flutter's existing full-screen damage flash, so a hit reads redder than Godot's capture; Godot's crit label sets `font_size` 80 then 64, so a crit number is the same size here too; the death topple is linear (Godot's `EASE_IN` on a linear transition); the probe counts ticks, `Mob.probeDrops` stands in for Godot's duplicated species dictionary, the combat capture waits one tick (the flash is 100 ms and the capture lands a few frames later) and the mining hold ends at progress 0.6 rather than after 40 frames, so the block is still standing when captured. Simplifications as Godot: no first-person hand (the flash shows on the third-person model only), the crack overlay is line-drawn, the bursts are pooled cube nodes rather than particles (counted by the probe), the crit rides the damage-number message, the hit-stop is per model and never the clock. Fixed on the way: `HudPainter` projected mob bars and damage numbers with the camera captured when the widget was built, so they drew at the player's first position (now the camera of the frame); `Mob._setTint` (stage 23 stun) never reached the screen after spawn for the same material reason; `VoxelWorld._refreshWindow` dropped every queued remesh when the window re-centred, which left an edited chunk with its pre-edit mesh and light (the stage 31 probe passed only when a dispatch frame ran before that tick, and failed once here with sky 15 in the roofed room); `GameInput.probeHold` crashed on the mouse-button actions. |
| 33 | **Playground: every feature around one spawn (Flutter only).** A sixth title button, **Playground**, opens a panel (what it is, the keys, a class row) whose *Build a new playground* makes a new slot through `Worlds.createPlayground` (`world.json` `type: playground`, creative, seed 42) and boots it; `GameState.playground` rides the stats block and `WorldEntry.playground` labels the list row *Playground*. **Generator** (`TerrainGenerator.playground`, passed through `VoxelWorld` and the isolate factory): a 144 x 144 plaza (`plazaMin` -64 .. `plazaMax` 80) at `plazaFloor` 64, plains, no caves, no decoration within 4, no structure within 48, the natural height eased back over `plazaBlend` 16. **`Playground`** (`lib/src/game/playground.dart`): nine `PlaygroundZone`s of 48 in a 3 x 3 grid around (8, 8), one built per 0.25 s poll once all its chunks are loaded (a write into an unloaded chunk is dropped), `built` saved as `playground` in `player.json`; hub (glider tower, 5 chests of all 171 items, stations, the hub waypoint and the world tour: 8 structure kinds within 48 chunks and 7 biomes within 1.5 km as block-less waypoint labels), block gallery (118 blocks + two liquid tanks), shapes & building, redstone (the stage 27 rows + a lamp row), rails (a 24 x 14 loop with a two-high hill and a powered stretch, `railLoop`), water / lava / portal, farm & animals, monster arena (`arenaMobs` 14, a spawner block ticked by the playground, `bossPlates` 6 summoning on the step, the gold refill button polled on its lit edge), light & mining. Creatures carry `Mob.exhibit`: the spawner neither despawns nor counts them and the save does not keep them, so the zoo and arena are placed again on every boot; villagers, companions, carts and the boat are placed once and saved. F7 / F8 / F9 (`GameAction.cycleWeather` / `cycleTime` / `rebuildExhibit`) cycle the weather, the time of day and rebuild the zone under the player. `ZoneCard` shows the exhibit's card for 12 s after entering; the HUD names the aimed block; the journal's waypoint tab runs in two columns past ten; the fresh kit is 36 showcase items, level 10 and 10 talent points. Probe `--playground` (`--shot=`, `--shots=`, `--pg-checks`), `--title-probe --open-playground`. Unit tests `test/playground_test.dart`. | ✅ | seed 42: `zones built=9/9 in 1119 ms, edits=11719 exhibit mobs=27 villagers=2 pets=3 carts=2 boats=1 chests=6 waypoints=16 gallery=118 library=171`, plaza surface 64, 0 structures inside; checks: steps / half step / climb wall / ladder / stairs roof / iron door cells right, troll summoned 1 and a second step keeps 1 with the boss bar, arena 15 -> 14 -> 15 through the gold button, F7 Rain, F8 0.50 then 0.74, F9 wall air -> oak_planks, save built 9 / flag / 16 waypoints / 5 pets; the reload boot read the nine back with `edits=0` and 27 exhibit creatures placed again. Seen: the aerial plaza, all nine exhibits, the pool from underwater, the arena inside, the dark hall, the steps, the journal's tour in two columns, the title panel. Hosted (s31): the `hello` carries `playground` beside the seed, and a client joined with `--join=127.0.0.1` (no `--playground`) generated the plaza and saw the pool, the pens and the portal from the aerial eye. |

## Session log

- **2026-09-24 s32** — turning off Settings → Show FPS left the frame rate on screen. The
  F1 developer overlay (`debugText`, which opens with `FPS …`) started visible:
  `Game.debugVisible` defaulted to `true`, carried over from the POC port. The HUD draws
  that overlay first and reads `Settings.showFps` only when the overlay is hidden, so the
  setting could never hide the number. `debugVisible` now starts `false`. F1 still toggles
  the overlay, and `showFps` alone decides what a player sees by default.

- **2026-09-23 s31** — a client that joined a hosted playground stood in the sea. Its
  exhibits hung in the air, and walking into them showed that their collision was missing
  too. The `hello` carried the seed and the edit delta but not
  `TerrainGenerator.playground`, and the Join button had just reset
  `GameState.playground` to false. The client therefore generated seed 42's natural
  terrain, which is ocean at (-29, -33), under the host's plaza. Only the cells the
  playground builders had written came across in the delta: pedestals with no plaza under
  them. The rendered blocks and the collision were missing together because both read the
  same chunk bytes. The host now sends `playground` in the hello. The client sets
  `GameState.playground` from it before its world exists, so it builds the same generator
  and also gets a `Playground` (the kit, endless stamina and mana; F7–F9 and the builds stay
  with the host, as the `isClient` gates already said). A hello that lands after the
  client's world exists already rebuilt the world for a different seed. It now rebuilds on
  `VoxelWorld.setWorldShape(seed, playground:)`, which swaps the generator and keeps the
  dimension. Seen: a `--host --playground` process and a plain `--join=127.0.0.1` process.
  The client logged `hello from host: seed 1337, playground true, 50434 edit bytes`, its
  HUD read Plains, and the aerial eye showed the flat plaza with the pool, the pens and the
  portal.

  The same report had a second cause, which the plaza hid: an edit from the other side was
  dropped whenever its chunk was not loaded where it landed. `VoxelWorld.setBlock` returns
  false for a chunk that has not generated. The client's `block` handler also returned
  early when `getBlock` already matched, and an unloaded chunk reads as air, so a break
  was skipped even before `setBlock`. Every exhibit the host built while a client was
  elsewhere was lost to that client. When the client walked there later, the chunk
  generated without it, or with the tree the host had cut still standing, and collision
  followed the same bytes. The host dropped a far client's edit the same way, and its ack
  read air from the unloaded chunk, which rolled a placed block back on the client. The
  kit's own sessions already went through `storeEdit`; the app never had. Now
  `VoxelWorld.storeEdit(d, b, id)` writes through `setBlock` when the chunk is loaded, and
  otherwise keeps the edit in the delta until the chunk generates. The client's `block`,
  `blocks` and rollback all use it. The host treats a far cell like one in another
  dimension: it stores it, broadcasts it to the peers and acks the id it was asked for.
  Seen with a `--radius=2` client (49 chunks) that joined while the host was still
  building (the hello held 39164 edit bytes): the new `edits` count on the `--wait-peer`
  line read 9830 on both host and client. The same run on the old code read 9830 on the
  host and 7675 on the client, 2155 cells lost. Two kit gaps found on the way are in the
  kit's ledger (`KL-002`, `KL-003`).

- **2026-09-23 s30** — the app is renamed `voxel_game_minecraft`, ahead of its move into the
  kit's repository as an example for the kit's users. About 95% of what was built here is
  Minecraft, not Cube World, so the name says Minecraft now: the Dart package, the
  macOS/iOS/Android product and bundle ids (`com.example.voxelGameMinecraft`,
  `com.example.voxel_game_minecraft`), the binary the probes launch, the window, title and
  credits text ("Voxel Minecraft"), the save folder, and the commit scope `poc(minecraft)`.
  Comments that credited a mechanic to Cube World (climbing, talents, staff spray, bonus
  loot) keep the mechanic and drop the credit. What still says cubeworld is a real name
  somewhere else: this folder, the branch, the Godot twin's path, and this log's history.
  The bundle id and the save folder both moved, so worlds saved under
  `com.example.voxelGameMinecraft/dawnforge_cubeworld_poc/` are no longer found; delete them.
  Before the rename the multiplayer was re-checked, because it looked abandoned: it is not.
  A `--host --wait-peer --stage21b` process and a `--join=127.0.0.1 --wait-peer --stage21b
  --strike` process on one Mac got the hello (seed + edits), mob puppets, the host's clock,
  a forced storm, a chest's contents, a given item, a poison bite through `hurt`, a melee
  strike resolved on the host, and the host riding a horse, which the client's screenshot
  showed. What it lacks is everything past a LAN: no discovery, no NAT traversal, no
  authentication, and JSON lines over TCP.

- **2026-09-23 s29** — the fog stops looking like weather. On a clear noon the world read
  as overcast: the linear ramp from s7 began at 45% of the render distance, so with the
  default 8 chunks everything past ~58 m was already washing out, half of the view. The
  fog is only there to hide the finite horizon, so it now lives only at the horizon. It is
  `FogMode.exponentialSquared` with `start` at 72% of the distance to the nearest unloaded
  chunk and a density that puts it at 98% at 97% (`1 - exp(-x²)` hits 98% where x² = ln 50).
  The curve is flat at first and steep at the end: about a third at 80%, 87% at 90%. Seen
  with `--seed=1337 --new --time=0.45 --weather=clear`, from the ground (the village and
  the sea stay sharp, the sea dissolves only at the horizon) and from the air with
  `--fly --tp=60,95,60` (no chunk edge shows). Rain and storms still pull the edge in by
  up to 35%, as before.

- **2026-09-23 s28** — the menu's letters turned to noise, and the fix is to stop showing
  the 3D scene before the GPU has finished it. Hovering a title button made the others
  flicker. The playground panel was unreadable. In play a few letters broke. The move of
  the kit to pub.dev was not the cause: the published code and the terrain shader bundle
  are byte-identical to the path copy. The trigger is load. With radius 0 or 1 (25
  chunks) the vista's text is clean; with the full 81 chunks it breaks, and it breaks on
  every capture once a second process is using the GPU. Allocating 256 MB of buffers
  without drawing does not break it, and neither does rendering the scene without
  drawing its picture. The Impeller source bundled with the SDK explains why. Impeller
  uploads new glyphs through its transient buffer, which it reuses every 4 frames with no
  GPU fence on Metal (`kHostBufferArenaSize`). A Flutter frame that samples the scene's
  texture waits on the GPU until the scene's command buffers finish, but the raster
  thread keeps building frames. A late frame then copies glyph bytes that a newer frame
  has already overwritten. The GPU ran ~2.7 frames behind on average, with peaks near 4.
  `lib/src/ui/paced_scene.dart` (`PacedScene`, used by the title vista and by `Game`)
  records each scene frame into a picture. A frame is drawn only after the completion
  tracker (`rendererSubmissions`) reports its submissions done. A new frame is submitted
  only when none is in flight, because flutter_scene draws into a ring of two swapchain
  textures. Limiting frames in flight while still drawing the newest picture was tried
  first and was not enough: 3 of 4 captures under load still broke. Under load the old
  build broke every capture and `PacedScene` none of seven. At idle the scene renders on
  about half the vsyncs (156 of 300; ~60 Hz on this 120 Hz display) and shows one frame
  late. The HUD's FPS went from 57 to 85, because the UI no longer queues behind the GPU.
  Probe: `--title-probe --open-playground --pace-probe`. To reproduce the bug, run two
  other copies of the app first. The real fix belongs upstream (Impeller's host buffer,
  or flutter_scene's `SceneView`). The kit's `VoxelGameWidget` draws through a plain
  `SceneView` and is exposed the same way. It lives in another repository now, so that
  finding goes to the kit's session.

- **2026-09-23 s27** — `VR4` and `VR5` of
  [`packages/voxel_game/docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md`](packages/voxel_game/docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md):
  the four packages are ready to publish. Each is `0.1.0` under MIT, points at
  `github.com/fluttely/voxel_game`, and depends on the others with `^0.1.0`, and the
  four dry runs pass. This app's four ranges moved to `^0.1.0` too; its overrides are
  untouched, so it builds exactly as before (408 tests).
  - **A nested package cannot publish in place in this layout, and the 2026-09-21 probe
    missed it.** Inside a git repository pub applies every parent folder's ignore file up
    to the git root. So the `.pubignore` line that keeps `packages/` out of `voxel_game`'s
    tarball also hides `voxel_engine` from its own publish: the archive comes out empty,
    "the pubspec is hidden". A nested `.pubignore` cannot re-include anything. The
    original probe had no `.git`, and without one pub reads only the package's own
    folders. The layout stays; `packages/voxel_game/tool/publish_package.sh` publishes
    the three nested packages from a copy with no `.git`, and `voxel_game` in place.
  - **The `flutter_scene: 0.23.0` pin stays and costs a warning.** Pub wants a range, but
    `voxel_scene` imports a private `flutter_scene` file, and patch releases of that
    package have happened before. The developer chose the warning. `PUBLISHING.md` now
    says a dry run ending with only that warning is green.
  - **`VR5` closes the plan.** A copy of the kit's 237 tracked files, taken outside the
    repository and `git init`-ed, resolved to the same lock, analyzed clean, passed its
    214 tests and gave the same four dry runs; nothing in it names this app outside the
    `.md` lineage. The folder is ready to leave.
  - **Next:** not in this plan. The developer moves `packages/voxel_game/` into
    `github.com/fluttely/voxel_game` (with or without `git subtree split` history). This
    app's four overrides then point at nothing, and choosing their replacement — git,
    a sibling checkout, or pub.dev once `0.1.0` is out — is the app's own move.

- **2026-09-22 s26** — the relayout runs: `VR0`–`VR3` of
  [`packages/voxel_game/docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md`](packages/voxel_game/docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md),
  one commit each. The kit now lives in `packages/voxel_game/` — `voxel_game` at the root
  as package and workspace root, the other three under its `packages/`, with
  `PUBLISHING.md`, the four voxel plans, three ledger entries and a `CLAUDE.md` of its own
  — and this app reaches it through four `dependency_overrides` by path, with a
  `pubspec.lock` of its own. Nothing changed behaviour: 408 tests before and after every
  step, and the probe logs identical after each one.
  - **The baseline had to be taken again, and s23's trap is why.** `tool/probe_baseline.sh
    --check` against `docs/baseline/` fails on this Mac before anything moves (1512x900 @2x
    against logs cut at 1600x900 @1x), so `VR0` recorded HEAD's own raw logs twice with a
    scratch copy of the script and every later gate diffed against those. One more thing
    the diff showed: the stage 32 footsteps line is compared on one side only, because its
    current wording carries `0.35 s` and the filter drops any line with a time in seconds.
    Re-cutting `docs/baseline/` on this machine would fix both; it is not a relayout step.
  - **Leaving the workspace thinned the app's lock and moved no version.** The kit's lock
    was seeded from the app's before the first `pub get`. Afterwards the app's had lost 25
    hosted packages, all of them `voxel_engine`'s dev dependency `test` and what it pulls, and the kit's
    had only demoted `flutter_soloud` and `hooks` from direct to transitive (they were the
    app's direct dependencies). A parser compared every hosted entry: no version moved.
  - **The terms (`VR2`).** 21 comments in 19 files lost "Minecraft", "Cube World" and "POC"
    and kept their reasons; `voxel_game`'s pub description is now "a voxel sandbox in a few
    lines". Its library header had also been naming `voxel_core`, `voxel_worldgen` and
    `voxel_content` since `VC` deleted them. The shader bundle, recompiled after the
    `.frag` comments changed, came out byte-identical. `McBrightness` kept its name.
  - **The docs (`VR3`).** The kit's `CLAUDE.md` carries rules 1–14, 17, 20 and 21
    renumbered 1–17, written from the kit's root. Its ledger took `CL-005`, `CL-008`,
    `CL-009` with their IDs and gives new entries `KL-nnn`, so the two ledgers cannot hand
    out the same number once they are in two repositories. The kit's `README.md` had been
    telling outside projects to depend on it with a plain `path:`, which cannot resolve in
    this layout; it now shows the four overrides.
  - **Next:** `VR4` — it waits on the developer's choice of license.

- **2026-09-22 s25** — the relayout is replanned before any of it ran:
  [`packages/voxel_game/docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md`](packages/voxel_game/docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md) is now
  `VR0`–`VR5`, and s24's shape is dead. The app does not become a `demo/` of the kit: it
  will leave for a repository of its own, apart from the kit, and that move is a later
  conversation. So nothing about the app moves — not its folder, not `cubeworld_poc`, not
  its bundle ids, not its save root, so there is no save bill and the Godot parity
  survives. What moves is the kit, *into* `packages/voxel_game/`: that folder becomes the
  workspace root and the published package, `voxel_engine`, `voxel_scene` and
  `sound_recipes` hang under its own `packages/`, and it takes `PUBLISHING.md`, the three
  extraction plans and its ledger entries with it — so that one folder, moved whole, is the
  new repository. The app stops being a workspace root and reaches the kit the way any
  outside project would. One probe decided how: an app outside a workspace that lives
  inside its own folder resolves the nested workspace fine, but **only** through
  `dependency_overrides` — with plain `path:` dependencies pub refuses, because the kit
  asks for `voxel_engine: ^0.0.0` from hosted while the app offers it from a path. Four
  path overrides are therefore the single edge between the two trees, and the one that
  has to be replaced the day the folder leaves. The last step, `VR5`, builds a copy of
  `packages/voxel_game/` outside the repository with nothing beside it; the move itself is
  the developer's. The vocabulary rule narrows with it: "minecraft", "cube world" and
  "poc" leave the kit's 19 non-`.md` files and stay in the app, which *is* the POC.

- **2026-09-21 s24** — the relayout is planned, nothing moved:
  [`packages/voxel_game/docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md`](packages/voxel_game/docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md)
  (`VR0`–`VR6`). This folder becomes the `voxel_game` package itself — the other three
  packages hang under its `packages/`, and today's root app moves whole into `demo/` as
  `voxel_game_demo`. Two findings decided the shape. The first: a pub workspace **root**
  can be published — a throwaway workspace with its `workspace:` key in place passed
  `dart pub publish --dry-run` — so `voxel_game` being both the root and the released
  package is not a contradiction. The second: that same dry run shipped the nested
  member's files inside the tarball, and only a root `.pubignore` naming `packages/` and
  `demo/` brought the archive back to `lib/`. Without it every release of `voxel_game`
  would carry the kit twice and the whole demo. `ROADMAP.md` itself is why `docs/` and
  `tool/` follow the app into `demo/`: Flutter serves assets only from inside the
  declaring package, and the credits screen reads this file at runtime. The port's
  vocabulary — "cubeworld", "poc", "minecraft" — stays in the `.md` files, which are the
  lineage, and leaves every Dart file, shader, script and native config, doc comments
  included, because `voxel_game`'s dartdoc is published. The demo's save root moves to
  `…/com.example.voxelGameDemo/voxel_game_demo/worlds/`, so the worlds on this machine
  and the path parity with the Godot POC both end there; the save *format* is untouched.

- **2026-09-21 s23b** — `CL-002` closes: the app's frame bank is the kit's.
  - **What moved:** six lines and one field. `Game._acc` and the `while (_acc >= fixedStep
    && steps < 4)` are gone; `onFrame` now says `_loop.advance(dt, _tick)` over a
    `FixedStepLoop(step: fixedStep)` from `voxel_game`. Every number is the one the app
    already used, so no timing changed — but two things came along that the app's copy
    never had: `advance` clamps the bank when it spends its fourth step, so a run of long
    frames cannot become a spiral of catch-up, and `alpha` is now available for smoothing
    a pose between two steps. Nothing reads `alpha` yet; it is there for the first thing
    that stutters.
  - **Why it was safe to trust so quickly:** because the pair's one real difference had
    already been dealt with an hour earlier. The defect both copies carried —
    `if (steps == 0) input.endTick()`, the line that threw away one-shot presses on any
    frame that ran no step — was fixed in `CL-003`'s commit in both files, so this one is
    a straight swap of a bank for the same bank.
  - **How it was verified:** `tool/probe_baseline.sh --check` was run and its output
    compared not against `docs/baseline/` (stale on this machine, see s23) but against the
    output of the same command on a build of `be939852` in a throwaway worktree: the two
    are byte-identical. `--touch --touch-probe` on seed 42 repeated its figures to the
    digit, the dig taking 132 ticks against 133 — the one number a frame rate moves.
    The suite is unchanged: analyze clean, 194 + 168 + 10 + 4 + 32 = 408.
  - **What is left on the ledger:** `CL-004` through `CL-009`, none of which is a
    duplicate pair. Two were written at the end of this session, checking what did *not*
    move: `CL-009`, the kit reads a finger and draws no thumb — the gesture rose into
    `InputMap` and the on-screen stick and buttons stayed in the app, because they are
    laid out against the app's own hotbar geometry — and an amendment to `CL-007`, whose
    three named pairs are all closed now, so what it guards has moved up a level to the
    surfaces that differ on purpose (`CL-005`, `CL-006`). `CLAUDE.md`'s suite snapshot was
    stale by two sessions and now reads 408 at `f6155a18`; it is the number that is
    supposed to catch a suite that stopped finding files, so an old one catches nothing.

- **2026-09-21 s23** — `CL-003` closes: the finger moves into the kit, and a press stops
  going missing.
  - **What moved:** `GameInput` is no longer a second input system. It kept what is
    Dawnforge's — the key table, the pad table, which action sits on which mouse button,
    and the one unit the kit does not share (it answers the look in pixels, because
    `Player` has owned the pixels-to-radians multiply since stage 4) — and handed every
    read to `InputMap<GameAction>` from `voxel_game`. 520 lines became 248, and the whole
    stage 44 touch scheme rose with them: `tapSlop` and `mineDelay` are constructor
    fields now, a finger that stays put holds whatever action the game bound to the
    primary mouse button, a tap presses that one or the secondary according to
    `touchTapPrimary`, and the on-screen stick, buttons and hotbar slots arrive through
    `touchMove` / `setTouchHeld` / `touchDigit` into the same `axis()` and
    `digitPressed()` a key goes through. `VoxelGameWidget` finally forwards
    `onPointerCancel`. Nothing in `lib/` outside `input.dart` changed a line, which was
    the test of whether the two really were twins: they were.
  - **The bug the probe found, and why it was fixed instead of recorded:** `--touch-probe`
    drives a scripted finger and prints what the simulation did with it. The first runs
    said the finger dug and dragged perfectly but that a tap on a zombie needed eight
    attempts and a hotbar tap seven. That is not a touch bug: `onFrame` ended with
    `if (steps == 0) input.endTick()`, so any frame that ran no simulation step drained
    the one-shot presses — and above 60 fps a frame that has just spent the bank runs
    none. The probe's own line measured it: **0 of 20 taps reached the simulation at
    120 fps**. It hit taps, clicks and keys alike, on every device, worse the better the
    display; the 396-test suite never saw it because no test runs the loop at a frame
    rate. Rule 21 says record and do not fix, so this was put to the human, who chose to
    fix it here. The drain now belongs to the step alone, in the app and in the kit, and
    the same line reads **20 of 20**.
  - **What the fix dragged with it:** if a press survives across frames, anything reading
    one-shots *per frame* reads them twice. Only one place did — the kit's
    `VoxelGameWidget._tick`, which closed a screen on inventory / pause before calling
    `frame(dt)`. That moved into `VoxelGame.step`, which is where the drain is, and
    `PlayerEntity` stopped opening the bag: the step is now the single reader of both
    shared buttons (rule 25). The old arrangement had a latent bug of its own — the
    widget closed the bag, then the step in the same frame saw the same press and the
    player reopened it — which the dropped presses had been hiding.
  - **How it was trusted:** the app is the kit's witness now, because the code under the
    finger is literally `InputMap`'s. On seed 42 with `--touch --touch-probe`: a finger
    that stayed put dug a real block in 133 ticks with no button pressed; a tap that
    lifted in place put it back; a tap with a zombie under the crosshair swung for 1.0
    damage (`tapAttacks=true`, written by `Player._updateAim`); a 60 px drag turned the
    head 0.132 rad and mined nothing; a cancelled touch decided nothing; the on-screen
    stick walked 2.05 m, the jump button lifted 1.49 m and a slot tap selected hotbar 3 —
    every one of them on the first tap. The capture shows the phone layout over the world.
    `packages/voxel_game/example` was built and launched to see the changed widget boot
    clean; it has no probe flag, so nothing visual is claimed for it.
  - **A trap for the next session:** `tool/probe_baseline.sh --check` fails on this
    machine, and not because of this commit. `docs/baseline/*.log` was recorded on a
    1600x900 @1x window; this Mac renders 1512x900 @2x, which moves the camera-settle
    and site lines with it. A build of `be939852` in a throwaway worktree produced
    byte-identical diffs, so the comparison that matters — this tree against unmodified
    HEAD — is clean. Compare against a baseline *build*, never against the logs alone.
  - **What is left:** `CL-002`, the fixed-step bank still written twice. Its entry is
    amended: the copies shared the defect above, which is now gone from both, but the six
    lines are still six lines in two files, and the kit's `alpha` still has no user.
    Stage 44 has no row in the table above (the table stops at 33; stages 34+ live in this
    log), so this entry is where its touch scheme's new address is recorded.

- **2026-09-21 s22** — `CL-001` closes: the app stops owning a socket.
  - **What moved:** `lib/src/game/net.dart` had its own TCP transport under the Dawnforge
    protocol — a `ServerSocket`, a client `Socket`, a private `_Peer` holding a socket and a
    `StringBuffer`, a `_feed` that split newline-delimited JSON by hand, `_sendTo` and
    `_broadcast`. All of it was already in `voxel_engine` as `NetHost` and `NetConnection`,
    tested there and used by nothing in the app. Now `Net` holds a `NetHost?` when it hosts
    and a `NetConnection?` when it joins, and `dart:io` has left the file entirely. Roughly
    80 lines went; the other ~1,200 — mounts, boats, carts, chests, bobbers, prediction —
    did not move a line, which was the whole reason this was the cheapest entry to close.
  - **Why it was safe to do at all:** the two implementations already agreed on the parts
    that are contracts. The engine numbers peers from 2, exactly as `_nextPeer = 2` did, so
    no message that carries a peer id — puppets, `give`, `hurt`, `effect`, mount ownership —
    needed rewriting or a mapping table. The framing is the same newline-delimited JSON, so
    the wire is byte-identical and a Godot-POC-shaped message still parses. Nothing above
    the transport changed signature: `host()`, `join()`, `stats` and every protocol method
    kept theirs, so no caller of `Net.instance` was touched.
  - **The two places the behaviour is genuinely different, both on purpose:** the engine
    removes a peer from its own map before it calls `onLeave`, so `_onPeerLeft` no longer
    removes it — it only does the Dawnforge cleanup (puppet, mount, bag, chest watchers).
    And a malformed line now throws where the old `_feed` caught it and printed
    `[net] bad message`, which is what rule 5 asks for: a peer that sends garbage is a bug,
    not a condition to recover from.
  - **How it was trusted:** a real two-process pair, not the kit's `net_test.dart` —
    `--host` against `--join=127.0.0.1` with `--seed=42 --radius=4 --wait-peer --stage21b`.
    The host numbered the client peer 2, forced a storm, filled a chest, mounted a horse and
    handed over two iron ingots; the client's capture shows the host's puppet riding that
    horse in the storm, the chest read back as 3 apples, "Poisoned 6s" in the corner and the
    two ingots in the hotbar. The first runs read `effects []` and an empty chest, which
    looked like a regression and was not: the client was spending 15 s filling its window
    while the host ran ahead and quit. Dropping both to `--radius=4` lined the timings up.
    The poison line still flakes, so before trusting any of it a build of `e97dfb5a` was
    made in a throwaway worktree and run the same way — it flakes identically, because a
    poisoned client sometimes dies of the poison before it prints its effects. That is worth
    remembering the next time this probe accuses a change: compare against a baseline build
    rather than against the ROADMAP's prose, because the prose records one lucky run.
  - **What is left:** `CL-003` next (touch rises into `InputMap`), with `CL-002` riding along.

- **2026-09-21 s21** — the ledger opens, with eight entries and no fixes.
  - **The question that started it:** why does `lib/` import `package:voxel_game` in only two
    files? The answer is that it does not consume the kit's top half at all — two `show`
    clauses (`player.dart:33`, `mob.dart:8`) for `CharacterMotor`, `MotorTuning`,
    `ShoulderOrbit` and `ViewBob` — while importing `voxel_engine` twenty-five times and
    `voxel_scene` thirteen. The kit is eaten from below and barely from above.
  - **Why that is mostly right:** VK5 delegated exactly what is engine-neutral (locomotion,
    camera, rig) and left what is Dawnforge's look and content, and `VKD5` settled that the
    kit grows first and the POC moves onto it after. `voxel_game`'s `VoxelGame` is 490 lines
    against the app's 6,379 `Game`; that is not an import away, and `CLAUDE.md` forbids
    rewriting the POC wholesale for good reason.
  - **Where it is not right:** three pairs duplicate code that carries no Dawnforge flavour
    whatsoever — the TCP transport (`CL-001`, and the save *codec* was shared correctly in
    the same subject, so the reasoning existed), the six-line fixed-step loop (`CL-002`), and
    `GameInput` against `InputMap`, twins down to their seven imports. The third one is the
    lesson: stage 44 put a whole touch scheme in the app's half and none in the kit's, so the
    product cannot be played on a phone while the demo can, and all 381 tests stayed green
    through it (`CL-003`, `CL-007`).
  - **Recorded, not fixed** — rule 21. `docs/LEDGER.md` is new; its IDs are `CL-nnn` and not
    `L-nnn` on purpose, because the 2D track's ledger owns that space and its own `L-013` is
    the entry about two ID spaces one hyphen apart. `CL-004` and `CL-005` say what is *not*
    broken (`Worlds` vs `WorldSaves` are homonyms; the kit's default HUD and bag are right to
    differ — they are simply witnessed by nothing but an example app). `CL-006` and `CL-008`
    are documentation drift: `CLAUDE.md` rule 12 names one `ScreenKind` where two exist, and
    the VK decision register still answers `VKD1` with "five packages" and `VKD4` with
    `voxel_worldgen`, both deleted by VC1 two days after they were written.
  - **The order to close them, when someone does:** `CL-001` first (the protocol does not
    move, only the transport under it, and the engine's side is already tested), then
    `CL-003` (touch rises, `GameInput` becomes `InputMap<GameAction>` plus Dawnforge's
    extras), with `CL-002` riding along with either.

- **2026-09-20 s20** — a phone can play it: a stick, five buttons and a finger that knows
  what it means. *(Amended 2026-09-21, s23: the scheme described below now lives in
  `voxel_game`'s `InputMap`; `GameInput` is the Dawnforge binding tables over it. Behaviour
  unchanged — same slop, same mine delay, same tap rule.)*
  - **What was missing:** s19 (`3f886bde`, logged nowhere, so it is logged here) made the
    Backbone work on Android and iOS, locked both to landscape, and taught a touch to tell a
    tap from a look drag. What it left behind it said so in its own message: without a
    physical pad on the phone there was no way to walk, jump, open the bag or reach the pause
    menu — the one thing a finger could do was swing once.
  - **Why widgets and not the HUD painter:** a `CustomPainter` is handed a canvas and never a
    pointer, so a control painted there cannot be pressed. The controls are real widgets, and
    — this is the part that matters — they are *siblings* of the world's `Listener`, above it
    in the same `Stack`, not children of it. A `Stack` hit-tests front to back and stops at
    the first child that takes the touch, so an opaque button is the end of the road for that
    finger. Had they been children, every jump would also have arrived at
    `GameInput.onPointerDown` and been read as a tap on whatever the crosshair was pointing
    at: one press, two readers, the bug that closes a menu while opening another.
  - **One input, three devices:** `TouchControls` writes only to `GameInput` —
    `touchMove(x, y)` folds into `moveAxisX/Y` beside the left stick, `setTouchHeld(action,
    bool)` into `down` / `justPressed` beside the keys and the pad buttons, `touchHotbar(i)`
    into `hotbarPressed` beside the digit row. `Player` and `Game` are untouched by any of
    it and cannot tell a thumb from a key.
  - **What a finger on the world means** (Minecraft's own split, since a phone has no second
    mouse button): lift where it landed = *use* — a block placed, a door opened, a chest
    looked into — unless a creature is the nearest thing under the crosshair, and then it is
    a swing. `Player._updateAim` writes that one bit into `GameInput.touchTapAttacks` every
    time it re-aims. Stay put for 180 ms = mine, and go on mining until the finger lifts,
    still steering the view while it digs. Travel more than 12 px first = the camera, and
    nothing else. A gesture that mined is never also a tap on the way up.
  - **The stick sprints** at the rim (past 92% of the ring), which is how Minecraft sprints
    on a phone — there is no button for it, and there is no room for one. Sneak latches
    instead of holding: a thumb cannot hold a button and still work the rest of the screen.
  - **The HUD moved for it:** the stats column lived exactly where the stick had to go, so
    with the controls up it sits at the top left (past the pause button), the status effects
    stack downward from it instead of upward, the pickup toasts rise clear of the jump
    button, and the F1/FPS text drops under the column. All of it behind `Game.touchControls`
    — on a desktop nothing moved. The hotbar's nine rects are `Hud.hotbarSlotRect` now, read
    by the painter that draws them and the layer that taps them, so the two cannot drift.
  - **Seen running:** `--touch` turns the layer on from a desktop (`README.md`), and the
    capture at 1600x900 shows the stick, the cluster, the bag at the hotbar's end and the
    pause button in place. `test/stage44_test.dart` pins fifteen of these: the three meanings
    of a finger, the one-tick press, the latch, the rim, and the layer letting go of
    everything it held when a menu takes it off the screen.
  - **Still keyboard-only on a phone**, on purpose (asked, and deferred): the abilities R and
    Q, dodge, eat, drop, the map, the journal and the view toggle. The HUD still names their
    keys in a corner a phone has no keys for. The tutorial card is 600 px wide over a 852 px
    screen and covers the stats column; mobile render performance was not touched.

- **2026-09-17 s18** — you cannot see through a wall the camera is standing in.
  - **The bug:** in third person, with a block wall at the height of the head, turning until the
    back of the head was against it showed the whole cave system straight through the rock. A
    face is only drawn from the outside, so a near plane one centimetre past a wall is a near
    plane with nothing between it and everything behind. First person never did it, because the
    eye there is where the body already is and a body is swept out of solid rock every tick.
  - **Why the ray missed it:** `_updateCamera` cast one ray from the shoulder straight down
    `backVec` and seated the eye 0.35 m in front of whatever it hit — but never nearer than
    0.6 m, a floor that pushes the eye *through* any wall standing closer than 0.95 m, which is
    exactly the wall you get by backing into one. Three more gaps besides: the ray started at
    the shoulder while the eye also rises 0.15 m, so a ledge only the risen eye meets was never
    seen; the ray was a line while the eye carries a near plane around it; and the jolt
    (`_shake`) and the sway (`_bobOffset`) were added to the camera *after* the ray, so nothing
    had checked where they put it. On top of all that the pull-in was a lerp at 18/s, so a quick
    turn spent a fifth of a second easing the eye through the wall it was backing into.
  - **What replaces it:** `Player.clearDistance` sweeps the box the eye really occupies
    (`eyeRadius` 0.25 m, which covers the near plane's furthest corner at any FOV) along the
    exact segment the eye will travel — jolt and sway included — and stops at the last clear
    step. It marches **from the head outward**, never from the seat inward, so an air pocket on
    the far side of a wall is never mistaken for room the camera may have. The pull-in is
    immediate now and only the push-out eases. `Player.orbitOffset` eases the shoulder and the
    rise in with the distance, so an eye pulled all the way in lands on the head itself instead
    of beside it, inside whatever the head is standing against. `Player.blocksCamera` is the
    cell test: opaque cubes and anything that stops a body (glass, a shut door, a fence) —
    where the old ray also stopped on grass, flowers and torches, which the camera now passes
    through.
  - **Measured** over a wall at head height, 360 yaws x 17 pitches (6120 views): the eye landed
    inside the wall in **1602 of them before, 0 after**. It costs ~39 steps of at most eight
    cell reads a frame.
  - **Tests:** `test/stage43_test.dart` (12) pin the cell test, the box test, the sweep against a
    wall, a ledge only the rise meets, a jolt toward the wall, the pocket beyond a wall, a head
    walled in on every side, the eased shoulder, a step fine enough not to jump a one-cell wall,
    and the 6120-view sweep — with the rule it replaces failing that same sweep, so the test
    would catch the bug coming back.
- **2026-09-17 s17** — nothing of a tree floats: every block of one joins the next by a face, and the walk down those faces always ends on dry ground.
  - **Drawn before it is written:** a tree used to be stamped straight into the chunk, block by block, and whatever the chunk refused or a later builder overwrote was simply left out — with everything that hung off it still in. A tree is now drawn on a canvas of its own (`_ink`, in world coordinates), and `_blitTree` floods the six faces out from its stump and writes **only what the flood reaches**. A frayed leaf with nothing under it, a vine hanging where the crown had already thinned away, a branch touching the trunk by an edge: none of them reach the stump, so none of them is written. The flood also knows what the world will refuse (`_blockedAt`: inside the ground, or under the sea), and it reads that from the position, never from the chunk.
  - **The same tree from either side:** `_crown`, `_placeWillow` and `_vineFall` rolled their frayed rim on the **chunk-local** x and z, so the two chunks that share a tree frayed it differently and each wrote leaves the other had cut the support from. Everything is rolled on world coordinates now. The ground test moved the same way: `_treeGround` (dry land, no cave mouth under the foot) is asked of the position, where the old test could only be asked by the chunk that owned the column — the other one planted the tree regardless and wrote its half of the crown over nothing.
  - **Never in the water:** a beach or a frozen shore column sits under the sea up to `seaLevel`, and a trunk drawn there was refused block by block until it cleared the surface — which left a tree growing **on** the water. `_treeGround` refuses any column whose ground is not above the sea, and `_blockedAt` drops anything at or under `seaLevel`, so a crown may lean out over a pond but nothing roots in one. The beach's share went 12% -> 30% to make up for the row it lost: the waterline is the only dry beach there is.
  - **Nothing joins by a corner:** `_limb` and the palm's lean stepped diagonally, so a log met the one before it at an edge and the whole limb hung off that corner. Both step one axis at a time now and leave the corner block behind; the palm's fronds (`_frond`) do the same and droop by a face at the tip. Anything still joined by an edge alone is dropped by the flood, which is what makes the rule hold for shapes nobody has drawn yet.
  - **A village keeps the trees out instead of felling them:** `_clearTrees` cut every log, leaf and vine standing in a 24-block radius — and a crown whose trunk was inside the circle while it was not stayed hanging over the huts. It is gone. `_structureClearance` keeps a tree from rooting where a builder is going to write at all: the village's 24, a camp's 8, a ruin's and a temple's 6, a tower's 4, a well's and a mine's 3, each widened by `_reach` (6), which is the farthest any part of a tree stands from its own trunk. The dungeon is dug under the trees and asks for nothing.
  - **And the camp it found:** pitched on a slope, a camp held its corner post a block over the ground, and the five rows of its roof each sat one across and one up from the next, touching by an edge alone. The post reaches its own ground now (through a cave mouth if it has to, `_carved` — the cave test of `generateIn` asked about a single block, which `_treeGround` uses too), the lamp's block does the same, and the roof carries a block under each step.
  - **Measured** over 961 chunks a seed, judged by a flood from the ground over every log, leaf and vine: **floating leaves and vines 5627 -> 0** and **blocks joined only by a corner 3503 -> 0** on seed 1337, 0 and 0 on seeds 42 and 7. Over 625 chunks of shoreline: **logs resting on water 29 -> 0**, logs on a column the sea covers **305 -> 47** (all of them a branch reaching out over the water from a trunk on dry land, which is what a tree beside a pond does). Generating 256 chunks costs **4.35 -> 4.54 ms a chunk**, the 4% the canvas, the flood and the structure list add. `test/voxel_parity_test.dart` only moved two hashes: both chunks generate byte for byte as they did at s16, and chunk (0, 0)'s solid mesh changed because a tree in the ring beside it lost a block at the border.
  - **Tests:** `test/stage42_test.dart` (4): in a forest, a jungle, a snow wood and a swamp, every tree block walks home to the ground by its faces and every log does it over logs alone; the shore grows trunks and not one rests on water or under the sea; a palm leans and the whole of its trunk is still reachable from its foot; and a village has no leaf hanging over it.
- **2026-09-17 s16** — a wood you walk through: the trees stand twice as far apart and grow twice as tall.
  - **The spacing:** every column rolled its own tree (`_decorate`: forest 55 in 1000, jungle 38, snow 30, swamp 22, mountain 12, plains 6), so two trunks could stand side by side and a forest was a wall you squeezed past. The world is cut into 7 x 7 patches now and each patch holds at most one tree, never closer than 2 blocks to its border (`TerrainGenerator.treePatchOf`, pure position so every chunk agrees), so **no two trees are ever closer than 5 blocks**. How many patches are wooded is per biome (`treeChance`: forest 92%, jungle 47, snow 37, swamp 27, plains and mountain 20, beach 12, desert 8), about a quarter of the old per-column rate, which is what doubles the gap. The patch test is a hash, so it is asked before the height and the biome are sampled: a column outside the chunk is only ever looked at for its tree, and the small stuff (grass, flowers, mushrooms, reeds, cacti, melons — `_plantSmall`) stays on this chunk's own columns at its old rates.
  - **The trees:** all six are new shapes built from two helpers, `_crown` (a leaf ball squashed in y with a frayed rim) and `_limb` (logs stepping out and up with a small crown on the end). The **oak** is a bare trunk 9-12 blocks tall with two limbs and a crown over them (it was 4-6 with leaves from the second block up). The **forest giant** is a 2 x 2 trunk 14-18 tall, four limbs and a crown five blocks wide. The **jungle giant** is a 2 x 2 trunk 16-24 tall with a crown at the top, a second one halfway and vines falling 2-6 blocks from both rims. The **spruce** is 12-17 tall with tiers that widen downward and a bare trunk up to `max(5, trunk / 3)`. The **willow** is 9-11 tall under a canopy four blocks wide whose rim droops. The **palm** is new: a leaning bare trunk 8-12 tall under a star of eight fronds, and it is why the desert and the beach have a tree at all. Nothing of any of them hangs at head height.
  - **Measured** on seed 1337 over 5 x 5 chunks per biome, the old generator run beside the new one: nearest neighbour **forest 3.17 m -> 6.77, jungle 2.72 -> 6.03, snow 3.63 -> 7.64, swamp 3.12 -> 6.23, mountain 3.72 -> 7.41, plains 9.18 -> 12.29**; the closest pair anywhere **2.0 -> 5.0**; the columns a body cannot stand in (something at knee or head height) **forest 5.4% -> 1.6%, jungle 4.1 -> 1.8, swamp 4.6 -> 1.6, mountain 8.7 -> 1.9, and the snow, whose spruces used to skirt the ground, 30.3 -> 0.6**; the lowest leaf over its own column **+0/+1 -> +4/+5**; the tallest trunk **7 -> 19 (forest), 14 -> 21 (jungle), 9 -> 16 (snow)**. Generating 64 chunks got **faster**, 4.72 -> 3.90 ms a chunk, because the border ring no longer samples a height and a biome per column.
  - **What moved with it:** `_reach` 3 -> 6 (the widest crown plus the far side of a 2 x 2 trunk), the playground's clear margin around the plaza 4 -> 8, and a village fells trees in a radius of 24 up to 34 blocks over the ground (19 and 18), which is what a crown five wide on an 18-block trunk needs. `test/voxel_parity_test.dart` is re-pinned for the overworld: chunk (0, 0) hashes differently on purpose, while chunk (5, -3) (no trees), the underworld and the edit delta still hash as they did at `b57cf2a2`.
  - **Seen** on seed 1337 through `--tp=` + `--fp`: a forest of trunks with the canopy overhead and floor between them, a jungle the same, a snow slope of conifers, a swamp of willows over the pools, and a desert of palms.
  - **Tests:** `test/stage41_test.dart` (3): every column of a patch names the same spot and no two spots are closer than five blocks over 400 x 400 columns; a forest, a jungle, a snow wood and a swamp each keep under 3% of their columns blocked, no leaf under +4 and a trunk of at least 13; the sand grows a jungle-log palm, and `treeChance` is zero for the ocean and highest for the forest.
- **2026-09-17 s15** — one reach for everyone, a step that is jumped, water that is swum, and a saddle you can work from.
  - **Reach:** aiming at a block with a creature behind it acted on the creature. `Player._updateAim` picked the nearest mob and the nearest block separately and then kept **both**: `aimedMob` stayed set even when the block was nearer, and mining refused while it was (`_mineTick` bailed on `aimedMob != null`). `Game.meleeStrike` never looked at the blocks at all, so a swing went through a wall, and a creature's own bite (`Mob._stateThink`) never did either. There is one rule now, in `lib/src/game/reach.dart`: what is nearest along the line is what is acted on. `Reach.toBarrier` is `VoxelRaycast.barrier`, a new shape-aware cast in `voxel_core` that returns the first **collision box** on the line rather than the first cell — so grass, a flower and the gap between two fence posts are not in the way, because a body walks through them, while a wall, a closed door and a fence post are. `Reach.nearestBody` is the one loop that picks a body no farther than the reach and never behind that block: the crosshair's creature, the boat, the cart and the mount all go through it, the swing goes through it, and `Mob.canReach` gates both entering the attack state and staying in it. The crosshair still mines and places at whichever of the block and the creature is nearer, so a block in front is mined while a creature behind grass is still swung at.
  - **The step:** `VoxelBody.tryStepUp` lifted a body onto a step in one tick. The player had stopped using it (`Settings.stepTeleport`, off by default), every mob had not, and a ridden horse teleported a floor up a staircase. It is gone from the package, and with it the setting, its config key, its switch and `--step-teleport`. What is left is `VoxelBody.stepAhead`, which only *reads* the step just walked into (`halfStep` 0.52, `fullStep` 1.02, or 0). Everything jumps it: the player as before (a half step hopped under double gravity, a full one jumped), and now `Mob._stepJump` for every creature, on its own legs or under a rider. A swimmer pushing at a bank launches over the lowest lip that fits, which is how the player already climbed out.
  - **Water:** a mob moving in a liquid got `velocity.y = 3.0` every tick, which pushed it to the surface and kept it there — so horses, ridden or not, walked on water. `Mob.swimming` is `inLiquid && !wading`, the same line the player draws, and a swimmer now paddles up only while its head is under (`swimStroke` 20, `swimRise` 2) and sinks at the liquid's gravity when it is out. It rides the surface instead of standing on it, and swims at `swimSpeedMult` 0.6 of its speed. Wading through a one-block puddle is untouched.
  - **The saddle:** mounted, you could not mine. `Player._mountTick` had its own copy of the end of the tick and that copy called `_attackPressed` on the button instead of `_attackTick`, which is what mines. It calls the shared `_finishTick` now, so the crosshair, the swing, the mining and the placing are the same code on foot and in the saddle.
  - **The playground:** stamina and mana are endless there (`Player.endlessStats`, `hasStamina` / `spendStamina` / `hasMana` / `spendMana` — the twelve scattered `stamina -= …` and `mana < …` sites now go through those four).
  - **Probes:** `--move-probe` walks a cow and then a ridden horse up a staircase of three whole blocks (both reach the top, largest rise in one tick **0.126** — a jump; a lift would be 1.0) and swims the horse across a pool four blocks deep (**59 of 68 ticks swimming, 0 standing on anything, 0 at the surface once sunk in, deepest 1.72 m under it**, then out on the far bank). `--reach-probe` (new): with a wall between, the crosshair holds the block, no creature is aimed, mining runs and a swing does **0.0** damage through it; with the wall gone the same swing does 10.0. A walled zombie does **0.0** damage over three seconds and 8.0 once the wall is taken away. From the saddle, the aimed dirt block breaks after 144 ticks.
  - **Tests:** `test/stage40_test.dart` (4): a creature behind a block is out of reach and in reach once it is broken; grass is aimed at but never in the way, and a fence is passed between its posts and stopped at one; a slab reads half a step and a block a full one while a wall reads none, and reading a step never moves the body; deep water is swum and a one-block puddle is waded. `voxel_core`'s `physics_test` and the app's `stage22_test` walk their bodies with the jump in place of the lift.
- **2026-09-16 s14** — one map in two sizes, and a dash in place of the roll.
  - **One map:** the minimap and the world map were two classes that each built their own bitmap. The minimap painter stretched its 128-block bitmap (96 shown plus 16 of margin each way) over a panel whose creature dots were scaled for 96 blocks. So the ground and the dots never matched, and the ground stood still between rebuilds. The sliding promised in `24fa7ce3` had only reached the bitmap, never the painter. `Minimap` is gone. `WorldMap` is the only map, `HudPainter._drawMap` draws it (bitmap, markers, creatures, arrow) through a `MapFrame` (window, world centre, pixels per block), and it has two frames. The corner is 240 px around the player at 2.5 px a block. The full frame is the whole bitmap fitted into the panel. `Game.mapView` (`MapView.off / corner / full`, in `hud_state.dart`) replaces the two booleans. M steps through them, so one frame is drawn at a time: the full map no longer paints over a live minimap. `Game.mapOrigin` (the old drift probe's hook) is replaced by `mapStats`.
  - **What that costs:** a whole rebuild of the loaded window (304 x 304 px at the default distance) took about 35 ms. That was fine for a map opened now and then, not for a corner map that is always on. The bitmap is now kept as one 16 x 16 tile per chunk. It is refreshed in laps: missing tiles first, up to 2 ms a frame, 1 s of rest between laps, and every missing tile painted at once when the map opens. The tiles are composed into the image once a second. The biome cache is kept across laps. `--map-probe`: 361 tiles, 0.19 ms a frame on average (worst 2.3), composed in 0.2 ms. Both captures show one map each.
  - **The dash:** the dodge spun the whole model a full turn around its feet (`tiltX` -2π). It is now a pose: `PlayerModel.dashing` blends in a forward lean (-0.45 rad), the arms thrown back (-1.35 rad, a little out), and the legs open (0.75 / -0.6). The body turns to face the dash at once, and the dash hops 4 m/s (about 0.3 m). It used to go along `_lastMoveDir`, which is the way the body faces. Walking backward, the body faces forward, so a backward dodge went forward. It now goes along `_moveWish`, the way the input pushed, and falls back to the facing only when standing. `--anim-probe`: a backward dash moved 6.95 m along +X, facing off by 0.00 rad, pose in 1.00, arms -1.35, legs open 1.35 rad, rose 0.28 m, pose out 0.00 afterwards; `_dash.png` shows it from the side.
  - **Tests:** `test/stage39_test.dart` (3): M steps off → corner → full → off; the corner frame puts the player at its centre over the bitmap's own corner block, and clips 48 blocks out; the full frame is the same transform around the fitted bitmap.
- **2026-09-16 s13** — a ladder you can bump into, a fence you can jump, a pen that still holds, the music's own volume, and flying that walks.
  - **The ladder's collider:** a ladder was not solid, so it stopped nothing. `collisionBoxesAt` now gives it one box, the one the outline already drew (`ladderBoxAt`, moved from `selection_box.dart` to `block_collision.dart` and shared): its rails and rungs, 0.12 deep on the wall it hangs from. A body stops against the rungs and still stands in the ladder's cell, so `_onLadder` still reads it and jump still climbs. `--outline-probe`: the player stops 0.421 into the cell (0.12 + 0.3 + skin) and rises 4.5 m, up the three-high ladder and onto the wall.
  - **Walking out of a box:** a ladder can be placed on a player standing against the wall (it is not solid, so placement does not refuse it), and a fence arm can grow into a player when a neighbour is placed. `VoxelBody.move` used to snap a body out of any box it overlapped, which here meant through the wall. A box the body already overlaps at the start of the move is now ignored, so the body walks out. On y this only applies to a box the body is beside (`_beside`: less overlap from the side than from above or below), so a body sunk into the floor is still lifted onto it.
  - **The ladder's flicker:** the rungs ran the full width of the rails, so their ends lay in the rails' outer planes. They now stop 0.005 short on each side (0.01 narrower in total), inside the rails.
  - **The fence is one block:** the post and arms were 1.5 tall while the fence is drawn 1 tall. `CollisionBox.fencePost` is now 1.0, so the player jumps onto a fence and over it (the jump rises about 1.4 m). To keep animals in, `VoxelBody.fenceBarrier` makes the same fence `fenceBarrierHeight` (1.5) tall for that body only: `fenceBoxesOf(joins, barrier: true)` is a second cached table. Every `Mob` sets it and clears it while ridden, so a rider jumps fences the way the player does. A mob's 8 m/s jump rises 1.23 m and a full step-up needs 1.02 m of clearance, so neither gets over the barrier. `Pathfinder.walkable` no longer counts a fence top as a floor, so a mob does not plan a route over one either.
  - **Music volume:** `Settings.musicVolume` (`[audio] music_volume`, 0..1) scales `Music.gain` alone, applied at once to the playing track (`Music.setVolume`) and to every crossfade after. The master volume still sits over both. There is a new slider under "Master volume".
  - **Flying:** fly mode (F5) animated the player with the glide pose (arms spread, legs still) and never turned the body. The tick's facing and limb code is now `Player._faceAndAnimate`, which the fly branch calls as if on the floor, with the stride slowed by `flySpeedScale` (2.5) so the legs keep a walking pace. `--anim-probe`: arm spread 0.00 rad, legs -0.65..0.65, 0.00 when hovering still.
  - **Tests:**
    - `test/stage38_test.dart` (3): the music volume saves apart from the master and clamps; it applies without an audio device; a mob never plans a path over a fence line, but does over a solid block.
    - `stage22_test`: the player crosses a fence, and a barrier body stops flush and never clears it.
    - `voxel_core` `physics_test` (+5): the player jumps a fence line; a barrier body with the same jump does not; a ladder stops a body at its rungs, which still climbs; a body a ladder is placed on walks out, and the wall still stops it; a body sunk in the floor is still lifted out. The join-mask test also pins the barrier table.
- **2026-09-16 s12** — a list that scrolls, fences that stop you, and a giant outlined to the top of its head.
  - **The craft list:** the inventory rolled its recipes only on a `PointerScrollEvent`, which is a mouse wheel. A macOS trackpad's two-finger swipe arrives as a pan-zoom gesture, and a finger as a drag, so neither moved the list. The list is now a `PanelScroll` (the journal's pixel scroll, with its bar), and `PanelScrollInput` feeds it from a wheel, a trackpad pan and a finger drag past an 8 px slop. On touch, a tap acts when the finger lifts, so a drag never crafts. The journal takes the same input.
  - **Fence arms:** `VoxelBody` collided with a fence's lone post only, so a joined run could be walked through between posts. `voxel_core` gets `block_collision.dart`: `fenceJoinsAt` is the join rule the mesher draws by, now shared with the outline; `fenceBoxesOf(joins)` is the post stretched along each joined axis, 1.5 tall (16 cached lists); `collisionBoxesAt(query, x, y, z)` is what the body sweeps against.
  - **The giant zombie:** the `Giant` affix scaled the drawing by 1.4 and left the collider alone, so the outline (the collider) stopped at the neck, and a shot at the head missed. `setAffix` now grows `halfWidth` and `height`, and the model's size is `Mob.sizeScale = height / species.height`, so the drawing follows the collider and cannot outgrow it.
  - **Future mobs:** `--outline-probe` now builds all 29 species at all 7 sizes (203 bodies) and lists every model over its collider's top. The first run found the birds (0.80 m models in 0.60 / 0.45 / 0.40 m colliders) and the scorpion (0.65 in 0.60). `_buildModel` now shrinks any model taller than its collider into it (`_modelFit`); a shorter one (the horse) is left as built. Result: worst overshoot 0.000 m; the giant's outline top, collider and model are all 2.52 m (`_giant.png`).
  - **Tests:**
    - `test/stage37_test.dart` (7): the wheel, trackpad and finger roll and clamp; a mouse drag never scrolls; a click reads the scrolled row; a giant's box and ray reach its head; every affix scales width and height together.
    - `voxel_core` `physics_test` (+5): a joined line stops a body between its posts; a lone post lets one pass beside it; an arm reaches a joined wall; all 16 join masks; air and a slab answer from their shape.
- **2026-09-16 s11** — one pickaxe, drawn in three places. **The first-person pickaxe:** its points ran left and right across the screen. `HandView` (s9) took `heldItem()` straight into the fist with only the lean into the screen, and missed the quarter turn about the shaft that s4 gave the third-person model. The two hands now share that turn (`VoxelMeshBuilder.headInSwingPlane`), and the first-person pose is `HandView.toolPose`. `--item-probe` measures the pickaxe head in the camera's own axes: **right 0.00**, up -0.58, into the screen -0.81. **One model per item:** until now an item was drawn three ways. The hand used a voxel model, the ground used a cube (or a tinted 3³ lump for anything that was not a block), and the bag used 2D glyphs painted on a canvas: a line for a pickaxe, a circle for food, a diamond for a material. `VoxelMeshBuilder.itemShape(id)` is now the only description. It returns an `ItemShape`: the voxel map, the scale, the grip origin, whether the model is flat (tools, weapons, armour, gems) and whether it is carried like a block. It is built once per id and cached. The hand in both views, the drop and the icon all read it. Blocks that are not a box in the world are not a box here either: a torch is a post with a flame, grass is two crossed diagonals, a flower is a stem with a head, and a slab is half a cube. Food became a filed-off lump, armour a chest piece and materials a cut gem, so the kinds still read apart without the glyphs. **The drop** (`ItemDrop.dropModel`) is the hand's node, centred on its bounds and scaled to a fixed size along its longest side: 0.28 m for a lump (a block, an apple) and 0.40 m for anything long (a tool, a torch, a flower). **The icon** (`lib/src/ui/item_icon.dart`) is not a 3D render per slot. flutter_scene's `RenderTexture` renders the whole scene into a GPU texture, which a hand-painted `Canvas` panel cannot take, and a second camera for every slot would cost a scene render each. Instead each model is projected once, on first sight, orthographically: flat pieces face the eye with the shaft on the diagonal, blocks are seen from a top corner. The exposed faces are shaded by a fixed light and painted into a 128 px `ui.Image` that is cached per id, so every frame after that costs one image copy per slot. Painting whole voxels from back to front is exact for an orthographic view of a grid, so no depth buffer is needed. `Hud.drawItemIcon` keeps its signature and now draws that image, so the hotbar, the bag, the recipe list, the trade screen and the cursor stack all changed at once. `--item-probe` fills the bag with a spread of kinds and drops one of each on a cleared pad. For each it prints the model size, the drop scale and the icon face count (pickaxe 0.41 × 0.45 m, x0.89, 39 faces; stone slab 0.36 × 0.18 m, x0.78, 32 faces). It captures `_drops.png` (the drops under the hotbar), `_fp.png` (the pickaxe in the fist) and `_bag.png` (the inventory). `--model-probe` still shows the block hanging off the fist in third person. Six tests pin these pieces:
  - every item has a model, built once;
  - the first-person head never points across the screen;
  - the two drop sizes;
  - every icon face fits the square, painted back to front;
  - a cube shows exactly its three 4×4 faces;
  - the model fills the square along its longer side.

- **2026-09-16 s10** — legs that stop flickering, and an outline that hugs what it outlines. **The flicker:** sheep, cows, pigs and horses flickered at the bottom of the barrel above each leg. A quadruped's barrel is `(halfWidth * 22).toInt()` voxels wide and its legs sit at `bodyW / 2 - 1.5`; when that width is odd (9 for a sheep or a pig, 11 for a cow or a horse) the leg's outer face lies exactly in the plane of the barrel's side, over the one voxel the leg sinks into it, and the two faces fight for the same pixels. The wolf, the ocelot and the bear are even and never did. Legs are now built centred on their pivot and drawn `Mob.partInset` (1 cm) in on each side about their own middle — 0.16 m where they were 0.18, which the eye does not catch, where a hundredth of a percent would have left the planes 6 µm apart and still fighting at any distance. The humanoid mobs' arms sat at 0.33, the pivot s4 moved off for the player (0.345) and left behind in `mob.dart`; they are at 0.345 now, and the tail hangs 1 cm off the rump. `--outline-probe` builds all 29 species and checks every pair of rest-pose part boxes for a face in the same plane facing the same way (faces meeting head on, like a leg's top against the belly, hide each other and are not counted): **before, sheep, cow, pig and horse, four legs each; after, 0 of 29.** **The outline:** the skeleton of sticks was always a whole cell, and a block flush with its neighbours lost the edges it shared with them, because half of each stick was inside the neighbour. It is `SelectionOutline` now (`lib/src/entities/selection_outline.dart`): twelve unit sticks stretched to any box, drawn 6 cm toward the eye through flutter_scene's `Material.depthBias`, which clears the centimetre a stick sinks into a neighbour while a cube's far edges stay behind the cube. The box is the thing's own. For a block it is `selectionBoxAt` in `voxel_core`, the bounds of what the chunk mesher draws in the cell — a torch's post, a slab's half, a door's panel (not its knob), a flower's head and a grass tuft where their jitter put them, a fence post reaching toward what it joins, a wall torch and a ladder on the wall they hang from, read in the mesher's own neighbour order; rails keep their whole footprint, since a curve's box would look lopsided. For a mob it is the collider (`Player.mobBox`), the same box the crosshair ray hits, so a creature in melee reach is outlined where before nothing happened. `--outline-probe`: a dirt block sunk flush in the floor shows all four top edges, the torch reads 0.20 × 0.62 × 0.20, the slab 1 × 0.5 × 1, the fence post 0.25 × 1 × 0.25, the door 1 × 1 × 0.19, the flower 0.28 × 0.62 × 0.28, the wall torch 0.20 × 0.55 × 0.20 against its wall, and the sheep 0.90 × 1.10 × 0.90, its collider; captures `_block.png`, `_torch.png` and `_mob.png`. `voxel_core`'s `selection_box_test` meshes every shape alone (the leaning ones against a wall in the neighbour chunk, which the mesher reads but does not draw) and pins the box to the mesh's bounds; seven app tests pin the plane check, the inset, the mob box and the bias. The probe marks every species as seen in the save slot it runs in.

- **2026-09-15 s9** — a calm eye and a hand that carries the walk. The bob was still too strong to play with: the eye is the one thing a player cannot look away from, and a camera that swings enough to be *noticed* is a camera that makes people ill. It drops half as far now (`Player.bobAmplitude` 0.05 against s7's 0.09) and sways a sixth of that instead of a half (`bobSwayRatio` 0.16), with the roll and the nose-up cut to match — `--move-probe`: **drop 0.0463, sway 0.0079, ratio 0.17**, standing 0.0000, back to 0.0000 after stopping, third person 0.0466 at the same 4.6 m/s. The s8 saddle figures scale with it from the one constant (`--anim-probe`: on foot 0.0500 in both views, the trot 0.1698 against the 0.1700 the 2.0 multiplier asks for, the gallop 0.2210) — the probe's printed expectation reads `Player.bobAmplitude` now rather than repeating the number. **What replaces it is the hand** (`lib/src/entities/hand_view.dart`): in first person the body model is hidden and there was nothing on screen at all, while in Minecraft the largest moving thing is the forearm and the item in the corner. There is one now — a 4×4 voxel forearm in the player's own skin and sleeve with whatever `heldItem()` returns in its fist, a tool standing up out of the grip and a block turned off-square so two faces catch the light. It sways about five times as far as the eye and **lags it by a fifth of a step**, and that slip is most of what actually reads as walking. A swing throws it across the corner over Minecraft's six ticks, front-loaded by a sine of the square root, so the strike is fast and the return lazy; every attack, dig and place in `player.dart` goes through the new `Player.swingArm` so the body's arm and this one can never fall out of step. This renderer has no separate view pass, so the hand is an ordinary world-space node whose transform is rebuilt every frame from the camera's own basis — the same roll and nose-up the camera gets, or the arm would slide across the screen whenever the view leaned. New probe flags: `--hold=<item>` puts a named tool or block in the selected slot and `--swing=N` starts a swing N frames before the shutter, which is how the arc was walked frame by frame until it stopped leaving the frame.

- **2026-09-15 s8** — the creatures move, and the saddle moves the camera. **Wings:** a bird had none. A `bird` body now carries two, built reaching out +X and mirrored through the new `VoxelMeshBuilder.mirrorX` for the other side — a voxel at x covers [x, x+1], so its mirror covers [-x-1, -x], and rebuilding the map keeps Godot's winding where a node scaled by -1 would reverse it and light the wing off its far faces. A flier beats them the whole time it is up (`wingRate` 22 rad/s, about three and a half beats a second, `wingSweep` 0.95 up and the same down, with a `cos` twist on the tip so the beat is a stroke and not a hinge); a ground bird beats only while its feet are off the floor and folds them otherwise. The fold is an angle **and** a span — voxels cannot fold the way feathers do, so `wingFoldSpan` draws the wing in to 45% as `wingFold` lays it down the flank, or a standing chicken wears two boards. **Every other body got the same treatment:** the walk eases in and out on a weight instead of switching at a 0.3 m/s threshold (legs used to drop mid-stride and flutter at the threshold); the cycle rate is per body (`Mob.gaitRate`, a chicken takes more steps over the same ground than a horse does); a quadruped's barrel rises twice a cycle with its head nodding a beat behind, and it grew a tail, hung off the barrel's **back face** rather than its centre line — `bodyLen / 2` puts a tail inside the animal; a spider walks the alternating tetrapod every eight-legged animal uses (legs {0,3,4,7} against {1,2,5,6}, reach on `ry` over the resting splay, which is kept in `_legFan` so the gait does not eat it) instead of a sine ripple down the row; a humanoid's arms swing against its legs and its shoulders twist, and the **arms-out shamble is now the undead's alone** (`Mob.armRest`) — an archer, a villager and the Underworld Lord used to shamble too; a melee swing is an arc over `attackSeconds` instead of an angle written onto the limb and left there for the walk to lerp away; a blob stretches off the top of a hop and splats on the tick it lands. **The trot:** riding never had a camera of its own and still does not — the saddle is the walk's own sway multiplied, by four numbers and nothing else (`Player.trotAmplitude` 2.0, `trotCadence` 0.55, `trotRoll` 1.6, `gallopBoost` 1.3), in first and third person alike, so the whole gait scales from one place. `gallopBoost` has to exist because a horse at 8.5 m/s is already past the speed clamp at a standing trot, so speed alone cannot tell a trot from a gallop. `--anim-probe`, new: a flying parrot sweeps -0.95..0.95 rad while a chicken on the floor holds the fold at -0.95, and the same chicken dropped four blocks beats -0.95..0.85 on the way down; sheep, zombie, spider and chicken all swing their legs walking and settle to -0.00 stopped; a slime reaches 1.190 tall in the air and 0.824 flat after landing; the camera peaks 0.0900 on foot in both views, **0.3058 first person and 0.3057 third in the saddle** against the 0.3060 the multiplier asks for, and 0.3978 galloping against 0.3978, over 16.4 m ridden. It captures `<name>_wings.png` (a parrot's wings out beside a chicken's folded) and `<name>_walk.png` (a horse from behind, its head 0.66 m ahead and its tail 0.72 m behind its centre, so the tail is clear of a barrel that is 0.66 m long each way, and each fore leg matching the hind leg diagonal from it). Twelve headless tests pin the mirror, the beat, the gait rates, the arm rest and the saddle's multiplier.
  The camera half of this work is in `07bd6579`, not here: a session working in parallel committed `player.dart` while it was still being edited. That commit is left alone (CLAUDE.md §Parallel sessions); this one carries the creatures, the probe and the tests.

- **2026-09-15 s7** — six playtest fixes. **View bobbing, again:** s6's sway was disliked, and rightly — it swung the eye as far sideways as it dropped it, which reads as a lurch, and Minecraft's does not. `bobView` there drops the eye by `|cos|` of the walk phase and sways it by `sin` at **half** that width, with about a third of a degree of roll and half a degree of nose-up on each footfall; that is now the shape here, cycle for cycle, at one cycle (two footfalls) every 3.3 m walked instead of s6's 2.3. It also bobs in third person now, as Minecraft's whole view does — the view is bobbed before the camera swings out behind the shoulder. `--move-probe`: drop 0.0865, sway 0.0442, **ratio 0.51**, standing 0.0000, back to 0.0000 after stopping, third person peak 0.0858 at the same 4.6 m/s (the two views bob alike). **Distance fog:** the world ended on a row of chunk edges hanging over nothing. The fog is now linear and tied to the render distance — it starts at 45% of the nearest chunk edge and reaches full cover at 92%, so the horizon dissolves into the sky while the near world stays clear, and rain or a storm pulls the band in. It also had to stop asking for the sky colour: `skyColorInfluence` samples the prefiltered radiance cube, and this scene's environment is a constant-diffuse one with no such cube, so the sample comes back **black** — invisible while the fog was a faint 0.003 haze, but at full cover it painted the far chunks in silhouette. `_updateSky` already writes the live horizon colour into `fog.color` every frame, which is the colour that sample was meant to find. **Held blocks:** a tool was turned a quarter about X to lay it forward out of the fist, but a block was not, so it grew up the +Y of a hand whose +Y runs back along the forearm — the block ran through the arm. Blocks take the same turn and drop half their depth, so one hangs from the fist with a face on the palm. **The saddle:** a rider stood on the horse's back. `Player.saddleOffset` added 0.6 to `centre()`, which is half the *collision* height, and for a horse that box is 0.4 m taller than anything you can sit on; `Mob.backHeight` is now filled by `_buildModel` from the voxels it actually laid down (a horse's barrel tops out 1.20 above its feet, not 1.60) and `Player.saddlePosition` seats the rider `saddleSink` 0.72 below it, so the hips land on the back line and the legs are inside the barrel. **Settings rows:** every switch row was pinned to 36 px, so the three labels that wrap at the pause panel's width overflowed their box and drew over the row beneath. They size themselves now. (The pause menu already scrolled; the overlap was never the scrolling.) **The credits' Back button:** it did nothing, while Esc — which does not go through a gesture — always closed the screen. The scroll was driven by a `setState` on the whole screen sixty times a second, which replaced the button's own subtree under every press; the clock is a `ValueNotifier` now and only the moving text rebuilds. The roll's height is also measured with a `TextPainter` instead of read back off the laid-out `Text`'s render object, which a widget has no business doing mid-layout. Both were checked by driving the real app with synthetic mouse events. `--model-probe` gained the two captures that prove the block and the saddle.

- **2026-09-15 s6** — three playtest fixes. **View bobbing:** the camera was rigid. It now carries a sway whose cycle is advanced by distance covered rather than by time, so one constant fits every gait and a sprint bobs faster as well as wider (peak 0.055 m): two dips per cycle against one side-to-side sway and one roll, the whole thing weighted in and out by `lerpd` so starting and stopping never snap. It rides the camera only — `aimOrigin` and `aimDirection` are untouched, so a bobbing head never misses a block — and it is first person only, off the floor it stops, and `Settings.viewBob` (`[video] view_bob`, a row in the settings panel) turns it off for anyone it bothers. `--move-probe`: standing 0.0000, walking peak 0.0548, two side-to-side crossings, back to 0.0000 after stopping. **The maps:** the minimap's ground bitmap was the only layer carrying the player's position and it was rebuilt once a second, while the creature dots were redrawn every frame from the live position — so between rebuilds the ground stood still and every dot appeared to drift backwards under a centred arrow. Both maps now share one transform: `toScreen(x, z)` for the ground, the creatures and the markers alike, with the minimap's image drawn at its own published `originX/originZ` and clipped to the panel, so the world slides continuously under an arrow that holds the centre. The bitmap samples 16 blocks of margin beyond the 48 shown to slide on, rebuilds when the player eats into that margin as well as on the timer, and floors instead of truncating (`toInt` shifted the sampling grid by a block across x = 0). The world map, which had no creatures at all, takes the same `_drawEntities`; its own framing — world fixed, player arrow moving — is kept, because that is the professional pair (HUD map centred on the player, full map centred on the world), and only the drawing is shared. `--map-probe` (new): the bitmap's drift from the live player saws between 0.9 m and 4.5 m while walking, which is **11.3 px of ground slide the old painter threw away**, and the peak stays well under the 16 blocks of margin. **Shallow liquid:** standing in a one-block puddle made the body tremble. `inLiquid` was a raw per-frame point sample at the feet (0.3 above the soles) with no hysteresis, and in a one-deep pool the probe rides the cell edge: the state flipped every tick and took gravity (4 vs 26), the speed, the sprint, the FOV, the splash and — through `onFloor` — the whole pose with it, and `PlayerModel` assigned its limb angles and body bob with no smoothing at all. Three fixes: entering a liquid is still decided at the feet probe but leaving is decided at the soles, 0.3 lower, and that gap is the hysteresis; `VoxelBody.wading` (on the floor with the head clear) walks, jumps and falls under full air gravity like Minecraft's one-block puddle, while `Player.swimming` keeps the swim rules for water deep enough to cover the head; and the model blends the walk and airborne poses in and out instead of switching. The air gravity for a wading body is not cosmetic: at the liquid rate one tick of falling moves the body less than the 0.001 skin, so the sweep misses the floor every other tick and `onFloor` flickers on its own. `--move-probe` puddle: liquid flips 0, floor flips 0, airborne ticks 0, feet y span 0.0000 over 150 ticks (before the gravity fix: 150 floor flips in 150 ticks); the deep-water bank exit still lands in 76 ticks with 0 falls back. Three `voxel_core` tests pin the hysteresis, the puddle and the head-under case.

- **2026-09-15 s5** — three playtest fixes. **Journal scroll:** every tab drew its rows straight past the panel's bottom edge. `PanelScroll` (`lib/src/ui/hud.dart`) clips a body, shifts it by the wheel and draws a bar when the content is taller than the box; a click is mapped back with `toContent` before it is matched against a recorded row, so the rects stay in the space they were painted in. The journal keeps one per tab (a list is left where it was left), and any hand-painted panel that can outgrow its box takes the same class. `--journal=1` / `=2`: the bestiary's 29 rows and the achievements' 22 stop at the panel's edge with the bar on the right. **Ladders:** a ladder was `BlockShape.cross`, the two crossed sheets grass uses. `BlockShape.ladder` (index 25, appended — the enum order is the mesher's byte contract, `shapeIndices` and `grid_test` pinned with it) draws two rails and four rungs flat on the first opaque horizontal neighbour (-z when it hangs on nothing), the rungs standing a little proud of the rails so it reads as a ladder from the side; one `u` along the wall / `v` out of it mapping serves all four facings. `--playground --shots=building`: the ladder wall reads as rails and rungs. **Block outline:** s4's white film (a 1.004 cube at alpha 0.16) fought the block's own texture; it is gone, and the outline is now a skeleton of twelve cuboid sticks 0.03 thick in a 75% white, 0.005 off every face (0.01 wider than the cell), so it sits outside the texture instead of over it. Found on the way and worth knowing: **a `LineSegmentsGeometry` node never reaches the screen in this build** — opaque or blended, thin or thick — so the black outline that had stood in `Player` since early on was invisible too, and s4's film was the only thing ever seen on an aimed block; stage 32's crack lines are built the same way and are probably invisible in play (not verified, not touched). `--model-probe` now aims at a block STANDING on the pad rather than sunk into the floor (a flush block buries eleven of the twelve edges in stone and lays the rest in the floor's plane, which shows nothing whatever renders); the capture shows the sticks framing the cube.

- **2026-09-15 s4** — seven playtest fixes. **Swing:** s3's roll toward the chest sank the hand into the torso; the chop now stays in the swing plane. **Arm flicker:** the arm is 0.22 wide on a pivot at 0.33, so its inner face sat exactly on the torso's side (x = 0.22) and the two z-fought; the pivots moved to 0.345 and the rest `rz` is 0 (straight, parallel). The old rest, glide and climb `rz` / climb `rx` signs all pointed the hands inward or backward and are flipped (a positive `rz` carries a hanging hand to +X). **Humanoid mobs:** arms were held at `rx` -1.4 (backward); now +1.4, attack +2.4. **Held items:** the flat XY shape gets a quarter turn about its shaft before it tips forward, so a pickaxe's points, an axe's blade and a sword's edge lead the chop instead of facing sideways. **Player texture:** the shirt softened 20% toward warm grey, with a darker hem and cuffs, a belt with a gold buckle, a neckline, a two-tone leg with boots and soles, and a face (fringe, brows, white + blue eyes, nose, cheeks, mouth); `Player.skinTone` / `pantsTone` / `hairTone`. **Hover:** the aimed block gets a white film (1.004 cube, alpha 0.16, `Player.hoverGlow`), as in Minecraft. **Water exit:** swimming rises at most 4 m/s and stops when the feet leave the water, so a bank one block high was cleared only by luck; swimming into a bank with jump held now launches over it (the lowest lift up to 1.9 that `stepFits`, plus 0.25), and a swimmer bobbing out of the water still counts for 0.5 s. **Backward walk:** a step more than 90° from the camera faces the body the opposite way, walking backward as in Minecraft. `--move-probe`: water exit on the bank after 76 ticks, 0 falls back; backward body yaw 0.00 both ways; half step, step, teleport and climb unchanged. `--model-probe` (new): three poses and a zombie captured from the front.

- **2026-09-15 s3** — four playtest fixes. **Sound:** the synthesised footsteps and the procedural music loops (the Godot POC has the same ones) are replaced by the Dawnforge 2D game's own audio, copied from `tessera_project/games/dawnforge/data/audio` into `assets/audio/`: the player's `sound_footstep` takes (forest, desert, snow, swamp, lava — `Player.stepKind` picks one per block) every `footstep_interval` 0.4 s instead of every 0.45 m, and each biome's `music_playlist` / `cave_music_playlist` streamed with `LoadMode.disk` (Meadow and Jungle Village Market, Dunes Stardust Dreams, Frost Fishing by the Lake, Marsh Raindrops on the Roof, Underworld Nighttime Fireflies, underground Rites of Passage; night keeps the day's track). **Arm:** the right-arm swing turned the arm backward; it is now Minecraft's `HumanoidModel` attack (0.3 s, ease-out forward chop plus a roll toward the chest), the sign checked with vector_math (a positive `rx` carries the hand to -Z). **Stairs:** a half step no longer lifts the body 0.52 in one tick; with `stepTeleport` off it is hopped at the jump's launch speed under double gravity, half the height in half the time. `--move-probe`: half step top 58.501, highest feet 58.641, largest one-tick rise 0.170; full step, teleport and climb unchanged. `--stage26`: day/night Village Market, desert Stardust Dreams, underground Rites of Passage, playing. `--stage32`: 3 footsteps over 5.3 m.
- **2026-09-15 s2** — stage 33, the Playground, asked for as a title mode that spawns the player among an example of every feature, for testing and for a YouTube showcase of what Flutter does with a Minecraft + Cube World voxel world. Three choices worth keeping: the plaza is flattened by the generator rather than by edits (a 144 x 144 clearing written block by block would have been ~300k edits in the save); the exhibits build zone by zone when their chunks load, because `setBlock` into an unloaded chunk silently does nothing and a render distance of 4 does not reach the corners; and the zoo and arena creatures are tagged, not saved, so they come back on every boot while the villagers, companions and carts ride the normal save. The world tour needs no blocks at the destinations: `travelToWaypoint` only reads the label map and lands 1.05 above the cell, and the destination's own key satisfies the 6-block rule for the way back.

- **2026-09-15** — four requests from a hand play. (1) **Night**: the terrain shader's curve is now Minecraft's light
  map (`l / (4 - 3l)`, sky factor 0.24 night .. 1.0 noon mapped from the game's 0.35 .. 1.0 `skyIntensity`,
  gamma 0.5, `x 0.96 + 0.03`, raised to 2.2 for the linear albedo) instead of Godot's `0.02 + 0.98 * level^4`,
  and `_updateSky` raises the moon (0.18 -> 0.45) and the night ambient (energy 0.10 -> 0.90 at night, 0.40 by
  day as before) so the engine's lighting stops darkening the night a second time. `skyIntensity` itself is
  unchanged, so the spawn gate and the daylight burn read the same numbers. Plain boot seed 42, mean luma of the
  lower screen band: noon 142.8, midnight 34.6 before -> 40.4 (curve + moon) -> **47.9** (0.34 of noon); the
  Minecraft map gives about 0.46 for a moonlit field at default brightness, ACES keeps the rest. (2) **Step
  teleport** behind `Settings.stepTeleport` (`[gameplay] step_teleport`, switch in the panel, `--step-teleport`),
  off: `VoxelBody.tryStepUp(fullBlock: false)` still lifts the half step, and a full block the body fits over
  (`VoxelBody.stepFits(1.02)`) is jumped instead. (3) **Wall climbing** behind `Settings.climbWalls`
  (`climb_walls`, `--climb`), off; the tutorial and the menu line stop mentioning it. It also stalled under the
  top (Godot's `wall_ahead` has the same bug): the lowest probe was 0.3 above the feet, lost the wall with the
  feet still below its top, gravity pulled the climber back and it climbed again. The probe now reads the feet
  cell. (4) **Underwater**: `Game._updateSubmerged` reads the camera's eye cell (a pool's top cell counts only
  under its 0.875 surface) and turns the fog deep blue at density 0.05 with no sky influence (lava: orange,
  1.2), and the HUD washes the screen blue (orange in lava). `--move-probe` on seed 42: teleport off, the step
  is climbed with a largest one-tick rise of 0.265 m (a jump) to y 59.001; on, 1.020 in one tick to the same
  top; climbing off, a jump to 59.495 against the 3-high wall; on, feet 61.001 on the wall top, on floor. Unit
  tests in `voxel_core/test/physics/physics_test.dart` (the climber stands on a 3-high wall, the step is jumped,
  a 2-high wall is not). `--underwater` frames the sea floor through the blue; `--stage22` unchanged (slab 67.5,
  stairs 68, fence blocked); `--stage31 --shot=room --time=0.0` still reads the torch room.

- **2026-09-14** — deterministic loot seeds. Stage 26 noted that a structure chest seeded its loot from
  `IVec3.hashCode ^ seed`. Dart's `hashCode` / `Object.hash` are seeded per process, so the same chest held
  different items after a restart, and a host and its client could roll it differently. `LootTables.seedFor(at,
  worldSeed)` is now the one explicit integer hash, `(x*73856093 ^ y*19349663 ^ z*83492791 ^ seed) & 0x7FFFFFFF`.
  The chest roll, the mine chest-minecart cargo (the private `_cellHash`) and `Mob.traderSeed` all seed through it.
  For a world seed below 2^31 the cart and trader seeds are bit-for-bit what they were, so only chests change.
  A grep for `hashCode` / `Object.hash` in `lib/` finds nothing else seeding a roll: `IVec3.hashCode` remains only a
  map key. `loot_seed_test.dart` pins the seed (1205562705 for (12, 40, -7) in world 42) and the first draw, and checks
  that two separate `Random` constructions roll every table identically.

- **2026-09-14** — probe determinism. Two probes drifted from their rows because of what stage 32 added around them.
  - **`--stage29` counted a third blaze now and then.** The count takes every blaze in `mobs`, as Godot's does
    (`main.gd` `_probe_stage29`). The fortress spawns exactly two, but the underworld spawner could add one more during
    the probe's teleport waits. Nulling `spawner`, the port's usual stand-in for Godot's `set_process(false)`, would
    have silenced the fortress too, because `_checkFortress` spawns its blazes through `forceSpawn`. So `Game` gained
    `spawnerPaused`: natural spawns stop and `forceSpawn` keeps working. The probe pauses from the trip down to the
    trip home. Two runs read `blazes=2`, and every other figure of the row came back (1557 bricks, the lord at 308 HP,
    soul sand 2.30, edits 436 / 59). Godot's probe has the same latent flake; it was not touched.
  - **`--strike` read 17.5 -> 7.5, and once 17.5 -> 2.5.** Since stage 32 a zombie under the morning sun burns
    0.5 HP per half second before the swing, and one melee hit in ten is a x1.5 critical. The probe now runs at night
    unless `--time=` is given, and sets `critsEnabled = false`. It reads 18 -> 8 at 2.01 m, as its row does. Godot's
    `--strike` is the same code, so it carries both latent flakes.

- **2026-09-14** — the render was mirrored left-right against Godot since the first port commit. flutter_scene's
  `PerspectiveCamera` builds `right = up x forward` and projects +forward into the screen, a left-handed view; the port
  fed it Godot's right-handed world unchanged, so world +X landed on screen-LEFT at yaw 0. `--stage22` and `--stage27`
  prove it: the same camera pose as Godot put +X on the opposite side. The port had compensated piece by piece instead
  of fixing it: a mirrored `rightVec`, `yaw += look.dx` against Godot's `_yaw -= relative.x`, quads wound the other
  way in both mesh builders, and the boat steering and roll signs flipped.
  - **One conversion, at the camera.** `GodotCamera` (`lib/src/world/godot_camera.dart`) is a `PerspectiveCamera`
    whose lens negates clip-space x, used by the player and the title vista. The world, the lights, raycasts and
    `worldToScreen` stay in Godot's coordinates. Everything compensated went back to Godot's form: `rightVec =
    (cos, 0, -sin)`, the mouse sign, the mesher's and `VoxelMeshBuilder`'s winding (Godot's `Quad` index for index),
    the boat's `steer * -1.7` and `-steer` roll, and the boat dismount offset.
  - **What the mirror costs.** Screen winding reverses. The engine's own `CuboidGeometry` and `SphereGeometry` (the
    crack box, debris, effects, TNT, bobber, fireball trail) sit in a child scaled (-1, 1, 1): they are symmetric,
    and flutter_scene re-winds a mirrored transform. The shadow pass is not mirrored, so the caster-faces default is
    now `front`, which draws the same real back faces `back` drew before. The engine-derived `cameraRight` used by
    SSAO, SSR, GI and contact shadows would disagree with the view, but the game enables none of them.
  - **A second convention bug of the same family.** flutter_scene's `lookAtFrom` turns local +Z toward the target,
    while Godot's `look_at` turns -Z. Arrows and bolt trails flew backwards; the projectile now aims at the point
    behind.
  - Verified: `handedness_test.dart` (+X at yaw 0 projects to NDC x > 0, while the plain camera gives < 0; strafe
    and forward are Godot's; a mouse move to the right turns right; stairs ids from yaw match Godot's `facing_suffix`),
    and the stage 31 winding test now expects clockwise. Captures: `--stage22` looking south shows the slab (west)
    right and the fence post and lava (east) left; `--stage27` looking north puts the lever end x0 of every row on the
    left; `--stage19` reads oak slab, stone slab, fences, stairs from left to right; the plain boot shows the ocean to
    the west on the left, and the `--map` minimap has the same ocean to the north-west, north up. `--stage31` (sky
    1 / block 10, sky 7, 4107 AO vertices, 28 cells in 9.7 s, 7.2 m), `--stage32` (seam 8/6, 1.62 m, vignette 0.90,
    crack alpha 0.48, 12 steps, 0.72 s, `+6 Apple`, damage numbers on the zombie) and `--title-probe` (81 vista
    chunks, 5 buttons) are unchanged. No face is inside out, and the shadows fall as before.

- **2026-09-14** — stage 32, the port of `82ff6b52e9`. Every `--stage32` line printed Godot's figures: the seam cell
  at 8 and the third at 6, the zombie shoved 1.62 m, vignette 0.90, crack alpha 0.48, 12 steps over 5.3 m, the sun /
  roof / pool zombies, the death clock and the merged `+6 Apple`. `--stage31`, `--stage29`, `--strike` and the title
  vista were unchanged. Engine differences:
  - **The pad buffers are isolate statics.** C#'s `[ThreadStatic]` becomes static fields of `ChunkMesher`: Dart statics
    live per isolate, so each worker binds one 48x48x128 set and reuses it for every job.
  - **The pad costs more here than in C#.** Single-threaded on the same 49 chunks the mesher went from 3.1 to 5.0 ms.
    Filling every layer above the volume's highest block with 15 at once (the result is identical, the equivalence
    test proves it) brought it to 4.6 ms. In the app the job clock reads 9-10 ms under the pool's contention (stage
    31: 6.5-7.7), and the window fills in 1.9-2.4 s (stage 31: 1.7 s).
  - **Swapping a material needs a mesh re-assign.** flutter_scene 0.23 copies each primitive's material into its render
    item when the mesh is attached. Writing `primitive.material` changed nothing on screen until
    `refreshMeshMaterials` re-assigned the same primitives. The stage 23 stun tint had the same silent bug.
  - **The crack lines ignore depth.** `LineSegmentsGeometry` draws over the terrain, so there is one node per stage and
    per face, and a face turned away from the camera is hidden.
  - **The HUD state is a class.** Godot's `hud.gd` `_process` becomes `HudState`, advanced once per frame by `Game`;
    the painter stays stateless.
  - Probe details: the waits count ticks (the death clock reads 0.72 s, 43 ticks), `Mob.probeDrops` replaces the
    duplicated species dictionary, `probeHold` now holds the mouse buttons, and a Flutter-only `--shot=seam` shows the
    torch across the border at night.

  Probe lessons: the first combat captures showed no damage numbers and no mob bars. `HudPainter` held the camera from
  the widget's build, so every projection used the player's spawn position; it now asks for this frame's camera. The
  flash was invisible twice over: `UnlitMaterial` multiplies the vertex colours by default, and the material swap never
  reached the render item. A `--stage31` regression read sky 15 in the roofed room. The probe moves the player into
  the next chunk right after its edits, and `_refreshWindow` cleared the queued remeshes; stage 31 had passed by
  timing. The fix keeps them queued. Also, a window that opens behind other windows gets no frames on macOS, so the
  probe runs bring the app to the front through System Events.

- **2026-09-14** — stage 31, the port of `455d8746de`. Every `--stage31` line printed Godot's figures (sky 1 / block 10 at
  the room centre, sky 7 under the overhang, 9 chunks remeshed, 4107 AO vertices, the maze in 9.7 s along 28 cells, the
  control stuck at 7.2 m), and `--stage29`, `--stage27`, `--strike` and the title vista were unchanged. Engine differences:
  - **The terrain shader is flutter_scene's standard lit shader with one term added.** A raw `ShaderMaterial` gets no
    sun, shadows, ambient or fog, so copying Godot's shader into one would have lost the whole look. `TerrainMaterial`
    subclasses `PhysicallyBasedMaterial`, swaps in `shaders/terrain.frag` (the standard shader, albedo x light, plus an
    emission share) and binds one extra `TerrainInfo` block. The shader keeps every texture read of the original: the
    material binds samplers by name, and one the compiler strips would crash the draw.
  - **The bundle is compiled by hand.** There is no app-level build hook, so `dart tool/build_shaders.dart` runs the SDK's
    impellerc (`darwin-x64`, an arm64 binary here) into `assets/shaders/`. Without `--gles-language-version=300` impellerc
    aborts inside spirv_cross. The material's `bind` signature is typed against flutter_scene's internal gpu shim, so
    `package:flutter_gpu` cannot be imported directly (the analyzer resolves the shim to a stub type).
  - **The light volumes cross the isolate boundary** as two more `TransferableTypedData`, beside a fifth array per surface.
  - **Night looks darker than Godot's** under ACES with Godot's 0.35 and fourth power; the numbers stay Godot's.
  - Probe lesson: the first light read once came back as the pre-room mesh. A chunk edited while its mesh job was in flight
    lost the new request when the stale result landed, so it is now kept pending (`_remeshAgain`).

- **2026-09-14** — stage 30, the port of `1ffac7c81c`. Both halves of `--stage30 --title-probe` printed Godot's
  lines: the title's five buttons, the world round trip, 33 credits rows, creative, the tutorial's seven events, and
  the stats read back after the session rebuild. Engine differences:
  - **The vista is a second `Scene` + `SceneView`.** Godot puts a `VoxelWorld`, a `WorldEnvironment` and a
    `Camera3D` under the title's `Control`. Here the title owns its own `Scene` (gradient sky, sun, ACES, fog) and a
    `VoxelWorld` with its own isolate pool. `_leave()` disposes that pool before the launcher builds the game, so
    two worlds never generate at once. The music waits for `Sfx.ready`, because the title can be up before SoLoud.
  - **Scene changes are widget swaps.** `change_scene_to_file` becomes `_Launcher` swapping `TitleScreen` and
    `GameView`, each under a fresh key. "Save & back to title" is `Game.exitToTitle`, and a title shown again does
    not re-run the probe flags.
  - **The credits read the roadmap as an asset.** An app-level build hook is not allowed, so `ROADMAP.md` is listed
    under `flutter: assets:` and read with `rootBundle.loadString`; the unit test parses the file on disk. The
    bundled copy is only as new as the last build.
  - **The tutorial card is a widget.** Godot's autoload owns a `CanvasLayer`. Here `Tutorial` is a
    `ChangeNotifier`, and `TutorialCard` sits inside the game view's `RepaintBoundary` over the HUD, so a capture
    sees it. F6 is a new `GameAction.skipTutorial`.
  - **The typed seed.** Godot hashes text with `hash()`. Dart's `hashCode` is seeded per process (gotcha 7), so
    text goes through FNV-1a: stable, but not Godot's number. Numbers and the empty (random) seed behave as Godot's.
  - **Counters reset on start.** Godot's `GameState` autoload keeps the last world's counters until a load replaces
    them, so a fresh world made after playing another inherits its stats. `Worlds.start` (and Join) call
    `GameState.resetStats()` first. This is a deliberate difference, not an engine one.
  - **The probe's settings file.** Godot's probe writes `tutorial/done` into the real `settings.cfg`. `main.dart`
    loads the real file, then points a `--stage30` run at `settings_probe30.cfg`.
  - Flutter-only capture flags: `--open-credits` and `--credits-t=` (seconds into the scroll).

  Probe lesson: the first run parsed 32 credits rows, not 33. The binary had been built before this row was
  added, and the asset bundle is a build product. The rerun after a rebuild read 33. The unit test counts the
  table rows of the file itself, so it follows every future row. Second lesson: the regression capture of a plain
  `--screenshot --new` boot showed the tutorial card on step 1. Flutter's launcher marks a bare `--new` as
  `freshWorld` (Godot's title never did), so "a fresh world" had to exclude `--new` explicitly; the recapture
  shows no card, and `--stage30` still begins it.

- **2026-09-14** — stage 29, the port of `3d46f2f410`. The generator's underworld and the fortress went across
  line for line, and every `--stage29` figure landed on Godot's session log. The census over the 5×5 core
  (hellstone 378100, lava 43743, glowstone 1604, quartz 13947, soul sand 2450) is identical, so
  `flutter_scene`'s FastNoiseLite 3D noise matches Godot's for this recipe too. The fortress (1557 bricks), the
  arrival cell, soul sand 2.30 and the saved edit counts 436 / 59 match as well. Engine differences:
  - **The job carries the dimension, the future carries the epoch.** Godot binds `(pos, dimension, epoch)` into
    a `WorkerThreadPool` task and filters `_gen_out` by epoch. Here the isolate's `gen` message gets a fourth
    field, and each `then` closure captures `_genEpoch` at dispatch and returns when it changed. A stale mesh or
    gen result therefore never touches `chunks` or the in-flight sets of the new dimension.
  - **`dim` meta → `Expando`.** Entities are plain objects in `Game`'s lists, so the dimension tag is an
    `Expando<int>` (untagged = the loaded dimension). "Hidden + `PROCESS_MODE_DISABLED`" is `node.visible` plus an
    `isHere` check in the `_tick` loops, the save and the mob broadcast.
  - **Portal logic moved to `portals.dart`** so the unit tests reach the frame check, the return frame and the
    safe spot without a scene. `Game.tryLightPortal` / `_arriveTick` call it where Godot's `Main` does.
  - **Sky.** The underworld branch sets `SunLight.intensity` and the sky's sun colour to 0, the gradient's three
    colours, a constant-diffuse ambient and red fog. The day branch rewrites all of them every frame, so the way
    back needs no restore.
  - **Probe timing.** The flow waits and the soul-sand walk count 60 Hz ticks (`_stage28Settle` /
    `_stage28Until`). Standing in the portal re-pins the player from the per-tick hook until `travels` moves.
    The arrival and chunk waits are wall-clock frames, as in Godot.
  - **IVec3** gained `* int` and `length` (Godot's `Vector3i` ops that `try_light_portal` uses).
  - Test fixes: `stage28_test` asserted `Blocks.count` after the rails (now "the next id is `obsidian`"), and
    `world_test` counts 29 species.

  Probe lessons: the first `--shot=portal` capture showed the trees the pad had cleared, not the frame. The
  capture waited 30 frames, and the pad's remeshes had not all landed; both shots now wait for `world.isIdle`
  too. Also, Godot's windowed captures do not show the lava sea, so a Flutter-only `--shot=cavern` hovers over
  the nearest open column above it.

- **2026-09-14** — stage 28, the port of `3a180ea741`. `rails.gd` and `minecart.gd` went across nearly line
  for line, and every `--stage28` figure landed on Godot's session log: the orientation counts, 3.93 / 3.07 on
  the slope, 5.23 off the powered leg, and the same seed 42 mine with 22 rails. The mine count comes from the
  generator's integer hash, so it matches exactly. Engine differences:
  - **The cart is not a scene node.** Godot's `Minecart extends Node3D` and joins the `carts` group. Here it is
    a plain class that owns a `Node`, listed in `Game.carts`, stepped in `_tick` after the boats and pruned
    like them. `setupCart` takes `model: false` so the unit tests step real carts without a GPU.
  - **Probe timing.** Godot waits with `_stage22_settle` (wall time) and `_stage28_until` (physics frames against
    the wall clock). Here both count 60 Hz simulation ticks (`_stage28Settle`, `_stage28Until`, gotcha 7).
    That is why the slope and the powered peak match to the hundredth. The rider's 0.86 m against Godot's
    0.89 is the one figure a frame early or late would move.
  - **The wire.** The five cart RPCs are JSON message types (`cart`, `cart_poses`, `cart_free`, `cart_req`,
    `cart_board_req`, `cart_unboard_req`, `break_cart_req`). A cart gets a counter net id like the boats, and a
    replica is built from the spawn message's cell and kind. As in Godot, no paired probe exercises them.
  - **The loot seed.** Godot seeds the mine cart's roll with `hash(ckey) ^ seed`. Dart's `hashCode` is seeded
    per process (gotcha 8), so `Game._cellHash` is an explicit integer hash. The roll is deterministic, but its
    stacks are not Godot's.
  - **F on a cart** is reached through a new `Player.probeInteract()`, where Godot's probe calls the private
    `_interact_pressed`. The rails need no raycast change: `voxelRaycast` already stops on any non-air,
    non-liquid block.
  - Test fix: `stage27_test` asserted `Blocks.count == melon + 22`. That becomes "`rail_ns` is melon + 22".

  Probe lesson: macOS has no `timeout` binary. The first run printed nothing because `timeout: command not
  found` went through the same grep as the probe lines. The app is now run bare, with its log written to a file.

- **2026-09-14** — stage 27, the port of `734b8cea2f`. `circuits.gd` went across nearly line for line
  as `lib/src/game/circuits.dart`, and every probe line matched Godot's session log. The ore count
  (3531 below y 30 in 49 chunks) matched exactly, because the veins come from the generator's integer
  hash. Engine differences:
  - **Host gate.** Godot asks `Net.is_client()` in `set_block` and `_process`. Here `VoxelWorld.flowEnabled`
    (false on a client) gates both `circuits.touch` and `circuits.tick`, so the circuits and the flow
    share one switch. The tick runs inside the stage 25 `beginBlockBatch` / `endBlockBatch`, after
    `tickFlow`.
  - **Signal -> callback.** `tnt_powered` is `Circuits.onTntPowered`, set to `igniteTnt` in `Game.init`.
    TNT is set to air inside the recompute's `_applying` window, so the ignition never re-dirties
    the cell.
  - **Glow surface.** Godot's unshaded `StandardMaterial3D` with vertex albedo is a flutter_scene
    `UnlitMaterial` (`vertexColorWeight` 1). `ChunkMeshResult` carries a fourth surface, the isolate
    reply packs 16 arrays, and the chunk node gets a fourth child. As in Godot, the vertex colour
    still holds the baked light, and the old `lamp` (15) and `waypoint` (10) move to that surface
    too.
  - **Probe timing.** Godot's `_stage22_settle(0.3)` is wall time. Here every wait is 18 simulation
    ticks, and the button is timed as ticks × 1/60 through `_probeTick` (gotcha 7). That gives
    0.02 / 1.00, Godot's numbers.
  - **Two boots.** `reloader` rebuilds the session like stage 24. The flag `probe27.flag` holds
    `x0,y,z0` as plain text and is read and deleted at init (Godot writes JSON and deletes it in the
    verify half). `_loadGame` honours it like the stage 24 flag.
  - **Capture.** A first-person hover pinned 6.5 m over the pad and 12 m south of the rows, looking
    at the middle rows. Godot's third-person camera would put the player model in the frame, and
    Godot's framing was too far to tell a lit wire from a dark one. Night alone shows the lamp; the
    day capture shows the rest.
  - **Plates.** `_platesFired` is now the set pressed on the last tick (the click and the "floor rumbles"
    note fire on a new press). `platesFired()` still reports 1 in `--stage23`. `Player._toggleDoor` became
    `toggleDoor` so the probe can use it.
  - Test fix: `stage26_test` asserted `Blocks.count == plate + 7`. That becomes "`redstone_ore` is
    plate + 7", since stage 27 appends after the melon.
  - Seen and not investigated: in the captures, the lever end of each row (the lowest x) sits on the
    right of a frame that looks north. The camera's handedness predates this stage.

- **2026-09-14** — stage 26, the port of `f931355a2e`. The generator diff went across line for
  line, and every block count on seed 42 landed on Godot's number. The biome map, the pools
  and the village layout all come from hash and noise, so they match exactly. Engine
  differences:
  - **Music.** Godot fills two `AudioStreamGenerator` voices, at most 4096 frames each per
    `_process`. SoLoud has no pull generator on desktop here, so `Music.render` runs the same
    pentatonic random walk for 32 eighth notes. That buffer loads as a looping WAV
    (`Sfx.wav16`), and a mood change crossfades the two handles with `fadeVolume` +
    `scheduleStop` over 3 s. The walk is seeded by an FNV hash of the mood name, so a mood
    repeats as a loop instead of wandering forever. Volume is the global SoLoud volume the
    stage 24 settings already set, not a per-voice `× Settings.volume`. The probe cannot
    hear. It reports the moods it picked, the samples rendered, the loops started
    (`handlesPlayed`) and whether the active handle is a live SoLoud voice. When four moods
    change inside one frame, a loop still loading is skipped for the newer mood (3 or 4
    loops started).
  - **Split and trader timing.** A slime dies inside loops over `Game.mobs` (projectiles,
    abilities), so its two children wait in `Game.pendingSplits` until the end of the tick.
    Godot adds them at once, so the probe counts after one tick. `setupMob` runs before the
    position is known here, so traders get their offers from `Mob.makeTrader(bornAt)`.
  - **Deterministic offers.** The first probe runs showed different offers for the same
    villager, because `IVec3.hashCode` is Dart's per-process seeded `Object.hash`. Offers
    now seed from a fixed spatial hash (`Mob.traderSeed`), and two runs rolled the same
    offer. Chest loot (`Game.chestInventory`, from stage 23) still seeds with
    `IVec3.hashCode`, so a chest's loot changes across restarts and between peers. Noted,
    not changed here.
  - **Trade screen.** A Flutter widget under a transparent `Material`. The rows are
    `CustomPaint` using `Hud.drawItemIcon`, and the flash state lives on `Game`
    (`tradeFlash`). The first capture showed all three rows piled at the left edge, because
    a `CustomPaint` gets no width in a start-aligned `Column`. Each row now takes the full
    width.

  Probe lesson: the village hover uses fly mode with nobody at the keys, so the camera is
  pinned to the hover point before the shot.

- **2026-09-14** — stage 25, the port of `40f3068dd4`. Every `--stage25` line landed green on
  both processes, with Godot's boat figure (1.95 m) and flow figure (24 cells in 4 batches).
  Engine differences:
  - **The wire.** Godot's 15 new RPCs are JSON message types on the TCP line: `drop_poses`,
    `give_rest`, `bag`, `boat` / `boat_poses` / `boat_free`, `boat_req` / `board_req` /
    `unboard_req` / `break_boat_req`, `bobber` / `bobber_gone`, `blocks`, `block_ack`, and
    `chest_set` / `block_req` grew their fields. Godot's reliable / unreliable split and its
    MTU limits (≤40 pose rows, ≤200 cells a packet) are moot on a TCP stream. The splits are
    kept, so the counters mean the same thing.
  - **Net ids.** A boat gets a counter id like drops, where Godot uses `get_instance_id`. A
    bobber replica takes the puppet's hand as a closure, the same trick `ItemDrop` uses to
    avoid naming `RemotePlayer`. The host does not relay one client's bobber to another,
    because a client only knows the host's puppet here.
  - **Pure pieces.** The chest accounting is `Net.chestEditVerdict`, and the prediction
    bookkeeping is `BlockPrediction`. Both are unit-tested without a socket. The flow batch
    wraps `tickFlow` in the fixed 60 Hz `_tick`, where Godot wraps `_process`.
  - **Probe timing.** Godot's host waits a flat 1.5 s before dropping the iron stack. The
    Flutter client can still be filling its window then, so the host also waits (up to 15 s)
    for the declared bag to show room for exactly one. The client waits at least Godot's
    4.5 s, and on until the rest drop shows. Boat rowing goes through `probeWalk`, as in
    Godot's headless run.

  Probe lessons: a Python port check before starting the client counts as a peer (the host
  logged "peer 2 joined" and a broken pipe on its `hello`), so the second pair waited on the
  host's "window filled" log line instead. The client's HP read 13/30 in the capture. The
  `--wait-peer` zombie is spawned on the client too in Flutter, while Godot spawns it on the
  host only. That comes from the stage 15/17 port; noted, not changed here.

- **2026-09-14** — stage 24, the port of `a7e167737f`. Every `--stage24` line landed on Godot's
  figures, and the three screens were captured. Engine differences:
  - **The scene reload.** Godot's probe saves, then calls `reload_current_scene`. Here
    `GameView` keys a `_GameSession` by a generation number, and `Game.reloader` bumps it.
    The old `Game` is disposed (its isolate pool too), and a fresh one runs `init` with the
    same arguments. The singletons (`GameState`, `Net`, `Settings`) survive, as Godot's
    autoloads do. `probe24.flag` sits beside `worlds/`, standing in for `user://`.
  - **Where the pieces live.** `Settings` is a static singleton loaded in `main` before
    `runApp`, not an autoload. `settings.cfg` is written as Godot's `ConfigFile` text by a
    small hand-written reader/writer. Master volume is `SoLoud.setGlobalVolume`, where Godot
    sets bus 0's dB; it is applied again once SoLoud finishes its background init.
  - **Map and journal.** The world map image is built on the UI thread every 2 s and
    uploaded with `decodeImageFromPixels`, like the stage 11 minimap. The panel scales
    down when the window is smaller than Godot's 1040x760. The tab list and
    `questEntries` live in `quests.dart` as `JournalTabs`, so `Game` never imports the
    UI; Godot keeps them on `JournalScreen`.
  - **Save details.** The "pets" group is `Game.pets`: the loader puts a tamed mob there
    itself instead of relying on `restore_tamed`'s `add_to_group`. A restored drop goes
    through `Net.onDropSpawned`, so a host announces it. A visited chunk is keyed by the
    floored position, not Godot's truncating `Vector3i`, which only differs a block west
    or north of the origin.
  - **A bug the capture found.** The first `--open-settings` capture showed Flutter's red
    "No Material widget found" over every slider and switch, and yellow-underlined text.
    The overlay sits in the game's `Stack` with no `Scaffold` above it. That was already
    true of the stage 12 pause-menu sliders and the death screen, so both screens are now
    wrapped in a transparent `Material`.

  Probe lesson: two app instances launched at once hang the second one (2 s of CPU in
  five minutes, no output), so the captures ran one at a time. The minimap's new second
  legend line wraps to two lines at 240 px and can run into the notifications column;
  left as is.

- **2026-09-14** — stage 23, the port of `ae79edbd53`. The Godot diff went across almost line
  for line, and every probe figure landed on Godot's except the loot lines. Engine differences:
  - Q is `GameAction.ability2`, and it shares the physical key with `dropItem`, exactly as
    Godot's `project.godot` binds `drop_item` and `ability2` both to Q. One press does both
    in each engine; not fixed here, because the spec does it too.
  - The table class is `LootTables`, because `Loot` already names the loot-weapon record in
    `game.dart`. Rows are `LootEntry` consts rather than dictionaries.
  - `ItemStack.dur` uses -1 for Godot's absent `dur` key, and is saved only when it is set.
    `copy` and `takeFromSlot` carry it, so a worn sword keeps its wear when it moves slots.
  - The plate check runs inside the fixed 60 Hz `_tick`, right after the bodies move. That
    stands in for Godot's `Main._physics_process`. It also scans pets, which Godot's "mobs"
    group includes. A lit fuse is the existing `_Tnt` entry, so defusing removes its node
    and puts the block back.
  - The stun and ghost tint swaps every part's `MeshPrimitive.material` for one blended
    `PhysicallyBasedMaterial` per mob, in place of Godot's `material_override`. The shared
    vertex-colour material comes back when the stun ends.
  - The probe's `await physics_frame` walks are `_ticks(n)` on the stage 22 per-tick hook.
    Only the capture loop counts rendered frames.
  - The stage 21a teleport is reused with radius 48, and it now returns the structure
    origin. Flutter's air pocket for the orbit camera is still carved there, 6–16 m south
    of the temple centre, outside the pyramid.

  Not Godot's numbers: the four loot lines, since the RNG differs. The boss bar reads
  "164 / 163" because `hp.ceil()` shows 163.2 as 164 while `maxHp.toInt()` shows 163; that
  rounding was already in the HUD. `test/world_test.dart` now expects 22 species.

- **2026-09-14** — stage 22, the port of `9a86811525`, and the missing row for stage 17
  (already in the code; `--strike` re-run, 18 → 8). The Godot diff went across almost line
  for line. Engine differences:
  - A `CollisionBox` holds min/max corners where Godot's `AABB` holds position + size.
  - The flow queue is an insertion-ordered `Set<IVec3>` standing in for Godot's
    `Dictionary` keys.
  - `tickFlow` is called from the fixed 60 Hz `_tick`, not from the frame's `_process`.
  - The client gate is a `flowEnabled` flag the game sets from `Net`, because
    `VoxelWorld` does not import the network.
  - Godot's probe walks `await physics_frame`. A per-frame `nextFrame()` here would drop
    ticks whenever one frame runs several (the probe run held 80 fps against 60 Hz ticks),
    so `Game` grew a `_probeTick` hook called right after each simulation step. The walks
    then count ticks exactly as Godot's do, and all three landed on Godot's numbers.

  One figure moved without a code cause I could find: `--stage20 --ride` reported 0.71 m
  at -8.1 m/s, against 0.85 m at -8.6 on 2026-09-10. That measurement counts ten *frames*,
  not ticks, and this run held 80 fps, so about 7.5 ticks fell inside the window. The ride
  is on a flat grass pad that the new box sweep resolves exactly like the old cube sweep.
  It was not re-measured against the previous commit.

- **2026-09-10 s6** — stage 21b, the network half of `5817cae3f`, as 11 new JSON message
  types. One real bug fell out of it: the client used to build its world before the host's
  `hello` arrived, so the spawn search ran on the default seed and the client started hundreds
  of metres from the host on terrain that was then replaced. The launcher now waits up to 8 s
  for `connected` before entering the game, and both peers spawn together. Two smaller notes:
  `ItemDrop` reaches a peer's puppet through the `Target` interface rather than naming
  `RemotePlayer` (the same import cycle Godot dodged by duck-typing), and the captured frame
  needed the camera pinned one more time right before the shot, because a body is swept out of
  whatever it stands in on every tick.

- **2026-09-10 s5** — stage 21a, the generator half of `5817cae3f`. A straight port: the same
  hash, the same 4x4 grid, the same 48-block clearance from a primary structure, so seed 42
  puts a ruin 29 m from spawn exactly as it does in Godot. One probe lesson of its own: a ruin
  in a forest sits under the canopy and the orbit camera ends up inside the leaves, so the
  readable captures are the temple (open desert) and the mine (`--fp`, its corridor is its own
  air pocket).

- **2026-09-10 s4** — stage 20 (`551d9830b`). Two engine differences: Godot's `ImmediateMesh`
  line is redrawn every frame, but a `LineSegmentsGeometry` here uploads a device buffer at
  construction, so the fishing line is a thin cuboid stretched and rotated from the hand to the
  bobber each frame instead. And a probe cannot press `Input.action_press` here, so `GameInput`
  grew `probeHold(action, down)` which injects the action's physical key; `--ride` uses it and
  reproduces the Godot numbers exactly (0.85 m in ten frames at -8.6 m/s).

- **2026-09-10 s3** — stage 19 (`0c0188eb2`): one `_subBox` in the mesher emits any
  axis-aligned box in block-local space, culling and lighting a face flush with the block
  boundary exactly like a cube face and lighting an inner face from the cell with no AO.
  Twelve blocks appended. The face counts are a unit test rather than a screenshot, because a
  half-height box is hard to read from a frame: an isolated slab is 6 faces, a lone fence post
  6, two fences 32 (each rail's far face meets the same block id and is culled), and one
  stairs 11 (six for the bottom slab, five for the step whose underside is skipped).

- **2026-09-10 s2** — stage 18 ported from the Godot POC's `c07fd0f20`: `effects.dart`,
  `talents.dart`, `achievements.dart`, `weather.dart` and `journal_screen.dart` are new; the
  block table grew by `brewing_stand` and `waypoint` (appended, so the save bytes still match
  Godot's). Two engine differences: Godot's `GPUParticles3D` became a
  `ParticleEmitterComponent` with a `BoxEmitterShape` (rain uses `BillboardFacing.velocityStretched`
  so a drop stretches along its own velocity, which is what the Godot `BILLBOARD_FIXED_Y` quad
  did by hand), and the rate is `amount / lifetime` scaled by intensity rather than Godot's
  `amount_ratio`. The mob health bar is painted by the HUD here, so the affix colour arrives
  through `Mob.barColor()` instead of a bar mesh material.

- **2026-09-10 s1** — worktree `poc_cubeworld` created from `dev`; the Godot POC read whole;
  every file ported; first screenshot through the probe; look tuned against the Godot frames
  (fog toward sky, sun 0.6 / ambient 0.6); shadows confirmed with a low sun; stages 13b, 16
  and 15 seen through `--fire`, `--stage16`, `--strike` and the two-process `--wait-peer` run.
  Stage 13 (playing it by hand) is the one thing a probe cannot do.
