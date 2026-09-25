# Architecture Ledger — the voxel kit

> Where rule 17 (`CLAUDE.md`) writes. One entry per structural observation found mid-task
> that was **not** the task. Four mandatory fields: `Lens`, `Evidence` (`file:line`),
> `Cost of leaving it`, `Found while`. An entry is recorded here and **not fixed in the
> commit that found it**. An entry that gets fixed moves to `## Closed` with a fifth field,
> `Closed by`; it is never deleted.
>
> **IDs.** The first three entries were written in the app's ledger
> (`poc_cubeworld/docs/LEDGER.md`), whose IDs are `CL-nnn`, and moved here on 2026-09-22
> with their IDs kept, so every citation of them still finds them by name. **New entries
> here are `KL-nnn`, from `KL-001`**: once this folder is a repository of its own, two
> ledgers handing out the same `CL-` counter would collide the first time both added an
> entry, and a separate prefix is what the app's ledger chose for the same reason.

## Open

### CL-005 · The kit's whole top half is exercised only by an example nothing runs

- **Lens:** testing / kit surface
- **Evidence:** `DefaultHud` (108 lines), the kit's `InventoryScreen` (181) and `VoxelGameWidget` (`packages/voxel_game/lib/src/ui/voxel_game_widget.dart:256,260`, which wires both) are reachable from exactly one place: `packages/voxel_game/example/lib/main.dart:4`, a one-line app. `packages/voxel_game/test/` holds three files (`game_test.dart`, `goal_test.dart`, `net_game_test.dart`) and none of them mounts a widget. The app the kit was extracted from never touches them — the app's `lib/src/ui/game_view.dart:128` (in `poc_cubeworld/`) builds its own `InventoryScreen` (352 lines) and its own HUD (809).
- **Cost of leaving it:** the split itself is right (rule 7 — the kit ships a default, the game ships Dawnforge's), but the default has no witness. Rule 18 says a stage is done when it was seen running, and this surface has been seen running once, by whoever last opened the example by hand. A `flutter_scene` upgrade, a shader bundle rebuild or an `InputMap` change can break the kit's only out-of-the-box screen and every test still passes, because the app that would have noticed draws its own.
- **Found while:** 2026-09-21 — answering why `lib/` imports `voxel_game` in only two files.
- **Moved:** 2026-09-22 (`VR3`) from `poc_cubeworld/docs/LEDGER.md`, ID kept. Paths rewritten from this folder; the app's files are named as the app's. Kit paths rewritten again on 2026-09-23, when `voxel_game` moved under `packages/`.

### CL-008 · The decision register still answers questions about packages that no longer exist

- **Lens:** docs / stale SSOT
- **Evidence:** `docs/VOXEL_KIT_PLAN_2026-09-18.md:415` (`VKD1`) records the decision as "**Five packages**, the kit on top" and justifies it with "a game that only wants the world takes `voxel_worldgen` + `voxel_scene`"; `:418` (`VKD4`) says the noise is copied "into `voxel_worldgen`". `VC1` (`8a2b9853`) folded `voxel_worldgen` and four others into `voxel_engine` and `VC2` (`e349d46e`) renamed `voxel_audio`, so both decisions cite packages that were deleted two days later. `docs/VOXEL_CONSOLIDATION_PLAN_2026-09-19.md` records the new answer but does not mark the old one superseded, and `VKD1` is the entry a reader reaches first, since it is the register's first row.
- **Cost of leaving it:** a decision register is consulted precisely when somebody is about to re-litigate a settled question — `CLAUDE.md` rule 4 (the app's and this folder's) ("a new package earns its place by an optional heavy dependency, never by being a different subject") is the *current* answer and it contradicts `VKD1` as written. The failure mode is a future session splitting a subject back out on the authority of the register, which is doing exactly what it was built to prevent.
- **Found while:** 2026-09-21 — answering why `lib/` imports `voxel_game` in only two files.
- **Moved:** 2026-09-22 (`VR3`) from `poc_cubeworld/docs/LEDGER.md`, ID kept. Paths rewritten from this folder; the app's files are named as the app's.

### CL-009 · The kit reads a finger and draws no thumb

- **Lens:** kit API / rule 13
- **Evidence:** `CL-003` moved the gesture half of the touch scheme into `InputMap` — a finger on the world mines, uses and looks, and `touchMove` / `setTouchHeld` / `touchDigit` accept an on-screen stick, button and slot. Nothing in the kit calls those three. `packages/voxel_game/lib/src/ui/default_hud.dart` (108 lines) is a `CustomPainter`'s worth of bars and a hotbar, and `voxel_game_widget.dart:249-259` stacks exactly three children over the world — the HUD inside an `IgnorePointer`, and the inventory screen. The controls that do call them are the app's: its `lib/src/ui/touch_controls.dart` (368 lines, in `poc_cubeworld/`), and they are positioned against the app's own HUD geometry (`:86` and `:142` both measure `Hud.hotbarSlotRect`, the app's `lib/src/ui/hud.dart:56`), which is why they did not rise with the rest.
- **Cost of leaving it:** the half that rose is the half that is hard — the tap-versus-hold-versus-drag rule, tuned against a real device once. The half left behind is the visible one, so the kit now *reads* a phone without *looking* like it can be played on one: a game built on `voxel_game` gets mining and looking from a finger and no way to walk, jump or open its bag. The gap is also the wrong shape for a first-time reader, who will conclude touch is unfinished rather than half-delegated. Closing it means the kit's HUD has to publish its hotbar geometry (the one thing the app's layer needs), which is the same conversation as `CL-005` — the kit's default HUD is witnessed by nothing but an example — so the two should be answered together, and by a layout the kit owns rather than a copy of Dawnforge's.
- **Found while:** 2026-09-21 — closing `CL-003`, checking what did *not* rise with the input map.
- **Moved:** 2026-09-22 (`VR3`) from `poc_cubeworld/docs/LEDGER.md`, ID kept. Paths rewritten from this folder; the app's files are named as the app's. Kit paths rewritten again on 2026-09-23, when `voxel_game` moved under `packages/`.

### KL-001 · The agent instructions still describe a folder inside Dawnforge

- **Lens:** docs / AI context
- **Evidence:** `CLAUDE.md:4-13` (and `AGENTS.md`, the same file) say the folder may "still be `poc_cubeworld/packages/voxel_game/` inside the Dawnforge repository", that Claude Code "also loads the app's `CLAUDE.md` and the 2D track's", and `:165-167` tell commits to follow that repository's `poc(voxel)` prefix. The folder is the root of `github.com/fluttely/voxel_game` (`git remote -v`), whose history starts at `9e55c57`; none of those files is loaded any more, and rules still cite their numbers there (`app 17`, `app 20`, `app 21`) as the source.
- **Cost of leaving it:** every session reads a third of its orientation about a repository it is not in, and the commit convention it is handed is conditional on a state that no longer holds, so two sessions can pick two formats. It is also the first thing to settle before standardising releases across the four packages, which is where the instructions are meant to go next.
- **Found while:** 2026-09-23 — moving `voxel_game` under `packages/`.

### KL-002 · A peer that hangs up surfaces as an unhandled write error on the host

- **Lens:** error handling / transport
- **Evidence:** `packages/voxel_engine/lib/src/net/connection.dart:71-73`: `send` checks `isClosed` and calls `socket.writeln`. A write to a socket whose peer is gone fails asynchronously (a `Socket` reports write errors through its `done` future), and nothing in `NetConnection` handles it; `:27` handles errors on the read side only. Two `--host --wait-peer` runs of `examples/voxel_game_minecraft` logged `Unhandled Exception: SocketException: Write failed (OS Error: Broken pipe, errno = 32)` and `Connection reset by peer (errno = 54)`, each when the client process exited.
- **Cost of leaving it:** a Flutter host only logs it and plays on. The engine is meant to run under plain Dart too (`CLAUDE.md` rule 3), and there an unhandled async error in the root zone ends the process, so a dedicated host would crash every time a client quit mid-broadcast. The loss is also invisible to the protocol: `send` returns normally for a message that never left.
- **Found while:** 2026-09-23 — probing the minecraft example's multiplayer fix (a client joining a hosted playground).

### KL-003 · The kit's host keeps a far client's edit but never passes it on

- **Lens:** replication / correctness
- **Evidence:** `packages/voxel_game/lib/src/net/sessions.dart:83-84`: a client's `set` goes through `GameWorld.storeEdit` (`packages/voxel_game/lib/src/world/game_world.dart:186-192`). When the host has not loaded the chunk, that call records the edit through the streamer and does not run the listeners, and `_edited` (`sessions.dart:101`, registered at `:51`) is the only thing that broadcasts. The other clients are never told, and a client that joins later gets the edit only because the hello carries the whole delta.
- **Cost of leaving it:** with two clients far from the host, one of them breaks or places a block and the other never sees it until it rejoins; its world disagrees with the host's, collision included. The example app had the same gap and closes it by broadcasting explicitly when the host stores an edit it could not write (`examples/voxel_game_minecraft/lib/src/game/net.dart`, `_onBlockRequest`).
- **Found while:** 2026-09-23 — fixing the example's lost edits in unloaded chunks.

### KL-004 · Windows and Linux get a drag to look, not a locked mouse

- **Lens:** platform parity / input
- **Evidence:** `packages/voxel_game/lib/src/input/input_map.dart:180-191`: the look is `pointer_lock`'s when `PointerLock.instance.isSupported`, and a drag otherwise. `pointer_lock` 0.4.1 registers only `macos` (and web), and its method channel answers `isSupported` false on every other target (`pointer_lock_method_channel.dart:28`). So a desktop with a mouse on Windows or Linux falls into the phone's branch: the cursor stays free and visible, and the view turns only while a button is held down. Both examples gained `windows/` and `linux/` runners on 2026-09-24, and neither has been built or run on those systems.
- **Cost of leaving it:** the kit says it targets every platform Flutter supports, but a first-person game on two of the three desktops plays like a touch screen with a mouse. Nothing tells a game author about it: `pointerLockSupported` is public, but the README never mentions it.
- **Found while:** 2026-09-24 — adding Windows and Linux runners to the examples, for the launch post.

### KL-006 · The minecraft example measures the published kit, not this tree

- **Lens:** testing / witness
- **Evidence:** `examples/voxel_game_minecraft/pubspec.lock` resolves `voxel_engine`, `voxel_scene` and `voxel_game` as `hosted` (pub.dev, with a `sha256`), and there is no `pubspec_overrides.yaml` beside it. Its `tool/perf_loop.sh` and its probe flags therefore run whatever 0.1.0-dev pub.dev holds. Its `CLAUDE.md` still describes itself as `poc_cubeworld/` with the kit under `packages/voxel_game/`.
- **Cost of leaving it:** the app that plays the kit hardest is not a witness of a kit change until the change is published, so a regression in the tree reaches it only after a release. It is also why the frame-rate plan (`docs/VOXEL_PERF_PLAN_2026-09-25.md`) measures the kit's own example instead.
- **Found while:** 2026-09-25 — `PF0`, choosing the game to benchmark.

### KL-007 · Every drop and every projectile meshes a geometry of its own

- **Lens:** rendering / draw batching
- **Evidence:** `packages/voxel_game/lib/src/entities/item_pickup.dart:50` builds a `VoxelModelMesh.node` for each drop from the item's colour, and `packages/voxel_game/lib/src/entities/projectile.dart:98` a `CuboidGeometry(size)` for each shot. flutter_scene 0.23 batches only render items with the identical geometry and material (`render/instance_batching.dart`, `opaqueBatchEnd` / `depthBatchEnd`), so each of them is a draw of its own in the colour pass and, being a moving caster, in every shadow cascade each frame. That is what the creatures' rigs cost before PF7 (`e770ef0`): 260 parts, 6.1 ms of the phone's shadow pass.
- **Cost of leaving it:** a mined-out room or a skeleton volley puts dozens of identical cubes on screen, each drawn once a pass; on the phone that is the encode PF7 just won back from the creatures. The fix is the rigs' one: a geometry per item kind and per projectile size, made once and shared.
- **Found while:** 2026-09-25 — PF7, sharing the creatures' meshes.

## Closed

### KL-005 · Windows and Linux builds of the examples cannot render in release

- **Lens:** platform parity / build
- **Evidence:** `packages/voxel_game/example/windows/runner/main.cpp` and `packages/voxel_game/example/linux/runner/my_application.cc` (and the minecraft example's) never switch Flutter GPU on. flutter_scene 0.23.0's README (`~/.pub-cache/hosted/pub.dev/flutter_scene-0.23.0/README.md:128-146`) says a Windows or Linux runner does it with `DartProject.set_enable_flutter_gpu` / `fl_dart_project_set_enable_flutter_gpu`, which exist only from Flutter 3.47.1; on 3.47.0 (this machine) only a command-line flag does, and release builds compile it out.
- **Cost of leaving it:** the runners added on 2026-09-24 build, launch and draw nothing in release; `KL-004`'s look-by-drag is moot until they draw. The fix is two lines per runner, but only after the Flutter upgrade, and the bundle must be rebuilt then too (`CLAUDE.md` rule 15).
- **Found while:** 2026-09-25 — `PF0`, deciding which platforms the benchmark can measure.
- **Closed by:** 2026-09-25 — Flutter 3.47.5 on this machine (the shader bundle rebuilt byte for byte the same), and `voxel_game example: the Windows and Linux runners turn Flutter GPU on`, which adds the call to both runners and has the kit require Flutter 3.47.1. The minecraft example's runners (`examples/voxel_game_minecraft/`) got the same two lines in `examples/voxel_game_minecraft: the Windows and Linux runners turn Flutter GPU on`, after this entry wrongly said that example lived in another repository.
