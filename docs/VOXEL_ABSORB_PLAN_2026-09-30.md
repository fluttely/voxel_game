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
| VA5 Items have a shape | todo | one voxel shape per item (the app's `VoxelMeshBuilder`) for the hand, the drop, the third-person held item and an icon; `KL-007` read before it |
| VA6 The bag screen grows | todo | a grid with icons, the stack follows the pointer, tooltips, a container panel beside the bag, drop outside |
| VA7 Settings | todo | a runtime, persisted `GameSettings` (render distance, sensitivity, FOV, volumes, view bob, FPS) and a panel for it |
| VA8 Worlds and the title | todo | `WorldSaves` keeps metadata (name, seed from text, mode, created, played, rename); a world list and a title with host / join (VAD4) |
| VA9 Weather | todo | clear / rain / storm / snow on `SkySpec` by biome, particles in `voxel_scene`, the sky and fog darkened, lightning and thunder |
| VA10 Dimensions and portals | todo | `WorldGenSpec` per dimension, `GameWorld.switchDimension`, the save and net carry the dimension, a `PortalSpec` |
| VA11 Richer worldgen | todo | weighted trees per biome, plant clusters, layers by depth and height, a stock structure library on `StructureSite` |
| VA12 Signals finish | todo | `SignalSpec.pistons` and `poweredRails` (the engine has both) |
| VA13 Creatures grow | todo | `MobSpec`: taming, pets (fight, heel), mounts, level scaling, XP, burns by day, splits, persistence, an effect on hit, cave spawns and biome weights; mobs saved; `Drop` becomes a `LootTable` |
| VA14 Combat feel | todo | crits, hit-stop, flash, stagger, camera shake, a death that fades |
| VA15 Vehicles and fishing | todo | a boat, a minecart on `RailGraph`, a fishing line on a `LootTable` |
| VA16 Net catches up | todo | block prediction with ack and rollback, drops replicated, container sessions, time and weather sync, vehicles |
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

## Out of scope

- The app's content (§Stays the app's) and its probes as probes.
- Key rebinding UI, chat, the full map (VA4 says why it waits).
- A new package (rule 4): weather particles live in `voxel_scene`, which already depends
  on `flutter_scene`; nothing here brings an optional heavy dependency.
