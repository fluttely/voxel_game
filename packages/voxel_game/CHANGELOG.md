# Changelog

## Unreleased

- The creatures of a species share their meshes: `RigModel.of(rig, halfWidth, height)`
  builds a look at a size once (its parts' voxels as `RigShape`s, their rest poses, the
  fit), and each `RigInstance` hangs only its own posable nodes on it. flutter_scene then
  draws a part once a pass, instanced over every creature that has it, instead of once a
  creature. `Rig` is equal by its values, so two species declared with the same look
  share one model; a humanoid's two legs and two arms, and a quadruped's four legs, share
  one shape. With 40 creatures (`mobs:6`) their meshes go from 260 to 8, and on the M2 Pro
  the shadow pass, which draws every creature again in every cascade each frame, from
  2.4 ms to 0.45 a frame.
- `gamepads: ^0.1.10`, the first version with `NormalizedGamepadState`. The constraint
  allowed `0.1.1-dev2`, which lacks it, so the lowest resolution did not compile and
  pana took 20 pub points.
- Formatted by `dart format` at the 120 columns the code is written at
  (`formatter: page_width: 120` in `analysis_options.yaml`); pana took 10 pub points
  for formatting.
- A step runs at most `Mob.searchesPerStep` (3) A* searches; a mob whose plan is due
  when they are spent plans on a later step (`VoxelGame.searchesLeft`). The random phase
  each mob starts with was lost at its first plan, so hunters that saw the player in one
  step replanned together every 0.6 s, as every hunter does when the player moves 1.5 m:
  up to 18 searches in one step. With 40 creatures (`mobs:6`, M2 Pro) a step's p99 falls
  from 4.5 ms to 1.15, with as many searches a second.
- Fixed: a `Wander`er whose last walk was blocked dropped every later goal at once and
  stood still. `Mob.pathBlocked` belonged to the last plan, which is made after the
  behaviours run, so `Wander` read the verdict on the previous goal. `walkTo` now clears it
  for a goal more than `Mob.replanDistance` (1.5 m, the distance that already triggered a
  replan) from the planned one, until that goal is planned.
- A walking mob replans its path every `Mob.replanEvery` (0.6 s), sooner (never before
  `Mob.replanSoonest`, 0.2 s) only when its goal moved 1.5 m, from a random phase per mob;
  it used to replan every step once its path ran out, which an unreachable goal makes
  happen every step. `Mob.pathsPlanned` counts its searches. With 40 creatures (`mobs:6`,
  M2 Pro) a step costs 0.27 ms instead of 7.8 at the median, and the frame rate goes from
  84 to 93 fps.
- `FrameReport.stepMs`: a fixed step's own cost (each tick's simulation time over the
  steps it ran), in the JSON as `stepMs`. `simMs` grows with the steps a slow frame banks,
  so on a device that is behind it reads `FixedStepLoop`'s cap, not the simulation.
- `GameWorld.isLoaded` and `groundHeight` read the chunk through
  `ChunkStreamer.chunkAtXZ`. With the engine's faster block queries, 40 creatures
  (`mobs:6`, M2 Pro at 120 Hz) run at 91 fps instead of 50, and the simulation's p99 falls
  from 66 ms to 11.

## 0.1.1-dev

- Requires Flutter 3.47.1, the first with a runner setting that turns Flutter GPU on for
  Windows and Linux. The README has the setting for every platform, and why the web is
  not one (worker isolates, TCP sockets and save files need `dart:isolate` and `dart:io`).
  The example's Windows and Linux runners turn it on.
- `FrameStats` (`VoxelGame.stats`): what the frames cost. An `fps` readout, and between
  `startRecording` and `stopRecording` every sample: Flutter's presented frames (interval,
  UI build, raster), the simulation (`VoxelGame.frame`), the scene's encoding and how long
  after it the GPU finished each scene frame (`gpuLatencyMs`: a latency, queue included, not
  the GPU's cost). `FrameReport` summarises them (percentiles, hitches). The scene is a
  `MeasuredScene`, which times its own encoding and the GPU's completion.
- `VoxelGameSpec.copyWith`; `GameWorld.chunksBuilt` and `GameWorld.facesEmitted`.
- `GraphicsSpec` (`VoxelGameSpec.graphics`): `renderScale`, `maxPixelRatio`,
  `antiAliasing` and a `ShadowSpec` (cascades, resolution, distance, the sun's step).
  `GraphicsSpec.desktop` is the look as it was; `GraphicsSpec.phone` draws at most 1.5
  pixels a point, with FXAA and two 1024² cascades over 48 m, and is what a spec without
  `graphics` gets on iOS and Android.
- The camera's far plane ends where the fog is full (`VoxelGame.viewDistance`, plus a
  chunk) instead of 800 m, so the loaded chunks past the fog are culled, not drawn.

## 0.1.0-dev

First version.

- `VoxelGameSpec` + `runVoxelGame`: a playable voxel game from one declaration.
- Mining, placing, an inventory and crafting screen, a HUD, first and third person.
- Keyboard and mouse, gamepad and touch controls.
- `InputMap` reads a finger as a gesture, not as a mouse button: one that lifts where it
  landed presses the primary or the secondary button (`touchTapPrimary`, the game's own
  "is a creature under the crosshair" bit), one that stays put for `mineDelay` holds the
  primary one until it lifts, and one that travels past `tapSlop` is the look and presses
  nothing. `touchMove`, `setTouchHeld` and `touchDigit` are the on-screen controls' half,
  read through the same `down` / `justPressed` / `axis(..., touch:)` / `digitPressed()`
  a key or a pad goes through. `VoxelGameWidget` forwards `onPointerCancel`, so a pointer
  the system takes away is dropped instead of left down.
- A one-shot press waits for the step that reads it. A frame that runs no simulation step
  no longer drains them, which above 60 fps threw away about half of every player's taps
  and clicks; and `VoxelGame.step` is now the single reader of the bag and pause buttons,
  so one press can no longer close a screen in one place and open another somewhere else.
- Mobs from `MobSpec`: rigs, gaits, drops, spawn rules and a brain of goals.
- `Goal` / `GoalSelector`: the goal system, usable with any creature class.
- Day and night sky, sounds, circuits (`SignalSpec`), liquids.
- Save slots, and hosting or joining a multiplayer world.
- Hooks: `onBlockBroken`, `onBlockPlaced`, `onMobKilled`, `onTick`, `GameSystem`.
- The package description and the dartdoc say what the kit does, not which game it was
  measured against: "a voxel sandbox in a few lines". The library's header names the
  three packages it sits on as they are called today.
