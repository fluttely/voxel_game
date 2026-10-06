# Voxel Minecraft — the app on the kit — Developer & AI Instructions

> **This file governs `examples/voxel_game_minecraft/`.** The repository's `CLAUDE.md`, two
> folders up, governs this folder too: its rules 1–17, its execution workflow, its commit
> and parallel-session rules, its benchmark rule. What follows is only what this app adds.
> `CLAUDE.md` and `AGENTS.md` here hold the same text, for agents that read either name.
>
> Chat in **Português Brasileiro**. Code, comments, commits, docs in **English**.

---

## What this is

A Minecraft clone built on the kit: one `VoxelGameSpec` (`gameSpec`, seed 1337), its content
as rows, its own systems and screens, booted by `runVoxelGame` with a title
(`lib/main.dart`). It is the kit's largest witness: a kit change that a game would feel is
tried here before it ships.

It began as a file-by-file port of a Godot POC (`ROADMAP.md`'s stages), grew the kit's four
packages, and since VA-Z (`docs/VOXEL_ABSORB_PLAN_2026-09-30.md` at the repository root,
done 2026-10-04) holds no engine code of its own: the loop, the player, the creatures, the
world, the save, the HUD, the screens and the network are the kit's. What is left here is
game content. It stays `publish_to: none` for good.

Targets: the kit's (not the web). **macOS is the development platform**; Flutter GPU is on
in `macos/Runner/Info.plist`.

## The map

| What | Where |
|:---|:---|
| The boot: the title, its credits, the vista, the HUD | `lib/main.dart` |
| The spec: blocks (in save order), items, recipes, effects, creatures and their elites, the overworld and the underworld, structure loot, sounds and music, keys, the title and its world options | `lib/src/spec/` |
| Classes, abilities, talents, stamina, mana, the dodge | `lib/src/classes/` |
| Quests, achievements, the tutorial, stats, the bestiary, the journal and stats screens | `lib/src/journal/` |
| Structures found, bosses, the fortress, spawner blocks, ruin ghosts | `lib/src/structures/` |
| Villages, villagers, the trade screen | `lib/src/villages/` |
| Waypoints · enchanting | `lib/src/waypoints/` · `lib/src/enchanting/` |
| The map and the minimap | `lib/src/map/` |
| The playground and its exhibits | `lib/src/playground/` |
| The heartbeat at low health | `lib/src/player/` |
| The HUD layer over `DefaultHud`, the hint card, the controls screen, the title's vista | `lib/src/ui/` |
| Tests, headless on the spec | `test/` |
| Stages (the credits read them) and the session log | `ROADMAP.md` |
| Running it, the keys, the saves | `README.md` |
| The app's ledger (`CL-nnn`) | `docs/LEDGER.md` |
| The Flutter vs Godot study, kept as history | `docs/PERFORMANCE_VS_GODOT_2026-09-11.md` |

## How a feature is built here

- **A behaviour is a row or a system, never a fork of the kit.** Content goes on the spec
  (`BlockType`, `ItemType`, `MobSpec`, `Biome`, `StructureSpec`, …); what runs each step is
  a `GameSystem`, a `SavedSystem` when it keeps state (its own key under `game.json`'s
  `game`), listening to the kit's `GameEvent`s.
- **The game's own hooks are the spec's fields:** keys as `ActionSpec`s (keyboard, pad and
  touch together, root rule 13), screens as `ScreenSpec`s, a use of a block or a creature in
  `blockUses` / `mobUses`, network messages in `messages`, per-world choices as
  `WorldOption`s (class, kind, tutorial) read through `playerFor` / `worldFor` /
  `VoxelGame.options`, HUD bars as `HudBar`s.
- **A gap in the kit is a kit commit first** (root rule 1), witnessed by
  `packages/voxel_game/example` and the kit's tests, then the app's commit on top of it, as
  VA-Za–VA-Zg did. Never a workaround here.

## The app's rules, on top of the root's 1–17

A1. **The block table's order is the save contract.** `lib/src/spec/block_table.dart`:
    `edits.bin` keys a world's edits by index, so a block is appended, never inserted or
    moved. `test/world_test.dart` pins the whole order by name.

A2. **Nothing has shipped, so a breaking change is free; the local worlds are the bill.**
    No save migration (VAD15). A commit that changes a persisted shape names in its body
    what became unreadable.

A3. **Every mechanic has a headless test on the spec** (`VoxelGame.startHeadless(gameSpec,
    options: ...)`). What a probe would have printed with a range is an assertion (VAD17).
    There are no probe flags and no baseline logs. `test/voxel_parity_test.dart` hashes two
    chunks, their meshes and an edit delta: re-pin it only when a change moves the world on
    purpose, and say so in the commit.

A4. **See it running** (root workflow step 4): `flutter run -d macos` from this folder. To
    read a frame back, a throwaway entry beside `main.dart` wraps the widget in a
    `RepaintBoundary`, forces a frame every 16 ms, writes `toImage` to a PNG under the
    system temp folder, and is deleted with its worlds before the commit. Never capture the
    desktop.

A5. **Player-facing text is readable by a 7-year-old.** Short sentences, concrete words, a
    number always explained by its effect. Tone and wording only, never a simpler mechanic.

## Workflow, where it differs from the root's

The app is not in the root pub workspace: it has its own `pubspec.lock` and takes the kit
from this tree through four `dependency_overrides` by path (`KL-006`). So the suite is the
root's plus:

```bash
cd examples/voxel_game_minecraft && flutter pub get && flutter analyze && flutter test
```

Green at VA-Zm (2026-10-04): analyze clean, **99 tests**. The app keeps stock
`flutter_lints`; format new or edited files with `dart format --page-width 120`.

| Changed | Also write |
|:---|:---|
| A mechanic, a fix worth remembering, a decision | a `ROADMAP.md` §Session log entry: what broke, why, what replaced it |
| The keys | `lib/src/ui/controls_screen.dart` and `README.md`'s key table |
| A plan step | that plan's Progress table, at the repository root's `docs/` |
| A structural observation that was not the task | `docs/LEDGER.md` here (`CL-nnn`); one about the kit goes to the root's (`KL-nnn`) |

Commits: `examples/voxel_game_minecraft: <what changed>`, the plan step in parentheses when
there is one. A commit that also touches the kit is two commits, the kit's first.
