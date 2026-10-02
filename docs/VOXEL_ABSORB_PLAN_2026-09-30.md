# The absorption plan (VA) — 2026-09-30

**Question.** `examples/voxel_game_minecraft/lib` (~23k lines) is a Minecraft clone that
predates the kit and still runs on its own `Game`, `Player` and `Mob`. What in it is a
second copy of something the kit has, what is a feature every voxel sandbox wants and the
kit lacks, and in what order does the kit take it, so that the packages are as complete as
they can be?

**Answer, in one line.** Nearly all of the app's gameplay, UI and systems are its own; it
takes from the kit only the pieces VK5 extracted (motor, cameras' orbit and bob, rig
animator, goal selector, input map, fixed step, and the engine's worldgen, registries,
signals and transport). The kit grows by **declared** features — survival, screens, a
richer HUD, weather, dimensions, creatures that tame and ride, vehicles — each witnessed by
`packages/voxel_game/example`, and the app moves onto `VoxelGame` last (`VA-Z`), deleting
its copies.

Found by reading, not by running: four read-only sweeps of the app against `packages/` on
2026-09-30 (gameplay and player; entities and mobs; UI; world, systems and net). Every
`file:line` below is from that sweep; re-check it before a step starts.

---

## Progress

| Step | State | Gate |
|:---|:---|:---|
| VA0 This plan, and the owner's answers to §Decisions | **done** 2026-09-30: the owner took every recommendation (VAD1–VAD5 settled). Next: VA1 on `opus 5.5:high` | the owner answers VAD1–VAD5 |
| VA1 Survival on `PlayerEntity` | **done** 2026-09-30 (`voxel_engine, voxel_game: survival on the player (VA1)`): `HungerSpec`, `XpSpec`, `PlayerSpec.armorSlots` / `armorPerPoint` / `armorFloor`, `VoxelGameSpec.effects`, `Damage.internal`; the engine's `ItemType` took `food: Food(...)` (hunger, heal, effect + seconds + power, `leaves`) and `armor: Armor(slot, points)` — the plan's loose `heal` / `effect` / `seconds` fields grouped into `Food`. Eating and wearing are a *press* of use, never a hold. Save `game.json` v2, v1 still loads. No HUD bar yet (VA4's). Learned: the app's armour is the best piece anywhere in the bag (`player.dart:798`), the kit's is what is worn, summed. Next: VA2 on `opus 5.5:high` | hunger, food, regen, starvation, XP, armor from worn items and status effects on the player, all `PlayerSpec` / `ItemType` fields; the example eats and wears |
| VA2 Blocks that do things | **done** 2026-09-30 (five commits, `29511a0` → the chests one): `BlockRules` (`VoxelGame.blockRules`) answers every block change on the authority. Rows: `falls`, `support` (`Support.below`/`side`), `onWall`, `loot`, `facing` (`Facing.compass`/`axis`), `tall`, `usedInto`, `grows` (`Growth`), `turnsWith`, `storage` (`Storage`); `ItemType.bucket` (`Bucket.empty`/`full`). The plan's `container` is `storage` (Flutter's `Container` would clash in a game's imports) and its `ItemType.container`/`liquid` is one `Bucket`. `game.json` v4 (crops v3, stores v4). Learned: a tall block's halves must pair by parity from the bottom of its family's run, counted before the change, and its family must include `SignalSpec.doors` or a signal-swung door loses a half; a falling block lands before it leaves, or the column above overtakes it. A client opens no store until VA16. Next: VA3 on `opus 5.5:high` | falling blocks, doors, buckets, crops, chests (a container with a saved inventory), facing blocks — each a `BlockType` / `ItemType` field |
| VA3 Screens as a state machine | **done** 2026-09-30 (`voxel_game: screens are one state machine (VA3)`): a sealed `GameScreen` (`BagScreen`, `StorageScreen`, `PauseScreen`, `DeathScreen`, `DeclaredScreen`) in `VoxelGame.screen`, changed by `openScreen` / `closeScreen` / `respawn`, each refusing what cannot be; `PauseMenu` (resume, the game's screens, Quit through `VoxelGameWidget.onQuit`) and `DeathMenu` (Respawn after `PlayerSpec.respawnDelay`, or jump); `VoxelGameSpec.screens` of `ScreenSpec(builder, menu:)` — the plan's `{id: builder}` took a menu label, so a phone reaches a game's screen with no key. A pointer lost mid-play opens the menu. Settings wait for VA7. Learned: a respawn below where the player died counted as a fall (fixed); a player saved dead loads dead, since health 0 is death; the kit's screens take no pad or arrow keys past their one button each (`KL-013`). Seen on the Mac: menu, Controls, death over the menu, Respawn, Quit. Next: VA4 on `opus 5.5:high` | `openScreen` becomes a typed screen (bag, container, pause, death, a game's own), pause and death screens in the kit, a respawn button instead of the timer |
| VA4 `DefaultHud` grows | **done** 2026-10-01 (two commits: `voxel_game: the default HUD shows survival and a notification feed (VA4)`, then `voxel_game: the default HUD reads the world (VA4)`): hunger, armour, the XP bar and level, the effects, `VoxelGame.notify` and merged pickups (`Notices`), each only as declared; then the crosshair red on a creature, the mining ring around it, a bar under a worn slot, a health bar over each creature hurt in the last 4 s or aimed and each hit's number rising over it (`DamageNumbers`, fed by `Mob.takeDamage` on the authority and by a replica's lost health on a client), the wash of `LiquidSpec.tint` while the camera is in a liquid, `MobSpec.boss` as a bar at the top, `VoxelGame.showFps`. The projection: `VoxelGame.frame` builds the frame's camera once and the scene and the HUD both read it (`camera()`), so a label lands where the scene draws, not a frame late; the over-world layer is one `CustomPainter` repainted by `frames`, mounted only while it has something to paint. The example has a boss (the brute). Learned: the HUD builds in the frame's tick, before the scene paints, so a camera built by the scene's paint is always the last frame's to the HUD; the first net state of a replica must not count as a hit. Seen on the Mac (window capture, the owner's mouse left alone): the world draws through the frame's camera, the HUD over it, a worn pickaxe's bar under its slot; the creature bars, numbers, tint and boss bar only in tests (they take playing). `showFps` has no switch yet (VA7's settings). Next: VA5 on `opus 5.5:high` | bars for what VA1 adds, effects, toasts, crosshair on a creature, damage numbers, underwater tint, boss bar, FPS overlay (`FrameStats`) |
| VA5 Items have a shape | **done** 2026-10-01 (`voxel_engine, voxel_scene, voxel_game: items have a shape (VA5)`): the engine's `ItemType.shape` (an `ItemShape`: twelve `StockItemShape`s or a `CustomItemShape` of boxes) and `ItemModel.of(item, blocks, items)`, one model a *look* (as `RigModel`), its `ItemGrip` (`block` / `flat` / `upright`); an item with no shape takes one from its row (block → its block's form, the five stock tool kinds, food → lump, armour → tunic, bucket → pail, else gem), and a tool of another kind must declare one (`buildItems` throws). `voxel_scene`'s `ItemMesh.of(model)`, one geometry a model (`KL-007`'s rule): the first-person hand (the app's sway and swing, lagging the view bob), `RigInstance.hold` (a humanoid's right fist; the player in third person, every remote player, whose item now crosses with its pose), the drop (`PickupModel` deleted) and `ItemIcon` in the hotbar and the bag. The engine took the shape, not just `voxel_scene`/`voxel_game` as this row's hand-off said: a declared look is a field of the item's row (rule 7), and `ItemType` is the engine's. Learned: a const map cannot key on `IVec3` (it overrides `==`), so a custom shape is a const list of boxes; `flutter test` builds no `MeshGeometry`, so the hand, the fist and the drop are judged on the Mac. Seen on the Mac: the icons, the hand with a pickaxe, a block and a torch. Not seen: the item in a third-person fist (a debug print put it, mounted and visible, 0.54 m above the feet, in front of the right hand; the grass in front of the camera hid that height) and a drop on the ground — the screen locked before a closer look. Next: VA6 on `opus 5.5:high`, after one look at those two in third person | one voxel shape per item (the app's `VoxelMeshBuilder`) for the hand, the drop, the third-person held item and an icon; `KL-007` read before it |
| VA6 The bag screen grows | **done** 2026-10-01 (two commits: `voxel_game: a dropped stack keeps its wear`, then `voxel_engine, voxel_game: the bag grows (VA6)`): the held stack follows the pointer (`InventoryScreen.fingerLift` above a finger), a long press is a right-click, a tooltip read off the item's row (the slot under the mouse, else what is held, so a finger sees what it picked up), a store beside the bag in the recipes' place, a stack let go outside the panel thrown ahead (`PlayerEntity.throwStack`), a held stack with no room at close on the ground, the panel scaled down to fit a phone. First, VA5's leftover look: in third person the item sits in the right fist, and drops lie on the ground as their shape (a block a cube, a tool upright, food a lump). Learned: every drop was rebuilt from id and count, so a worn tool came back new — `VoxelGame.dropStack` and `ItemPickup.stack` carry the stack, `Inventory.put` takes it back. Seen on the Mac: a chest beside the bag, scaled into an 800-px window; the stack following the mouse and the tooltip only in tests (they take the owner's mouse). Not done: shift-click to move a stack across, and a pad still cannot work the bag (`KL-013`). Next: VA7 on `opus 5.5:high` | a grid with icons, the stack follows the pointer, tooltips, a container panel beside the bag, drop outside |
| VA7 Settings | **done** 2026-10-02 (`voxel_game: the player's settings (VA7)`): `GameSettings` (render distance, `lookSpeed` — the plan's sensitivity, a multiple of the stock turn —, FOV, volume, music volume, view bob, FPS), each range-checked, `GameSettings.of(spec)` the defaults (`renderDistance`, `PlayerSpec.fov`, `SoundSpec.musicVolume`; volume, look speed, bob and FPS have no spec field). `VoxelGame.settings` / `applySettings` apply live: `GameWorld.loadRadius` trims and refreshes the window (it only set the radius before), `InputMap.lookScale` scales the mouse, a drag, `look` and the stick (rule 13; a scripted `turn` stays a rate), the camera reads the FOV, `view.bob`, `playSound` under the volume, the HUD's FPS (`VoxelGame.showFps` removed). `SettingsStore`: `settings.json` beside `worlds`, version 1, read before the game starts (so the world starts at the player's distance), written 0.5 s after a change rests; the widget sets the music to `volume × musicVolume`. `SettingsScreen` from the game menu, Done and pause back to it; `SettingsPanel` is value-in, change-out, so VA8's title reuses it with no game. Decisions: settings are the player's, not the world's — one file per app, never in a world save, and a joined game uses them too; the app's `weather`, `climbWalls`, `tutorialDone` stay out until their feature is the kit's (VA9 adds weather as settings version 2). Seen on the Mac (a throwaway entry opening the screen from code, the owner's mouse left alone): the panel, FPS at the top left, FOV 100 and 10 chunks live, `settings.json` written; the file then deleted. A pad still cannot work the panel (`KL-013`). Next: VA8 on `opus 5.5:high` | a runtime, persisted `GameSettings` (render distance, sensitivity, FOV, volumes, view bob, FPS) and a panel for it |
| VA8 Worlds and the title | **done** 2026-10-02 (`voxel_game: worlds and the title (VA8)`): `WorldSaves` keeps `world.json` v1 per slot, read as `WorldInfo` (name, seed, `WorldMode` survival/creative or none = as the spec declares, created, last played, play time = `VoxelGame.time`); `create` (slot from the name in lower case, `_2`, `_3` when taken; only `world.json` written), `rename` (slot kept), `info`, `worlds()` (last touched first), `contains`; `save` writes `world.json` beside `game.json`; `seedOf` (a number is itself, text FNV-1a, empty random). A slot with no `world.json` is the legacy branch: name = slot, seed and play time from `game.json`, created unknown, loads, gets one on its next save. `WorldInfo.applyTo(spec)` (seed, mode through the new `PlayerSpec.copyWith`), applied by `VoxelGameWidget` to any `saveSlot` that is a world. `TitleSpec` + `runVoxelGame(spec, menu:)` (VAD4; throws with `saveSlot`/`hostPort`/`join`); `VoxelGameHome` alternates `TitleScreen` and the game (`TitleChoice`: `PlayWorld`, `JoinHost`), the game menu's Quit saves and returns; `TitleScreen`: Play (`WorldList`), Multiplayer (host a listed world on `TitleSpec.port`, this machine's IPv4 addresses shown; join `host[:port]`), Settings (`SettingsPanel` on the `SettingsStore`, no game), Credits (`CreditsRoll`), Quit on a desktop, Escape leaves a panel. `VoxelGameWidget.onNetError`: a refused join or a taken port returns to the title with a line saying why. Decisions: the app's vista (a second world orbiting behind the title) is not taken — `TitleSpec.background` is the hook, a dusk gradient by default; the app's class and playground stay the app's. Keyboard reaches the title through Flutter's focus traversal (it is not under `GameSurface`); a pad does not (`KL-013`). Learned: a dialog must own its `TextEditingController`, which outlives the pop's animation. Seen on the Mac (a throwaway entry driving the title by synthetic taps, the owner's mouse left alone, then deleted): title, list, form, a new world played, pause → Quit → the list showing `played 5 s`, Multiplayer, Settings, Credits. Next: VA9 on `opus 5.5:xhigh` | `WorldSaves` keeps metadata (name, seed from text, mode, created, played, rename); a world list and a title with host / join (VAD4) |
| VA9 Weather | **done** 2026-10-02 (`voxel_engine, voxel_scene, voxel_game: weather (VA9)`, then `docs: VA9 seen on the Mac`): `Biome.precipitation` (rain / snow / none: the app's hard-coded biome ids as the biome's row); `SkyLook.at` (pure: the sky, sun, ambient, sky light and fog reach under `overcast` and a bolt's `flash`, the app's `game.dart:540-610` numbers) applied by `DayNightSky.update(overcast:, flash:)`; `WeatherParticles` (the app's two emitters); `SkySpec.weather` = `WeatherSpec` (`WeatherOdds` + per-biome odds, spell length, fade, thunder, bolt spacing), `VoxelGame.weather` (`Weather`: `spell` the sky's, `kind` the player's biome's, `set`), `GameSettings.weather` with `settings.json` v2 (v1 loads, weather on), the panel's switch, the example's sky. Decisions: the sky greys over a desert too (Minecraft's), snow under a storm is a blizzard with no bolts; only an authority rolls (a client stays clear until VA16); weather is not saved; the app's rain-waters-crops and rain-puts-out-fire stay the app's (the kit has no fire). Learned: a storm rolled again must keep its bolt clock, or short spells never strike. **Seen on the Mac** (a throwaway entry, `RenderRepaintBoundary.toImage` around a `VoxelGameWidget`, `set(..., now: true)` from code, the window behind the owner's editor, then deleted): clear; rain, streaks falling, the sky grey and the ground about 16 % darker; a storm, about 28 % darker, a bolt 9.5 s in that whitens the sky and lifts the ground back; snow (a spec whose biomes snow), flakes and no streaks; snow under a storm, the storm's darkness and no bolt. Not judged: the fog closing in (16 % and 26 % of its reach), too slight to see past the forest's trees. The app's numbers kept: nothing looked wrong, and VA-Z wants them. Learned: macOS reports a covered window as `AppLifecycleState.hidden` and Flutter stops its frames, so the first session's entry never filled; a capture entry forces them (`SchedulerBinding.scheduleForcedFrame` every 16 ms) and logs to a file, not through `grep`, which holds its output until it exits. The same frames drive `VoxelGame.step`, so a covered desktop host stops its world (`KL-014`). Next: VA10 on `opus 5.5:high` | clear / rain / storm / snow on `SkySpec` by biome, particles in `voxel_scene`, the sky and fog darkened, lightning and thunder |
| VA10 Dimensions and portals | **done** 2026-10-02 (`voxel_engine, voxel_game: dimensions and portals (VA10)`): the engine's `WorldGenSpec.cavern` (`CavernSpec`: the app's underworld as rows — a slab of `stone` between a bedrock floor and roof opened by 3D noise, the sea in it, each floor its biome's `top`, `hangs` from the ceilings; no trees, no caves) and `DimensionGenerator` (a `SpecGenerator` per dimension, the workers' generator). `VoxelGameSpec.dimensions` `{id: WorldGenSpec}` beside `world` (id `'world'`), `portals` of `PortalSpec` (frame, portal, lighter, from/to, 2 × 3, 2 s, search 16), `checkDimensions`. `GameWorld` takes every dimension's spec: `switchDimension`, `storeEditIn`, `editCountIn`, `arrivalAt` (nearest firm spot to the surface in the column or four out, else a pocket of the dimension's stone above its sea). `VoxelGame.travel` / `dimension` / `travelState` (sealed `Travel`: `Staying`, `Charging`, `Arriving`, `Lingering`), `Portals` (lighting through the player's use, so every device; the return portal); the world keeps stepping during an arrival, only the player waits (`PlayerEntity.hold` / `placeAt`); a respawn elsewhere goes to the main world's spawn. Crops, stores and circuits per dimension. `game.json` v5 (dimensions, the player's, crops and stores by dimension), `edits.bin` v2 (`WorldSaves.codecFor`); v4 and its v1 file load. Net: edits per dimension, the hello names them, poses carry it (`RemotePlayer.dimension`, `playersHere`), the host's mobs only where the host is. Decisions: same seed for every dimension, 1:1 columns (the app's); a trip drops the creatures and items of the dimension left (the app frees wild mobs; nothing of the kit's is saved yet, VA13); no `if` by dimension anywhere, the arrival and the cavern read their spec's rows. Seen on the Mac (a throwaway entry, `RepaintBoundary.toImage`, frames forced every 16 ms, then deleted): the frame lit purple in the overworld, two seconds in it, the underworld — hellstone caverns, glowstone hanging, soul sand floors, fog to black — and back through the return portal to the overworld. Not judged: the return portal in the underworld drew nearly black (an alpha block over a dark cave; its own light 11 does not seem to brighten its faces); the tests prove it is built and leads back. Not done: a dimension's own sky and fog (the cavern shows the main sky's day over its roof; nothing looked wrong under it), a portal's blocks going when its frame breaks, and a host steps only its own dimension — a client in another has no liquids, block rules or mobs there (VA16, with the app's host-granted travel, `net.dart:521`). Learned: a hosted world's per-cell maps (crops, stores, circuits) must key by dimension or one dimension's chest opens in another. Next: VA11 on `opus 5.5:high` | `WorldGenSpec` per dimension, `GameWorld.switchDimension`, the save and net carry the dimension, a `PortalSpec` |
| VA11 Richer worldgen | **done** 2026-10-02 (`voxel_engine, voxel_game: richer worldgen (VA11)`): rows on `WorldGenSpec` — `strata` (`Stratum`: rock by depth, veined by ores), a biome's `covers` (`Cover`: by surface height, per mille, in patches) and `pools` (`Pools`: water over a bed where noise runs high, only where no neighbour stands lower and no cave opens), `TreeSpec.weight` / `belowY`, `Plant.maxHeight` / `spread` (whole across chunk borders: the ring just outside the chunk rolls too) / `byWater` (a column away from water skips it without spending its share). **Breaking:** `StructureSpec(name, structure, ...)` takes a `Structure` (radius, depth, clearing, blockNames, build); a build function is a `CustomStructure` (a const constructor cannot wrap a parameter in another object, so the function form could not stay beside the stock one). The stock library on `StructureSite`: `Dungeon`, `Tower`, `Well`, `Camp`, `Ruins`, `Mine` (rail, veins, liquids sealed), `Village` (doors to the well, paths from the doors, `VillageFarm`), blocks by name, furnishings nullable; their blocks are in `blockNames`. Structures keep apart (a site within the two radii of an earlier one's candidate is dropped; candidates cached, 4096 kept); two of one name throw. `StructureSite.hashAt` / `isRock` / `isOpen` / `level(floor:)`. A chunk's heights and biomes are worked out once (they were twice). **Parity:** a spec using none of the rows generates what it did, pinned in `spec_test.dart`; the example's world (and so the benchmark's) moves on purpose, once: peaks, tundra, desert, swamp, jungle, forest by weight, dark stone, gravel sea floor, all seven structures. Seen on the Mac (a throwaway entry finding each structure and biome through the generator, frames forced, `toImage`, then deleted): the village (huts, well, gravel paths, farm), tower, tent, ruins, well, the mine's frame and its corridor (supports, torches, rail), the dungeon's last room (chest, glowstone), swamp pools over mud with reeds, cacti, melons under jungle giants, snow in the tundra. Not judged: the peaks' snow line and the forest's big oaks (the camera stood in a tree), dark stone (underground, only the tests see it). Not done: chests are generated empty (loot tables on a generated store: VA13), the app's swamp flattening and temple, a spawner block. Learned: an inapplicable plant must not spend its share or the next one's odds move; a plant that spreads must roll from the ring outside the chunk too, or a patch at a border is cut. Next: VA12 on `opus 5.5:high` | weighted trees per biome, plant clusters, layers by depth and height, a stock structure library on `StructureSite` |
| VA12 Signals finish | **done** 2026-10-02 (`voxel_game: signals finish (VA12)`): `SignalSpec.pistons` (retracted to extended) and `poweredRails` (unpowered to powered) with `railReach` (8), over the engine's `SignalReactions.piston` / `poweredRun`; the engine did not change. A piston pushes the way its retracted block faces in a `Facing.compass` (the row that already turns placing toward the look, so it pushes away from the player, as the app's `Blocks.pistonDir`); one that is no compass variant throws at start. What moves: hardness ≥ 0, no `storage`, not `tall` (the app pushed any block of hardness ≥ 0; a chest would have spilled, a door half split); what it moves into: `BlockRegistry.isReplaceable` (the app's). The extend plays `place_<family>` at pitch 0.7 (the app's `Sfx.play('place', -8, 0.7)`). The example declares circuits for the first time — wire, lever, lamp, four pistons, powered rails on both axes, recipes — appended to its blocks, so saves and the generated world keep their ids. `game/circuits.dart` has nothing left that the kit lacks: every reaction it builds is now a `SignalSpec` row. Seen on the Mac (a throwaway entry, frames forced every 16 ms, `toImage`, then deleted): an east piston pushed a cobblestone one cell and a north one a log, both turned to their grey extended block, both went back to wood unpowered with the blocks left where pushed; a lamp lit down a wire; 13 rails lit (the run touched a north-south run powered from the other end, so both ends fed it: the reach itself is in the test). Not judged: a powered rail's colour at nine blocks (the bars look alike lit and unlit there; the log read them `_on`). Not done: a piston's head as a block of its own (the app has none either), sticky pistons, rails that carry anything (VA15). Learned: a probe entry needs the `MaterialApp` `runVoxelGame` gives, or the loading screen throws and the game never steps. Next: VA13 on `opus 5.5:high` | `SignalSpec.pistons` and `poweredRails` (the engine has both) |
| VA13 Creatures grow | **done** 2026-10-02, in three commits: **VA13a** the mob's own rows (loot, xp, levels, burns, splits, onHit, cave spawns, biome weights), **VA13b** taming, pets and mounts, **VA13c** persistence and mobs saved (`game.json` v6). **VA13a done** 2026-10-02 (`voxel_game: creatures grow, their own rows (VA13a)`): `MobSpec.loot` (the engine's `LootTable`; `Drop` gone), `xp` (to the player whose blow kills it; a spec with none in `PlayerSpec.xp` throws), `levels` (`MobLevels`: the player's level + 1 ± `spread`, + `caveBonus` in a cave; HP, every strike's damage and xp grow by a share a level — the app's 0.18 / 0.15), `burnsInDaylight` (the app's rule: head at sky 15, daylight ≥ 0.9, out of liquid, 0.5 twice a second), `splitsInto` (`MobSplit`, children at the parent's level), `onHit` (`HitEffect`, through `Mob.strike`), `SpawnRule.place` (`SpawnPlace`), `.cave()`, `biomeWeights`; the spawner searches pockets underground (the app's 70 %, 6 under the column's ground) and in a cavern dimension always; `checkMobs`. Not seen on the Mac yet: VA13b's look covers both. Not done here: the app's affixes (stay the app's), a shot that sets the target burning (VA14), `ghost` (VA13c). Learned: Flutter's `Split` curve took the name, hence `MobSplit`; the host's client-hit loop ran over the live mob list, which a split grows (now a copy). **VA13b done** 2026-10-02 (`voxel_game: creatures grow, tamed and ridden (VA13b)`): `tameWith` / `tameChance` / `tamedBrain`, `PetFight`, `Heel` (teleport past 30 m to a clear side of the owner), `MountWait`, `MountSpec`; riding is the player's (`ride` / `dismount` / `riding`), the mount moved inside the player's step (`Mob.carry`) so the rider never lags a step; use mounts, sneak gets off (no new action: every device has sneak; a touch's sneak switch stays on after). Seen on the Mac (a throwaway entry, frames forced, `toImage`, deleted): a zombie burning at noon (0.5s over it, 20 → 14.5 with the wolf's bites), the player seated on the horse with its notice, the wolf 2.7 m away with the zombie as its target, a slime dying into two small ones, xp 8. Not judged: the wolf and the small slimes were out of frame. Not done: pets are dropped on a trip to another dimension (VA10's rule), a client cannot tame or ride (VA16), a tamed pet's name or heart over it. **VA13c done** 2026-10-02 (`voxel_game: creatures grow, kept in the save (VA13c)`): `MobSpec.persistent` (the spawner neither takes it away nor counts it) and `ghost` (`noclip`; a ghost must fly, `checkMobs` throws otherwise). `game.json` v6: `mobs` by dimension, the tamed and persistent creatures of the dimension the player is in (id, position, facing, health, level, tamed); a load spawns them again (`spawnMob`, `growTo`, `tame(game.player)`), a wild creature is not kept, a v5 save loads with none, a network hello (no player) brings none. `Mob.facing` became a settable field. Seen on the Mac (a throwaway entry: a wolf tamed 3.7 m ahead at 9 hp, saved to a temporary `WorldSaves`, the game torn down and loaded again from the slot, `toImage` both times, then deleted): the same grey wolf on the same block in both frames, tamed, owned by the new player, 9 hp, at 7, 49, -8. Not judged: a level kept on screen (the example's tameable creatures have no levels; the test covers it). Not done: a ghost drawn see-through (every rig shares one opaque material: `KL-015`), the mount the player sat on (a load stands the player beside it), pets kept across a trip (VA10's rule stands), a client's creatures (VA16). Learned: a solid body spawned inside stone is pushed out of it, so a ghost is witnessed crossing a wall, not leaving a block. Next: VA14 on `opus 5.5:high` | `MobSpec`: taming, pets (fight, heel), mounts, level scaling, XP, burns by day, splits, persistence, an effect on hit, cave spawns and biome weights; mobs saved; `Drop` becomes a `LootTable` |
| VA14 Combat feel | **done** 2026-10-02 (`voxel_scene, voxel_game: combat feel (VA14)`): `PlayerSpec.critChance` (0 by default: nothing rolled) / `critMultiplier` (1.5, rounded, the app's), `PlayerEntity.critical` for a swing and a shot of the player's, `Damage.crit` to the victim and over the wire, the number yellow with `!`; a blow from outside holds the victim's pose `Mob.hitStop` 0.06 s and shows it white `hitFlash` 0.1 s (creatures, replicas, the player's model), an internal hurt only shakes; stagger was already the kit's (`CharacterMotor.shove`, 0.3 s); the camera shakes by the damage (`PlayerEntity.shake`: /10, ≤ 0.3 m, 0.15 s, the app's numbers) and no longer on an effect's tick; a death topples in 0.4 s and fades in 0.3 s (`Mob.opacityAfterDeath`, 16 steps); `Mob.ignite` (fire over the daylight rule's numbers, liquid puts it out), orange and an ember a burn; `VoxelGame.debris` (voxel_scene's `DebrisParticles`, one particle system: two chips a dig, twelve a break by hand, shaded by the light on the block's faces since sprites are unlit); `ProjectileSpec.light` / `trail` / `burns` / `onHit`, `bolt` lights and trails, `fireball` new. voxel_scene: `VoxelModelMesh.flash()` / `tinted(rgba)`, one material a look, `RigInstance.paint`; `KL-015` closed (a ghost see-through). The example: crit 0.1, a `burning` effect, a wisp (a ghost throwing fire). Seen on the Mac (a throwaway entry, frames forced, `toImage`, deleted): the wisp see-through before a wolf; a fireball's box and orange trail crossing the view, and the player left `Burning 4s` by the wisp's shot; a wolf set alight drawn orange-brown (grey times orange) with an ember over it; a wolf white the frame after a blow, its `3!` yellow; a dead one lying on its side half faded; a dozen green chips out of a broken grass block; the player's model white in third person. Not judged: the bolt's light by day (the noon sun washes a 4 m light out), the hit-stop (a still cannot show it). Not done: debris for a block broken by another player or a blast (a crater would be thousands), a burning player of the kit's own (the fire shot's `onHit` is the hook), the app's spawn poof. Learned: the death fade cannot be seen headless (no rig, so a death removes at once), hence the pure `opacityAfterDeath`; `groundHeight` is the first air cell, not the ground's. Next: VA15 on `opus 5.5:high` | crits, hit-stop, flash, stagger, camera shake, a death that fades |
| VA15 Vehicles and fishing | **done** 2026-10-02, in three commits: **VA15a** a seat and a boat, **VA15b** rails and a minecart, **VA15c** fishing. Decided for all three: a vehicle stays where it was left — a trip parks the vehicles of the dimension left (`parkedVehicles`) and puts back those of the one entered, and the save keeps every dimension's (`game.json` v7); the host owns them, and their net is VA16. **VA15a done** 2026-10-02 (`d383349` `voxel_game: vehicles, a seat and a boat (VA15a)`): `Rideable` (`Mob` is one), the sealed `VehicleSpec`, `BoatSpec`, `Vehicle`, `Boat`, `VoxelGameSpec.vehicles` / `checkVehicles`, `VoxelGame.placeVehicle` / `vehicleRows` / `restoreVehicles`. Seen on the Mac (a throwaway entry, frames forced, `toImage`, deleted): the boat afloat, boarded, rowed at ~6.4 m/s, rolled into a turn, left by the sneak. Learned: the body's `inLiquid` is sensed 0.3 m over the feet, so the boat has its own `afloat`; `usableOn` asked a rider for no mount of theirs, a crash of VA13b's, fixed. Not done: the boat's icon, a seated pose, chips as it breaks, the net. **VA15b done** 2026-10-02 (`5dcc924` `voxel_game: rails and a minecart (VA15b)`): `Rails` (`VoxelGame.rails`, `world/rails.dart`) reads the rails from the blocks — a rail shape is a rail of the kind it drops (`dropOf`), a `poweredRails` value powers (6 m/s²) and its key brakes (12) — and lays them on the authority (`RailGraph.place` / `removed`, guarded against its own edits as `BlockRules` is); checked at start (one block a kind, shape and state; both straights; a powered rail a rail). `CartSpec` (the app's numbers and cart) and `Minecart` (the app's state: cell, from, to, t, speed; hops, reversal), put on the aimed rail heading for the end nearest the look, pushed by `wish · heading`, rolling alone, still with no rail under it; `Vehicle.restoreRow` reads its `rail` row back. The example lays its rail in every shape (appended, drop `rail`), crafts rails and a minecart. Seen on the Mac (a throwaway entry, frames forced, `toImage`, deleted): the cart on the bars by the lit powered rails, ridden in third person east, through the north-west curve at 5.8 m/s, up the slope onto a block (y 48.39 on it at 5.2 m/s) to the end of the line on top (49.125, turned to roll back). Learned: a rail set by code over another rail is not turned (a rail-to-rail change is the circuits' flip, so `Rails` lays only what was no rail); the circuit test's powered rail had one straight and an on state of another kind (no `drop`), which `Rails` now refuses, so its fixture gained the north-south pair. Not done: the minecart with a chest (decided), a cart shoved by walking into it, a rolling sound, the net. **VA15c done** 2026-10-02 (`voxel_engine, voxel_game: fishing (VA15c)`): the engine's `LootTable.oneOf` (one entry by its chance as a slice of one roll, the rest nothing; `check()` throws past 1, and `roll` checks: a const table cannot sum in an assert). `FishingSpec` (`fishing/`: rod, catches, liquids `{'water'}`, reach 8, a wait of 3–8 s, a bite of 1.5 s, xp 2), `VoxelGameSpec.fishing` / `checkFishing` at start. `Bobber`, an entity: the app's arc (2.2 a second, 1.4 m), float, dip on a bite, a line from the hand (`PlayerEntity.drawnHand`) drawn every frame under the float's node, which never turns. `PlayerEntity.bobber`: the rod, on a press only, casts at the first of the spec's liquids, lands a bite, reels in an empty line; the rod out of hand, twice the reach, death reel it in, a trip forgets it. The catch goes in the bag (`pickUp`), the rest on the ground. The example: `fishing_rod`, `raw_fish`, catches one-of 70/10/15/5 (a fish, two, a bowl, a lighter). Seen on the Mac (a throwaway entry, frames forced, `toImage`, deleted): the float mid-arc over a pool with its line to the fist, floating at the surface, dipped 0.21 m on a forced bite with "Something bites!", the line from the body's right to the float in third person, "+1 Raw Fish" and xp 0 → 2 after the use. Not judged: the line from the first-person fist while walking (the fist it hangs from is the resting one, without the hand's sway). Not done: a rod's own shape (it shows the stock item), a splash of droplets, the app's treasure with bonuses and its "Treasure!", the rod's wear, the net (VA16). Next: VA16 on `opus 5.5:high` | a boat, a minecart on `RailGraph`, a fishing line on a `LootTable` |
| VA16 Net catches up | **split** 2026-10-02 into seven commits, decisions VAD6–VAD11 settled (§VA16 has the split). **VA16a done** 2026-10-02 (`voxel_engine, voxel_game: a client's block edit is a prediction the host settles (VA16a)`): a client's edit leaves as a `requests` row (number, cell, old id, new id), the host compare-and-sets it where it has the chunk and acks the id that stands (`acks`), unchecked and passed on elsewhere (`KL-003`'s rule); `BlockPrediction` (`net/block_prediction.dart`, not exported) holds the cell until the ack, so the host's echo waits, and an ack that differs from the prediction rolls back (`ClientSession.pendingEdits` / `rollbacks`); a malformed message throws. The lever: `SignalRules.usedInto` (engine) and `VoxelGame.useSignal`, a flip on a client being a plain edit the host's `SignalNetwork.touch` answers (a button's release runs on the host's clock, since `touch` starts it). Learned: an ack's rollback compares with the edit's own prediction, not the world (the app's `current != finalId` rolls back a later prediction of the same cell); only the cell's latest edit rolls back. Witnessed in `net_game_test.dart` (four tests, the echo one failing without the hold). **VA16b done** 2026-10-02 (`voxel_engine, voxel_game: drops and the bag (VA16b)`): the host numbers every `ItemPickup` its game makes (a scan of the step's entities, so every path is covered) and sends `drops` (made, with its dimension), `drop_poses` (10 Hz, moved > 5 cm) and `drops_gone`; a client draws replicas (`ItemPickup.replica` / `netId` / `setNetPose`) in the host's dimension only, and is sent them again on coming back to it; the hello carries them (`joinHost`'s `drops`). `dropStack` on a client where the host is is a `drop` request (`GameSession.handOffDrop`) and returns null; the host picks the nearest living player whose bag takes some of the stack (`Inventory.roomForStack`, engine), `RemotePlayer.give` / `onGive` / `bag` (declared ≤ 5 Hz, counted until the next declaration), `give_rest` dropped at the puppet's feet with `ItemPickup.wait` 2 s. Decisions: where the host is not, a client keeps its own drops (nobody else steps that world), and a request that crosses a trip goes back to the bag; a puppet with no declared bag is pulled toward by nothing; the game's own player with a full bag is no longer pulled toward either. Learned: a host's drop where it has no world (a far client's break) fell to the world's floor, since an unloaded cell reads as air — now it waits in the air (`net_game_test`'s far-client test fails without it). Not done: a replica's count after a partial pickup stays what it was made with (nothing draws it); a client's own drops elsewhere stay its own if the host arrives later. Witnessed by six tests (five in `net_game_test.dart`, one in `dimensions_test.dart`). Next: VA16c on `opus 5.5:high`. Found while orienting: time already crosses (the 20 Hz `state` carries `time` / `tod`), the dimension already rides poses, edits and the hello; nothing of the items on the ground crosses (a client's break drops only on the client, `voxel_game.dart:1094-1104`, and `ItemPickup.tick` reads only `game.player`, `item_pickup.dart:76`); a client pulls no lever (`signals` is null off the authority, so the use falls through to placing); a client's shots are seen by nobody. Next: VA16a on `opus 5.5:high` | block prediction with ack and rollback, drops replicated, container sessions, time and weather sync, vehicles | with ack and rollback, drops replicated, container sessions, time and weather sync, vehicles |
| VA17 Sound catches up | todo | `SoundSpec`: music from recipes with no files, moods sharing a track, footsteps by a block's field |
| VA-Z The app on the kit | todo | `examples/voxel_game_minecraft` runs on `VoxelGame`; its copies deleted (§What the app deletes); its probes print what they printed |

Each step is one or more commits, each with tests (rule: the API is a spec) and the example
showing the feature. Steps VA1–VA17 touch only `packages/`; the app is untouched until VA-Z,
except where a step's own row says the app switches a file (a duplicate that becomes
deletable the moment the kit's version exists).

Run every step on `opus 5.5:high` (a kit API a game reads, most of them crossing
`voxel_engine` / `voxel_scene` / `voxel_game`); VA9 and VA5 on `opus 5.5:xhigh` (particles,
meshes, rendering); VA-Z on `opus 5.5:max` (6.5k lines of `game.dart` and its probes).

---

## Where the app stands against the kit

### Already the kit's (the app imports it)

`FixedStepLoop`; `CharacterMotor` / `MotorTuning`; `ShoulderOrbit`, `ViewBob`; `InputMap`,
`InputBindings`; `Goal`, `GoalSelector`, `RigAnimator`, `RigKind`, `RigMotion`; the engine's
`Inventory`, `StatusEffects`, `RecipeBook`, `LootTable`, `BlockRegistry`, `OreTable`,
`CaveCarver`, `TreeCanvas`, `ChunkStreamer`, `LiquidFlow`, `RailGraph`, `SignalNetwork`,
`NetHost` / `NetConnection`, `Pathfinder`; `voxel_scene`'s `NodeBody`, `VoxelModelMesh`,
`VoxelChunkView`; `sound_recipes`' `SoundBank`, `MusicDirector`. `rails.dart`,
`circuits.dart`, `recipes.dart` and `sfx.dart` are thin wrappers over these.

### Second copies (the kit has it, the app wrote its own)

| The app's | The kit's | Why it stayed |
|:---|:---|:---|
| `Game._tick` order, `_prune`, pressure plates into signals (`game/game.dart:797`, `:963`, `:825`) | `VoxelGame.step` (`core/voxel_game.dart:453`) | the app's `Game` is not a `VoxelGame` |
| sky, sun, fog (`game.dart:487-621`) | `DayNightSky` | no weather input in the kit's (VA9) |
| save and load, autosave (`game.dart:1851-1924`) | `WorldSaves` / `SavedWorld` | the kit's keeps clock, player, edits; the app's also chests, crops, entities, dimension (VA2, VA10, VA13) |
| `explode`, `spawnDrop`, `addMob` | `VoxelGame.explode` / `dropItem` / `spawnMob` | — |
| walk, sprint, sneak, swim, ladder, footsteps, fall, lava, drowning, hotbar, aim, mine, place (`player/player.dart:522-1573`) | `PlayerEntity` | the app's has survival stats around it (VA1) |
| `Target`, `SceneBody`, `Projectile`, `RemotePlayer` (`entities/`) | `entities/target.dart`, `GameEntity`, `entities/projectile.dart`, `net/remote_player.dart` | hooks the kit lacks: burning, crits, a bolt's light (VA14) |
| `Mob._buildModel`, A* steering, fly / hop / swim (`entities/mob.dart:605-749`, `:1026`, `:1069`) | `Rig` / `RigModel`, `Mob._steer`, `Mob._locomote` | per-part access for shearing; `Vector3` colours |
| goals `Roam`, `Chase`, `Kite`, `Strike`, `Fuse`, `Flee` (`entities/mob_brain.dart`) | `Wander`, `Hunt`, `RangedAttack`, `MeleeAttack`, `Explode`, `FleeWhenHurt` | the pet goals have no kit twin (VA13) |
| `ui/touch_controls.dart` (368 lines) | `TouchControls` / `TouchControlsSpec` | the kit's is bound to `VoxelGame` / `VoxelAction`; the kit's is better (floating stick, safe area, claimed touches, per-pointer holds) |
| `VoxelWorld` facade (`world/voxel_world.dart`) | `GameWorld` | dimensions (VA10) |
| its biome classifier, height field, per-biome trees (`world/terrain_generator.dart`) | `SpecGenerator` | swamp pools, rivers, layers, multi-tree biomes (VA11) |
| `Items.mineTime` (`core/items.dart:251`) | `MiningRules.mineTime` | a shears-on-leaves case |
| `Worlds` (`game/worlds.dart`) | `WorldSaves` | metadata (VA8) |
| `game_view.dart` loading text | `LoadingScreen` / `LoadingStage` | — |
| `VoxelMeshBuilder`, `HandView`, `PlayerModel.setHeld`, `ui/item_icon.dart` | `ItemModel`, `FirstPersonView`, `RigInstance.hold`, `ItemIcon` (VA5) | the app's shapes by its own `ItemKind` and weapon style; VA-Z declares them as `ItemShape`s |

### Stays the app's (game content, not kit)

Classes, abilities, talents, mana, the dodge; quests, achievements, the tutorial's text, the
journal, the bestiary counters; villager offers, bosses and their structures (fortress,
temple, the underworld lord); the playground; the credits' lines; the block, item, recipe
and species rows; every probe (`game.dart:2014-6560`, ~4.5k lines, which VA-Z moves under
`tool/` or a probe file rather than deleting).

---

## The steps

### VA1 · Survival on `PlayerEntity`

The app has it in `player/player.dart:798-840`, `:1828` (eating), `:1905` (XP), `:1330`
(wearing). The engine's `StatusEffects` exists and nothing in the kit's player carries it.

- `PlayerSpec`: `hunger` (null: no hunger, the example's default stays as today), regen and
  starvation rates; `xp` curve; the engine's `ItemType` gains `food`, `heal`, `armor`
  (slot and points), `effect` + `seconds`. Rule 7: a row's field, never a branch by id.
- `PlayerEntity` carries a `StatusEffects`; armor reduces damage as the app's does
  (`totalArmor * 0.4`, floor 35 %), saved in `SavedWorld.state`.
- `VoxelAction` gains only what a new feature reads (`VAD2`).

### VA2 · Blocks that do things

`game.dart:1739` (crops), `:1765` (falling), `:1805` (a wall torch pops, a door's other half
breaks), `:1067` (chests); `player.dart:1233` (doors), `:2205` (buckets);
`core/blocks.dart:326-375` (facing).

- `BlockType.falls`, `BlockType.supportedBy` (the neighbour rule for a break), a crop's
  stages as rows (`grows: ['wheat_0', …]`, light-gated), `BlockType.container` (slots; the
  inventory lives in the world save, and spills on a break through a `LootTable`), facing
  variants chosen from the player's forward.
- `ItemType.container` / `liquid`: a bucket scoops and pours through `LiquidFlow`.

### VA3 · Screens as a state machine

`openScreen` is a `ValueNotifier<String?>` holding a station id; `GameSurface` always shows
`InventoryScreen`; `playerDied()` is empty (`core/voxel_game.dart:339`, `:638`); a respawn
is a timer. Rule 9: a sealed `GameScreen` (bag, container of a cell, pause, death, and a
game's own by id), the builders declared on the spec (`screens: {id: builder}`), a pause
menu (resume, settings, save and quit) and a death screen with a respawn button. Rule 12
holds: the world keeps stepping behind every one.

### VA4 · `DefaultHud` grows

`ui/hud.dart:383-808`, `ui/hud_state.dart`. Each piece is shown only when its feature is
declared (no hunger bar without `PlayerSpec.hunger`): bars, the effects list, merged pickup
toasts and a notification feed (`VoxelGame.notify`), the crosshair turning on a creature, a
radial mining ring, a durability bar on a slot, damage numbers and bars over creatures
projected from the world, the underwater / lava tint, a boss bar, the FPS overlay over
`FrameStats`. The map and minimap (`hud.dart:209-381`) wait until the rest is in: they
depend on explored-chunk bookkeeping the kit does not keep.

### VA5 · Items have a shape

`entities/voxel_mesh_builder.dart` (173 lines), `entities/hand_view.dart`,
`entities/player_model.dart:133`, `ui/item_icon.dart`. One shape per item, derived from
`ItemType.block` / `tool` and the block's `BlockShape`, instanced (`KL-007`): the
first-person hand holds it with the app's sway and swing, a third-person rig holds it, a
drop is it, and the HUD and bag draw a cached isometric icon of it instead of a colour
square.

### VA6 · The bag screen grows

`ui/inventory_screen.dart` (352 lines) against the kit's 209: slots with VA5's icons, the
held stack under the pointer (and under a finger: a tap picks, a tap places — rule 13), a
tooltip, VA2's container beside the bag, a stack dropped outside the panel.

### VA7 · Settings

`game/settings.dart`, `ui/settings_panel.dart`. The spec's values are the defaults; a
`GameSettings` the player changes at run time, saved beside `worlds/`, applied live
(render distance through `GameWorld`, sensitivity through `InputMap`, FOV, volumes, view
bob, FPS). Key rebinding is out of scope here; `InputBindings` can back it later.

### VA8 · Worlds and the title

`game/worlds.dart`, `ui/world_list.dart`, `ui/title_screen.dart`, `ui/credits_screen.dart`.
`WorldSaves` keeps a `world.json` (name, seed from text by FNV-1a, mode, created, last
played, play time), rename and collision-safe slots. A `WorldList` and a `TitleScreen`
(new world, play, delete, rename, host a world, join by address — the kit already has
`hostPort` / `join`), reached through `runVoxelGame` when the game asks for it (`VAD4`).

### VA9 · Weather

`game/weather.dart` (230 lines). `SkySpec.weather`: per-biome odds of clear, rain, storm,
snow; an eased intensity that darkens `DayNightSky`'s sun and fog; lightning flash and a
thunder recipe; rain and snow particles in `voxel_scene` (on `flutter_scene`'s
`ParticleSystem`). The host decides and sends it (VA16). The app's hard-coded biome ids
(`weather.dart:155-162`) become the biome's row.

### VA10 · Dimensions and portals

`world/terrain_generator.dart:1110-1292` (the underworld), `world/voxel_world.dart:270-312`,
`game/portals.dart`. The engine's `ChunkStreamer` already keys by dimension;
`SpecGenerator.generateIn` ignores it. `WorldGenSpec` per dimension (`dimensions: {id:
spec}`), `GameWorld.switchDimension` and edits stored for a dimension one is not in, the save
and the net's edits carry it, and a `PortalSpec` (frame block, portal block, target, the
return portal and a safe arrival).

### VA11 · Richer worldgen

`terrain_generator.dart:215-602`, `:642-1105`. Weighted trees per biome, plant clusters
(melons, cacti two or three tall, reeds on a pool's edge), surface layers by depth and
height (dark stone below, snow above), water-over-mud pools; a stock structure library on
`StructureSite` — dungeon, tower, well, camp, ruins, mine with rails, village with paths —
taking block names as parameters. Parity hashes for the example's world move on purpose,
once, and the commit says so.

### VA12 · Signals finish

`game/circuits.dart`: `SignalSpec.pistons` and `SignalSpec.poweredRails` over the engine's
`SignalReactions.piston` / `poweredRun`. Then `circuits.dart` has nothing left of its own.

### VA13 · Creatures grow

`entities/mob.dart`, `entities/mob_brain.dart:205-276`, `entities/spawner.dart`,
`core/species.dart`. On `MobSpec`: `tameWith` / `tameChance` and the goals a tamed creature
switches to (`PetFight`, `Heel` with the teleport past 30 m, `MountWait`), `mount` (riding
from the rider's input), `levels` (HP and damage scaling), `xp`, `burnsInDaylight`,
`splitsInto`, `persistent`, `onHit` effect, `ghost`; `SpawnRule` gains caves (air pockets
underground) and biome weights; mobs saved in `SavedWorld`; the kit's `Drop` gives way to
the engine's `LootTable` (`Mob.kill` rolls drops by hand today, `mobs/mob.dart:385`).
Affixes stay the app's content, on a kit hook.

### VA14 · Combat feel

`game.dart:1485-1565`, `mob.dart:753-770`, `player.dart:198`: a crit chance on
`PlayerSpec`, hit-stop, white flash, stagger, camera shake on a hit taken, a death that
topples and fades, debris on a break, `Projectile` hooks (a light and a trail, fire that
sets the target burning).

### VA15 · Vehicles and fishing

`entities/boat.dart` (112), `entities/minecart.dart` (297), `entities/bobber.dart` (164),
`player.dart:1089-2193`. A seat an entity offers and the player takes (`Rideable`), a boat on
liquid, a minecart on `RailGraph` with powered runs (VA12), and a fishing line whose catch is
a `LootTable`. Last among the gameplay steps: each one needs VA13's riding.

### VA16 · Net catches up

`game/net.dart` (1266 lines): block prediction with a sequence number, the host's ack and a
rollback (`:29-56`, `:441-480`); drops replicated with interpolated poses; a peer's full bag
(give / give-rest); container sessions with the host checking the peer's bag (`:893`); time
and weather sync; the dimension on travel (`:521`); vehicles. Each lands with the feature it
replicates where it can, and this row closes what is left. `KL-002` and `KL-003` read first.

The kit's side today: `packages/voxel_game/lib/src/net/sessions.dart` (`HostSession`,
`ClientSession`), `remote_player.dart`, the engine's `net/` transport. Split into seven
commits, in this order, each with its tests in `test/net_game_test.dart` (a headless host and
clients over localhost):

- **VA16a Blocks.** A client's edit carries a sequence number and the id it replaced (VAD6);
  a prediction owns its cell until its ack, so the host's echo for that cell waits; the ack
  carries the id that stands, and a different one rolls the client back. An edit where the
  host has not loaded the world is taken unchecked and passed on (`KL-003`'s rule). A client's
  lever becomes a request the host's signals answer.
- **VA16b Drops and the bag.** The host owns every drop; a client's `dropStack` is a request
  (VAD7). Replicas by net id, poses at 10 Hz for a drop moved more than 5 cm, lerped; the
  host decides the pickup (the nearest player, its own or a peer's puppet), `give` hands the
  stack to the peer, `give_rest` brings back what did not fit, dropped at the puppet's feet.
  The client declares its bag when it changes (≤ 5 Hz); the host pulls no drop toward a full
  one. The hello carries the drops there are.
- **VA16c Stores.** `StorageScreen` on a client through `store_open` / `store_close`; the
  host sends the store, and every change to whoever has it open (its own screen too); each
  slot edit is checked as VAD8 says. A store broken while open shuts the screen.
- **VA16d Sky.** The host's weather (spell, intensity, at full on a join) followed by the
  client; each keeps its own bolt clock.
- **VA16e Creatures.** A client tames: a request with the item in hand, the host rolls
  `tameChance`, the owner is the puppet; a mob's row carries its owner's peer and its
  rider's; a client rides its own pet (VAD9).
- **VA16f Vehicles.** Requests to put down, board, leave and break; replicas with poses;
  the vehicles in the hello; driven as VAD9 says. `Vehicle.takes`, `placeVehicle` and the
  player's swing lose their `authority` gates.
- **VA16g Closing.** Each player's float in its pose (a `RemotePlayer` draws the float and a
  line from its rig's hand), a rider's seated pose, a client's shots seen by the others; the
  VA16 row closed.

### VA17 · Sound catches up

`game/music.dart`, `game/sfx.dart`, `player.dart:223`. `SoundSpec.music` takes a
`MusicScore` per mood (music with no files), moods can share a track, night keeps its day's
track, a music volume beside the master (VA7); a block's footstep kind as a field rather than
the app's recorded takes.

### VA-Z · The app on the kit

`examples/voxel_game_minecraft` becomes a `VoxelGameSpec` plus its own content and systems
(`GameSystem`s for quests, achievements, bosses, trades, classes), its own screens through
VA3, and its probes. What it deletes then: `Game`'s tick, sky, save, prune; `Player` but for
its classes; `Mob` but for its affixes and bosses; `Target`, `SceneBody`, `Projectile`,
`RemotePlayer`, `ItemDrop`, `Spawner`, `HandView`, `PlayerModel`, `VoxelMeshBuilder`,
`Boat`, `Minecart`, `Bobber`, `VoxelWorld`, `Worlds`, `Settings`, `touch_controls.dart`, most
of `hud.dart`, `inventory_screen.dart`, `title_screen.dart`, `world_list.dart`,
`settings_panel.dart`, `weather.dart`, `portals.dart`, `rails.dart`, `circuits.dart`, and
`net.dart`. Its saves must still load: the Godot-compatible format is the app's contract
(its `CLAUDE.md`), so VA-Z starts by reading one old save into the kit's `SavedWorld` in a
test.

---

## Decisions

Settled by the owner on 2026-09-30, each as recommended. Do not re-litigate them.

| ID | Question | Settled |
|:---|:---|:---|
| VAD1 | Is the end state the app on `VoxelGame` (VA-Z), its copies deleted? | **Yes.** Until then every duplicate above is paid twice, and the app does not witness the kit's gameplay, only its lower pieces |
| VAD2 | The actions: does `VoxelAction` grow, or do the kit's widgets take a game's own action enum (`InputMap<A>`)? | **`VoxelAction` grows**, one action per kit feature that reads it (glide, fly, interact); a game's own (the app's abilities, journal) stay a game's through a `GameSystem` reading its own binding. Generic widgets over `A` would make every kit widget take a mapping for little gain |
| VAD3 | Survival's scope | **Hunger, XP, armor and status effects are the kit's**; stamina, mana, classes, talents and the dodge stay the app's. The first four are Minecraft's own; the rest is an RPG layer the app chose |
| VAD4 | Does `runVoxelGame` show a title and a world list (VA8), or does a game opt in? | **A game opts in** (`runVoxelGame(spec, menu: TitleSpec(...))`): today's one-line game still drops straight into its world |
| VAD5 | Order | **Survival and screens first (VA1–VA8), then the world (VA9–VA12), then creatures and net (VA13–VA17), then VA-Z.** VA1–VA4 change what the example plays like the most, and VA3 is what VA6–VA8 mount on |

Settled by the owner on 2026-10-02 for VA16, each as recommended.

| ID | Question | Settled |
|:---|:---|:---|
| VAD6 | What does the host check of a client's block edit? | **Compare-and-set**: the client sends the id it replaced, and the host refuses when its own differs (the ack carries the id that stands, the client rolls back). It holds for every action (doors, buckets, hoes, portals) without the host running each one again, and settles two players on one cell. The cost, accepted: one half of a door may be refused and the other not. The app checks nothing, so it rolls back only when a rule of the host's changes the block |
| VAD7 | Who rolls the loot of a block a client breaks? | **The client**, as the app does: `dropStack` on a client is a request to the host, one path for a break, a throw, a bag's overflow and a catch's rest. The host could not roll it, since it does not know the tool |
| VAD8 | How does the host check a store edit? | **Compare-and-set per slot** (the client sends the slot before and after) **and** the app's account: what enters must be in the peer's declared bag or have left this store in this session. A refusal undoes the client's whole operation, the stack in hand too. The app's escrow alone duplicates: two players take one stack, the second is refused and still holds it |
| VAD9 | Who drives a vehicle or a mount a client rides? | **The rider.** While a client rides, its copy is the live one and the host's follows as a replica; getting off hands it back to the host. No input lag. The app's host simulates from the input in the pose, and its client feels a round trip as it rows |
| VAD10 | Travel between dimensions | **The client's own**, as now: its pose is trusted already. The app's host grants it (the puppet's feet in a portal, `net.dart:521`); not taken. A host simulating a dimension it is not in is out of scope (below) |
| VAD11 | A malformed message from a peer (an id that is not, an undeclared dimension) | **Throws** (rule 5): a peer with the same spec never sends one. A compare-and-set refusal is a legitimate branch (rule 6), not a warning |

## Out of scope

- The app's content (§Stays the app's) and its probes as probes.
- Key rebinding UI, chat, the full map (VA4 says why it waits).
- A new package (rule 4): weather particles live in `voxel_scene`, which already depends
  on `flutter_scene`; nothing here brings an optional heavy dependency.
- A host stepping a dimension it is not in (VAD10): a client alone in another dimension has
  no liquids, block rules or creatures there. The app has none either.
