# voxel_game

A Minecraft-like game in a few lines. You declare the blocks, the world,
the player and the creatures in one `VoxelGameSpec` and call
`runVoxelGame`. You get a playable 3D world: mining and placing, an
inventory and crafting, day and night, creatures with goals, saves and
multiplayer.

It is the kit over `voxel_engine`, `voxel_scene` and `sound_recipes`, and it
re-exports what a game needs, so a game imports only this library.

> **Status: 0.3.0-dev**, beta. The API can still change.

## The four packages

`voxel_game` sits on three packages, released from the same repository:

```
voxel_engine    pure Dart        core · worldgen · content · signals · net
voxel_scene     flutter_scene    chunk views, terrain material, rigs, outlines, sky   → voxel_engine
sound_recipes   flutter_soloud   sounds synthesised from recipes, no audio files      → (nothing of ours)
voxel_game      Flutter          VoxelGameSpec, loop, input, player, cameras, mobs,   → all three
                                 spawns, drops, HUD, save, host / join
```

A game needs only `voxel_game`. The other three are there for a game that wants less:
`voxel_engine` alone runs a world with no screen (a server, a test, a worker isolate).

## Features

- `VoxelGameSpec`: blocks, items, recipes, status effects, world, player, mobs, sky, sounds,
  circuits, liquids.
- Survival, declared: `PlayerSpec.hunger` (a `HungerSpec`: the bar empties, a full one heals,
  an empty one starves), `PlayerSpec.xp` (an `XpSpec` curve; `PlayerEntity.gainXp`), food
  (`ItemType(food: Food(hunger: 4, heal: 2, effect: 'regeneration', seconds: 8))`, eaten with
  use) and armour (`ItemType(armor: Armor('chest', 3))`, put on with use, turning a blow aside
  down to `PlayerSpec.armorFloor`). The player carries the spec's `effects` in
  `PlayerEntity.effects`, which bend its speed, damage, mining and armour. Each is off until
  declared.
- Blocks that do things, each a field of its row: sand `falls` to where it lands, a torch
  with a `support` drops once its floor or wall goes and is never placed where it would not
  stand, a torch put against a wall becomes its `onWall` form, a block with `loot` drops
  what its `LootTable` rolls, stairs take the `facing` variant the player looks toward, and
  a door is `tall` (two cells, broken as one) and turns into its `usedInto` on a press of
  use. The host runs them (`VoxelGame.blockRules`); a client receives what they changed.
- `runVoxelGame` / `VoxelGameWidget`: the 3D view, a HUD, the inventory and crafting screen.
  A HUD of your own is built once; its pieces follow the game through `HudSelector`s.
  The default HUD's hotbar takes a finger: tap a slot to pick it, hold the one in hand to
  drop one, and `⋯` opens the bag. A HUD is hit-tested like any widget: a piece that takes a
  finger claims it (`InputMap.claimTouch`), a piece that only shows sits in an `IgnorePointer`.
  A loading screen (`LoadingScreen`, or your own `LoadingBuilder`) covers the game until the
  world around the player has filled and the renderer has compiled what it draws.
  Once loaded, the widget shows a `GameSurface`: the world, the touch controls, the HUD and
  the open screen under the one `Listener` that feeds the input. It is public, so a test (or
  a game that draws the world its own way) can mount the kit's wiring over any widget.
- Controls for keyboard and mouse, gamepad and touch; first and third person. A finger on
  the world is a gesture: lift in place to use (or swing), stay put to mine, drag to look.
  A phone also gets `TouchControls`: a floating stick in the lower-left zone (pushed to the
  rim it runs), jump and a sneak switch at the bottom right, the view and pause at the top
  right. They show only while the last device was a finger (`InputMap.lastDevice`), so a
  keyboard or a pad takes them off the screen and a touch puts them back. Lay them out with
  `VoxelGameSpec.touchControls` (a `TouchControlsSpec`), or set it to null for a game that
  draws its own; `TouchControls` is public, and `InputMap.touchMove` / `setTouchHeld` /
  `touchToggle` / `touchPress` / `touchDigit` / `claimTouch` are what any control writes,
  read by the game as the same actions a key presses.
- `MobSpec` with a `Rig` (humanoid, quadruped, bird, blob), a `Gait` and a brain of goals:
  `Wander`, `Hunt`, `MeleeAttack`, `RangedAttack`, `FleeWhenHurt`, `Explode`, `LookAtPlayer`, or `Behavior.custom`.
- `Goal` / `GoalSelector`: the same goal system for your own creature classes.
- `SpawnRule.daylight()` / `SpawnRule.dark()`, `Drop`s.
- Save slots, and `hostPort` / `join` for multiplayer.
- Hooks: `onBlockBroken`, `onBlockPlaced`, `onMobKilled`, `onTick`, and `GameSystem`s.
- `GraphicsSpec`: render scale, a pixel-ratio cap, anti-aliasing and the sun's shadows, with
  a `desktop` and a `phone` preset (the phone's is picked on iOS and Android).
- `VoxelGame.stats`: an FPS readout, and per-frame samples (UI, raster, simulation, scene
  encoding, GPU latency) for a benchmark.

## Install

```yaml
dependencies:
  voxel_game: ^0.3.0-dev
```

To work against a checkout of the repository instead, override all four packages by
path — a plain `path:` on `voxel_game` alone does not resolve, because it still asks for
the other three from pub.dev:

```yaml
dependency_overrides:
  voxel_game:    {path: ../voxel_game/packages/voxel_game}
  voxel_engine:  {path: ../voxel_game/packages/voxel_engine}
  voxel_scene:   {path: ../voxel_game/packages/voxel_scene}
  sound_recipes: {path: ../voxel_game/packages/sound_recipes}
```

Dart SDK `^3.13.0`.

- **Flutter 3.47.1 or later**, with Flutter GPU turned on in each runner: `flutter_scene`
  draws through it, and it is off by default.

  | Platform | File | Add |
  |:---|:---|:---|
  | macOS, iOS | `macos/Runner/Info.plist`, `ios/Runner/Info.plist` | `<key>FLTEnableFlutterGPU</key><true/>` |
  | Android | `android/app/src/main/AndroidManifest.xml`, in `<application>` | `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />` |
  | Windows | `windows/runner/main.cpp`, after `flutter::DartProject project(L"data");` | `project.set_enable_flutter_gpu(true);` |
  | Linux | `linux/runner/my_application.cc`, after `fl_dart_project_new()` | `fl_dart_project_set_enable_flutter_gpu(project, TRUE);` |

  The Windows and Linux settings first shipped in Flutter 3.47.1; before it only the
  `--enable-flutter-gpu` flag turns Flutter GPU on, and release builds ignore it.
  macOS and Android are measured (`example/`); the example's iOS, Windows and Linux
  runners are set up but have not been run yet. On Windows and Linux the mouse look is a
  drag, not a locked cursor: `pointer_lock` locks it only on macOS.
- **Not the web.** Chunks are generated on worker isolates, multiplayer is TCP sockets and
  saves are files, through `dart:isolate` and `dart:io`, which a browser does not have.
  (`flutter_scene` itself runs on the web; the kit does not.)

- **Landscape on a phone.** `runVoxelGame` locks a phone or tablet to the two landscape
  orientations; declare the same in the runners so the launch screen is not upright:
  `android:screenOrientation="sensorLandscape"` on the activity in
  `android/app/src/main/AndroidManifest.xml`, and in `ios/Runner/Info.plist` only
  `UIInterfaceOrientationLandscapeLeft` / `Right` under both
  `UISupportedInterfaceOrientations` keys, with `<key>UIRequiresFullScreen</key><true/>`.

- For multiplayer on macOS, add the `com.apple.security.network.server` and
  `com.apple.security.network.client` entitlements. On Android, add
  `<uses-permission android:name="android.permission.INTERNET"/>` to
  `android/app/src/main/AndroidManifest.xml`: Flutter's template grants it only to debug
  and profile builds, so a release build cannot host or join.

## Usage

1. **Declare your blocks.** Air is added for you.

   ```dart
   const blocks = [
     BlockType('stone', color: 0x7F7F84, hardness: 1.5, tool: 'pickaxe', tier: 1),
     BlockType('dirt', color: 0x8A5E3B, hardness: 0.5, tool: 'shovel'),
     BlockType('grass', color: 0x5C9E3A, hardness: 0.6, tool: 'shovel', drop: 'dirt'),
     BlockType('sand', color: 0xDCCB8A, hardness: 0.5, tool: 'shovel'),
   ];
   ```

2. **Declare the world.**

   ```dart
   const world = WorldGenSpec(
     bedrock: 'stone',
     biomes: [Biome('plains', top: 'grass', under: 'dirt')],
     beach: Biome('beach', top: 'sand'),
   );
   ```

3. **Add creatures.** The brain is a list of goals; the lower priority wins.

   ```dart
   const zombie = MobSpec('zombie', hp: 20,
       rig: Rig.humanoid(skin: 0x5E9A5A, armsForward: true),
       brain: [MeleeAttack(damage: 3), Hunt(range: 18), Wander()],
       spawn: SpawnRule.dark());
   ```

4. **Run it.**

   ```dart
   void main() => runVoxelGame(
         const VoxelGameSpec(blocks: blocks, world: world, mobs: [zombie]),
         saveSlot: 'world1',
       );
   ```

5. **Grow it** with `items`, `recipes`, `effects`,
   `player: PlayerSpec(startingItems: {...}, hunger: HungerSpec())`, `sky`, `sounds`,
   `signals`, `graphics`, and the `on...` hooks.

6. **Play together (optional):** `runVoxelGame(spec, hostPort: 7777)` on one
   machine and `runVoxelGame(spec, join: '192.168.0.10')` on another.

## Example

```sh
cd example
flutter run -d macos
```

[`example/lib/main.dart`](example/lib/main.dart) is a small game in one file:
twelve blocks, two biomes with trees and coal, a few recipes, a player with a
pickaxe, sheep by day and zombies by night.

## Working on the kit

The four packages share one repository, [`fluttely/voxel_game`](https://github.com/fluttely/voxel_game);
its root README says how to run the suite, and its `CLAUDE.md` the rules the code is held to.
