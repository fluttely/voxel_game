# voxel_game

A Minecraft-like game in a few lines. You declare the blocks, the world,
the player and the creatures in one `VoxelGameSpec` and call
`runVoxelGame`. You get a playable 3D world: mining and placing, an
inventory and crafting, day and night, creatures with goals, saves and
multiplayer.

It is the kit over `voxel_engine`, `voxel_scene` and `sound_recipes`, and it
re-exports what a game needs, so a game imports only this library.

> **Status: 0.1.2-dev**, beta. The API can still change.

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

- `VoxelGameSpec`: blocks, items, recipes, world, player, mobs, sky, sounds, circuits, liquids.
- `runVoxelGame` / `VoxelGameWidget`: the 3D view, a HUD, the inventory and crafting screen.
- Controls for keyboard and mouse, gamepad and touch; first and third person. A finger on
  the world is a gesture: lift in place to use (or swing), stay put to mine, drag to look —
  and `InputMap.touchMove` / `setTouchHeld` / `touchDigit` take an on-screen stick, button
  or hotbar slot, which the game reads as the same actions a key presses.
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
  voxel_game: ^0.1.2-dev
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

- For multiplayer on macOS, add the `com.apple.security.network.server` and
  `com.apple.security.network.client` entitlements.

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

5. **Grow it** with `items`, `recipes`, `player: PlayerSpec(startingItems: {...})`,
   `sky`, `sounds`, `signals`, `graphics`, and the `on...` hooks.

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
