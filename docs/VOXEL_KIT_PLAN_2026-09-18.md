# Voxel Kit Plan — from two engine packages to a Bonfire-style game kit

> **The executable plan that follows `VOXEL_PACKAGES_PLAN_2026-09-14.md`.** Written 2026-09-18.
> Stable IDs (`VK<phase>.<step>`) — reference them in commits.
>
> **The goal, in the developer's words:** make a Minecraft clone as easy to start as a
> [Bonfire](https://pub.dev/packages/bonfire) game — a developer declares blocks, mobs, rules and
> world generation in a few lines and gets a playable world.
>
> **Same ground rules as the VP plan.** Everything stays on branch `poc_cubeworld`, packages at
> `0.0.0`, `publish_to: none`, no per-package changelog until the fresh-repo `0.0.1` export
> (publishing is paused by the developer since 2026-09-15). **The POC keeps working at every
> commit:** a file moves into a package and the POC imports it from there in the same commit;
> tests, parity hashes and probe logs stay as they were.

## Progress

| Phase | State | Gate |
|:---|:---|:---|
| VK1 Finish the moves into `voxel_core` / `voxel_scene` | **done** 2026-09-18 (VK1.1–VK1.6); probe logs not rerun (see log) | every engine-generic file left in `lib/` that needs no new API has moved |
| VK2 `voxel_worldgen` | **done** 2026-09-18 (VK2.1–VK2.4) | the POC's `TerrainGenerator` is written on the package; parity hashes unchanged |
| VK3 `voxel_content` | **done** 2026-09-18 (VK3.1, VK3.3; VK3.2's POC half deferred, see log) | `Blocks` / `Items` / `Recipes` / `Inventory` / `LootTables` / `StatusEffects` are rows fed to package registries |
| VK4 `voxel_game` — the kit | **done** 2026-09-18 (VK4.1–VK4.11) | `example/` is a playable Minecraft-like in under 150 lines of game code |
| VK5 The POC on the kit | **done** 2026-09-18 (VK5.1–VK5.5; the POC's own geometry, hand and loop stay, see log) | the POC's player, mobs and loop run on `voxel_game`; probes unchanged |
| VK6 `voxel_audio` | **done** 2026-09-18 (VK6.1–VK6.4; the POC's `Sfx` on it) | the kit plays procedural sound effects for steps, digging, placing, hits and hurts with no audio files; music by context |
| VK7 `voxel_signals` | **done** 2026-09-18 (VK7.1–VK7.3, plus VK7.4 `SignalSpec` in the kit) | levers, wires, lamps, doors and rails as declared block roles, the POC's circuits and rails written on it |
| VK8 `voxel_net` | **done** 2026-09-18 (`21500e4a`: transport, host / join in the kit; drops stay local, mob loot on the host; never run with two real apps) | two kit games share a world over TCP: block edits, the player, mobs and drops replicated from a host |

---

## The package map

```
voxel_core       pure Dart   grid, mesher, streaming, physics, rays          (exists)
                              + reach, pathfinder, liquid flow, voxel models   (VK1)
voxel_scene      flutter_scene  chunk view, terrain material, mirrored camera (exists)
                              + outline, model meshes, rig parts, scene bodies (VK1)
voxel_worldgen   pure Dart   noise, terrain recipes, biomes, caves, ores,
                             trees, structures → a ChunkGenerator             (VK2)
voxel_content    pure Dart   block / item registries by string id, tags,
                             variants, recipes, inventory, loot, effects      (VK3)
voxel_game       Flutter     the kit: VoxelGame widget, loop, input, player
                             controller, cameras, mobs, spawns, drops         (VK4)
```

Dependencies only point down: `voxel_game` → everything; `voxel_worldgen` and `voxel_content`
→ `voxel_core`; `voxel_scene` → `voxel_core`. No package imports `package:cubeworld_poc`.

> **Superseded on 2026-09-19 by `VOXEL_CONSOLIDATION_PLAN_2026-09-19.md`.** The package names in
> this plan are the ones it was written against. The five pure-Dart packages are now one
> package, `voxel_engine`, with a library per subject, and `voxel_audio` is `sound_recipes`.
> The code and the phases are unchanged; only where each piece lives moved.

Out of scope here, named so nothing drifts into the kit by accident: `voxel_audio` (the SoLoud
synth bank and the music crossfader), `voxel_net` (transport, block prediction, a replicated
entity channel) and `voxel_signals` (circuits, rails). They follow once VK4 has an entity model
to replicate and to wire.

## The API the kit ships (VK4, `packages/voxel_game/example/lib/main.dart`)

A whole game is one `const` declaration and one call. This is an excerpt of the example; the
full file is about 80 lines.

```dart
void main() => runVoxelGame(game);

const game = VoxelGameSpec(
  blocks: [
    BlockType('stone', color: 0x7F7F84, hardness: 1.5, tool: 'pickaxe', tier: 1, drop: 'cobblestone'),
    BlockType('grass', color: 0x5C9E3A, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
    BlockType('torch', color: 0xFFD070, shape: BlockShape.torch, solid: false, hardness: 0, light: 14),
    BlockType.liquid('water', color: 0x3366CC),
    // ...
  ],
  items: [ItemType('wooden_pickaxe', color: 0xB08850, tool: 'pickaxe', tier: 1, stack: 1, durability: 60)],
  recipes: [Recipe('planks', 4, {'log': 1})],
  world: WorldGenSpec(
    biomes: [
      Biome('desert', top: 'sand', climate: Climate.hotDry),
      Biome('plains', top: 'grass', under: 'dirt',
          trees: [TreeSpec.oak(log: 'log', leaves: 'leaves')], treeChance: 12),
    ],
    ores: [Ore('coal_ore', share: 0.11)],
    structures: [StructureSpec('tower', build: tower, biomes: ['plains'], radius: 3)],
  ),
  player: PlayerSpec(startingItems: {'wooden_pickaxe': 1}),
  mobs: [
    MobSpec('zombie', hp: 20, rig: Rig.humanoid(skin: 0x5E9A5A, armsForward: true, redEyes: true),
        brain: [MeleeAttack(damage: 3), Hunt(range: 18), Wander()], spawn: SpawnRule.dark()),
    MobSpec('sheep', hp: 8, rig: Rig.quadruped(body: 0xEEEEEE),
        brain: [FleeWhenHurt(), LookAtPlayer(), Wander()], drops: [Drop('wool', 1, 2)],
        spawn: SpawnRule.daylight(biomes: ['plains'])),
  ],
);

void tower(StructureSite s) {
  s.level(-2, -2, 2, 2, 'cobblestone');
  s.fill(-2, 0, -2, 2, 7 + s.roll(1) % 4, 2, 'cobblestone', hollow: true);
}
```

What makes this possible, and what each phase owes it:

- **Blocks by string id.** `voxel_content` numbers them in declaration order (air is 0) and
  projects the `VoxelBlockTable` the engine reads. The number is the save contract, so the
  registry is append-only by rule and says so in its docs.
- **Declarative world generation.** `WorldGenSpec` is plain data plus pure callbacks, so it
  crosses `Isolate.spawn` to the worker pool (a closure is sendable when it captures nothing
  unsendable — the VP1.5 finding). It builds a `ChunkGenerator`.
- **Behaviour as a list, not flags.** The POC's `Mob` is an FSM steered by eleven booleans on
  `SpeciesDef` (`hostile`, `ranged`, `explodes`, `hops`, `flying`, …). The kit makes each one a
  behaviour (`Hostile`, `MeleeAttack`, `RangedAttack`, `Explode`, `Wander`, `FleeWhenHurt`,
  `FollowOwner`, `Rideable`) and each gait a locomotion (`Walker`, `Hopper`, `Flier`). A game
  adds its own by implementing the same interface — the Bonfire move (`SimpleEnemy` +
  mixins), without Bonfire's inheritance tree.
- **Escape hatches on every level.** `VoxelGame` takes a spec *or* the parts; every system is
  replaceable (`systems:`); hooks (`onBlockBroken`, `onMobKilled`, `onTick`) reach game code
  without subclassing; the HUD is a Flutter widget slot.

---

## VK1 — finish the moves

The two audits of 2026-09-18 read every file left in `lib/` (70 files, 21k lines). What can
move now, without an API that does not exist yet:

- **VK1.1** `SelectionOutline` → `voxel_scene`. `GodotCamera` is deleted and its seven importers
  call `MirroredCamera` (it only forwarded two statics).
- **VK1.2** `Reach` → `voxel_core/physics/` (it imports only `voxel_core` today).
- **VK1.3** `Pathfinder` → `voxel_core/navigation/`, over `VoxelQuery` and a `PathCosts` policy
  (`avoid(id)`, `costOf(feet, below)`, `isFloor(id)`). The POC supplies lava, fences and the
  block speed as its policy.
- **VK1.4** The model half of `VoxelMeshBuilder`: a pure `VoxelModel` (voxel map, `box`,
  `mirrorX`) and the angle helpers (`eulerYXZ`, `lerpAngle`, `lerpd`) → `voxel_core/model/`;
  `build`, `meshNode`, the shared material and `refreshMeshMaterials` → `voxel_scene`. The item
  shape catalogue stays in the POC.
- **VK1.5** `Part` (the rig pivot) and a generic `SceneBody` (node, `syncNode`, `removed`, world
  typed as `VoxelQuery`) → `voxel_scene`. The POC's `SceneBody` keeps `inLava` and the facade
  type as a subclass.
- **VK1.6** Liquid flow → `voxel_core/liquids/` as `LiquidFlow`: it reads liquid kinds from the
  `VoxelBlockTable` and takes, per kind, a flowing id, a period and a reach, plus a contact rule
  (the POC's lava + water → obsidian / cobblestone). The three string compares in
  `voxel_world.dart` leave.

**Gate:** analyze clean; the three test suites green; parity hashes unchanged; probe logs
unchanged (`tool/probe_baseline.sh --check`) once at the end of the phase.

**VK1 log:**

| Step | Commit | Notes |
|:---|:---|:---|
| VK1.1 `SelectionOutline` | `63d3bb67` | the stick layout became a pure static (`stickTransforms`) so it is tested without a GPU; colour is a parameter. The POC's duplicate constant test left for the package's |
| VK1.2 `Reach` | `a2dacd9b` | moved as is |
| VK1.3 `Pathfinder` | `b4527c85` | `PathCosts(avoid, liquidCost, floorCost)`; the POC passes `Blocks.pathCosts`. Below y 0 counts as solid, as `VoxelWorld.isSolid` did |
| VK1.4 voxel models | `4db2dac9` | `VoxelModel` (box, mirrorX, arrays) + `eulerYXZ` / `lerpAngle` / `lerpd` in core; `VoxelModelMesh` + `refreshMeshMaterials` in scene. `ItemShape` and the item catalogue stay (content) |
| VK1.5 `RigPart`, `NodeBody` | `897ba02c` | the POC's `Part` renamed `RigPart` on the way (a package export needs a specific name) |
| VK1.6 `LiquidFlow` | `45ba4ff3` | `VoxelEditor` (a `VoxelQuery` that can `setBlock`) is new in core; `VoxelWorld` implements it. The lava + water rule is the POC's `LiquidContact` |

Checks after every step: analyze clean, the three suites green, parity hashes unchanged. The probe
logs were **not** rerun: they need the app window in front for minutes, and every VK1 step moved
code without changing it (the stage tests that cover each moved piece — stage 22 flow, stage 31 and
38 paths, stage 35 outline, stage 40 reach — stayed green). Run `tool/probe_baseline.sh --check`
when the machine is attended.

## VK2 — `voxel_worldgen`

A pure-Dart package. The POC's 1,667-line `TerrainGenerator` becomes content written on it.

- **VK2.1** Scaffold + noise. `FastNoiseLite` is copied from `flutter_scene` 0.23.0
  (`lib/src/noise/fast_noise_lite.dart`, MIT, self-contained by its own header) with its
  licence notice; the POC's generator imports it from the package. Parity hashes prove the copy.
- **VK2.2** The machinery, each piece moved out of the generator and called back by it:
  `ChunkWriter` (`put`, `get`, `levelColumn`, world-space and clipped to one chunk),
  `ScatterGrid` (one feature per N×N patch with an inset), `TreeCanvas` (a tree drawn in world
  space, kept to what a flood fill from the stump reaches, printed clipped — the piece that
  makes trees agree across chunk borders), `StructureGrid` (a region grid with its own hash,
  neighbour lookup and a clearance against another grid), `OreTable` (depth bands over a vein
  hash) and `CaveCarver` (cheese noise, caverns, an entrance threshold).
- **VK2.3** The declarative layer: `WorldGenSpec` (`seaLevel`, `terrain`, `biomes`, `ores`,
  `caves`, `structures`, `dimensions`), `TerrainRecipe` (the continental / hills / ridge / river
  height as parameters), `Biome` with a `Climate` window (temperature, humidity, altitude) and
  `TreeSpec` presets (oak, spruce, palm, …). `WorldGenSpec.build(blocks)` returns a
  `ChunkGenerator` plus `surfaceHeight` / `biomeAt` / `structuresNear` queries.
- **VK2.4** An example: the hills of `voxel_scene/example` rewritten as a 30-line spec.

**Gate:** parity hashes unchanged through VK2.1–VK2.2 (the POC's world is byte-identical); the
POC's generator imports no noise and writes no chunk array directly.

**VK2 log:**

| Step | Commit | Notes |
|:---|:---|:---|
| VK2.1 scaffold + noise | `5d386034` | FastNoiseLite copied byte for byte (a `diff` against the pub cache proved it) with upstream's 23 pinned-value tests, less curl and baking |
| VK2.2 machinery | `14e8e541` | `worldHash`, `ChunkWriter`, `ScatterGrid`, `StructureGrid`, `OreTable`, `CaveCarver`, `TreeCanvas`, `Trees`. The POC's generator 1,667 → 1,292 lines. **Proof beyond the parity test:** a scratch test hashed 1,832 samples (11 x 11 chunks around three centres, three seeds, both dimensions, the playground, structure lists, heights, biomes) before and after — identical |
| VK2.3 `WorldGenSpec` | `3f717dab` | the declarative layer. **Deviation:** `Biome.ice` is a block name, not a flag, so no block is named by the engine. The POC's generator is *not* rewritten as a spec: its ten structure builders, underworld and plaza are content, and a byte-identical rewrite would buy nothing. The spec is proven by its tests and the example instead |
| VK2.4 example | `d3672f22` | an ASCII map of a four-biome world with towers; 25 chunks on 11 isolates in 116 ms |

## VK3 — `voxel_content`

- **VK3.1** `BlockType` + `BlockRegistry`: string id, colour, shape, solid, opaque, light,
  hardness, tool, tier, drop, speed, **tags** (replacing id-substring tests such as `_flow`,
  `piston_`, `powered_rail_`) and **variant groups** (orientations, on / off, open / closed).
  It projects `VoxelBlockTable`. The POC's 128 rows become `BlockType` rows in the same order;
  `Blocks`' static API forwards, so its 35 importers do not change in this step.
- **VK3.2** `ItemType` + `ItemRegistry` (every block is an item unless a variant folds it),
  `mineTime`, tool tiers as data.
- **VK3.3** `Inventory` (slot count and hotbar size as parameters), `Recipe` / `Crafting`
  (shapeless, per station), `LootTable` (entries, `roll`, a positional seed), `StatusEffects`
  with an effect registry whose stat modifiers are data.

**Gate:** the POC's block / item / recipe / loot tables are rows; parity hashes unchanged; save
round-trip tests (stage 24) unchanged.

## VK4 — `voxel_game`, the kit

- **VK4.1** Scaffold: `VoxelGame` widget and `runVoxelGame`; the fixed 1/60 s step loop with at
  most four catch-up steps; a `GameSystem` list replacing the hard-wired tick order; the world
  facade (streamer + worker pool + chunk view + liquid flow) built from the spec.
- **VK4.2** `InputMap<A>`: the POC's `GameInput` made generic over the action type (keys,
  mouse buttons, gamepad buttons and sticks, pointer lock with a drag fallback). Default
  bindings for a stock `VoxelAction` enum.
- **VK4.3** `CharacterController` over `VoxelBody`: walk / sprint / sneak / swim / wade, the
  auto-step with the half-step hop, the water exit, fall damage, ladders as a climb rule.
  The player and the kit's `Walker` share it (the POC has it twice, player and mob).
- **VK4.4** Cameras: first person with the hand view, third person with the orbit and its
  clearance sweep, view bob and shake. Aim: ray + nearest body + the outline; mine and place
  driven by `voxel_content` hardness and tools.
- **VK4.5** Entities and mobs: `Target` (anything that can be hurt), `MobSpec`, the behaviour
  and locomotion interfaces with the stock set named above, the five stock rigs (humanoid,
  quadruped, blob, spider, bird) built from `Part`s, hit feel (knockback, hit-stop, flash,
  topple), `SpawnRule`s (ring sampling, light gate, biome filter, cap and despawn radius),
  `Pickup` drops and `ProjectileSpec`.
- **VK4.6** Environment: the day / night sky, sun steps (the VP3.1 finding), fog tied to the
  render distance, underwater tint — `DayNightSky` in `voxel_scene`, driven by the kit.
- **VK4.7** The example: the spec above, playable, in `voxel_game/example/`.

**Gate:** the example runs on macOS and is under 150 lines of game code; every stock behaviour
has a headless test (a mob, a flat world, N ticks, an assertion on where it went).

**VK3 log:**

| Step | Commit | Notes |
|:---|:---|:---|
| VK3.1 package + blocks | `135870b4` | the whole package landed here (blocks, items, mining, inventory, recipes, loot, effects, 12 tests). The POC keeps its 128 `BlockDef` rows and its `ToolType` enum and projects them once into `Blocks.registry`; numbering, the engine table, liquid kinds, drops, replaceable, flowing forms and path costs come from the package. Parity and the scratch wide check unchanged |
| VK3.2 items | — | **Deferred for the POC.** Its `ItemDef` carries an `int` block index and a `ToolType`, where `ItemType` carries a block name and an open tool string; a subclass cannot retype the fields, so adopting it means renaming ~70 call sites. The kit uses `ItemType` and `MiningRules` directly. **Found:** the POC's `mineTime` gives a tool-less item with a tier the tier's speed on a tool-less block; `MiningRules` does not, so the POC keeps its own |
| VK3.3 inventory, recipes, loot, effects | `08a234c4` | `Inventory` extends the package's; `Recipes` is a `RecipeBook`; `LootTables` rolls `LootTable`; `StatusEffects` extends the package's, and its four stat hooks became `StatModifier` data. Every caller kept its names |

**VK4 log (`fa394cda`, one commit — the pieces reference each other):** 1,900 lines, 10 headless tests
that play the game through `InputMap` on a flat world. Design decisions made on the way:

- **Behaviours are Minecraft's goals, not an FSM.** Each declares the body slots it needs (move,
  look, attack) and a priority. A running goal is pre-empted only by a lower number on a slot it
  holds, so a zombie chases (`Hunt`, move) and bites (`MeleeAttack`, attack) at once. A creeper's
  `Explode` takes the legs from `Hunt` without losing the target: `Hunt.stop` forgets the target
  only when it is really lost (a test caught that).
- **Behaviours are `const` and shared by every mob of a spec**, so they hold no state. Per-mob
  state lives in `Mob.memory(behavior, create)`, and timers live in `Mob.cooldown`.
- **The fall height is the highest point since the feet last had footing**, not the POC's "rising
  only" rule, which missed a body that was placed in the air.
- **`Spawner` became `MobSpawner`** (flutter_scene exports a particle `Spawner`).
- **Headless is a first-class mode** (`VoxelGame.startHeadless`, `GameWorld.headless`): jobs are
  answered on the calling isolate, no scene, no rigs. Every behaviour is tested there.
- **Seen running:** the example built for macOS, captured from inside the app with a scratch
  probe (`RepaintBoundary`, the app's sandbox temp). 169 chunks in 1.3 s, and in third person the
  player among a sheep and a slime.

**VK4.8–VK4.11 log:**

| Step | Commit | Notes |
|:---|:---|:---|
| VK4.8 inventory and crafting | `93e3c730` | E opens the bag; using a block that a recipe names as its station opens that station (sneak places against it instead). The screen rebuilds on bag changes only, never per frame (the POC's credits-screen lesson: a per-frame rebuild swallows taps). Seen in the app |
| VK4.9 save and load | `93e3c730` | `WorldSaves`: `edits.bin` (`EditDeltaCodec`, magic `VXK1`) and `game.json`, written through a temporary file. A saved world keeps its own seed. Mobs are not saved: natural spawns come back by themselves, and nothing in the kit tames or names one yet |
| VK4.10 hand and crack | `da817dc9` | **Found:** a blended (`AlphaMode.blend`) primitive never reaches the screen in this flutter_scene build, and neither does a material edited after its mesh sits on a node. The POC's darkening crack box is built that way, so it has likely never shown; the POC's crack *lines* were already known invisible (`LineSegmentsGeometry`). The kit draws its crack from opaque cuboid sticks, as the outline is |
| VK4.11 hit feel | `da817dc9` | the player's red wash and eye jolt. A mob still only shakes when hit (a red flash needs a second material per rig, or a tint uniform) |

## VK6 — `voxel_audio`

The POC synthesizes every sound effect into WAV bytes at start-up (`lib/src/game/sfx.dart`, no audio
files) and crossfades music by context (`music.dart`), on `flutter_soloud`.

- **VK6.1** `SoundBank`: named recipes (`Sfx.tone`, noise bursts, envelopes) rendered to WAV and
  loaded into SoLoud once; `play(name, volumeDb, pitchJitter)`; a muted mode for tests.
- **VK6.2** A stock recipe set by material family (stone, wood, earth, plant, glass, metal, liquid):
  dig, place, step. Blocks name their family with a tag (`'sound:wood'`), defaulting by shape.
- **VK6.3** The kit plays them: steps by distance walked, dig ticks while mining, break, place,
  hit, hurt, a pickup pop; `VoxelGameSpec.sounds` to override or add.
- **VK6.4** `MusicDirector`: tracks chosen by a game-supplied context function, crossfaded.

## VK7 — `voxel_signals`

- **VK7.1** A signal network over a `VoxelEditor`: sources (lever, button, plate, a powered block),
  conductors with decay (wire), consumers with reactions (lamp, door, piston, TNT, powered rail),
  declared per block by role; flood-fill rebuild capped per tick, as the POC's `Circuits` does.
- **VK7.2** Auto-connecting blocks (the POC's `Rails`): a connection table per orientation variant.
- **VK7.3** The POC's circuits and rails on the package, stage 27 and 28 tests unchanged.

**VK6 log:** `bc22ad58` — the package (`renderWav`, `StockSounds`, `SoundBank`, `SilentSounds`,
`MusicDirector`, 4 tests) and the kit wiring (`SoundSpec`, families from a `sound:` tag or inferred,
distance attenuation, a headless test of what is heard). The example opened the audio device.
`588e4f49` — the POC's `Sfx` became a facade over `SoundBank` (its four own sounds as recipes, its
recorded footsteps as takes). The POC's `Music` stays (probe counters, its own tracks);
`MusicDirector` is the kit's.

**VK7 log:** `eca91d61` — `SignalNetwork` (the POC's algorithm step for step over declared roles),
stock reactions, `RailGraph`; 5 tests. `1702de7c` — the POC's `Circuits` and `Rails` on it, stage
23 / 27 / 28 tests unchanged. `0d79ffa2` — `SignalSpec` in the kit (levers, buttons, plates pressed
by any body, lamps, doors, explosives), a headless test, circuits in the example. Pistons and
powered rails are available as `SignalReactions` but not yet declarable in `SignalSpec`.

## VK8 — `voxel_net`

- **VK8.1** The transport (TCP, newline-delimited JSON), host-authoritative, the edit-delta hello.
- **VK8.2** Block edits with client prediction (the POC's `BlockPrediction`).
- **VK8.3** One replicated-entity channel (spawn, pose, free by net id), replacing the POC's six
  copies of that pattern (boats, carts, drops, bobbers, mobs, players).
- **VK8.4** The kit hosts and joins: `runVoxelGame(spec, host: true)` / `join: address`.

## VK5 — the POC on the kit

The POC's `Player` (2,473 lines) and `Mob` (1,543 lines) delegate piece by piece: locomotion
first (VK4.3's controller), then the cameras, then rigs, then brains; the POC's species table
becomes `MobSpec`s with its own behaviours for what is Dawnforge's (traders, affixes, bosses).
Each step keeps `--strike`, `--move-probe`, `--anim-probe` and `--outline-probe` printing what
they printed.

- **VK5.1** The player's locomotion on `CharacterMotor` — done.
- **VK5.2** The mob's locomotion on `CharacterMotor` — done.
- **VK5.3** The cameras on `ViewCamera` / `FirstPersonView` — done (the camera; the hand stays).
- **VK5.4** The rigs on `Rig.*` — done (the motion; the geometry and the hand stay the POC's).
- **VK5.5** The brains: the species table as `MobSpec`s, Dawnforge's own behaviours — done (goals on the kit's selector).

Log. VK5.1: `CharacterMotor` gained `jump()`, `resetFall()`, `canGlide`, a `glide` step (a
capped fall that counts as footing), an `accel` override (a dash, a glide) and `fly()` (creative
flight), with a kit test. The POC's `Player` drops its own gravity, swim, hop, bank launch, fall
height and knockback window for the motor; a wall climb is a ladder to it. The glide is now
decided on the velocity before the step's gravity (one tick later at a jump's peak at most).
Probes built from HEAD and from the change: `--stage31`, `--stage32`, `--radius=8` and
`--move-probe` print the same. One run printed `water exit ... after 74 ticks` against 76; four
reruns of both builds printed 76, because the probe resumes on a microtask. `docs/baseline/` is
stale (the terrain moved after VP0.2), so each check builds HEAD beside the change.

Log. VK5.2: `CharacterMotor.step` gained `jumpSpeed` (a jump off the floor at another launch,
the mount's 9 m/s leap that clears a fence) and `leaveWater` (a creature launches over a bank
without a jump key; the kit's `Mob` passes it too), with a kit test. The POC's `Mob` walks,
hops (accel 3, a 7 m/s leap, no knockback window) and carries its rider on the motor, tuned to
its own numbers (step jump 8, accel 8, stroke 20 up to 2); a flier keeps its own flight, as in
the kit. Probes against a HEAD build: `--stage31`, `--radius=8` and `--outline-probe` print the
same; `--anim-probe` moves between runs of one build (frame-timed), HEAD's included. Two lines
changed on purpose: `stage32 knockback` 1.62 m to 1.69 m (the motor counts the knockback window
down after the move, one tick longer), and `move mount water` 68/59 ticks over/swimming to
64/55 (the stroke replaces the liquid's gravity instead of fighting it, and the launch over the
bank carries), every expectation on the line still met. One `--anim-probe` run stopped after
its sheep line; two reruns of that build finished.

Log. VK5.3: the kit's camera splits into two engine-neutral pieces, `ShoulderOrbit` (the
third-person seat whose shoulder and rise grow with the distance, the eye's box swept along it
with the jolt and the sway, in at once and out gently) and `ViewBob` (Minecraft's bob: the drop,
the sway, a breath of roll and nose-up, cycled by distance, with cadence, gait and lean knobs for
a mount's trot); `ViewCamera` is rebuilt on them and gains the roll and the nose-up, with kit
tests. The POC's `Player` drops its own sweep, orbit and bob for them, tuned to its numbers; its
shake (the stage 32 jolt from the game's random), `blocksCamera` and the trot's constants stay
Dawnforge's. The hand stays the POC's `HandView`: it is built from the POC's model and answers
the bob's phase, where the kit's `FirstPersonView` is a plainer arm, so moving it is a rig
concern (VK5.4), not a camera one. Probes against a HEAD build: `--stage31`, `--stage32`,
`--radius=8` and `--outline-probe` print the same; `anim camera` prints the same peaks (0.0500,
0.1698, 0.2210); `move mount steps`' largest one-tick rise moves 0.126..0.158 between runs of
either build.

Log. VK5.4: the kit's `RigInstance` splits its animation into `RigAnimator`, which poses any
named parts as a `RigKind` (legs on their diagonals or a spider's tetrapod, wings beating and
folding, the tail, the arms' swing and chop, the quadruped's trot lift, the bird's head throw,
the blob's squash and splat), tuned by a `RigMotion` (gait rate, wingbeat, fold, swing time, the
splat, and the nod and peck a swing adds). `RigInstance` builds the kit's geometry and hands
its parts over. The POC's `Mob` keeps its own geometry per species (its models are Dawnforge's
look, far richer than the stock plans), its hit-stop, breath, shake and topple, and poses on the
animator with its own numbers (fold -0.95 at span 0.45, the splat 0.22 over 0.18 s, no nod and
no peck), a species' `body` mapped to a `RigKind`. The first-person `HandView` stays: it is built
from the POC's player model. Probes against a HEAD build: `--stage31`, `--stage32`,
`--radius=8` and `--outline-probe` print the same, and so do `anim wings` (sweep and fold),
`anim blob` and the chicken's legs; the other `anim` values and `move`'s water ticks move as they
do between runs of one build.

Log. VK5.5: the kit's brain splits out of its `Mob` into `Goal<M, G>` and `GoalSelector<M, G>`
(slots, priority, a goal taking the slots of what it outranks), generic over any creature and
game; the kit's `Behavior` is now a `Goal<Mob, VoxelGame>` with the same API, and a kit test runs
a selector over a creature that is not a `Mob`. The POC's `Mob` drops its state machine: each
state is a Dawnforge goal (`Roam`, `Chase`, `Kite`, `Strike`, `Fuse`, `Flee`, and a pet's
`PetFight`, `Heel` and `MountWait`) in `mob_brain.dart`, and `brainOf` reads a species row as
its goal list, as a kit `MobSpec` declares its `brain`; a tamed creature thinks with its owner's
goals from the moment `tamed` is set. `state` is now read off the goal holding the legs. The
rows stay `SpeciesDef`s, not kit `MobSpec`s: the POC's `Mob` is not the kit's, and a row carries
Dawnforge's own look, XP, affixes, taming and trades. Stun, riding, puppets and the probe's walk
stay outside the brain, as they were outside the state machine. A transition now happens in the
tick its condition holds instead of the next one (a zombie in reach strikes one tick sooner); a
pet hit by its owner now reads `idle` where the old state machine left a `chase` or `flee` it
never reset (nothing a pet does read it). Probes against a HEAD build: `--stage31`, `--stage32`, `--stage23`,
`--stage29`, `--radius=8` and `--outline-probe` print the same; `--stage18`, `--stage20`,
`--stage26`, `--anim-probe` and `move`'s water ticks move as they do between runs of one build
(the game's random is unseeded). One run of six printed a gallop peak of 0.2206 against 0.2210;
the ridden horse never consults the brain.

---

## Verification — the same checks after every step

From `poc_cubeworld/`: `flutter analyze` (zero errors; zero issues in `packages/`);
`flutter test`; `dart test` in each pure package; `flutter test` in each Flutter package;
`test/voxel_parity_test.dart` unchanged. `tool/probe_baseline.sh --check` at every phase gate
(it needs the window in front, so it is run when the machine is attended).

## Decision register

| ID | Question | Decision | Why |
|:---|:---|:---|:---|
| `VKD1` | One big kit package, or several? | **Five packages, the kit on top** | A game that only wants the world (a builder, a viewer) takes `voxel_worldgen` + `voxel_scene` without player or mobs; the pure packages stay testable with `dart test` |
| `VKD2` | Bonfire-style inheritance (`SimpleEnemy` → subclasses) or composition? | **Composition: behaviour and locomotion lists** | The POC's `Mob` shows where inheritance plus flags ends: one 1,543-line class. A list is declared in one line and extended by one class |
| `VKD3` | Blocks addressed by string or by number? | **String at the API, number in the engine** | A game author writes `'stone'`; the engine keeps its byte grid. The registry is the only place the two meet |
| `VKD4` | Noise: depend on `flutter_scene` or copy? | **Copy into `voxel_worldgen`** | `flutter_scene` pulls Flutter into a pure package; the file is MIT and self-contained by design |
| `VKD5` | Does the kit replace the POC's code before it exists? | **No — the kit grows first (VK4), the POC moves onto it after (VK5)** | Rewriting `Player`/`Mob` onto an API still being designed would move the target twice |
