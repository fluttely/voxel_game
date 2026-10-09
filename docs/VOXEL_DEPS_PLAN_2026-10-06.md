# The dependencies-and-debts plan (VD) — 2026-10-06

**Question.** `0.4.0-dev` went out on 2026-10-05 (VL13) with `sound_recipes` at 150 of 160
points: `flutter_soloud` 5 is a major version past its constraint (`KL-026`). Hours before,
`flutter_scene` 0.24.0 came out, and the kit's exact pin on 0.23.0 costs `voxel_scene` and
`voxel_game` the same 10 points on 2026-11-04 (`KL-027`). pub.dev lists `voxel_game` for
macOS alone (`KL-028`), and two of the ledger's entries are bugs a player can meet (`KL-024`,
`KL-025`). What does the kit move, in what order, and how does `0.5.0-dev` get out before
the deadline?

**Answer, in one line.** The two small debts first (the dungeon's doorways, one owner of
the audio device), then `flutter_scene` 0.24, which unblocks `flutter_soloud` 5, and
`0.5.0-dev` of all four before 2026-11-04. Meanwhile an issue upstream asks `pointer_lock`
to declare the platforms it does not lock.

Closes `KL-024`, `KL-025`, `KL-026` and `KL-027`. Moves `KL-028` upstream, where the kit waits
on it. Opens `KL-029` (the terrain's `discard`, VDD7). The app's visual leftovers (VLD4) and
the chest minecart (`VAD24`) stay out (§Out of scope).

Every decision below was the owner's answer on 2026-10-05 and 2026-10-06 (§Decisions). The
facts come from reading the code and from two probes on 2026-10-06. Each probe copied the
workspace to a scratch folder and moved one dependency there, so none of it is in this tree.
Every `file:line` is from 2026-10-06; re-check it before a step starts.

---

## Progress

| Step | State | Gate |
|:---|:---|:---|
| VD0 This plan, and the owner's answers to §Decisions | **done** 2026-10-06: every recommendation taken (VDD1–VDD7) | the owner answers VDD1–VDD7 |
| VD1 `KL-028` asked upstream | **done** 2026-10-06: the owner approved the draft; [pleiondev/flutter3d#80](https://github.com/pleiondev/flutter3d/issues/80) is open, `KL-028` waits on it, the README says why | the issue is open and linked from `KL-028`; the README says why pub.dev shows one platform |
| VD2 A dungeon's doorways (`KL-025`) | **done** 2026-10-06: two doorway cells in the west wall of rooms 1 and 2; the flood-fill test reaches `[true, true, true]` (it read `[true, false, false]` before the fix) | a flood fill from the shaft reaches every room; suite green |
| VD3 One owner of the audio device (`KL-024`) | **done** 2026-10-06: `AudioDevice` in `sound_recipes`, exported by `voxel_game`. Its queue keeps no future once idle: a device that outlives a test's zone would otherwise chain the next test's step onto a dead zone. `voxel_game` and the app set a device that never opens in `test/flutter_test_config.dart`. Then `MusicDirector.setMood` checks the device before `SoLoud.instance`, whose native library fails to load on Linux: the red CI since the 0.4.0-dev merge (runs 37400177007, 37400205441), found by a parallel session | the title and a world never close each other's device, proven with a fake device; the tests no longer depend on SoLoud failing to load |
| VD4 `flutter_scene` 0.24.3 (`KL-027`) | pending; **retargeted 2026-10-09** from 0.24.0 to 0.24.3, with the terrain's geometry on 0.24's public path (FS1, `docs/FLUTTER_SCENE_FOLLOWUP_PLAN_2026-10-09.md`) | the five suites green, the bundle rebuilt, the terrain drawn in `flutter run -d macos` with shadows and torchlight; `terrain_geometry.dart` imports nothing under `flutter_scene/src/` |
| VD5 `flutter_soloud` 5 (`KL-026`) | pending; **the owner's word to push** (CI) | the suites green locally and on CI; the example plays its title music on the Mac |
| VD6 Ready to release | pending | CHANGELOGs under `## 0.5.0-dev`, the four dry runs green, the four at 160 locally (pana) |
| VD7 `0.5.0-dev` out | pending; **the owner's word in that session**; **before 2026-11-04** | the four on pub.dev at 160; four tags pushed |

Effort per step: VD1 `low` (an issue's text and a README line), VD2 `medium` (four cells and a
test, the fix already probed), VD3 `high` (an ordering primitive two packages share), VD4
`xhigh` (shader work: three shaders re-derived from new stock ones, a uniform layout, a
visual check), VD5 `high` (a native build hook new to the CI), VD6 `medium`, VD7 `low` (a
checklist, with the owner present).

---

## What exists (read before VD1)

- **Releases.** All four are at `0.4.0-dev` on pub.dev, published by hand from `a8ef77d`
  and tagged `<package>-v0.4.0-dev` there (VL13). Points: `voxel_engine`, `voxel_scene`,
  `voxel_game` 160; `sound_recipes` 150.
- **Suite.** analyze clean; `voxel_game` 477, `voxel_engine` 247, `voxel_scene` 49,
  `sound_recipes` 7; the app 111. The CI (`.github/workflows/ci.yml`) runs it on
  `ubuntu-latest` with Flutter 3.47.5.
- **The order is forced.** The probe on `flutter_soloud` 5 found two things:
  - **Version solving fails** next to `flutter_scene` 0.23.0: "`flutter_scene 0.23.0`
    depends on `code_assets ^1.2.1` … `flutter_soloud ^5.1.6` depends on `code_assets
    ^2.0.0`". Every 5.x from `5.0.0-pre.2` needs `code_assets ^2.0.0`, and `flutter_scene`
    0.24.0 accepts `>=1.2.1 <3.0.0`. **So VD5 waits on VD4.**
  - **Three tests fail** under 5.x: `title_music_test` goes `+3 -3`, with a "Null check
    operator" at `:150`. Under 4.x, `SoLoud.init` fails at once in a test ("Failed to
    lookup symbol 'isInited'"), and the tests count on that failure. Under 5.x the native
    library loads and `init` gets as far as `path_provider`
    (`MissingPluginException(... getTemporaryDirectory ...)`). **So VD5 waits on VD3**,
    whose fake device makes the tests independent of SoLoud loading.
- **`flutter_soloud` 4.1.7 → 5.1.6, the calls we make** (`packages/sound_recipes/lib/src/sound_bank.dart`;
  `lib/src/soloud.dart` in each version):
  - Source-compatible: `init` (three new optional named parameters), `deinit`,
    `isInitialized`, `loadMem`, `loadAsset`.
  - Bodies identical (diffed): `setPause`, `setRelativePlaySpeed`, `setGlobalVolume`,
    `setVolume`, `getIsValidVoiceHandle`, `fadeVolume`, `scheduleStop`.
  - `play` no longer throws when the device fails to start (that goes to
    `audioDeviceStartFailures`); a full voice pool still throws
    `SoLoudFailedToStartPlaybackCppException`.
  - Floors: Flutter ≥3.41.0, Dart ≥3.11, which the kit already exceeds. No `hooks:` block
    is needed in a pubspec.
  - **`flutter test` now runs a native build hook.** On the Mac, the first run took 48 s
    and a cached one 2 s, against 6 s on 4.x. It compiles C and downloads prebuilt Xiph
    libraries from GitHub (`hook/build.dart:363,566-573`). The CI needs a C compiler and
    network in every job that resolves `sound_recipes`; that `ubuntu-latest` has the
    compiler is **unverified**.
  - 5.x does **not** order `init` against `deinit`. Its Dart lifecycle is 4.x's: a second
    `init` queues and then re-opens an open engine (5.1.6 `soloud.dart:436,561`), and a
    `deinit` makes an in-flight `init` throw (`:927,956`). The "serialized device
    operations" in its changelog are the native start, stop and `changeDevice`.
- **`KL-024`, the race, read in code.**
  1. The title runs `_play` (`packages/voxel_game/lib/src/ui/title_screen.dart:120`), which
     calls `bank.init()` (`:126`). If the screen went in the meantime, it calls `dispose`
     (`:127`). A title left mid-`init` still has `_bank == null`, so its own `dispose`
     (`:144-145`) closes nothing.
  2. The world calls `_startAudio` (`packages/voxel_game/lib/src/ui/voxel_game_widget.dart:273`)
     once `VoxelGame.start` returns: `init` at `:322`, `dispose` at `:389-390`.
  3. `SoundBank.init` opens the device (`sound_bank.dart:56`) and `dispose` closes it
     (`:95`). So the world's `init` queues behind the title's and re-opens the device;
     then the title's `dispose` closes it.
  4. The world's `init` throws `SoLoudInitializationStoppedByDeinitException`, which the
     catch-all at `:64` turns into a silent world.
- **`KL-025`, confirmed.**
  - Along the site's x (`dungeon_plan.dart:25`), the room boxes span -16..-8, -4..4 and
    6..18. The corridors run -8..-4 and 4..8 (`dungeon.dart:87`). Each next room's box
    (`:70-74`) bricks over x -4 and x 6.
  - A flood fill from the shaft (8 seeds × 2 depths) reached `[true, false, false]`.
  - Cutting the four doorway cells after the rooms loop, before the shaft (`:104`), gave
    `[true, true, true]`, with the engine's suite green.
  - Re-drawing the corridors after the rooms would push corridor 1's shell into the
    treasure room (x 7..8), so not that.
  - Nothing reads those cells: `DungeonPlan` keeps no doorways; the app's
    `examples/voxel_game_minecraft/lib/src/world/structures.dart:175-187` reads the plan,
    and its test (`structures_test.dart:72-81`) looks only for the chest. A save keeps only
    edits (`world_save.dart:15-25`).
- **`flutter_scene` 0.24.1–0.24.3, read on 2026-10-09** at the `flutter_scene-0.24.3` tag
  of `github.com/bdero/flutter_scene`. The probe below ran on 0.24.0; these change VD4:
  - **#435 is closed by flutter_scene's own PR #458** (merged 2026-10-03, in 0.24.0). The
    shadow cache refreshes one cascade per frame on a turn of up to 5° and keeps its tile
    textures; the per-draw path stopped allocating closures, records, views and uniform
    slots. Nothing of #435 is left for the kit to send (FS0).
  - **A public path for a packed vertex** (MATERIALS.md §"A packed vertex format"):
    an `UnskinnedGeometry` with `setVertexLayout`, `setVertexShader`,
    `uploadVertexStreams` and `setDepthOnlyVertex`. `package:flutter_scene/gpu.dart` now
    exports `Shader`, `IndexType`, `VertexFormat` and `VertexStepMode`. The encoder binds
    `FrameInfo` once per shader for an `UnskinnedGeometry` (`scene_encoder.dart:1547`),
    so the 13% of allocations #435 §2 measured on a custom `Geometry`'s `bind` goes with
    the subclass.
  - **What stays private.** `gpu.RenderPass` is not in the public `gpu.dart`, and
    `TerrainMaterial.bind` takes one (`terrain_material.dart:77`). `rendererSubmissions`
    is still in `src/render/frame_transients.dart`, read by `gpu_paced_scene.dart:9` and
    `voxel_game`'s `measured_scene.dart:10`. So the exact pin stays (FS2).
  - **`Scene.warmUp` gained `allShadingTiers`** (0.24.3, `scene.dart:2044-2049`), next to
    `sliceBudget`. The override forwards both.
  - **Debug views are opt-in** (0.24.1): the surface debug channels compile only with
    `hooks: user_defines: flutter_scene: debug_views: true`. Re-read
    `scene_encoder.dart:1400-1420` before trusting the `DebugViewInfo` lead below.
  - **A lean lit shader** (0.24.3) for scenes without irradiance, area lights, AO or
    point-light shadows. `terrain.frag` is re-derived from the stock lit shader, so read
    which tier is the base before re-deriving it.
  - **Pacing.** Scenes drawn in one frame pace together (0.24.2);
    `maxGpuFramesInFlight` is still there (`scene.dart:683`), so VDD5 holds.
- **`flutter_scene` 0.23.0 → 0.24.0, from a probe** that moved the pins and ran analyze,
  `build_shaders.dart` and the suites:
  - **One Dart break.** `GpuPacedScene.warmUp`
    (`packages/voxel_scene/lib/src/gpu_paced_scene.dart:82`) is no longer a valid override:
    `Scene.warmUp` gained `Duration? sliceBudget`. 0.24's `warmUp` also waits twice more
    before it renders (`scene.dart:1945-1952`), which the comment at `:83` does not know.
  - **The deprecations.** Every `castsShadows` is deprecated for `shadowCastingMode`. That
    is 11 analyze infos, which fail `flutter analyze`, in `first_person_view.dart`,
    `mirrored_camera.dart`, `selection_outline.dart` and `test/mirrored_camera_test.dart`.
  - **Its own GPU pacing.** 0.24 adds pacing, on by default (`Scene.maxGpuFramesInFlight
    = 1`, `scene.dart:667`): a frame may re-show the last image instead of encoding. It
    overlaps our `ScenePacer` (`packages/voxel_scene/lib/src/scene_pacer.dart:16`) and
    could make `MeasuredScene`'s `rendered` overcount (unverified at runtime). VDD5 turns
    it off.
  - **Vertex shaders no longer compile.** `TerrainVertex:52: 'ApplyDepthBias' : no matching
    overloaded function`: it takes `camera_transform` as a second argument. The calls are
    at `packages/voxel_scene/shaders/terrain.vert:51` and `terrain_depth.vert:36`.
  - **`FrameInfo` grew from 80 to 112 bytes.** The depth passes now bind 112 bytes into our
    80-byte block (0.24 `depth_prepass.dart:818`, `shadow_encoder.dart:513`), and
    `terrain_geometry.dart:107` fills a `Float32List(20)`.
  - **`FragInfo` changed.** Bytes 784-831 were padding and are now `froxel_grid`,
    `view_projection` and `camera_position`. The committed bundle reads point lights wrong
    under 0.24, so the rebuild is required (rule 15).
  - **A missing `DebugViewInfo` very likely crashes the first draw.** 0.24's lit shader
    includes `material_debug.glsl`, and `scene_encoder.dart:1320-1330` binds
    `DebugViewInfo` for every material that opts into debug views.
    `PhysicallyBasedMaterial` does, and so does `TerrainMaterial`. Ours declares no such
    block, and `flutter_gpu`'s `render_pass.dart:477` throws "Failed to bind uniform".
    Inferred from the code, not seen running.
  - **What still holds.** The private imports still resolve:
    `package:flutter_scene/src/gpu/gpu.dart` (only gains an export) and
    `src/render/frame_transients.dart` (`rendererSubmissions` unchanged). So do
    `TerrainGeometry`'s overrides, `TerrainMaterial.bind`, `MirroredProjection`,
    `ResizeSafeScene` and `MeasuredScene`. Nothing in the kit or the app constructs
    `Lighting` or uses `Material.depthLayer`. The app uses `SceneView` and `Camera`
    directly (`title_vista.dart:5`), and nothing there breaks.
  - **The patched probe passed.** With `sliceBudget` forwarded and `ApplyDepthBias`
    patched, the five suites passed in the probe. That checks the Dart side only, not a
    drawn frame.
  - **The pins.** Four exact or caret pins move:
    - `packages/voxel_scene/pubspec.yaml:26`
    - `packages/voxel_game/pubspec.yaml:27`
    - `packages/voxel_scene/example/pubspec.yaml:17`
    - `examples/voxel_game_minecraft/pubspec.yaml:13` (`^0.23.0`)
- **`KL-028`.** `pointer_lock` 0.4.2+1 (2026-10-01; publisher `pleion.dev`, repository
  `github.com/pleiondev/flutter3d`) still declares only `macos`.
- **The catches.** Each of these logs and goes on (rules 5, 6):
  - `sound_bank.dart:64` catches anything from `init`;
  - `:88` anything from `play`;
  - `:203` a third. VD3 and VD5 narrow the first two to the branch each is for.

## Decisions

| ID | Decision | Why |
|:---|:---|:---|
| VDD1 | **One plan: the kit's dependencies and its open debts, then `0.5.0-dev`.** (Owner, 2026-10-05.) `KL-024`, `KL-025`, `KL-026`, `KL-027`, `KL-028`. The app's looks (VLD4) and the chest minecart (`VAD24`) wait for a later app plan; `KL-004` stays deferred (VLD3). | `KL-027` has a date, and `KL-026` cannot move before it. The two debts are small and touch the same files. The app's looks are a game's, not the kit's. |
| VDD2 | **The version is `0.5.0-dev`**, the four together. (Owner.) | `flutter_scene` 0.24 changes types a game sees (it shares `SceneView`, `Camera`, `Material` with the kit), and every world's dungeons change (VDD4). Below 1.0 a break moves the minor. |
| VDD3 | **`KL-028` goes upstream, and the kit waits.** (Owner.) An issue asks `pointer_lock` to declare the other platforms with a Dart-only implementation whose `isSupported` is false. The README says why pub.dev shows one platform. No native code here. | The fix belongs in the plugin that declares one platform. A plugin of the kit's own is native code to keep, and rule 4 asks a new package for an optional heavy dependency, which this is not. |
| VDD4 | **Every world gets the doorways, saved ones included.** (Owner.) | A save keeps only edits over what the seed draws, so the fix reaches old worlds with no code, and it is a bug fix. A generation version in the save would be code that keeps a bug alive. |
| VDD5 | **`flutter_scene`'s own GPU pacing is off** (`maxGpuFramesInFlight = 0` in `GpuPacedScene`), and `ScenePacer` stays. (Owner.) | That is the frame the PF plan measured. Adopting the new pacing changes the frame, and judging that needs numbers, which no one asked for. Adopting it is §Out of scope. |
| VDD6 | **`AudioDevice` is public in `sound_recipes`.** (Owner.) One device, opened by the first holder and closed by the last, every open and close in one queue. Its open and close are injectable, so a test fakes the device. | A game that plays SoLoud itself goes through the same owner and cannot close a bank's device. The fake is also what VD5's tests need. |
| VDD7 | **The terrain's `discard` stays; it goes to the ledger** (`KL-029`). (Owner.) | It is frame work (early depth on tile GPUs), and nothing judges it without a measurement. 0.24's stock shaders split opaque from masked; VD4 keeps ours as one shader. |

## Steps

### VD1 · `KL-028` asked upstream

`packages/voxel_game/README.md`, `docs/LEDGER.md`. No `lib/`, so no CHANGELOG.

- Draft the issue for `github.com/pleiondev/flutter3d` (`pointer_lock`). It states:
  - The pubspec declares `flutter.plugin.platforms` with `macos` alone, so pub.dev lists
    every package that depends on it for macOS only.
  - pub.dev's report for `voxel_game` 0.4.0-dev says Android, iOS, Windows and Linux are
    "blocked by the `pointer_lock` package".
  - The ask: declare the other platforms with a `dartPluginClass` whose `isSupported` is
    false and whose calls are no-ops, the shape the method channel already answers off
    macOS.
  - Offer a PR.
- **Gate:** show the draft to the owner, who posts it or gives the word to post it (`gh
  issue create`). It is outward-facing.
- `KL-028` gains `Waiting:` (the date and the issue link). It stays under `## Open`.
- The README's platform section gains one sentence: pub.dev lists macOS only because of
  `pointer_lock`, the kit runs on the five, and the issue is linked.
- Commit `docs:` (README and ledger only).

### VD2 · A dungeon's doorways (`KL-025`)

`packages/voxel_engine/lib/src/worldgen/structures/dungeon.dart`,
`packages/voxel_engine/test/stock_structures_test.dart`, `packages/voxel_engine/CHANGELOG.md`.

- After the rooms loop, before the shaft (`dungeon.dart:104`), set air on the doorway of
  rooms 1 and 2: x = `next.centre.x - site.x - next.half`, at `floor + 1` and `floor + 2`,
  z = 0. Four cells. Read the loop first: name the doorway from the corridor's own end,
  not a recomputed constant.
- Test, next to the dungeon's (`stock_structures_test.dart:163`): a flood fill through air
  from the shaft's foot reaches a cell inside every room. Run it for several seeds and
  both depths, as the probe did.
- CHANGELOG `## Unreleased`: the rooms are joined, and every world's dungeons open,
  saved ones included (VDD4).
- Commit `voxel_engine: a dungeon's rooms are joined (VD2)`. `KL-025` moves to `## Closed`.

### VD3 · One owner of the audio device (`KL-024`)

`packages/sound_recipes/lib/src/audio_device.dart` (new), `lib/sound_recipes.dart` (export),
`lib/src/sound_bank.dart`, `test/`; `packages/voxel_game/lib/src/ui/title_screen.dart`,
`voxel_game_widget.dart` only if they call the device directly (they should not), and
`packages/voxel_game/test/` (the title's music test); both CHANGELOGs and
`sound_recipes`' README.

- **`AudioDevice`** (`final class`, VDD6):
  - `acquire()` (`Future<bool>`: open or not) and `release()`.
  - The first `acquire` opens; the last `release` closes, and only after any open in
    flight.
  - Every open and close runs in one queue (each chained onto the last future), so a
    `release` that lands while an `acquire` is opening never closes the device under it.
  - The real device is SoLoud's `init` / `deinit`. A test builds one with its own open and
    close.
  - There is one instance, `AudioDevice.instance`, with a `@visibleForTesting` setter that
    a test restores in `tearDown`. A held count below zero is a `StateError` (rule 5).
- **`SoundBank`:**
  - `init` acquires.
  - `dispose` frees its own sources (`disposeSource`) and releases. It never calls
    `deinit`.
  - An open that fails is the legitimate "no audio" branch: `acquire` returns false, with
    no log. The catch-all at `sound_bank.dart:64` narrows to the open's exception type.
    Name it after reading `soloud.dart`'s `init`.
- **Tests in `sound_recipes`, with a fake device:**
  - An acquire held on a `Completer`, a release, then a second acquire: close never runs
    after the second open.
  - The last release closes exactly once.
  - Two banks share one open.
  - A failed open leaves the bank silent.
- **Test in `voxel_game`:** hold the title's open, enter a world, resolve the open; the
  device stays open, and the world's music plays.
- `title_music_test` runs on the fake device, never on SoLoud failing to load. That is
  what lets VD5 pass.
- Commit `sound_recipes, voxel_game: one owner of the audio device (VD3)`. `KL-024` closes.

### VD4 · `flutter_scene` 0.24.3 (`KL-027`)

The four pins (§What exists); `packages/voxel_scene/lib/src/{gpu_paced_scene,terrain_geometry}.dart`
and the files with `castsShadows`; `packages/voxel_scene/shaders/{terrain.frag,terrain.vert,terrain_depth.vert}`;
the rebuilt `packages/voxel_scene/assets/shaders/terrain.shaderbundle`; the `voxel_scene`
and `voxel_game` CHANGELOGs; `examples/voxel_game_minecraft/pubspec.{yaml,lock}`.

Retargeted on 2026-10-09 from 0.24.0 to 0.24.3, the latest on that day: it fixes three
regressions of 0.24.0 and keeps the kit off a version already three releases old. If a
newer 0.24.x is out when the step starts, take it and read its CHANGELOG first.

- **The method for the shaders.** Each of ours says what it is: 0.23's stock shader with
  one change.
  - `terrain.frag:3` is `flutter_scene_standard.frag` with a different `Surface()`.
  - `terrain.vert:1` is `flutter_scene_unskinned_body.glsl`.
  - `terrain_depth.vert:2` is its depth counterpart.

  Diff each against its 0.23 original to isolate that change. Then take 0.24.3's version
  of the same file and reapply the change. Do not patch 0.23's copy forward line by line.
  That way `ApplyDepthBias`'s second argument, `FrameInfo`'s 112 bytes, `FragInfo`'s new
  fields and `material_debug.glsl` with its `DebugViewInfo` branch all come with the new
  base. 0.24.3 has two lit tiers (the full one and a lean one); read which one a
  `PhysicallyBasedMaterial` subclass draws with before choosing the base, and say it in
  the comment. The comments say 0.24.3.
- **The opaque split.** Keep ours as one shader, with its `discard` under `alpha_mode ==
  1.0` (`terrain.frag:106-110`; VDD7, `KL-029`).
- **The terrain's geometry on the public path (FS1).** `TerrainGeometry` becomes an
  `UnskinnedGeometry` built the way MATERIALS.md §"A packed vertex format" shows:
  - `setVertexLayout` with the two `uint32x2` streams and the 80-byte instance record,
    `setVertexShader(TerrainVertex)`, `uploadVertexStreams([positions, attributes],
    vertexCount, indices: ..., indexType: ...)`, `setLocalBounds` as today;
  - `setDepthOnlyVertex(TerrainDepthVertex, positionStream: ...)` replaces the
    `depthOnlyVertex` override;
  - no `bind` override: the encoder binds the engine's `FrameInfo` once per shader
    (`scene_encoder.dart:1547`), so `terrain.vert` and `terrain_depth.vert` declare the
    block the engine fills. Read its layout from 0.24.3's `bindUnskinnedFrameInfo`, not
    from 0.23's 80 bytes. `_frameInfo` and its `Float32List(20)` go;
  - the `gpu` types come from `package:flutter_scene/gpu.dart`. The
    `invalid_use_of_internal_member` and `implementation_imports` ignores leave the file;
  - `materialVertexVariant`: read whether 0.24.3 still asks for it on a geometry with a
    vertex shader of its own. Keep the override only if a test fails without it.

  If the public path cannot express something the terrain needs, stop there: keep the
  `Geometry` subclass for that part, name the gap in `KL-027`'s closing line, and FS2
  carries it upstream. Do not reach back into `src/` for a member the public path lacks.
- **Rebuild.** `cd packages/voxel_scene && dart tool/build_shaders.dart` (rule 15).
- **`GpuPacedScene`:**
  - `warmUp` takes `Duration? sliceBudget` and `bool allShadingTiers` and forwards both.
  - Re-read 0.24.3's `warmUp` (`scene.dart:2044`) and correct the comment and the
    `_warming` span at `gpu_paced_scene.dart:83`.
  - Set `maxGpuFramesInFlight = 0` (VDD5), with a test that says so.
- **The deprecations.** `castsShadows: false` becomes `shadowCastingMode:
  ShadowCastingMode.off` everywhere (`grep -rn castsShadows packages`).
- **The pins.** The four move together: `0.24.3` exact in the three, `^0.24.3` in the app,
  whose `pubspec.lock` is regenerated with `flutter pub get`. A pin left behind fails
  version solving. The pin stays exact: `terrain_material.dart` (`gpu.RenderPass`),
  `gpu_paced_scene.dart` and `measured_scene.dart` (`rendererSubmissions`) still import
  `src/` (FS2).
- **Gates:**
  - The five suites green.
  - `grep -n "flutter_scene/src/" packages/voxel_scene/lib/src/terrain_geometry.dart`
    finds nothing.
  - Then the visual check: `cd packages/voxel_game/example && flutter run -d macos` and
    `cd packages/voxel_scene/example && flutter run -d macos`. You must see the terrain
    drawn, the sun's cascaded shadows, a torch lighting a wall at night, the selection
    outline, the first-person hand. The log must show no "Failed to bind uniform".
  - No benchmark (CLAUDE.md).
  - If the first draw crashes, the `DebugViewInfo` reasoning above is the lead; 0.24.1
    made the debug channels opt-in, so re-read whether the block is still bound.
- **CHANGELOGs** (`## Unreleased`, **Breaking**): `voxel_scene` and `voxel_game` need
  `flutter_scene` 0.24.3 exact, so a game that names `flutter_scene` moves with them.
  `voxel_scene`'s also says the terrain's geometry is now an `UnskinnedGeometry`.
- **Commits.** One for the kit (`voxel_scene, voxel_game: on flutter_scene 0.24.3 (VD4)`),
  then one for the app's constraint, as VL12 did. `KL-027` closes, and the remaining
  `src/` imports are listed in its closing line for FS2.

### VD5 · `flutter_soloud` 5 (`KL-026`)

`packages/sound_recipes/pubspec.yaml:25`, `lib/src/sound_bank.dart`, its CHANGELOG;
`.github/workflows/ci.yml` only if the first red run asks; the app's `pubspec.lock`.

- `flutter_soloud: ^5.1.6`, then `flutter pub get` at the root and in the app.
- `play`'s catch-all (`sound_bank.dart:88`) narrows to
  `SoLoudFailedToStartPlaybackCppException`. A full voice pool is the one legitimate
  silent branch left, since 5.x reports a device that fails to start on
  `audioDeviceStartFailures`. Read `:203` and give it the same treatment, or say why it
  stays.
- Suites green locally. The build hook's first run takes about a minute.
- **The CI.** The hook compiles C and downloads prebuilt Xiph libraries on every job that
  resolves `sound_recipes`, which is all of them through the workspace.
  - **Gate:** push to `dev`, with the owner's word since it is outward-facing.
  - Install what the first red run names, nothing guessed, as VL1 did.
  - Cache `.dart_tool/hooks_runner` only if the runs are slow enough to matter.
- See it on the Mac: `cd packages/voxel_game/example && flutter run -d macos` plays the
  title music and a block's sound. That is a listening check, not a benchmark.
- CHANGELOG `sound_recipes` (`## Unreleased`, **Breaking**): needs `flutter_soloud` 5, whose
  native build moved to build hooks.
- Commit `sound_recipes: on flutter_soloud 5 (VD5)`; the app's lock in its own commit if it
  changes. `KL-026` closes.

### VD6 · Ready to release

As VL12, on `0.5.0-dev`:

- **CHANGELOGs.** Each opens `## 0.5.0-dev` with its **Breaking** list, and every line maps
  to a commit of `git log a8ef77d.. -- packages/<p>/lib`.
- **Versions and constraints.** `0.5.0-dev` in the four, and `^0.5.0-dev` in the four,
  both examples and the app.
- **`PUBLISHING.md`** names `0.5.0-dev`.
- **Score before publishing (VL13's lesson: a dry run scores nothing).**
  `tool/publish_package.sh --dry-run` also runs pana and prints the points. Use pana
  0.23.19 or newer, against the Flutter in use. Expect 160 each.
- **pub's grace.** Check `dart pub outdated` in each package: a newer major past its 30
  days would cost points right after publishing, as `flutter_soloud` did.
- **`pointer_lock`.** If a version that declares more platforms exists by then, raise its
  constraint and close `KL-028`. Otherwise it stays `Waiting:`.
- **Gate:** the four dry runs green: only the accepted warnings, pub's "not an incremental
  update" hint, and 160 from pana.

### VD7 · `0.5.0-dev` out

The owner gives the word in that session; publishing cannot be undone. **Before
2026-11-04**, when the 0.4.0-dev pin would cost its points.

- `tool/publish_package.sh` for the four, in order (it waits for each dependency's
  analysis), or by hand as the owner did for VL13. Either way, record which.
- Tag each package at the release commit (`<package>-v0.5.0-dev`) and push the tags.
- Read the four reports on pub.dev, and record the points and any new warning in this
  row. A new warning goes to the ledger.

## Out of scope

- The app's visual leftovers (VLD4): the bow's and staff's fan and arc, the abilities'
  particles, coloured damage numbers, the dash's pose. A later app plan.
- The chest minecart (`VAD24`).
- `KL-004`'s fix (VLD3): a Windows or Linux machine lifts it.
- The terrain's opaque/masked split (`KL-029`, VDD7) and adopting `flutter_scene`'s own
  GPU pacing instead of `ScenePacer` (VDD5). Both change the frame, and both are the
  owner's call when they want numbers.
- Any benchmark.
