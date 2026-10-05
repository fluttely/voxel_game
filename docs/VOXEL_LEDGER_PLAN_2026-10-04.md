# The ledger-and-release plan (VL) — 2026-10-04

**Question.** The absorption plan (`docs/VOXEL_ABSORB_PLAN_2026-09-30.md`) closed with the
minecraft example on the kit and ten entries open in `docs/LEDGER.md`, most of them found
while porting it: a copy the app still writes because the kit has no field for it, a
screen a pad cannot work, a desktop host that stops when its window hides. pub.dev holds
`0.3.0-dev` (2026-09-29), and 98 commits have landed since. What does the kit settle
before its next version, and how does that version go out?

**Answer, in one line.** First a CI that guards everything after it, then the ledger's
API gaps (each one deletes a copy in the app), the pad's reach and the loop's two
entries, and last `0.4.0-dev` of all four packages, tagged, so the API breaks once.

Closes `KL-013`, `KL-014`, `KL-016`, `KL-017`, `KL-018`, `KL-019`, `KL-020`, `KL-022` and
`KL-023`, plus two gaps the VA-Z row left (`VA-Zl`'s "Not ported"). Defers `KL-004` with
its limit documented. Ships `PUBLISHING.md`'s one remaining item, the CI.

Every decision below was the owner's answer on 2026-10-04 (§Decisions). Found by reading
the code; every `file:line` is from 2026-10-04, so re-check it before a step starts.

---

## Progress

| Step | State | Gate |
|:---|:---|:---|
| VL0 This plan, and the owner's answers to §Decisions | **done** 2026-10-04: every recommendation taken (VLD1–VLD12) | the owner answers VLD1–VLD12 |
| VL1 A CI for the workspace and the app | **done** 2026-10-05 (`23bd795`, `925958f`, `a4c3a60`): `.github/workflows/ci.yml`, one analyze-and-format job and a matrix with one job per suite. Run #5 green on the first push, the counts the same as on the Mac (421 · 244 · 49 · 7 · 99); nothing failed only on Linux, and no native library had to be installed. Before it, the format check found the app written at 120 columns but declaring no page width (58 files rewrapped at 80) and two kit files drifted: fixed in `23bd795`. Next: VL2 on `opus 5.5:medium` | a push to `dev` runs analyze, the format check and the five suites on GitHub Actions, green; the README carries its badge; `PUBLISHING.md`'s "Before the first release" is empty |
| VL2 `copyWith` on a creature's specs (`KL-018`) | **done** 2026-10-05: `copyWith` on `MobSpec`, `SpawnRule`, `ProjectileSpec` and the ten behaviours with fields, nullable fields by `ValueGetter`; 13 tests in `creature_copy_test.dart` (the kit 434). The app's elites, weighed spawns and harder strikes are `copyWith` calls; its old copy had always spawned an elite alone (`group` left at `(1, 1)`), which the new one keeps on purpose. Next: VL3 on `opus 5.5:high` | the app's elites are built by `copyWith`; a test per spec shows a field left out is kept and a nullable one can be asked for null |
| VL3 A new world's start declared (`KL-023`) | **done** 2026-10-05: `VoxelGameSpec.spawn` answers a `SpawnPoint` (column and yaw) from a world's options, not from `WorldInfo` as VLD10 wrote it: a game in no slot (a test's, one made in code, the app's `exhibits_test.dart`) has options and no info, and `playerFor`/`worldFor` already take options. `_begin` stands the column and the yaw before the first step; a save, a client's too, never asks it. 3 tests in `spawn_test.dart` (the kit 437). The app's `Playground.spawnFor` answers the hub, its `_begin` only hands out the kit, the level and the morning; the start's pitch (-0.1) went with the move, the kit's -0.2 stands (the app 101). Next: VL4 on `opus 5.5:high` | `VoxelGameSpec.spawn` places the player in `_begin`; the app's `Playground` no longer waits for `game.ready` to move them |
| VL4 A title's own music (`KL-019`) | **done** 2026-10-05: `TitleSpec.music` names a track; `TitleScreen` plays it on a bare `SoundBank` closed in its `dispose`, before the game widget's first await reaches its own bank. The mapping is `GameMusic` (`lib/src/audio/`), which the game widget plays through too, at `GameSettings.musicGain`, one at a time (`GameMusic.playing`: a second one throws, so the order is asserted, not hoped for). The widget now keeps its music silent where there is no audio device, as the title does, which is what lets a headless test see the track asked for. 6 tests in `title_music_test.dart` (the kit 443); the app's `TitleVista` opens no audio, `gameTitle` names `titleTrack`, one test in `game_title_test.dart` (the app 102). A title left while its device still opens closes it late: `KL-024`, recorded, not fixed. Next: VL5 on `opus 5.5:high` | `TitleSpec.music` plays through the kit's mapping and follows the slider live; the app's title vista opens no `SoundBank` |
| VL5 A game's own player settings (`KL-020`) | **done** 2026-10-05: `GameSettings.game`, JSON frozen and checked as it is built, compared by value, `settings.json` at version 3 (1 and 2 read it empty). `VoxelGame.startHeadless` took `settings` too, beyond the step's text: without it a test could not start a game on a machine that has seen the tutorial, since the tutorial and a save's restore read the settings before the first step. 4 tests in `settings_test.dart` (the kit 447). The app's `tutorialOption` is gone; `Tutorial.doneKey` (`tutorialDone`) is read at its start and on a save's restore, and set on its end or skip through `applySettings`; the app's tests rewritten around it, none added (the app 102). Next: VL6 on `opus 5.5:high` | `GameSettings.game` round-trips through `settings.json`; the app's tutorial is shown once per machine again and `tutorialOption` is gone |
| VL6 A stock structure's plan (`KL-022`) | **done** 2026-10-05: `DungeonPlan.of(dungeon, site, roll)` and `MinePlan.of(mine, site, roll)`, in world cells; both drawings read them. The step's `of(site)` takes the structure and the roll beside the site: a game holds a `PlacedStructure`, never a `StructureSite` (it needs a chunk's writer), and a plan reads the structure's own fields (`floorY`, the lengths, whether it has a spawner or a chest). `SpecGenerator.rollOf(site)` and `StructureSite.placed` (new) make the two sides' rolls one. 3 tests in `stock_structures_test.dart` (the engine 247). The app's `Structures` reads both plans and only the spawner cell itself, to see the block is still there. Found while: the dungeon's doorways are bricked over by the rooms drawn after them, `KL-025`, left open. Next: VL7 on `opus 5.5:high` | `DungeonPlan` and `MinePlan` are what the drawing and the game both read; the app's `Structures` scans no cell |
| VL7 A boss marked on the creature, a cart's start speed | **done** 2026-10-05: `Mob.boss`, seeded from `MobSpec.boss`, read by `VoxelGame.boss`, kept in `Mob.row` (`game.json` version 10; a version 9 save marks each creature as its species is) and carried to a client's replica (`'b'` in the host's state), which the step's text did not name but a client's boss bar needs. `Minecart.push(speed)`, not a constructor parameter: `placeVehicle` is every vehicle's path and a client's hand-off, and a cart pushed there would need a speed on both; `push` asserts 0 to `CartSpec.maxSpeed`. 5 tests (the kit 452). The app's plate summon and `Structures._wake` mark their creature (the arena's troll and boomer, the dungeon's troll), and Boss Slayer reads `Mob.boss`; the old cart's start speed lived only in its debug probes, gone with VA-Zm2, so the app's spec wants none (the app 102). Next: VL8 on `opus 5.5:high` | a summoned troll shows the boss bar, and the save keeps it; a cart can start rolling |
| VL8 A pad steps the hotbar (`KL-016`) | **done** 2026-10-05: `VoxelAction.hotbarNext` / `hotbarPrevious` on the right and left bumpers, no key; `PlayerEntity.tick` adds a press of each to the wheel's steps, around the bar both ways. `checkActions` needed no change: it refuses a button pressed twice and never asked that every action be bound, so a game binding only `hotbarNext` already passes, and a game action on a bumper now throws until the game moves the kit's (breaking, in the CHANGELOG). 2 tests (the kit 454). The app: `hotbarNext` on `dpadLeft`, `hotbarPrevious` unbound, the abilities on the bumpers; the tutorial's skip keeps F6 and leaves the pad for `TutorialScreen`, Tutorial in the game menu while the tutorial runs; the pad lines of `controls_screen.dart` and the README say so. 2 tests (the app 104). Next: VL9, split at its start, on `opus 5.5:high` | the bumpers step the slot in the kit's example; the app's `dpadLeft` steps it forward |
| VL9 A pad and the arrows work every screen (`KL-013`) | **split** 2026-10-05 into VL9a–VL9d, one commit each; `KL-013` closes with VL9d | a widget test drives the pause menu, the bag (pick, half, place, craft), settings, the title and the world list with pad events alone, and the same with arrows/Enter/Esc |
| VL9a The intent bridge in `GameSurface` (VLD5), and the simple menus: pause, death, settings, credits | **done** 2026-10-05: `FocusBridge` (keys and pad presses to the focus intents, a held direction repeating from the bridge's own timer, acting only while the focus is under the surface) and `ScreenFocus` (a scope per screen, `NavigationMode.directional`, a white ring on the focused button), both exported; `InputMap.interceptPad` hands the bridge a pad press before the map records it, so a press that worked a screen is not a jump after it closes. Backing out (B, Esc) is `input.tap(VoxelAction.pause)` from a `DismissIntent` action above the surface's `Focus`: the arbiter still decides what pause means on each screen, and a screen may take `DismissIntent` itself. A slider's arrows are its own shortcuts, but a pad reaches it as a `DirectionalFocusIntent`, so `SettingsPanel`'s sliders take left and right as their step (a game's own `Slider` gets the arrows, not the pad, unless it does the same). A screen with no `autofocus` gets its scope focused, so the first direction lands on it. Directional mode is what lets a disabled Respawn hold the focus until it wakes. The credits (the title's) open on Back and are tested by keys; their pad test needs the title's bridge, VL9c. 8 tests in `screen_navigation_test.dart` (the kit 462); with the bridge cut, 6 of them fail. Next: VL9b on `opus 5.5:high` | while a screen is open, the dpad, the left stick, A, B and the arrows, Enter, Space, Esc reach the screen as focus intents and not `InputMap`; each of the four opens with a focus and draws it; a widget test works each one with pad events alone and again with keys alone |
| VL9b The bag as a focusable grid, crafting included | **done** 2026-10-05: each slot is a `FocusableActionDetector` whose `ActivateIntent` and `SecondaryActivateIntent` (new, exported) call the `_click` a tap and a right-click call; the bag opens on the slot in hand; a focused slot is filled and ringed by a foreground decoration, so the ring does not move it. X is `SecondaryActivateIntent`, and its key is **X** (decided here, rule 13): no kit or app binding uses it, and it matches the pad's label. Shift+Enter was weighed and dropped: the bridge would have to keep Shift's state, and shift-click means a quick move to a Minecraft player. The bridge takes X **only where the focus has an enabled action for it** (`Actions.maybeFind`), so off a slot the pad's X stays the app's dodge and the key types in a text field. The held stack and the tooltip go to the focused slot's top-right corner (a `_Pointer` marked `focus`, whose slot a mouse's move forgets). Right from the hotbar's last slot lands on the first recipe tile, up from it on the close button; `ScreenFocus` now rings `IconButton`s and sets `focusColor` to `ScreenFocus.fill` (white24), so a focused list tile (the recipes, the settings' rows) is easier to see. A held stack has no pad or key way to be thrown outside the panel; B closes the bag and stows it, as closing always did. 3 tests in `screen_navigation_test.dart` (the kit 465). Not yet seen on the Mac by the owner. Next: VL9c on `opus 5.5:high` | a slot takes focus; A picks up and puts down, X takes half, through a click's handlers; a widget test picks, halves, places and crafts with pad events alone and again with keys alone |
| VL9c The title, its choice and the world list | pending | outside `GameSurface`, the same bridge on their own `Focus`; a widget test enters a world from the title with pad events alone and again with keys alone |
| VL9d The app's own screens (`examples/voxel_game_minecraft`), `TutorialScreen` and `PlaygroundScreen` included | pending | each one the app declares is worked by a pad and by keys in a widget test; a custom widget that took no focus takes it; `KL-013` closed in the ledger |
| VL10 A hidden window keeps stepping (`KL-014`) | pending | a test that turns the lifecycle to `hidden` sees steps advance with no frame; the Mac example, covered by another window, keeps its clock moving |
| VL11 The scene's frames in the frame report (`KL-017`) | pending | `FrameStats` and `FrameReport` carry the scene frames rendered beside the Flutter ones; a paced game's readout shows the rendered rate |
| VL12 Ready to release | pending | CHANGELOGs under `## 0.4.0-dev`, READMEs and `PUBLISHING.md` current, `KL-004` deferred in the ledger, the four dry runs green |
| VL13 `0.4.0-dev` out | pending; **the owner's word in that session** | the four on pub.dev, 160 points each; four tags pushed |

Effort per step: VL1 `medium` (a YAML file and a badge, no judgement in the kit), VL2
`medium` (mechanical, with KL-010's settled pattern), VL3–VL7 `high` (kit API a game
reads), VL8 `high`, VL9 `high` (a focus model across every screen; the step splits itself
first), VL10 `high` (the loop's authority, rule 12), VL11 `medium`, VL12 `medium`, VL13
`low` (a checklist, with the owner present).

---

## What exists (read before VL1)

- **Releases.** The four packages are on pub.dev at `0.3.0-dev`, published together on
  2026-09-29 (`34d7a6e`). Since then, 22 commits touched `voxel_engine/lib`, 6
  `voxel_scene/lib`, 2 `sound_recipes/lib` and 62 `voxel_game/lib`. **Two CHANGELOGs are
  wrong**: `voxel_engine` (+165 lines) and `voxel_scene` (+52) wrote what came after the
  release under the published `## 0.3.0-dev` heading. `sound_recipes` and `voxel_game`
  use `## Unreleased`, which is right. VL12 moves the extra lines under `## 0.4.0-dev`.
  No git tag exists.
- **CI.** There is no `.github/` folder. `PUBLISHING.md` lists the CI as the one item
  still to do before the first release. The minecraft example sits outside the workspace
  and resolves the four packages through path overrides (`KL-006`), so it gets its own
  `flutter pub get`.
- **Flutter.** 3.47.5 on this machine; the kit requires `>=3.47.1` (`packages/voxel_game/pubspec.yaml:19`).
- **Suite.** analyze clean; `voxel_game` 421, `voxel_engine` 244, `voxel_scene` 49,
  `sound_recipes` 7; the app 99.
- **The pad today.** `VoxelAction.defaultBindings.gamepad`
  (`packages/voxel_game/lib/src/input/voxel_action.dart:76-86`) leaves both bumpers, X,
  dpad left, back, home and the touchpad free. The app takes all of them
  (`examples/voxel_game_minecraft/lib/src/spec/game_spec.dart:131-148`): bumpers for its
  two abilities, X for dodge, touchpad for the journal, back for the map, home for its
  controls, dpad left to skip the tutorial.
- **Screens.** `packages/voxel_game/lib/src/ui/`: `pause_menu`, `death_menu`,
  `settings_menu` + `settings_panel`, `inventory_screen`, `title_screen`, `title_choice`,
  `world_list`, `credits_roll`, plus a game's own (`ScreenSpec.build`). Only
  `game_surface.dart`, `title_screen.dart` and `voxel_game_widget.dart` hold a `Focus`, and
  `GameSurface`'s `Focus` hands every key to `InputMap.onKey`, which answers handled.
- **The loop.** No code reads `AppLifecycleState`. `VoxelGame.frame` runs from the loading
  ticker and `SceneView.onTick` only (`voxel_game_widget.dart`, `KL-014`).
- **Settings** carry a `version` and read their own and version 1
  (`packages/voxel_game/lib/src/settings/game_settings.dart:125-140`).
- **Boss.** `VoxelGame.boss` (`packages/voxel_game/lib/src/core/voxel_game.dart:1272`)
  is the first live creature whose `spec.boss` is set; the app's playground summons a
  troll or a boomer (`examples/voxel_game_minecraft/lib/src/playground/playground.dart:481`)
  whose species is not a boss.
- **Cart.** `Minecart._speed` (`packages/voxel_game/lib/src/vehicles/minecart.dart:56`)
  has no setter, so a cart starts still.
- **KL-004** is already in the kit's README (`packages/voxel_game/README.md:293-294`).
  `InputMap.pointerLockSupported` (`input_map.dart:241`) does not say it.

## Decisions

| ID | Decision | Why |
|:---|:---|:---|
| VLD1 | **One plan: CI → the ledger's debts → release.** (Owner, 2026-10-04.) | The CI guards every later step. The debts are API changes, so landing them before the version breaks the API once, and the version ships without the copies the app still writes. Releasing first would add a second break soon after. |
| VLD2 | **The version is `0.4.0-dev`**, all four together. (Owner.) | The API still moves (VL9 changes the screens), and `-dev` says so, as every version has. Below 1.0 a break moves the minor. |
| VLD3 | **`KL-004` is documented and deferred.** (Owner.) The README already says it; VL12 adds it to `pointerLockSupported`'s doc and gives the ledger entry a `Deferred:` line naming what lifts it: a Windows or Linux machine to see a fix run. | A fix is native code (upstream in `pointer_lock`, or a plugin the kit would carry), and nothing here can run it. |
| VLD4 | **Of VA-Z's "Not done", only the kit's two gaps join** (VL7): a boss on the creature, a cart's start speed. (Owner.) The bow's and staff's fan and arc, the abilities' particles, coloured damage numbers and the dash's pose stay the app's, for a later app plan. The chest minecart stays dropped (`VAD24`). | Those four are the app's look, not a field a second game would want. The two gaps are what the app could not port for want of a setter or a flag. |
| VLD5 | **A pad and the arrows work a screen through Flutter's focus.** (Owner.) While a screen is open, `GameSurface` turns the dpad and left stick (and the arrows) into `DirectionalFocusIntent`, A (and Enter, Space) into `ActivateIntent`, B (and Esc) into `DismissIntent`, and X into the bag's half. The kit's buttons and slots take focus; a game's screen built of Material buttons gets the pad for free. The bag is a focusable grid: A picks up and puts down the stack, X takes half, through the same handlers a click uses. | Rule 13 asks for parity on every surface, and the arrows come with it. A virtual cursor was weighed and dropped: it fakes pointer events and does nothing for a keyboard. |
| VLD6 | **A game's player-wide preferences live in `GameSettings.game`**, JSON the kit never reads, saved and read with the rest. (Owner.) | `Mob.data`'s pattern (`KL-021`). Declared setting rows were weighed: a hidden flag such as "tutorial seen" is not a control the player should see. |
| VLD7 | **A hidden window steps from a `Timer`**, at the fixed step's rate, whenever the lifecycle says `hidden`, a lone game included. (Owner.) | Rule 12 (no global pause). A phone in the background is suspended by its system anyway, so one rule is enough and there is no host-only branch to test. |
| VLD8 | **The CI is GitHub Actions on `ubuntu-latest`, Flutter pinned to 3.47.5**, on every push to `dev` and `main` and on every PR: `flutter analyze`, `dart format --set-exit-if-changed` (page width 120), the four packages' suites and the app's. (Owner.) | It is the cheapest runner, and nothing in the suites needs a GPU. If a `voxel_scene` test turns out to need macOS, only that job moves. No shader `--check` in CI: the bundle is tied to the engine that built it, and rule 15 already makes rebuilding it a local step. |
| VLD9 | **`hotbarNext` / `hotbarPrevious` on the bumpers by default; a game may bind only one** (next wraps around). (Owner.) The app keeps its abilities on the bumpers, binds `hotbarNext` to dpad left, and moves its tutorial skip into the game menu, as its playground actions already are. | It is Minecraft's own layout. The app's pad has no two free buttons, and one stepping forward is enough on a nine-slot bar. |
| VLD10 | **`VoxelGameSpec.spawn`: a function of `WorldInfo` giving a column (x, z) and a yaw, or null for the spiral.** (Owner.) | It works like `worldFor`, which shapes a world by its options: a playground and a plain world in one game start in different places. A fixed column cannot tell them apart. |
| VLD11 | **`Mob.boss` is the creature's own flag**, seeded from `MobSpec.boss`, set by a game's system on a summon or a wake, read by `VoxelGame.boss` and kept in the creature's save row. (Owner.) | It is one field. A `bossOf` hook on the spec was weighed: it would be a callback on every HUD frame. |
| VLD12 | **Each package gets a tag at a release**: `voxel_engine-v0.4.0-dev` and the other three, pushed with the version. (Owner.) | `PUBLISHING.md` tells a git dependency to pin a tag, and none exists. |

## Steps

### VL1 · A CI for the workspace and the app

`.github/workflows/ci.yml` (new). It is the repository's own file, so it needs no CHANGELOG.

- One workflow with `subosito/flutter-action` pinned to 3.47.5 stable and the pub cache
  cached. Jobs, matching CLAUDE.md's suite: `flutter pub get` at the root, `flutter
  analyze`, `dart format --output=none --set-exit-if-changed packages
  examples/voxel_game_minecraft`, then each suite (`flutter test` in `voxel_game`,
  `voxel_scene`, `sound_recipes`; `dart test` in `voxel_engine`; `flutter pub get &&
  flutter test` in `examples/voxel_game_minecraft`). Use a matrix or one job: whichever
  keeps a red suite's name visible on the PR.
- Native libraries that `flutter_soloud`, `gamepads` or `pointer_lock` need on Linux to
  compile under `flutter test`: install what the first red run names, nothing guessed.
- The README gets a CI badge. `PUBLISHING.md` moves the CI from "Still to do" to "Done".
- CLAUDE.md's suite section says the CI runs the same list, and that a local green run is
  still required before a commit.
- **Gate:** push to `dev` (the owner's word: it is outward-facing) and see it green. If a
  suite fails only on Linux, that is a finding: record it in the step's row and fix it in
  its own commit, never by skipping the suite.

### VL2 · `copyWith` on a creature's specs (`KL-018`)

`packages/voxel_game/lib/src/mobs/mob_spec.dart` (`MobSpec`, and `SpawnRule` at `:31`),
`entities/projectile.dart` (`ProjectileSpec`), and the behaviours that carry numbers
(`MeleeAttack`, `RangedAttack`, and the others with fields).

- Each gains `copyWith`. A nullable field takes a `ValueGetter` of its new value, as
  `VoxelGameSpec.copyWith` does (`KL-010`), never a sentinel (rule 8).
- Tests: per spec, a field left out is kept, one given is changed, a nullable one can be
  asked for null.
- The app: `mob_table.dart`'s elites (`:556`, `:575`, `:587`, `:732`) become `copyWith`
  calls on the base creature.
- Additive, so not breaking.

### VL3 · A new world's start declared (`KL-023`)

- `VoxelGameSpec.spawn` (VLD10): `SpawnPoint? Function(WorldInfo info)?`. `SpawnPoint` is
  a new class holding `x`, `z` and `yaw`, in `spec/`. `_begin`
  (`core/voxel_game.dart:345-357`) uses it instead of the spiral when it answers, and
  `player.tryPlace` (`:1151`) places there and turns the look. A loaded world keeps its
  saved position; `spawn` is read only for a new one.
- Tests: a spec with a spawn starts the player there, facing the yaw, before its first
  drawn frame; `null` keeps the spiral; a reloaded world ignores it.
- The app: `Playground._begin`'s wait and move go, and its spec answers the hub for a
  playground and null otherwise.

### VL4 · A title's own music (`KL-019`)

- `TitleSpec.music`: the id of one of the spec's `MusicSpec` tracks, or null. `TitleScreen`
  plays it through the same mapping `VoxelGameWidget._startAudio` uses
  (`ui/voxel_game_widget.dart:304-327`), so the mapping moves to one place both call. It
  follows the live `GameSettings`, so the title's own Settings panel moves its volume at
  once, and it closes the device before the game's widget opens its own.
- Tests: the title starts the named track; a volume changed in the title's panel reaches
  it without reopening; entering a world stops it before the game's bank opens.
- The app: `title_vista.dart:121-136` loses its `SoundBank` and its mapping, and its spec
  names the meadow track.

### VL5 · A game's own player settings (`KL-020`)

- `GameSettings.game` (VLD6): `Map<String, Object?>` JSON, empty by default, written and
  read by `toJson` / `fromJson` with the version bumped (old files read as empty `game`,
  as version 1 reads `weather` today). `copyWith` and the store carry it.
- Tests: a round-trip through `SettingsStore`; an older file reads with an empty map.
- The app: `tutorialOption` goes from the new-world form, and the tutorial reads and
  writes a `tutorialDone` key in `settings.game`, shown once per machine as before VA-Zk.

### VL6 · A stock structure's plan (`KL-022`)

`packages/voxel_engine/lib/src/worldgen/structures/`.

- `DungeonPlan.of(site)` and `MinePlan.of(site)`: the rolled floor, the rooms, the
  spawners and the chests (dungeon); the rolled length, the spawner and the chests (mine).
  Each is computed from the site and its rolls, and the drawing reads it too, as the
  app's `FortressPlan` does.
- Tests: the plan's cells are where the drawn blocks are (spawner blocks at the plan's
  spawners, air in its rooms), for several seeds.
- The app: `structures.dart:175-207` reads the plans and scans no cell. Its
  `structures_test.dart` still passes.

### VL7 · A boss marked on the creature, a cart's start speed

- `Mob.boss` (VLD11): a mutable `bool`, seeded from `spec.boss`, written to and read from
  the creature's save row (the row's version moves if the row has one). `VoxelGame.boss`
  reads it.
- `Minecart` takes a start speed: a `speed` parameter on the constructor or a
  `push(double)` method, whichever the vehicle's existing placement path makes natural.
  It is asserted at or above 0, as `speed` already is.
- Tests: a creature flagged after spawning drives the boss bar and survives a save; a cart
  started at speed rolls on a flat rail.
- The app: the playground's summon flags its troll or boomer; the old cart's start speed
  is ported, if the app's spec still wants one.

### VL8 · A pad steps the hotbar (`KL-016`)

- `VoxelAction.hotbarNext` / `hotbarPrevious` (VLD9), bound to `rightBumper` /
  `leftBumper` in `defaultBindings.gamepad`, and to nothing on the keyboard (the wheel and
  the digits stay). `PlayerEntity` reads them beside `takeWheel`
  (`player/player_entity.dart:458-463`), wrapping around.
- Tests: each bumper steps the slot and wraps; a game that binds only `hotbarNext` still
  passes `checkActions`.
- The app: `bindings` rebinds `hotbarNext` to `dpadLeft` and unbinds `hotbarPrevious`.
  Its abilities keep the bumpers; the tutorial's skip moves from `dpadLeft` into the game
  menu; `controls_screen.dart`'s pad line says so.

### VL9 · A pad and the arrows work every screen (`KL-013`)

**Split first**, into one commit per group, in the row: (a) the intent bridge in
`GameSurface` plus the simple menus (pause, death, settings, credits); (b) the bag as a
focusable grid, crafting included; (c) the title, its choice and the world list (which
sit outside `GameSurface`, so they need the bridge on their own `Focus`); (d) the app's
own screens, checked and fixed where a custom widget takes no focus.

- The bridge (VLD5): while `VoxelGame.openScreen` is set, `GameSurface` maps pad
  presses and stick flicks (edge-triggered, with a repeat while held) and arrows, Enter,
  Space and Esc to the intents, instead of handing them to `InputMap`. The step's arbiter
  still owns pause and inventory (rule 14: the handler reads its event; the arbiter
  polls).
- Every kit screen opens with a sensible first focus and draws a visible focus ring.
- Tests: per group, a widget test drives the screen with pad events alone and again with
  keys alone. The bag test picks, halves, places and crafts.
- Breaking for a game whose screen relied on `GameSurface` swallowing arrows; the
  CHANGELOG says so.

### VL10 · A hidden window keeps stepping (`KL-014`)

- `VoxelGameWidget` observes `AppLifecycleState`. On `hidden` it starts a periodic
  `Timer` at the fixed step's period that calls `VoxelGame.frame` with no render; on
  `resumed`/`inactive` it stops the timer, and the ticker takes over without a time jump
  (`FixedStepLoop`'s clamp, checked). VLD7: a lone game keeps stepping too.
- Tests: with the binding's lifecycle set to `hidden`, steps advance and no scene frame
  is asked for; back to `resumed`, one driver only.
- Seen on the Mac: the example with a world, covered by another window for 30 s; the
  clock (or a T-told time) has moved when it is uncovered.

### VL11 · The scene's frames in the frame report (`KL-017`)

- `FrameStats` reads `GpuPacedScene.rendered` (via `VoxelGame.scene`) and reports scene
  frames a second beside the tick rate; `FrameReport` carries rendered and shown counts.
  The FPS overlay shows the rendered rate.
- Tests: a fake scene's counts reach the stats and the report.
- **No benchmark** (CLAUDE.md §Benchmarks): the change is judged by its tests.

### VL12 · Ready to release

- CHANGELOGs: `voxel_engine` and `voxel_scene` move their post-`34d7a6e` lines from
  `## 0.3.0-dev` to a new `## 0.4.0-dev`, which means checking each line against `git log
  34d7a6e..` for that package. `sound_recipes` and `voxel_game` rename `## Unreleased` to
  `## 0.4.0-dev`. Each gets a **Breaking** list at the top.
- Versions to `0.4.0-dev`, and the constraints between the four (and in both examples and
  the minecraft app) to `^0.4.0-dev`.
- READMEs: every package's README checked against its API (VA's fields and this plan's),
  and `KL-004`'s line kept. `InputMap.pointerLockSupported`'s doc says which platforms
  lock. The ledger's `KL-004` gets `Deferred:` (VLD3).
- `PUBLISHING.md`: the release history names `0.4.0-dev`, and the releasing section adds
  the tags (VLD12).
- The four dry runs, in the order `PUBLISHING.md` gives, green but for the two accepted
  warnings.

### VL13 · `0.4.0-dev` out

The owner gives the word in that session; publishing cannot be undone.

- `tool/publish_package.sh` for the four, in order (it waits for each dependency's
  analysis).
- Tag each package at the release commit and push the tags.
- Check 160 points on each, and record the result in this row.

## Out of scope

- The app's visual leftovers from VA-Z (VLD4): the bow's and staff's fan and arc, the
  abilities' particles, coloured damage numbers, the dash's pose. A later app plan.
- The chest minecart (`VAD24`).
- `KL-004`'s fix (VLD3).
- Any benchmark, including the paced A/B that `KL-017` enables. It is the owner's call
  when they want numbers.
