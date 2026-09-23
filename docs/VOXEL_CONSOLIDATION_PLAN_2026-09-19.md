# Voxel Consolidation Plan — eight packages become four

> **The executable plan that follows `VOXEL_KIT_PLAN_2026-09-18.md`.** Written 2026-09-19.
> Stable IDs (`VC<phase>.<step>`) — reference them in commits.
>
> **The goal, in the developer's words:** adopt the Flame-style layout — one git repository,
> several published packages — but publish only the packages whose split is paid for by a real
> dependency boundary. Eight becomes four.
>
> **Ground rules, unchanged.** Everything stays on branch `poc_cubeworld`, inside this
> repository, packages at `0.0.0` with `publish_to: none`. Nothing is published here. The move to
> a repository of its own and the first `0.0.1` happen after the developer reviews this work.
> **The POC keeps working at every commit.**

## Progress

| Phase | State | Gate |
|:---|:---|:---|
| VC1 `voxel_engine` — five pure-Dart packages become one | **done** 2026-09-19 (`8a2b9853`) | the POC, `voxel_scene` and `voxel_game` import `package:voxel_engine/<subject>.dart`; every test that passed still passes |
| VC2 `sound_recipes` — `voxel_audio` renamed | **done** 2026-09-19 | no package named `voxel_audio` remains; the sound board example still builds |
| VC3 The guard the split used to give for free | **done** 2026-09-19 | a test fails when a subject inside `voxel_engine` imports a subject it may not |
| VC4 Docs realigned to four packages | **done** 2026-09-19 | four READMEs, four CHANGELOGs, one example folder per package, and a written pre-publish checklist |

---

## Why — the reasoning behind the consolidation

Recorded here so it does not have to be re-derived. The question that started it: *should the
eight packages all go to pub.dev, the way Flame keeps `flame`, `flame_forge2d`, `flame_tiled` in
one repository?*

### 1. What Flame's split actually buys

The Flame and Flutter monorepos are not split by subject — they are split by **optional heavy
dependency**. `flame_forge2d` carries a physics engine, `flame_tiled` a map parser,
`flame_audio` an audio backend. A developer who does not use Tiled never downloads the parser.
The split exists so the user does not pay for what they do not use; the monorepo exists so the
maintainer can test every piece in one CI run and change an API across packages in one PR.

### 2. The same ruler, applied here

| Package | Lines | External dependencies | Does the ruler justify publishing it alone? |
|:---|---:|:---|:---|
| `voxel_core` | 3.437 | meta, vector_math | pure Dart, nothing to avoid downloading |
| `voxel_worldgen` | 5.865 | + `voxel_core` | pure Dart, useless without the core's chunk format |
| `voxel_content` | 950 | + `voxel_core` | pure Dart, same |
| `voxel_signals` | 668 | + `voxel_core` | pure Dart, a niche inside a niche |
| `voxel_net` | 174 | none | generic, but 174 lines is too small to be a package |
| `voxel_scene` | 585 | `flutter_scene` (Flutter GPU, an `Info.plist` flag) | **yes** |
| `voxel_audio` | 296 | `flutter_soloud` (a native library) | **yes** — and it has nothing to do with voxels |
| `voxel_game` | 5.428 | gamepads, path_provider, pointer_lock | **yes**, it is the product |

Five of the eight were split by **subject**, which is internal organisation, not distribution.
Folders under `lib/src/` and one exported library per subject give the same separation for free.

### 3. What eight published packages would cost

Seven of the eight depend on `voxel_core`. Every breaking change to the core becomes seven
version bumps, seven changelog entries and seven `pub publish` runs in topological order, with
seven version constraints edited by hand. Flame pays that because its core has been stable for
years; a `0.x` API that still moves every week does not survive the ritual.

Three things the workspace hides today and publishing would expose:

- `voxel_core: ^0.0.0` means `>=0.0.0 <0.0.1`. It only resolves because pub resolves workspace
  members locally. Published, each of those seven lines becomes a real range, maintained by hand.
- No package carries a `LICENSE`, a `homepage`, a `repository` or `topics`. That is eight times.
- pub points ask every package for an example, dartdoc coverage and declared platforms. Eight
  times.

Consolidating to four cuts the version graph from seven edges to three.

### 4. What is lost, and how it is paid back

The eight-package split enforced the dependency direction physically: the analyzer could not
resolve an import that would have made a cycle between subjects. Merging five packages into one
gives that up — nothing stops `core` from importing `worldgen` afterwards.

**VC3 buys it back**: a test that walks `lib/src/` and fails on an import that crosses a subject
boundary in the wrong direction. It is the same rule, enforced by a test instead of by pub.

---

## The package map after this plan

```
voxel_engine    pure Dart      core     grid, mesher, streaming, physics, rays, models,
                                        pathfinder, liquids, persistence
                               worldgen noise, biomes, caves, ores, trees, structures
                               content  block / item registries, mining, inventory,
                                        crafting, loot, status effects
                               signals  circuits, wires, lamps, doors, rails
                               net      a TCP host and clients over JSON lines
voxel_scene     flutter_scene  chunk views, terrain material, rigs, outlines, sky
sound_recipes   flutter_soloud sounds synthesised from recipes, no audio files
voxel_game      Flutter        the kit: VoxelGameSpec, loop, input, player, cameras,
                               mobs, spawns, drops, HUD, save, host / join
```

Dependencies still only point down: `voxel_game` → everything; `voxel_scene` → `voxel_engine`;
`sound_recipes` → nothing of ours. No package imports `package:cubeworld_poc`.

### The libraries `voxel_engine` exports

One library per subject, plus an umbrella for whoever wants the whole thing:

```dart
import 'package:voxel_engine/voxel_engine.dart'; // all five
import 'package:voxel_engine/core.dart';         // just the chunk grid and physics
import 'package:voxel_engine/worldgen.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/signals.dart';
import 'package:voxel_engine/net.dart';
```

The rewrite of every importer is one-to-one, which is why the merge is mechanical:
`package:voxel_core/voxel_core.dart` → `package:voxel_engine/core.dart`, and the same for the
other four. Our own code keeps importing the narrow library it used before, so the narrow
libraries stay exercised instead of decorative. Checked before starting: the five packages
share no top-level name, so the umbrella library has no collision to resolve.

---

## VC1 — `voxel_engine`

| Step | What |
|:---|:---|
| VC1.1 | Create `packages/voxel_engine/`: pubspec (meta, vector_math, SDK `^3.13.0`, `0.0.0`, `publish_to: none`, `resolution: workspace`), analysis options, the six libraries. |
| VC1.2 | `git mv` each package's `lib/src/` into `lib/src/<subject>/`; rewrite cross-subject imports to `package:voxel_engine/<subject>.dart`. |
| VC1.3 | `git mv` each package's `test/` into `test/<subject>/`. |
| VC1.4 | `git mv` the four one-file examples into `example/<subject>_example.dart`, and add `example/voxel_engine_example.dart` — one end-to-end run across subjects, which is the argument for the package being one package. |
| VC1.5 | Rewrite every importer (the POC, `voxel_scene`, `voxel_game`, both example apps), the workspace list and the dependent pubspecs; delete the five old package folders. |

Gate: `dart analyze` clean and every test that passed before passes, counted package by package.

## VC2 — `sound_recipes`

| Step | What |
|:---|:---|
| VC2.1 | `git mv packages/voxel_audio packages/sound_recipes`, rename the library file and the pubspec name, rewrite `voxel_game` and the POC, update the workspace list. The API keeps its names — `SoundRecipe`, `SoundBank`, `StockSounds` — because they are what the new package name is taken from. |

Gate: no `voxel_audio` left anywhere; the example still analyses.

## VC3 — the dependency-direction guard

| Step | What |
|:---|:---|
| VC3.1 | `voxel_engine/test/architecture_test.dart`: read every file under `lib/src/`, collect its `package:voxel_engine/<subject>.dart` imports, and fail unless each one is allowed. Allowed edges: `worldgen → core`, `content → core`, `signals → core`. `core` and `net` import no subject. The test fails with the offending file and edge named. |

Gate: the test fails when an illegal import is introduced on purpose, and passes on the tree.

## VC4 — docs for four packages

| Step | What |
|:---|:---|
| VC4.1 | `voxel_engine` and `sound_recipes` get a README (what it is, features, install, a numbered walkthrough per subject, the examples) and a CHANGELOG at `0.0.0`. The five old READMEs are folded in, not thrown away. |
| VC4.2 | `voxel_scene` and `voxel_game`: install sections and dependency lists updated to the four-package map. |
| VC4.3 | This plan's progress table and log; the VK plan's package map gets a pointer here; memory updated. |
| VC4.4 | `PUBLISHING.md` next to the packages: the checklist that has to pass **after** the move to a repository of its own — license, `homepage` / `repository` / `topics`, `publish_to` removed, `^0.0.0` replaced by real ranges, `dart pub publish --dry-run` in topological order, pub points. Written, not executed. |

---

## The pre-publish checklist (VC4.4, for the repository move — not done here)

1. **A repository of its own.** The packages live on a branch of a game repository today; a
   published package's `repository:` field has to point at a repository that is the packages'
   home, with its own history, its own CI and its own contribution rules.
2. **A license**, chosen by the developer, one `LICENSE` per package. Without it the code is "all
   rights reserved" and pub.dev docks the score.
3. **Metadata**: `homepage`, `repository`, `issue_tracker`, `topics`, a one-line `description`
   between 60 and 180 characters, `platforms` where it is not obvious.
4. **Real version constraints.** `voxel_engine: ^0.0.0` becomes `^0.1.0` once the first release
   is cut. Decide the first published version — `0.1.0` says "usable, unstable" better than
   `0.0.1`.
5. **`publish_to: none` removed** from the four, and kept on the two example apps.
6. **Publish in topological order**: `voxel_engine`, then `voxel_scene` and `sound_recipes`, then
   `voxel_game`. `dart pub publish --dry-run` on each first.
7. **Consider the intermediate step.** A `git:` dependency with `path:` gives the monorepo
   layout and reuse across the developer's own projects with none of the release ceremony. It is
   a legitimate place to stop if publishing is not worth it yet.

---

## Log

**VC1, 2026-09-19 (`8a2b9853`).** The merge was mechanical, as designed: five
`git mv`s into `lib/src/<subject>/`, one `sed` over every importer, five
dependency lines collapsed into one. `dart analyze` was clean on the first run
and the merged suite counts 164 tests — 104 + 42 + 12 + 5 + 1, exactly what the
five counted apart. `lib/src/worldgen/core/` was left where it was rather than
renamed; nested under `worldgen` it is not ambiguous, and the move was already
large enough.

A sixth example, `voxel_engine_example.dart`, was written for the merge: it
declares blocks with `content`, compiles a `worldgen` spec against
`registry.ids`, meshes a chunk and casts a ray with `core`, and mines what the
ray hit back into a `content` bag. It is the argument for the package being one
package, in a form that runs.

**VC2, 2026-09-19.** `voxel_audio` → `sound_recipes`. The API kept every name
(`SoundRecipe`, `SoundBank`, `StockSounds`, `MusicDirector`) — the new package
name is taken from them. The `[voxel_audio]` prefix in its debug output and the
example's app bar moved too.

**VC3, 2026-09-19.** `voxel_engine/test/architecture_test.dart` reads the
import lines of every file under `lib/src/` and fails on an edge the map above
does not allow, naming the file and the edge. Verified both ways: an import of
`worldgen` added to `lib/src/core/math/ivec3.dart` failed it with
`core must not import worldgen`, and removing it passed. It also checks that
each subject library exports only its own folder and that the umbrella exports
all five, so a new subject cannot be added and left out.

**VC4, 2026-09-19.** `voxel_engine` and `sound_recipes` have a README and a
CHANGELOG; the five old READMEs are folded into the engine's, one usage section
per subject. `voxel_scene` and `voxel_game` name the new packages. The
pre-publish checklist is `packages/PUBLISHING.md`, which is written to be read
on the day the packages move, not today.
