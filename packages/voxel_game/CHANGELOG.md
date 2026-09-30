# Changelog

## Unreleased

- **A phone gets controls it can see.** `TouchControls` draws a floating stick in the
  lower-left zone (centred where the thumb lands; pushed past `sprintAt` of its reach it
  also holds sprint), jump and sneak at the bottom right, the view and pause at the top
  right, inside the safe area. It shows only while `InputMap.lastDevice` is a finger, the
  game is in `gameplay` and no screen is open. Every control claims its finger, so it is
  never also a look, a dig or a tap on the world. `VoxelGameWidget` mounts it between the
  world and the HUD. It is declared by the new `VoxelGameSpec.touchControls`, a
  `TouchControlsSpec` (`stickRadius`, `stickZoneWidth` / `stickZoneHeight`, `sprintAt`,
  `buttonSize`, `sneakToggles`, `dropHold`), `TouchControlsSpec.standard` by default; null
  for a game that draws its own, which also takes the finger off the default HUD's hotbar.
- The player walks by the on-screen stick: `PlayerEntity` read the left stick and the keys
  but not `InputMap.touchMove`, so a stick drawn by any game moved nothing.
- A finger's tap on a creature hits it. `PlayerEntity` now writes
  `InputMap.touchTapPrimary` every step (true while a creature in reach is under the
  crosshair), which nothing in the kit wrote before, so a tap always pressed the secondary
  button and a phone could only hit by holding, which mines.
- A screen opening lets go of every held input (`InputMap.releaseKeys`), as that method's
  documentation said it did: a switched-on sneak, a finger's jump and the stick no longer
  survive the bag.
- **Breaking: `VoxelGameSpec.copyWith` can ask for null.** Its nullable fields (`signals`,
  `graphics`, `touchControls`, `onBlockBroken`, `onBlockPlaced`, `onMobKilled`, `onTick`)
  are now given as a getter of the new value, so `copyWith(touchControls: () => null)`
  takes the kit's controls away; before, `x ?? this.x` turned a null into "keep it" and the
  call did nothing. Wrap what you passed: `graphics: GraphicsSpec.phone` becomes
  `graphics: () => GraphicsSpec.phone`.
- The bag opens under a `VoxelGameWidget` with no `Scaffold` above it: `InventoryScreen`'s
  panel is its own `Material`, so its recipe tiles no longer fail to build ("No Material
  widget found") in a game that mounts the widget straight under its app.
- `GameSurface`: what `VoxelGameWidget` shows once the game has loaded, the world under
  the touch controls, the HUD and the open screen, inside the one `Listener` and `Focus`
  that feed the input map; it takes the pointer on the first press, keeps a press on an open
  screen from the world, and frees the pointer and every held input when a screen opens.
  `world` is any widget, so the kit's own wiring can be mounted in a widget test, and its
  tests now mount it instead of a copy. `HudBuilder` moved into its file (still exported
  from `package:voxel_game/voxel_game.dart`). A screen opened before the game has loaded
  no longer frees or takes the pointer; the surface arbitrates only while it is shown.
- **Breaking: the HUD is hit-tested.** `VoxelGameWidget` no longer wraps the `HudBuilder`'s
  widget in an `IgnorePointer`, so the default HUD's hotbar can take a finger: a tap on a
  slot picks it, a hold of `TouchControlsSpec.dropHold` on the slot in hand drops one item, and
  while the last device was a finger a `⋯` after the last slot opens the bag. Each slot
  claims the finger that lands on it (`InputMap.claimTouch`), so the world never reads it as
  a tap; a mouse over the hotbar is still the world's. The hint says "Tap to play" while the
  last device was a finger. A HUD of your own that drew plain widgets is unaffected (the
  game's `Listener` sees every pointer either way); one with buttons, `GestureDetector`s or
  `InkWell`s on it now receives their gestures, so wrap it in `IgnorePointer` to keep the
  old behaviour.
- **`InputMap` knows which device spoke last, and which fingers a control took.**
  `InputMap.lastDevice` (the new `InputDevice`: `keyboardMouse`, `gamepad`, `touch`) is
  written by `onKey`, `onPointerDown` and `onPad` from the event each is handed, a pad only
  on a press or a stick past the dead zone; it starts as `touch` on Android and iOS. An
  on-screen control calls `claimTouch(pointer)` from its own `onPointerDown`, and the map
  then reads that finger as no look, no dig and no tap until it lifts. `touchToggle(action)`
  holds an action from one tap to the next (sneak) and `touchHeld(action)` reads it back;
  `touchPress(action)` presses a one-shot for a single step. The pad handler is public as
  `onPad`, so a game can feed a pad source of its own. Nothing on screen changes yet.
- **Breaking: a shot's shape is declared, not read from its kind's name.** `ProjectileSpec`
  takes `thickness` and `length`, the box it is drawn as (only its look; `radius` still
  hits), defaulting to the arrow's `0.06 × 0.06 × 0.6`; `ProjectileSpec.bolt` sets
  `0.5 × 0.5`, the cube it had. `ProjectileModel.of` sized the box by `kind == 'arrow'`,
  so a spear under another name drew a cube and a fireball named `'arrow'` a stick. A
  spec that relied on a kind other than `'arrow'` drawing a cube of its radius now sets
  `thickness` and `length` to `radius * 2`.
- **A loading screen covers the game until it can be shown without a stall.**
  `VoxelGameWidget` runs the game undrawn until the window around the player has filled
  (the new `VoxelGame.filled`: the player stands and `GameWorld.isIdle`), then encodes
  every chunk and body once, offscreen, through flutter_scene's `Scene.warmUp`
  (`includeOffscreen`), so the pipelines Impeller compiles on first use are compiled
  behind the screen. The game keeps stepping while it loads, with its controls off. A
  first run after a build (the Mac, `orbit:6`) drew its first frames in encodes of ~650,
  ~320 and ~570 ms; it now compiles in one ~1.06 s encode before the first frame, which
  encodes in ~1 ms, and fills ~0.4 s sooner; on a Galaxy S24 (a fresh install) the
  encodes of ~330 and ~255 ms become one of ~0.55 s behind the screen, and a warm start
  fills ~0.1 s sooner, the scene no longer drawn while it fills. The screen's stages are the new
  `LoadingStage`; `VoxelGameWidget(loading:)` and `runVoxelGame(loading:)` take a
  `LoadingBuilder` in place of the default `LoadingScreen`. `onReady` still fires as the
  game starts, before the screen goes.
- Drops and shots share their meshes, as the creatures' parts do: `PickupModel.of(r, g, b)`
  builds a drop's cube once a colour, and `ProjectileModel.of(spec)` a shot's box and
  material once a size, colour and glow, so flutter_scene draws a floor of mined blocks
  or a volley of arrows once a pass, instanced, instead of once a drop or a shot. It
  batches only draws sharing both a geometry and a material, and each drop and each shot
  made its own.
- A host passes on a client's block edit that lands where the host has not loaded the
  world. It stored such an edit for when the chunk generates but told no one, so two
  clients far from the host each kept their own blocks until they joined again; now the
  edit leaves with the step's other edits, like one the host could write.

## 0.3.0-dev

- `GameWorld.update` rebuilds the chunk regions the streaming changed within the view's
  frame budget, nearest the focus first (`VoxelChunkView.rebuild`), so a column of chunks
  entering or leaving the window is drawn over a few frames instead of in one long one;
  `GameWorld.isIdle` also waits for the regions still to draw.
- **Breaking: the HUD is built once, not every frame.** `HudBuilder` is called when
  `VoxelGameWidget` builds (the game starts, a screen opens or closes), and the HUD sits
  behind a `RepaintBoundary`, so the scene's repaint every frame no longer repaints it.
  A piece that shows the game's state watches it through the new `HudSelector`, which
  checks a value on every tick of the new `VoxelGame.frames` and rebuilds only when it
  changes; a custom HUD that read the game in its `build` must move those reads into
  selectors. `DefaultHud` is such a tree: while nothing it shows changes, a frame builds
  none of it.
- `RigInstance.place` composes the root's pose into its matrix at once and allocates
  nothing, as `RigPart.apply` now does; every creature is placed every step.
- A networked game sends the block edits of a step together, as one `edits` message at
  the step's end, no longer a `set` message per cell as each was made: an explosion's
  ~120 cells cost the host 1.7 ms with 4 peers and 3.3 with 8 (M2 Pro), a message and a
  write each per peer, against 37 and 50 µs as one. The session now ticks last in
  `VoxelGame.step`, after the game's systems and `onTick`, so every edit of a step leaves
  in it. **The wire changed**: a host and a client of different versions cannot talk.
- The mining crack is one draw: its sticks were a node and a geometry each, up to 60 draws
  at its last stage, and each stage is now one `BoxMesh` (voxel_scene) holding its sticks
  and every earlier stage's, on one node. `FirstPersonView.crackBoxes(stage)` lists them.

## 0.2.0-dev

- **Frames between two steps are drawn between them.** Above 60 fps half the frames ran
  no step, and everything drawn moved in the steps, so the view and every body stood
  still one frame and moved a whole step the next: a 60 Hz world on a 120 Hz display.
  Now `VoxelGame.frame` draws every body `alpha` of the way between its last two steps'
  poses (`NodeBody.drawNode`, the steps keeping the pose before theirs with `beginStep`),
  the camera's eye and the first-person hand follow the drawn player
  (`PlayerEntity.drawnEye`), and the view bob and the third-person pull-out move by
  `VoxelGame.drawnTime`, the game time a frame shows. A frame is drawn a step behind the
  simulation, 16.7 ms. The step is unchanged: 60 Hz, nothing paused.
- **The look is drained once a frame**, by `VoxelGame.frame`, before the steps, and no
  longer by the step: the view turns at the display's rate, and the steps aim with the
  newest yaw. `PlayerEntity.look` applies it (dropped while dead or not yet placed). The
  buttons are still read by the step alone. A game that calls `step` itself, without
  `frame`, turns the player with `look`.
- A rig's facing is its owner's: `RigInstance.place` no longer turns the rig's root, and
  the mob, the player and a remote player turn their node by `rig.yaw` through
  `syncNode`, so a body turns as smoothly as it moves. The limbs are still posed a step
  at a time. The outline around an aimed creature follows its drawn box, once a frame
  (`PlayerEntity.drawOutline`).
- Drops and projectiles set their pose through `syncNode` (a drop's bob and spin, a
  projectile's heading) instead of writing their node, so they are drawn between steps
  too; a respawn or a placement snaps (`syncNode(snap: true)`) instead of gliding there.
- `FrameStats` at 120 Hz, the Mac, `dpr` 2.0: `view judder` 1.0 → 0.0 at `orbit:6` and
  `mobs:6`, 1.0 → 0.05 at `fly:6` (its first four frames, before the flight starts), and
  no other frame shows the view of the frame before.
- `InputMap.turn(yaw, pitch)`: a steady turn from code, radians a second, taken by
  `takeLook` over its `dt` as the right stick's is. A bot, a cutscene or the benchmark
  turns the view the way a held stick does.
- `FrameStats` measures how evenly the view moves, which no frame timing can: a frame
  presented on time may show the view the one before showed. `addView(eye, forward)`,
  which `ViewCamera` calls once a frame, keeps how far the view moved (the angle its
  forward turned, plus its eye's travel over `FrameStats.viewDepth`, 10 m), and
  `addFrame` takes the frame's `seconds`. `FrameReport.viewJudder` is the root mean
  square of each frame's speed against the mean, minus one (0 for a view that moves by
  the time that passed, about 1 for one that moves every other frame) and `stillFrames`
  counts the frames that moved less than a quarter of the mean; the JSON has them under
  `view`. At 120 Hz the kit today reads about 1 and half its frames: the view moves in
  the 60 Hz steps.

## 0.1.2-dev

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
