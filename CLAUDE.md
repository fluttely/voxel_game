# voxel_game — the voxel kit — Developer & AI Instructions

> **This file governs everything under this folder**: the `voxel_game` package at the
> root, and the three packages under `packages/`. Every path below is written from this
> folder, so the file reads the same whether the folder is still
> `poc_cubeworld/packages/voxel_game/` inside the Dawnforge repository or the root of a
> repository of its own.
>
> While it still lives inside `poc_cubeworld/`, Claude Code also loads the app's
> `CLAUDE.md` and the 2D track's above it. **Neither governs this folder**: the app's
> rules are about the app (the POC that the kit was extracted from and that consumes it),
> the 2D one is another product. Where a rule below descends from the app's, its number
> there is named in parentheses (`app 17`).
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

`voxel_game` is this folder's root: it is the published package **and** the pub workspace
root. `pubspec.yaml`'s `workspace:` lists `packages/voxel_engine`, `packages/voxel_scene`,
`packages/sound_recipes` and the two example apps (`example/`,
`packages/voxel_scene/example/`), which stay `publish_to: none` for good. `.pubignore` keeps
`packages/`, the build output and this folder's own working files (`CLAUDE.md`, `AGENTS.md`,
`PUBLISHING.md`, `docs/`, `tool/`) out of `voxel_game`'s tarball — it is not optional, and it
is why the three nested packages publish from a git-less copy through
`tool/publish_package.sh`, never in place (`PUBLISHING.md`).

Target: every platform Flutter supports. **macOS is the development platform** (Flutter GPU
is enabled in each example's `macos/Runner/Info.plist`).

## The map

| What | Where |
|:---|:---|
| The kit, what a game imports | `lib/voxel_game.dart` · `lib/src/{camera,core,entities,input,loop,mobs,net,player,spec,ui,world}/` |
| The three packages under it | `packages/{voxel_engine,voxel_scene,sound_recipes}/` |
| The smallest game built on it | `example/lib/main.dart` |
| Pre-publish checklist, release order, the version graph | `PUBLISHING.md` |
| Publishing (or dry-running) one of the four | `tool/publish_package.sh <package> [--dry-run]` |
| How the packages were extracted (VP, VK) and consolidated (VC) | `docs/VOXEL_PACKAGES_PLAN_2026-09-14.md` · `docs/VOXEL_KIT_PLAN_2026-09-18.md` · `docs/VOXEL_CONSOLIDATION_PLAN_2026-09-19.md` |
| How this folder got its shape (VR) | `docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md` |
| Architecture ledger (rule 17) | `docs/LEDGER.md` |
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
    reader of the buttons every surface shares.
15. **Never hand-edit a generated artifact** (app 17).
    `packages/voxel_scene/assets/shaders/terrain.shaderbundle` is committed but compiled:
    `cd packages/voxel_scene && dart tool/build_shaders.dart` after editing
    `shaders/*.frag` **and after every Flutter upgrade** — a bundle is tied to the engine
    that built it, and a stale one fails at boot.
16. **Every automation is a script, named for the job** (app 20), runnable standalone from
    its package's root, `--dry-run`/`--check` when it writes something committed. Today
    there are two: `packages/voxel_scene/tool/build_shaders.dart` and
    `tool/publish_package.sh` (from this folder's root).
17. **Record an architectural observation, do not fix it mid-task** (app 21). A structural
    problem found while doing something else goes to `docs/LEDGER.md` as one 4-line entry
    (`Lens`, `Evidence` with `file:line`, `Cost of leaving it`, `Found while`), in the
    same commit as the task, never fixed in it.

---

## 🔄 Execution Workflow

1. **Orient before touching anything.** `git log --oneline -10`, `git status --short`
   (another session may be in this tree), `docs/LEDGER.md`, and the Progress table of any
   live plan in `docs/`.
2. **Implement ONE concern** — one commit, one subject.
3. **Run the whole suite from this folder, inline.** Never in the background; wait for the
   exit code:

   ```bash
   flutter pub get                                         # once, resolves the workspace
   flutter analyze                                         # zero issues, all four packages
   flutter test                                            # voxel_game
   cd packages/voxel_engine  && dart test                  # pure Dart
   cd packages/voxel_scene   && flutter test
   cd packages/sound_recipes && flutter test
   ```

   Green as of VR3 (2026-09-22): analyze clean · 32 + 168 + 10 + 4 = **214 tests**. A
   count that drops without a deletion in the diff is a suite that stopped finding files.
4. **See it running** for anything visual: `cd example && flutter run -d macos` is the
   kit's own witness. A green test is not a visual result.
5. **Validate against the rules above.**
6. **Document it** (below), then **commit** (below).

### Testing policy

Tests ship with the code. The API is a spec, not a draft. A package test runs without a
screen and without a world (the engine's do not even need Flutter). Never delete a test to
make the suite green.

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

The subject names the package(s) touched and says what changed; the body says why. While
this folder still lives inside the Dawnforge repository, that repository's history
prefixes kit commits with `poc(voxel)` and a plan step (`VR3`) — follow it there.

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
