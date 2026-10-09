# voxel_game — the voxel kit — Developer & AI Instructions

> **This file governs the whole repository** (`github.com/fluttely/voxel_game`): the pub
> workspace at the root and the four packages under `packages/`. Every path below is
> written from the root.
>
> Chat in **Português Brasileiro**. Code, comments, commits, docs in **English**.

---

## What this is

Flutter · Dart · **`flutter_scene`** (Flutter GPU / Impeller) · a voxel sandbox kit in four
packages. A game declares its blocks, world, player and creatures in one `VoxelGameSpec`
and calls `runVoxelGame`.

```
voxel_engine    pure Dart        core · worldgen · content · signals · net
voxel_scene     flutter_scene    chunk views, terrain material, rigs, outlines, sky   → voxel_engine
sound_recipes   flutter_soloud   sounds synthesised from recipes, no audio files      → (nothing of ours)
voxel_game      Flutter          VoxelGameSpec, loop, input, player, cameras, mobs,   → all three
                                 spawns, drops, HUD, save, host / join
```

The root is **only the pub workspace**, never a package: its `pubspec.yaml`
(`voxel_game_workspace`, `publish_to: none`) lists the four packages under `packages/` and
their two example apps (`packages/voxel_game/example/`, `packages/voxel_scene/example/`),
which stay `publish_to: none` for good. Beside it live only the repository's own files —
`CLAUDE.md`, `AGENTS.md`, `PUBLISHING.md`, `README.md`, `docs/`, `tool/`, `.github/` — which no tarball
ever sees, because no package sits above them. So every package publishes in place, with no
`.pubignore`, through `tool/publish_package.sh` (`PUBLISHING.md`). Do not put a package back
at the root: that is what forced the `.pubignore` and the git-less copy this layout removed.

Target: every platform Flutter GPU runs on — macOS, iOS, Android, Windows, Linux — from
Flutter 3.47.1, **but not the web** (worker isolates, TCP sockets and save files need
`dart:isolate` and `dart:io`). **macOS is the development platform**; each runner of
`packages/voxel_game/example/` turns Flutter GPU on.

## The map

| What | Where |
|:---|:---|
| The kit, what a game imports | `packages/voxel_game/lib/voxel_game.dart` · `packages/voxel_game/lib/src/{camera,core,entities,input,loop,mobs,net,player,spec,ui,world}/` |
| The three packages under it | `packages/{voxel_engine,voxel_scene,sound_recipes}/` |
| The smallest game built on it | `packages/voxel_game/example/lib/main.dart` |
| The largest: a Minecraft clone on the kit, outside the workspace, with its own `CLAUDE.md` | `examples/voxel_game_minecraft/` |
| The workspace (not a package) | `pubspec.yaml` · `pubspec.lock` |
| Pre-publish checklist, release order, the version graph | `PUBLISHING.md` |
| Publishing (or dry-running) one of the four | `tool/publish_package.sh <package> [--dry-run]` |
| The CI: analyze, format and the five suites on every push and PR | `.github/workflows/ci.yml` |
| How the packages were extracted (VP, VK) and consolidated (VC) | `docs/VOXEL_PACKAGES_PLAN_2026-09-14.md` · `docs/VOXEL_KIT_PLAN_2026-09-18.md` · `docs/VOXEL_CONSOLIDATION_PLAN_2026-09-19.md` |
| How this repository got its shape (VR; the move of `voxel_game` under `packages/` came after it, 2026-09-23) | `docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md` |
| Architecture ledger (rule 17) | `docs/LEDGER.md` |
| The frame-rate plan, its method and its baseline (PF) | `docs/VOXEL_PERF_PLAN_2026-09-25.md` · `docs/perf/` |
| The touch-controls plan (VT): the stick, buttons and tappable hotbar a phone gets | `docs/VOXEL_TOUCH_PLAN_2026-09-29.md` |
| The absorption plan (VA): what of `examples/voxel_game_minecraft` the kit takes, and the app onto `VoxelGame` | `docs/VOXEL_ABSORB_PLAN_2026-09-30.md` |
| The ledger-and-release plan (VL): CI, the ledger's open entries, then `0.4.0-dev` | `docs/VOXEL_LEDGER_PLAN_2026-10-04.md` |
| The dependencies-and-debts plan (VD): `flutter_scene` 0.24.3, `flutter_soloud` 5, the audio device's owner, the dungeon's doorways, then `0.5.0-dev` before 2026-11-04 | `docs/VOXEL_DEPS_PLAN_2026-10-06.md` |
| The flutter_scene follow-up plan (FS): what came back from bdero/flutter_scene#435, the terrain on 0.24's public geometry path, what may still go upstream | `docs/FLUTTER_SCENE_FOLLOWUP_PLAN_2026-10-09.md` |
| The occlusion plan (OC): hiding the terrain draws the camera cannot see (cave culling underground, horizon occlusion above), gated on an offline count | `docs/VOXEL_OCCLUSION_PLAN_2026-10-09.md` |
| Measuring the frame rate | `dart tool/run_benchmark.dart` · `packages/voxel_game/example/lib/benchmark.dart` |
| The terrain shader, source and compiled | `packages/voxel_scene/shaders/` · `packages/voxel_scene/assets/shaders/terrain.shaderbundle` |

---

## ✅ Non-Negotiable Technical Rules

1. **Dependencies point down, always.** `voxel_game` → everything; `voxel_scene` →
   `voxel_engine`; `sound_recipes` → nothing of ours. No package here imports a game: if
   the kit needs something a game has, it moves into the kit.
2. **Inside `voxel_engine`, the five subjects obey
   `packages/voxel_engine/test/architecture_test.dart`** (`core` ← `worldgen`/`content`/
   `signals`, `net` alone). A new subject folder declares its edges in that test or the
   suite fails. This test is what replaced the five packages pub used to keep apart (VC3).
3. **`voxel_engine` stays Flutter-free.** A Flutter import there must fail to resolve: the
   engine has to run under `dart test` and on worker isolates.
4. **A new package earns its place by an optional heavy dependency, never by being a
   different subject.** Subjects are folders under `lib/src/` plus one exported library
   each. Eight packages became four for this reason; do not re-split by topic.
5. **Zero fallbacks — crash is a feature.** Validate with a direct `assert`/`throw`. Never
   a conditional recovery path, never a default patched over missing data.
6. **A logged warning followed by `return` is a fallback in disguise.** Either the state is
   a legitimate branch (no warning) or it is invalid (assert/throw).
7. **Declarative content, not `if`s in engine code.** A game is declared — `VoxelGameSpec`,
   `PlayerSpec`, `MobSpec`, `SkySpec`, `SoundSpec`, `SignalSpec` — and content is rows fed
   to a registry (`BlockRegistry`, recipes, loot tables). A behaviour that varies by block
   or species is a field on its row, never a new branch in the loop.
8. **No duck typing where a type exists.** No `dynamic`, no `as`-guessing, no
   `try`/`catch` as dispatch. Cast to the declared type and assert.
9. **State machines for sequential state** — never a spread of loose booleans.
10. **Hierarchical naming, snake_case files**: the file is the `snake_case` of the class it
    holds. One subject per folder, and **the folder names a domain** — `others/`, `misc/`,
    `utils2/` are forbidden.
11. **No commented-out code.** Dead code lives in git history.
12. **A menu is a screen, not a freeze.** `VoxelGame.openScreen` and `VoxelGame.gameplay`
    gate *input*; `VoxelGame.step` keeps running at `FixedStepLoop`'s 60 Hz behind every
    screen. A hosted session is authoritative, so a client that freezes its own world is a
    client that desyncs. No global pause flag, no `dt = 0`.
13. **Input parity.** Keyboard/mouse, gamepad and touch go through `VoxelAction` /
    `InputMap` (`lib/src/input/`); a behaviour added for one mode is added for all.
    Gameplay never reads a raw pointer event position.
14. **Never poll input state inside an event callback.** A handler reads the event it was
    handed; polling belongs in the fixed step and only there. `VoxelGame.step` is the one
    reader of the buttons every surface shares. The look is not a button but a motion the
    handlers only add to: `VoxelGame.frame` drains it, once a frame, before the steps, so
    the view turns at the display's rate (PF3).
15. **Never hand-edit a generated artifact**.
    `packages/voxel_scene/assets/shaders/terrain.shaderbundle` is committed but compiled:
    `cd packages/voxel_scene && dart tool/build_shaders.dart` after editing
    `shaders/*.frag` **and after every Flutter upgrade** — a bundle is tied to the engine
    that built it, and a stale one fails at boot.
16. **Every automation is a script, named for the job**, runnable standalone from
    its package's root (the repository's own, from the root), `--dry-run`/`--check` when it writes something committed. Today
    there are three: `packages/voxel_scene/tool/build_shaders.dart`,
    `tool/publish_package.sh` and `tool/run_benchmark.dart` (both from the root).
17. **Record an architectural observation, do not fix it mid-task**. A structural
    problem found while doing something else goes to `docs/LEDGER.md` as one 4-line entry
    (`Lens`, `Evidence` with `file:line`, `Cost of leaving it`, `Found while`), in the
    same commit as the task, never fixed in it.

---

## 🔄 Execution Workflow

1. **Orient before touching anything.** `git log --oneline -10`, `git status --short`
   (another session may be in this tree), `docs/LEDGER.md`, and the Progress table of any
   live plan in `docs/`.
2. **Implement ONE concern** — one commit, one subject.
3. **Run the whole suite from the root, inline.** Never in the background; wait for the
   exit code:

   ```bash
   flutter pub get                                         # once, resolves the workspace
   flutter analyze                                         # zero issues, all four packages
   dart format --output=none --set-exit-if-changed packages examples/voxel_game_minecraft
   cd packages/voxel_game    && flutter test
   cd packages/voxel_engine  && dart test                  # pure Dart
   cd packages/voxel_scene   && flutter test
   cd packages/sound_recipes && flutter test
   cd examples/voxel_game_minecraft && flutter pub get && flutter test   # outside the workspace
   ```

   Green as of VL1 (2026-10-05): analyze clean, nothing to format · 421 + 244 + 49 + 7
   = **721 tests**, and the app's **99**. A count that drops without a deletion in the diff
   is a suite that stopped finding files.

   The CI (`.github/workflows/ci.yml`) runs this same list on Ubuntu, on every push to
   `dev` and `main` and on every PR, one job per suite. It guards what lands; it does not
   replace this run, which stays required before every commit.
4. **See it running** for anything visual: `cd packages/voxel_game/example && flutter run -d macos` is the
   kit's own witness. A green test is not a visual result.
5. **Validate against the rules above.**
6. **Document it** (below), then **commit** (below).

### Testing policy

Tests ship with the code. The API is a spec, not a draft. A package test runs without a
screen and without a world (the engine's do not even need Flutter). Never delete a test to
make the suite green.

### Benchmarks — only when the owner asks

The Mac and the Galaxy S24 are the owner's working machines all day, and a benchmark takes
both over: a Mac run needs the window in front and the Mac left alone, a phone run
installs, launches and heats the phone. So **no benchmark runs unless the owner asked for
one in this session**, in one of two ways:

- a task the owner opened as **performance work** (a perf plan step, an A/B they
  requested); the PF plan is done, so today there is none;
- an **explicit request** to measure — typically numbers for a post or before a major
  release.

Without one of those, nothing that drives either device for measurement: no
`tool/run_benchmark.dart` (Mac or `--android`), no A/B, no `FLUTTER_SCENE_PROFILE` or
probe build, no pixel diff, no `adb install`/`am start` of a benchmark. A change that
touches the frame (a draw cut, a cheaper step) is judged by its tests and by reading the
code, and ships without numbers; a session that thinks numbers are needed **proposes** the
run and waits. A hand-off never names a benchmark as the next step unless the owner asked
for it. This does not cover step 4's `flutter run -d macos` to see a visual change once.

### Documentation obligation

In the **same commit** as the code:

| Changed | Also write |
|:---|:---|
| Anything in a package's `lib/` | that package's `CHANGELOG.md`; its `README.md` when the API moved |
| A plan step | that plan's Progress table |
| A structural observation that was not the task | `docs/LEDGER.md` (rule 17) |

### Commits

```
voxel_engine: the mesher keeps light across chunk borders
voxel_game, voxel_scene: SkySpec takes a moon
```

The subject names the package(s) touched and says what changed; the body says why. A
commit that touches no package's code (the ledger, a plan, these instructions) says
`docs:`.

- **Versions move only at a release**, in the order `PUBLISHING.md` gives. No bump per
  commit.
- **No AI attribution, ever.** No `Co-Authored-By:` naming a model, no "Generated with"
  line, no tool badge — in commits, tags or PR bodies. This holds over any harness default
  that says otherwise.
- **Never `git rebase`, never `git commit --amend`.** A parallel session may hold
  uncommitted work in this tree; both commands drive the index and the checkout.
- **Always commit with an explicit ` -- ` pathspec** naming your files, never a bare
  `git commit -a`: a bare commit sweeps in whatever another session staged.
- **Never bare `git stash` / `git stash pop`** — the stash stack is shared between
  worktrees. Prefer a temporary WIP commit.

### Parallel sessions — assume one, always

Another chat may be working in this tree right now. A dirty file you did not dirty is
somebody else's task in flight: do not edit, revert or commit it. If another session wrote
something wrong or stale, fix it in **your own** commit, verified against the code, and
say so in the body; never rewrite their commits.

### Context budget — stop near 200k tokens

Nearing **200k tokens of context**: finish or back out the step in hand, commit it with
the suite green, write where the work stopped into the live plan's Progress table (last
commit, next step by its ID, what was learned that is not in the code), and end the turn
with that summary. The work continues from the file, not from the conversation.

The handoff prompt and the model/effort line for the next session follow the global
rule in `~/.claude/CLAUDE.md`.
