# Changelog

## Unreleased

- `FrameStats` (`VoxelGame.stats`): what the frames cost. An `fps` readout, and between
  `startRecording` and `stopRecording` every sample: Flutter's presented frames (interval,
  UI build, raster), the simulation (`VoxelGame.frame`), the scene's encoding and the GPU's
  time to finish each scene frame. `FrameReport` summarises them (percentiles, hitches).
  The scene is a `MeasuredScene`, which times its own encoding and the GPU's completion.
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
