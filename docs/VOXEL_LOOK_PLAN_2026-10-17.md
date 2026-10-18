# The app's look plan (AL) — 2026-10-17

**Question.** VA-Z (2026-10-04) moved `examples/voxel_game_minecraft` onto the kit and
left four looks of the old app behind (VLD4): the bow's and the staff's right-click fan and
arc, the abilities' particles, coloured damage numbers, and the dash's pose. VLD4 called
them the app's look, not fields a second game would want. But none of the four can be built
in the app as the kit stands. A use with a bow in hand does nothing. A number over a
creature is white or a crit's yellow. The kit has no flash to colour. A rig knows only how
to sit and how to glide. What does the kit take so the app can have its looks back, and in
what order?

**Answer, in one line.** Four small, generic hooks in the kit, each its own commit and each
a row or a call a second game would also use: `VoxelGameSpec.itemUses`, `VoxelGame.pulse`,
`VoxelGameSpec.hitColors` (carried to a client), and declared `RigPose`s. Then the app puts
its four looks back on them, at the old app's numbers.

What the old app did is read from git, at `837d670^` (the last tree before VA-Zm2 deleted
the copies): `lib/src/player/player.dart`, `lib/src/game/game.dart`,
`lib/src/entities/player_model.dart`, `lib/src/entities/projectile.dart`, all under
`examples/voxel_game_minecraft/`. Every `file:line` below is from 2026-10-17; re-check it
before a step starts. The owner settled ALD1–ALD5 on 2026-10-17 (§Decisions).

---

## Progress

| Step | State | Gate |
|:---|:---|:---|
| AL0 This plan, and the owner's answers to §Decisions | **done** 2026-10-17: every recommendation taken (ALD1–ALD5) | the owner answers ALD1–ALD5 |
| AL1 `VoxelGameSpec.itemUses` (kit) | **ready** | the kit's suites green; `uses_test.dart` covers the order and the press |
| AL2 `VoxelGame.pulse` (kit) | **ready** | the suites green; `pulse_effects_test.dart`; a pulse seen on the Mac through the kit's example |
| AL3 `VoxelGameSpec.hitColors`, carried to a client (kit) | **ready** | the suites green; a client's number takes the host's hit's colour in `net_game_test.dart` |
| AL4 Declared poses: `RigPose`, `PlayerEntity.holdPose` (kit) | **ready** | the suites green; a peer's held pose reaches its `RemotePlayer` in `net_game_test.dart` |
| AL5 The fan and the arc (app) | **ready** after AL1 and AL2 | the app's suite green; a test fires each and counts the shots and the cost |
| AL6 The abilities' pulses and coloured hits (app) | **ready** after AL2 and AL3 | the app's suite green; a test reads a whirlwind's number colour and pulse |
| AL7 The dash's pose (app) | **ready** after AL4 | the app's suite green; a test reads the pose held through a dodge |
| AL8 Seen on the Mac | after AL5–AL7 | the four looks in a throwaway capture (the app's rule A4); the owner plays it when they choose |

Effort per step: AL1 `medium` (one map, one call site, a check), AL2 `high` (a new
`voxel_scene` class across two packages, a transparent draw), AL3 `high` (a field on the
mob's state row, two sides of the net), AL4 `high` (a pose layer through the animator and
the net), AL5–AL7 `medium` (rows and calls on hooks that exist by then), AL8 `medium`.

**Release.** AL1–AL4 add to the kit's API without breaking it. Those that land before VD6
starts ride `0.5.0-dev`, each with its `## Unreleased` CHANGELOG line, which VD6 maps. VD6
does not wait for them (VDD9, `docs/VOXEL_DEPS_PLAN_2026-10-06.md`).

---

## What exists (read before AL1)

### The use button with a launcher in hand

`packages/voxel_game/lib/src/player/player_entity.dart:647` calls `_use(pressed:)` on a
press, then every 0.2 s while use is held. `_use` (`:1307`) offers the use, in order, to the
aimed creature, the aimed vehicle, the game's `blockUses`, a bed, a lever, a store, a
station and a door. Then it takes the held item (`final item = _heldType; if (item == null)
return;`, near `:1370`) and tries its own uses: a portal's lighter, a bucket, a tool that
works a block, food, armour, a vehicle to put down, a block to place. A bow or a staff is
none of these, so a use with one in hand does nothing. The attack button fires a launcher
(`_attack`, `:1171` → `_shoot`, `:1258`).

`VoxelGameSpec.blockUses` / `mobUses` (`packages/voxel_game/lib/src/spec/voxel_game_spec.dart:212`,
`:216`; typedefs in `spec/use_handlers.dart`) are the pattern: a map keyed by name, called
once a press. `VoxelGame`'s constructor runs the spec's checks (`core/voxel_game.dart:94`,
`checkVehicles`; `:98`, `checkMusic`).

The old app (`player.dart:913–1025` at `837d670^`) on the use button:

| Held | What | Cost | Then |
|:---|:---|:---|:---|
| bow, longbow | **fan**: 3 arrows across 24°, each at 0.85 of a shot's damage | 3 arrows, 14 stamina ("Need 3 arrows", "Too tired to draw") | attack waits 0.7 s, use 1.4 s |
| staff, crystal staff | **arc**: 5 bolts across 50°, each at 0.9 | 18 mana less the Focus talent ("Not enough mana") | attack waits 0.6 s, use 1.1 s; a pulse `(1, 0.55, 0.2)` radius 1.0 at the muzzle |

The directions turn the look about the up axis (`_fanDirection`, `:921`: index `i` of
`count` at `(i / (count − 1) − 0.5) × spread`). The app's `_volley`
(`examples/voxel_game_minecraft/lib/src/classes/class_table.dart`, Volley) already does the
same turn through `game.shoot`. `game.shoot` (`core/voxel_game.dart:1394`) works on a
client too: `session?.fired(shot)`.

### Particles

The kit has `VoxelGame.debris` (`core/voxel_game.dart:925`), a `DebrisParticles`
(`packages/voxel_scene/lib/src/debris_particles.dart`): chips, one particle system, added to
the scene at `core/voxel_game.dart:298`. It has nothing like the old app's `spawnEffect`
(`game.dart:1552` at `837d670^`). That was a translucent sphere: an `UnlitMaterial` in
`AlphaMode.blend` over `SphereGeometry(radius: 0.5)`, built by
`MirroredCamera.primitiveNode(..., castsShadows: false)`. Each frame (`game.dart:927`) it
took `t = age / 0.35` and `eased = 1 − (1 − t)³`, and drew at scale
`1 + (radius × 2 − 1) × eased` (so `radius` is the radius it reaches) and alpha
`0.55 × (1 − t)`. The kit already draws blended unlit material
(`voxel_scene/lib/src/voxel_chunk_view.dart:98`, `voxel_model_mesh.dart:38`) and spheres
(`voxel_game/lib/src/fishing/bobber.dart:164`).

The old pulses, by ability (`player.dart:1255–1415` at `837d670^`), as `0xRRGGBB`:

| Ability | Pulse | Radius | Where |
|:---|:---|:---|:---|
| Whirlwind | `0xFF9933` | 4.0 | the player's centre |
| Shield Bash | `0xFFE666` | 2.0 | 1.5 m ahead of the centre |
| Arrow Volley | `0x99E680` | 2.0 | centre |
| Volley | none | | |
| Fire Nova | `0xFF591A` | 6.0 | centre |
| Frost Nova | `0x80BFFF` | 5.0 | centre |
| Shadow Dash | `0x664DB3` | 2.0 | centre |
| Smoke Bomb | `0x4D4D59` | 4.0 | centre |
| (staff arc) | `0xFF8C33` | 1.0 | the muzzle |

### Damage numbers

`DamageNumbers` (`packages/voxel_game/lib/src/ui/damage_numbers.dart`) holds `(id, at,
amount, age, crit)` and has no colour. `DefaultHud` paints white, or `_critColor` for a
crit (`ui/default_hud.dart:668–690`). A number is added in two places:

- the authority, on a hit: `Mob.takeDamage` (`mobs/mob.dart:775`, `taken`, `crit:
  damage.crit`);
- a client, from a replica's health lost since its last state: `Mob.applyNetState`
  (`mobs/mob.dart:437–453`), fed by the host's `mobs` rows (`net/sessions.dart:1005–1020`,
  written; `:1650–1665`, read: `n s p yaw hp dead sh b o r`).

`Damage.source` (`entities/target.dart:27`) already names the hurt: `'melee'` by default, a
projectile's `spec.kind` (`entities/projectile.dart:384`: `'arrow'`, `'bolt'`),
`'explosion'`, `'burning'`, `'fall'`, `'lava'`, `'drowning'`, `'starving'`, an effect's id.
The app's abilities strike through `ClassSystem.strike`
(`examples/voxel_game_minecraft/lib/src/classes/class_system.dart:174`), which makes a
`Damage` with no source, so `'melee'`.

The old colours (`spawnDamageNumber` callers at `837d670^`), as `0xRRGGBB`:

| Source | Colour | Old site |
|:---|:---|:---|
| `melee` (a swing) | `0xFFF299` | `game.dart:1511` |
| `arrow` | `0xFFE680` | `projectile.dart:134` |
| `bolt` | `0xFF7326` (the bolt's own colour; the crystal bolt's kind is `bolt` too, so it shares it) | `projectile.dart:134` |
| `explosion` | `0xFF8033` | `game.dart:1697` |
| `burning` | `0xFF8C26` (the effect's colour, `effect_table.dart:8`) | `player.dart:1881` |
| `whirlwind` | `0xFF8033` | `player.dart:1273` |
| `shield_bash` | `0xFFE666` | `player.dart:1371` |
| `fire_nova` | `0xFF661A` | `player.dart:1308` |
| `frost_nova` | `0x80B3FF` | `player.dart:1397` |

A crit stays yellow over any colour, as the old (`game.dart:1548`) and the kit do.

### Poses

`RigInstance.animate` (`packages/voxel_game/lib/src/mobs/rig.dart:506`) passes `seated` and
`gliding` to `RigAnimator.pose` (`mobs/rig_animator.dart:132`), which sets each part's
`rx/ry/rz`. A humanoid's parts are `body`, `head`, `arm0`, `arm1`, `leg0`, `leg1`
(`rig.dart:293–309`). `RigInstance.place` (`rig.dart:541`) takes a `topple` about X for the
whole model. The player animates its rig at `player/player_entity.dart:1612–1642`, and a
peer at `net/remote_player.dart:226` (seated only). The pose row's extras are built in
`net/sessions.dart:307–316` (`s f nm op x`) and read at `:581–583` and `:1627–1629`.

The old dash (`player_model.dart:31–41, 282–299` at `837d670^`), held while the dodge ran
(`player.dart:686–691`, third person only):

| Part | Target | Note |
|:---|:---|:---|
| the whole body | lean `−0.45` rad about X | forward |
| `leg0` / `leg1` (old `legL` / `legR`) | `rx` `0.75` / `−0.6` | one forward, one back |
| `arm0` / `arm1` | `rx` `−1.35`; `rz` `−0.3` / `0.3` | behind the back, out from the torso |

Its weight went in and out as `lerp(w, target, dt × 20)`.

---

## Decisions

| ID | Decision | Why |
|:---|:---|:---|
| ALD1 | **`VoxelGameSpec.itemUses`, keyed by item id.** (Owner, 2026-10-17.) Called once a press of use, when nothing aimed took the use (after the door, before the held item's own uses: lighter, bucket, tool, food, armour, vehicle, block). An unknown id throws when the game is made. | It is `blockUses`' pattern for the held item. The right button stays the old app's, and the pad's and touch's use come with it (rule 13). An `ActionSpec` key would have lost the right button. |
| ALD2 | **`VoxelGameSpec.hitColors`: `Damage.source` → `0xRRGGBB`, and a client sees them.** (Owner.) A source not in it is white. A crit stays yellow. The host's `mobs` row carries the last hit's source since the row before, so a client's number is the host's colour. | One table, not a colour chosen at every blow (rule 7). Without the wire, every number on a client would be white. |
| ALD3 | **`VoxelGame.pulse(at, color, radius)`, local only.** (Owner.) A `PulseEffects` in `voxel_scene`: one sphere geometry, a pool of nodes, each with its own blended `UnlitMaterial`, at the old numbers (0.35 s, ease-out cubic, alpha 0.55 → 0). Headless, it keeps its state and draws nothing. | It sits beside `debris`, which is the kit's other flash. The old pulses were local; the hits they come with already reach every side. The app building nodes on `game.scene` would put render code back in the app, which VA-Z took out. |
| ALD4 | **Declared poses: `PlayerSpec.poses` of `RigPose`, held by `PlayerEntity.holdPose(name, seconds)`.** (Owner.) A `RigPose` gives target angles per part name and a lean of the whole body, blended in and out at its `rate`. The pose row carries the held pose's name, so a peer draws it. A name not in the spec throws. | A pose is a row (rule 7), not a branch per behaviour as `seated` and `gliding` are. A second game's cheer or bow is the same row. |
| ALD5 | **The app's numbers are the old app's**, as §What exists lists them. Where the kit's shot differs (the projectile's speed and size are its `ProjectileSpec`'s), the kit's stands. | VA-Z ported at the old numbers, and its tests pin them. |

Decided here, not asked: the dash's pose is held by the dodge and by Shadow Dash, each for
its shove's seconds (0.4 s, 0.17 s). The old held it only through the dodge, and Shadow Dash
had no pose. A dash with no pose is the gap this plan closes, and it costs one call.

---

## Steps

Each kit step is its own commit (`voxel_game:` or `voxel_scene, voxel_game:`) with its
CHANGELOG lines under `## Unreleased` and its tests. The kit's example
(`packages/voxel_game/example/lib/main.dart`) uses each new hook once, so the hook has a
witness outside the tests. That follows the app's "a gap in the kit is a kit commit first"
(`examples/voxel_game_minecraft/CLAUDE.md`). Each app step is
`examples/voxel_game_minecraft: … (ALn)`, with a `ROADMAP.md` §Session log entry. Run the
root suite (root `CLAUDE.md` workflow step 3) and the app's before each commit.

### AL1 · `VoxelGameSpec.itemUses` (kit)

Files: `packages/voxel_game/lib/src/spec/use_handlers.dart`, `spec/voxel_game_spec.dart`,
`player/player_entity.dart`, `core/voxel_game.dart`, `test/uses_test.dart`,
`example/lib/main.dart`, `CHANGELOG.md`, `README.md` (where `blockUses` is described).

- `typedef ItemUse = void Function(VoxelGame game, ItemType item);` beside `BlockUse`. Its
  doc says: once a press of use, with the held item's row, when nothing aimed took the use.
- `VoxelGameSpec.itemUses` (`Map<String, ItemUse>`, default `const {}`), in the constructor,
  `copyWith` and the field docs, next to `blockUses`.
- `VoxelGameSpec.checkItemUses(ItemRegistry<ItemType> items)` throws for an id that is not
  an item. Call it beside `checkVehicles` (`core/voxel_game.dart:94`).
- In `_use`, right after `final item = _heldType; if (item == null) return;`:
  `final use = _game.spec.itemUses[item.id]; if (use != null) { if (pressed) { _swingArm();
  use(_game, item); } return; }`. Held, it does not repeat (the 0.2 s re-entry is for
  placing).
- Tests in `uses_test.dart`: a held item's use runs once a press and not on the hold's
  repeats; an aimed station, door or `blockUses` block still takes the use first; it runs
  in place of placing (a block item with an item use places nothing); the spec with an
  unknown id throws at start.
- The example: one item use (e.g. a stick that tells the time through `game.notify`).
- **Gate:** the five suites green; the counts rise by the new tests only.

### AL2 · `VoxelGame.pulse` (kit)

Files: `packages/voxel_scene/lib/src/pulse_effects.dart` (new),
`packages/voxel_scene/lib/voxel_scene.dart` (export),
`packages/voxel_scene/test/pulse_effects_test.dart` (new),
`packages/voxel_scene/CHANGELOG.md`, `packages/voxel_game/lib/src/core/voxel_game.dart`,
`packages/voxel_game/CHANGELOG.md`, `packages/voxel_game/example/lib/main.dart`.

- `PulseEffects({int capacity = 16})`, shaped like `DebrisParticles`: `static const double
  seconds = 0.35`, `static const double alpha = 0.55`, `add(Vector3 at, int color, double
  radius)` (throws for a radius that is not above 0 or a colour outside `0..0xFFFFFF`; a
  full pool drops the oldest), `advance(double dt)`, `shown` (a record per live pulse:
  `at`, `color`, `radius`, `age`). Two pure statics carry the old numbers:
  `scaleAt(age, radius)` gives `1 + (radius × 2 − 1) × (1 − (1 − t)³)` for the unit-diameter
  sphere, and `alphaAt(age)` gives `alpha × (1 − t)`, with `t = (age / seconds).clamp(0, 1)`.
- `late final Node node`, built the first time it is asked for: `capacity` children, each
  `MirroredCamera.primitiveNode` of `SphereGeometry(radius: 0.5)` (one geometry, shared)
  with its own `UnlitMaterial` in `AlphaMode.blend`, shadows off. `advance` places, scales
  and fades the live ones and hides the rest (`visible = false`). Nothing is allocated per
  frame.
- `VoxelGame.pulses` (`final PulseEffects pulses = PulseEffects();`) beside `debris`, its
  node added to the scene beside `debris.node` (`core/voxel_game.dart:298`), advanced in
  `frame` (`:1038`) on the frame's clock as `damageNumbers` is. `VoxelGame.pulse(Vector3 at,
  int color, double radius)` calls `pulses.add`; its doc says local only (ALD3).
- Tests (`pulse_effects_test.dart`, no GPU): `scaleAt` at 0, at `seconds` and halfway;
  `alphaAt` falls to 0 at `seconds`; `advance` drops a pulse past `seconds`; a full pool
  drops the oldest; the throws. The node is not built in the test (no GPU), as
  `debris_particles_test.dart` does.
- The example: a pulse where a block breaks, or on a key the example already has.
- **Gate:** the suites green; `cd packages/voxel_game/example && flutter run -d macos`
  shows the pulse grow and fade over the world, unshadowed and see-through (root workflow
  step 4).

### AL3 · `VoxelGameSpec.hitColors`, carried to a client (kit)

Files: `packages/voxel_game/lib/src/spec/voxel_game_spec.dart`,
`ui/damage_numbers.dart`, `ui/default_hud.dart`, `mobs/mob.dart`, `net/sessions.dart`,
`test/damage_numbers_test.dart`, `test/default_hud_test.dart`, `test/net_game_test.dart`,
`CHANGELOG.md`, `README.md`.

- `VoxelGameSpec.hitColors` (`Map<String, int>`, `Damage.source` → `0xRRGGBB`, default
  `const {}`), in the constructor and `copyWith`. A check at start throws for a colour
  outside `0..0xFFFFFF`.
- `DamageNumber` gains `int? color` (null for the HUD's white). `DamageNumbers.add(at,
  amount, {crit, color})`.
- `Mob.takeDamage` (`mob.dart:775`) passes `color: _game.spec.hitColors[damage.source]`, and
  on the authority keeps the source as `lastHitSource` (a `String?`).
- The host's `mobs` row (`sessions.dart:1005`) writes `'hs': m.lastHitSource` when one is
  set since the last row, then clears it. The client reads it (`:1659`) into
  `applyNetState(..., hitSource:)`, whose number takes `hitColors[hitSource]`.
- `DefaultHud` (`default_hud.dart:681`) paints `n.crit ? _critColor : n.color == null ?
  Colors.white : Color(0xFF000000 | n.color!)`.
- Tests: a source in the table colours its number and one outside it stays white; a crit
  stays yellow; on a hosted session, a client's replica shows the host's hit's colour
  (`net_game_test.dart`); a row with no hit since the last carries no `hs`.
- The example: two entries (its melee and its arrow).
- **Gate:** the suites green; `default_hud_test.dart` paints a coloured number.

### AL4 · Declared poses: `RigPose`, `PlayerEntity.holdPose` (kit)

Files: `packages/voxel_game/lib/src/mobs/rig_pose.dart` (new), `mobs/rig_animator.dart`,
`mobs/rig.dart`, `player/player_spec.dart`, `player/player_entity.dart`,
`net/remote_player.dart`, `net/sessions.dart`, `lib/voxel_game.dart` (export),
`test/rig_model_test.dart` or a new `test/rig_pose_test.dart`, `test/net_game_test.dart`,
`example/lib/main.dart`, `CHANGELOG.md`, `README.md`.

- `RigPose({Map<String, ({double rx, double ry, double rz})> parts, double lean = 0.0,
  double rate = 20.0})`, const. A part's target replaces that part's animated angles,
  blended by the weight. `lean` tilts the whole model about X through `place`'s `topple`.
- `RigAnimator.pose(..., RigPose? held)` keeps a `heldWeight` that goes as
  `lerp(w, held == null ? 0 : 1, dt × rate)` (the last pose's rate while it fades out). It
  applies after the gait, the seat and the glide, as the old dash did after the walk.
  `RigInstance.animate` passes it through, and `place` adds `held.lean × heldWeight` to its
  topple.
- `PlayerSpec.poses` (`Map<String, RigPose>`, default `const {}`), in `copyWith`.
  `PlayerEntity.holdPose(String name, double seconds)` throws for a name not in
  `spec.poses`. It holds the pose that long (a new hold replaces the old one), and
  `heldPose` is the name or null.
- The pose row's extras gain `'ps': name` while one is held (`sessions.dart:307`). The
  `RemotePlayer` reads it and animates its rig with the peer's `PlayerSpec` pose
  (`playerWith`, as its rig already is). A name the peer's spec lacks throws, as a
  malformed message does (VAD11).
- Tests: weight in and out at `rate`; a part's angle at full weight is the target; the
  lean reaches `place`; `holdPose` with an unknown name throws; a held pose expires after
  its seconds; a peer's held pose reaches its `RemotePlayer` (`net_game_test.dart`).
- The example: one pose (e.g. a wave on the key `_Wave` already uses).
- **Gate:** the suites green.

### AL5 · The fan and the arc (app)

Files: `examples/voxel_game_minecraft/lib/src/classes/class_table.dart`,
`classes/class_system.dart`, `spec/game_spec.dart`, `test/class_system_test.dart`,
`ROADMAP.md`.

- A row per launcher, beside `shotCosts`: `fanShots` (`bow`, `longbow`: 3 shots, 24°, power
  0.85, 3 arrows, 14 stamina, again in 1.4 s; `staff`, `crystal_staff`: 5 shots, 50°, power
  0.9, 18 mana less Focus, again in 1.1 s, a pulse `0xFF8C33` radius 1.0 at the muzzle).
- `ClassSystem.fan(VoxelGame game, ItemType item)` is the `ItemUse`. It refuses with the
  old notices ("Need 3 arrows", "Too tired to draw", "Not enough mana") and refuses while
  its own wait runs. It pays, then shoots through `game.shoot` as `_volley` does, with the
  launcher's own shot (`ItemType.launcher.shot`), `power: p.damageMultiplier × row.power`,
  `overDrop: false`. Creative pays nothing, as abilities do (`class_system.dart:306`).
- `itemUses` in `game_spec.dart`: the four launcher ids → the system's `fan`, found as the
  blockUses' handlers find theirs (`game.system<ClassSystem>()`).
- The old "attack waits 0.7 s / 0.6 s after" is not ported: the kit owns the attack's
  cooldown and no game reaches it. The step's §Session log entry says so.
- Tests: a ranger's fan looses 3 arrows and takes 3 arrows and 14 stamina; a mage's arc
  looses 5 bolts and costs 18 mana less Focus; short of arrows or mana it fires nothing and
  notifies; a second use inside the wait fires nothing.
- **Gate:** the app's suite green; the root suite green.

### AL6 · The abilities' pulses and coloured hits (app)

Files: `examples/voxel_game_minecraft/lib/src/classes/class_table.dart`,
`classes/class_system.dart`, `spec/game_spec.dart`, `test/class_system_test.dart`,
`ROADMAP.md`.

- `ClassSystem.strike` takes `required String source`. Whirlwind, Shield Bash, Fire Nova
  and Frost Nova pass `whirlwind`, `shield_bash`, `fire_nova`, `frost_nova`.
- `hitColors` in `game_spec.dart`: the nine rows of §What exists's damage table.
- Each ability calls `game.pulse` with its row of §What exists's pulse table (Volley none).
- Tests: a whirlwind's number over a creature is `0xFF8033`; a Fire Nova raises a pulse of
  radius 6 at the player; an arrow's hit is `0xFFE680`.
- **Gate:** the app's suite green.

### AL7 · The dash's pose (app)

Files: `examples/voxel_game_minecraft/lib/src/classes/class_table.dart` (where
`classPlayer` builds the `PlayerSpec`), `classes/class_system.dart`, `test/class_system_test.dart`, `ROADMAP.md`.

- `classPlayer` adds `poses: {'dash': RigPose(parts: {'leg0': (rx: 0.75, ry: 0, rz: 0),
  'leg1': (rx: −0.6, ry: 0, rz: 0), 'arm0': (rx: −1.35, ry: 0, rz: −0.3), 'arm1': (rx: −1.35,
  ry: 0, rz: 0.3)}, lean: −0.45, rate: 20)}`, the old numbers (§What exists). Check the sign of `lean` against `topple`
  on the Mac (AL8): the old leaned forward.
- `ClassSystem._dodge` calls `p.holdPose('dash', dodgeSeconds)`, and `_shadowDash` calls
  `p.holdPose('dash', 0.17)`.
- Tests: the player's `heldPose` is `dash` through a dodge and null after it.
- **Gate:** the app's suite green.

### AL8 · Seen on the Mac

No code. Following the app's rule A4: a throwaway entry beside `main.dart` that wraps the
game in a `RepaintBoundary`, scripts a ranger's fan, a mage's arc and Fire Nova, a hit on a
creature and a dodge in third person, forces frames and writes PNGs to the system temp
folder. The entry and its worlds are deleted before the commit. Record what was seen in
this table's AL8 row, then commit `docs:`. The owner's own play-through (`ROADMAP.md`
stage 13) stays theirs.

---

## Out of scope

- The old app's other pulses: a mob's death (`mob.dart:821`), a bolt's impact
  (`projectile.dart:154`), level-up, effects applied, ghosts, healing (`game.dart:1052`,
  `:1336`, `:1464`; `player.dart:2271`, …). Once `pulse` exists, each is one call, for a
  later app plan.
- Numbers over the player (its own hurts and heals, `player.dart:838`, `:1880`): the kit's
  numbers are over creatures.
- A boss's reflected hit (`mob_brain.dart:266`).
- Mobs holding a declared pose. The animator takes one; no creature asks for one yet.
- Any benchmark (root `CLAUDE.md`).
