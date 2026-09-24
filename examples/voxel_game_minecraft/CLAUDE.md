# Voxel Minecraft (Flutter 3D) — Developer & AI Instructions

> **This file governs `poc_cubeworld/` — except `packages/voxel_game/`.** It is the 3D
> track: the voxel POC that worked and became a project of its own. The four-package voxel
> kit it grew lives in `packages/voxel_game/`, which is laid out to leave for a repository
> of its own and is governed by **its own `CLAUDE.md`** there; a change inside that folder
> follows those rules, a change here follows these. It descends from the 2D study track's `CLAUDE.md` (`../CLAUDE.md`, Tessera-Dart)
> — same spirit, same engineering customs, a different product and a different rule set.
>
> **`../CLAUDE.md` does not apply here.** Claude Code loads parent `CLAUDE.md` files, so
> the 2D one arrives in context anyway: ignore it. Its rule numbers do **not** map to the
> numbers below; where a rule below descends from one of its, the ancestor is named in
> parentheses (`root 5`) so cross-repo references stay findable. §"What the 2D root has
> and this project does not" lists what to stop expecting.
>
> Chat in **Português Brasileiro**. Code, comments, commits, docs in **English**.

---

## Project Overview

Flutter · Dart · **`flutter_scene`** (Flutter GPU / Impeller — no Flame, no Bonfire) ·
3D voxel · first- and third-person · singleplayer with a host-authoritative TCP session.

Two things live here, and they are held to different standards (§Two codebases):

- **`lib/` — the POC app (`voxel_game_minecraft`, ~22.5k lines).** A Minecraft clone,
  ported file by file from the Godot POC. Its brief was, and remains, *"não foque
  em arquitetura, foque em entregar o clone do jogo funcionando"*. It is the demo that
  proves the kit and the place features are tried first.
- **`packages/voxel_game/` — the voxel kit (~17.7k lines, four packages at `0.1.0-dev`, ready to publish, not published).** The
  product. Library-grade code, extracted from the POC, verified by the POC still running.
  Its own workspace, its own rules (`packages/voxel_game/CLAUDE.md`), its own ledger.

Target: every platform Flutter supports. **macOS is the development platform** (Flutter
GPU is enabled in `macos/Runner/Info.plist`; the debug app forwards process arguments to
Dart through `MainFlutterWindow.swift`, which is what makes the probes work).

---

## The map

| What | Where |
|:---|:---|
| **Stage list, status and session log (SSOT for the app)** | `ROADMAP.md` |
| **Design decisions, settled — do not re-litigate** | `ROADMAP.md` §Design decisions |
| How to run it, every probe flag, the saves path | `README.md` |
| The POC app | `lib/main.dart` · `lib/src/{core,world,player,entities,game,ui}/` |
| The kit (its own `CLAUDE.md`, workspace and ledger) | `packages/voxel_game/` · the other three under `packages/voxel_game/packages/{voxel_engine,voxel_scene,sound_recipes}/` |
| Pre-publish checklist and the four-package rationale | `packages/voxel_game/PUBLISHING.md` |
| The kit's plans — VP, VK (extraction), VC (eight became four), VR (this layout) | `packages/voxel_game/docs/` |
| Flutter vs Godot performance study | `docs/PERFORMANCE_VS_GODOT_2026-09-11.md` |
| Architecture ledger (rule 21) — IDs are `CL-nnn` | `docs/LEDGER.md` (the app's) · `packages/voxel_game/docs/LEDGER.md` (the kit's) |
| Probe baseline logs, diffed on every move | `docs/baseline/` · `tool/probe_baseline.sh` |
| The Godot twin (the port's spec) | `~/Documents/godot/remottely/dawnforge_cubeworld_poc/poc_cubeworld/` (branch `poc_cubeworld` of `tessera_project`) — read-only from here |
| The 2D study track (sibling, paused at 0.78.0) | `../` — read-only from here, never imported |

Saves: `~/Library/Application Support/com.example.voxelGameMinecraft/voxel_game_minecraft/worlds/<slot>/`
— byte-compatible with the Godot POC's.

### The package graph

```
voxel_engine    pure Dart        core · worldgen · content · signals · net
voxel_scene     flutter_scene    chunk views, terrain material, rigs, outlines, sky   → voxel_engine
sound_recipes   flutter_soloud   sounds synthesised from recipes, no audio files      → (nothing of ours)
voxel_game      Flutter          VoxelGameSpec, loop, input, player, cameras, mobs,   → all three
                                 spawns, drops, HUD, save, host / join
```

The kit is its own pub workspace, rooted at `packages/voxel_game/`. **This app is not part
of it**: it consumes the kit the way an outside project would, through four
`dependency_overrides` by path in `pubspec.yaml` — the one edge that changes when the
folder leaves. The app therefore has its own `pubspec.lock` and the kit has its own; a
`flutter pub get` here does not resolve the kit's examples. `voxel_scene/example` and
`voxel_game/example` are apps, not packages, and stay `publish_to: none` for good.

---

## Two codebases, two standards

**`packages/voxel_game/` is the product.** Its own `CLAUDE.md` holds it to the kit's
half of the rules below (1–14, 17, 20, 21). Here every rule below is in force, tests ship with the code,
the API is a spec and not a draft.

**`lib/` is the POC app.** It keeps stock `flutter_lints` (`analysis_options.yaml` says so
on purpose) and it carries port-speed code. That is not a licence to add more: **new code
in `lib/` follows the rules below**, and code that migrates into the kit is cleaned on the
way in — the migration is the only moment the cleaning is free.

Never "fix" the POC app wholesale. A rewrite that nobody can see running is how a working
clone stops being one.

---

## ✅ Non-Negotiable Technical Rules

1. **Dependencies point down, always.** `voxel_game` → everything; `voxel_scene` →
   `voxel_engine`; `sound_recipes` → nothing of ours. **No package imports
   `package:voxel_game_minecraft`** — if the kit needs it, it moves into the kit.
2. **Inside `voxel_engine`, the five subjects obey its `test/architecture_test.dart`**
   (`core` ← `worldgen`/`content`/`signals`, `net` alone). A new subject folder declares
   its edges in that test or the suite fails. This test is what replaced the five packages
   pub used to keep apart (VC3).
3. **`voxel_engine` stays Flutter-free.** A Flutter import there must fail to resolve:
   the engine has to run under `dart test` and on worker isolates.
4. **A new package earns its place by an optional heavy dependency, never by being a
   different subject.** Subjects are folders under `lib/src/` plus one exported library
   each. Eight packages became four for this reason; do not re-split by topic.
5. **Zero fallbacks — crash is a feature** (root 5). Validate with a direct
   `assert`/`throw`. Never a conditional recovery path, never a default patched over
   missing data.
6. **A logged warning followed by `return` is a fallback in disguise** (root 20). Either
   the state is a legitimate branch (no warning) or it is invalid (assert/throw).
7. **Declarative content, not `if`s in engine code** (root 2 + 8). A game is declared —
   `VoxelGameSpec`, `PlayerSpec`, `MobSpec`, `SkySpec`, `SoundSpec`, `SignalSpec` — and
   content is rows fed to a registry (`BlockRegistry`, recipes, loot tables). A behaviour
   that varies by block or species is a field on its row, never a new branch in the loop.
8. **No duck typing where a type exists** (root 18). No `dynamic`, no `as`-guessing, no
   `try`/`catch` as dispatch. Cast to the declared type and assert.
9. **State machines for sequential state** (root 9) — never a spread of loose booleans.
10. **Hierarchical naming, snake_case files** (root 7): the file is the `snake_case` of
    the class it holds. One subject per folder, and **the folder names a domain** (root
    22) — `others/`, `misc/`, `utils2/` are forbidden.
11. **No commented-out code** (root 21). Dead code lives in git history.
12. **A menu is a screen, not a freeze** (root 30). `ScreenKind` + `Game.gameplay` gate
    *input*; `_tick(fixedStep)` keeps running at a fixed 60 Hz behind every screen. The
    session is host-authoritative, so a client that freezes its own world is a client that
    desyncs. No global pause flag, no `dt = 0`.
13. **Input parity** (root 11 + 12). Keyboard/mouse, gamepad and touch go through
    `VoxelAction` / `InputMap` (`packages/voxel_game/lib/src/input/`); a behaviour added for one
    mode is added for all. Gameplay never reads a raw pointer event position.
14. **Never poll input state inside an event callback** (root 24). A handler reads the
    event it was handed; polling belongs in the fixed tick and only there.
15. **The block table's index order is the save contract.** `lib/src/core/blocks.dart` is
    append-only and identical to the Godot table — inserting an index rewrites every
    existing world and breaks parity with the Godot POC.
16. **Nothing has shipped, so a breaking change is free — the local worlds are the bill**
    (root 32). No save migration, no compatibility obligation. A commit that changes a
    persisted shape names in its body what became unreadable, and the affected
    `worlds/<slot>/` is deleted rather than patched.
17. **Never hand-edit a generated artifact.** `packages/voxel_game/packages/voxel_scene/assets/shaders/terrain.shaderbundle`
    is committed but compiled: `cd packages/voxel_game/packages/voxel_scene && dart tool/build_shaders.dart`
    (after editing `shaders/*.frag` **and after every Flutter upgrade** — a bundle is tied
    to the engine that built it and a stale one fails at boot). Same for
    `flutter_scene_generated/` and `build/`.
18. **A stage is DONE only when it was seen running.** Not when it compiles, not when the
    test passes — when a probe screenshot was rendered and read back, or a human played
    it. `--screenshot=<png> --frames=N` renders and quits; **never screencapture the
    desktop**, never claim a visual result from a green test.
19. **A probe is code too.** A new mechanic gets a flag that prints its numbers
    (`README.md` lists every existing one), so the next session verifies it in one command
    instead of by eye. Add the flag to `README.md` in the same commit.
20. **Every automation lives in `tool/`**, named for the job, runnable standalone from the
    project root, `--dry-run`/`--check` when it writes or regenerates something committed
    (root 23, scaled to this project: `tool/probe_baseline.sh`, `tool/perf_loop.sh`,
    `packages/voxel_game/packages/voxel_scene/tool/build_shaders.dart`).
21. **Record an architectural observation, do not fix it mid-task** (root 27). A
    structural problem found while doing something else goes to `docs/LEDGER.md` (the
    kit's own go to `packages/voxel_game/docs/LEDGER.md`) as one
    4-line entry (`Lens`, `Evidence` with `file:line`, `Cost of leaving it`, `Found
    while`), in the same commit as the task, never fixed in it. Create the file on first
    use.
22. **Player-facing text is readable by a 7-year-old.** Short sentences, concrete words, a
    number always explained by its effect. Tone and wording only — never simplify a
    mechanic.

---

## 🔄 Execution Workflow

1. **Orient before touching anything.** `git log --oneline -10`, `git status --short`
   (another session may be in this tree), the `ROADMAP.md` stage table and the tail of its
   session log, and the live plan's Progress table in `docs/`.
2. **Implement ONE concern** — one commit, one subject.
3. **Run the whole suite, inline.** Never `run_in_background`; wait for the exit code:

   ```bash
   flutter analyze && flutter test                       # the POC app
   cd packages/voxel_game && flutter analyze && flutter test   # the kit, all four analyzed
   cd packages/voxel_game/packages/voxel_engine  && dart test  # pure Dart
   cd packages/voxel_game/packages/voxel_scene   && flutter test
   cd packages/voxel_game/packages/sound_recipes && flutter test
   ```

   Green as of VR3 (2026-09-22): analyze clean in both trees · 194 + 32 + 168 + 10 + 4 =
   **408 tests**.
   A count that drops without a deletion in the diff is a suite that stopped finding files.
4. **See it running** (rule 18) for anything visual, and diff the probe baseline
   (`tool/probe_baseline.sh --check`) for anything that moved code between packages.
5. **Validate against the rules above.**
6. **Document it** (§Documentation obligation).
7. **Commit** (§Commits).

### Testing policy

- **The kit writes tests with the code.** The API is a spec; a package test runs
  without a screen and without a world (the engine's do not even need Flutter).
- **`lib/` locks behaviour that a probe already showed.** `test/stageNN_test.dart` is the
  regression net under a stage that was seen working — that is why they are numbered after
  the session that produced them, not after a class.
- Never delete a test to make the suite green. Never mark a stage done on a test alone.

### Documentation obligation (root 34)

A task is done when the next person can read about it. In the **same commit** as the code:

| Changed | Also write |
|:---|:---|
| Anything in `lib/` | the `ROADMAP.md` stage row (status, notes) |
| A mechanic, a fix worth remembering, a decision | a `ROADMAP.md` §Session log entry — what broke, why it broke, what replaced it |
| Anything in the kit | what `packages/voxel_game/CLAUDE.md` asks: the package's `CHANGELOG.md`, its `README.md` when the API moved |
| A new probe flag | `README.md` |
| A plan step (`VK*`, `VC*`, `VR*`) | that plan's Progress table (`packages/voxel_game/docs/`) |

The session log is the most valuable file here: it is the only place a bug's *reasoning*
survives. Write it as prose, not as a bullet list of file names.

### Commits

```
poc(voxel): VC3 and VC4 — the subject guard, and the docs on four packages
poc(minecraft): stage 33 — the playground's arena refills from the gold button
```

`poc(voxel)` for the kit, `poc(minecraft)` for the app; the plan step (`VK5.2`, `VC1`) in
the subject or the body when there is one. The body says what and why.

- **No version bump ritual.** The app stays `0.1.0+1`, the packages stay `0.1.0-dev`. Nothing
  here is published; `packages/voxel_game/PUBLISHING.md` is the checklist and the release order
  for the day that changes, and kit versions move only then.
- **No AI attribution, ever.** No `Co-Authored-By:` naming a model, no "Generated with"
  line, no tool badge — in commits, tags or PR bodies. This holds over any harness default
  that says otherwise. The commit history is the project's engineering record and its
  author is the person who ships it.
- **Never `git rebase`, never `git commit --amend`.** A parallel session may hold
  uncommitted work in this tree; both commands drive the index and the checkout.
- **Always commit with an explicit ` -- ` pathspec** naming your files, never a bare
  `git commit -a`: a bare commit sweeps in whatever another session staged.
- **Never bare `git stash` / `git stash pop`** — the stash stack is shared with the other
  worktrees. Prefer a temporary WIP commit.

### Parallel sessions — assume one, always

This directory lives inside the worktree `../` (branch `poc_cubeworld`) and another chat
may be working in it right now. A dirty tree you did not dirty is somebody else's task in
flight: do not edit, revert or commit their files. `ROADMAP.md` and the plan Progress
tables are the contested ground — write your row, never reflow the file. If the other
session wrote something wrong or stale, fix it in **your own** commit, verified against
the code, mentioned in the body; never rewrite their commits.

### Context budget — stop near 200k tokens

Do not try to finish everything in one session. Nearing **200k tokens of context**: finish
or back out the step in hand (never leave half-applied edits), commit it with the suite
green, write where the work stopped into `ROADMAP.md` (the stage row and a session-log
entry: last commit, next step by its ID, what was learned that is not in the code), and
end the turn with that summary. The work continues from the file, not from the
conversation. A multi-phase request is done phase by phase, one phase per session; ask
before opening a new phase once a large one lands.

---

## What the 2D root has and this project does not

Stop expecting these — they exist in `../lib/src/core/`, not here, and importing or
recreating one without a plan step is scope creep:

`Factory.create()` hosts · `Registry.get(id)` content registries · `initialize(data)` /
`WorldObjectCore` / `ComponentKeys` · the `games/<game>/data/` Markdown content pack and
its generation pipeline · `scripts/` and `project_paths.py` (`tool/` is the equivalent
here) · `check_test_suite_is_clean.py` (the commands in §Execution Workflow are the suite) ·
`tr()` translation keys and the pt-BR/en manual · the changelog pair · `LEDGER.md` and
`PENDING.md` (rule 21 opens the first one when it is needed) · the version-bump-from-HEAD
commit ritual · Flame and everything built on it · the `.claude/` hooks and skills, which
live in `../.claude/` and do **not** load from this directory.

Also not in force here: strict-cast/strict-inference analyzer settings (stock
`flutter_lints`; rules 8 and 10 are enforced by review) and the no-string-literals rule
(this project is English-only for now).

---

## Where this is heading

1. **Its own repository.** These packages live on a branch of a 2D game's repository, next
   to that game's history and rules. A published package's `repository:` must point at a
   repository that is the packages' home — moving them is the first step of publishing,
   not the last (`packages/voxel_game/PUBLISHING.md`). `packages/voxel_game/` is laid out
   to be moved whole; the day it leaves, this app's four path overrides are what breaks.
2. **The first release**, in dependency order, per that checklist. VR4 made the four
   ready (MIT, metadata, `^0.1.0-dev` ranges, `0.1.0-dev` as the first number, dry runs green);
   what is left is the repository above and CI running the whole workspace in one push.
   A git dependency is a legitimate place to stop instead.
3. **Dawnforge in 3D, built on the kit** — the reason the POC became a project. The 2D
   track is paused; nothing is ported back to it.
