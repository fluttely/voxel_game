# Publishing these packages

All four packages are on pub.dev. `0.1.0-dev` went out on 2026-09-23, `0.1.1-dev` on
2026-09-25 (Windows and Linux runners, the phone graphics preset, the frame measurements)
and `0.1.2-dev` after it (the frame-rate work of the PF plan, the fixes that give every
package its 160 pub points). `0.2.0-dev` followed, the four moving together: frames drawn between two steps, the greedy mesher, the packed terrain vertex and
recipe music. It broke the API (`MeshSurface.colors`, `RigInstance.place`, the bundle
`TerrainMaterial.loadLibrary` requires). `0.3.0-dev` went out on 2026-09-29, again with the four together: it broke the API
once more (`VoxelChunkView` draws what changed in `rebuild`), and below 1.0 a break moves the minor: a caret
range such as `^0.2.0-dev` stops before `0.3.0`, so nobody on it is upgraded into the break.
`0.4.0-dev` is the next release, the four together once more: the Minecraft clone's
mechanics taken into the kit (`docs/VOXEL_ABSORB_PLAN_2026-09-30.md`) and the ledger's
debts paid (`docs/VOXEL_LEDGER_PLAN_2026-10-04.md`). It breaks the API in `voxel_engine`
(`StructureSpec` takes a `Structure`) and in `voxel_game` (events instead of the spec's
callbacks, the screens a state machine, `SoundSpec.music`, `FrameStats.fps` the scene's
rate, and more); each CHANGELOG opens its `0.4.0-dev` with the list. Each package is under the MIT license, with
its metadata and real version ranges (`docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md`, VR4). They resolve
each other through the pub workspace declared in the root `pubspec.yaml`, which is
not a package: all four live under `packages/`. The reasoning behind the four-package split is in
[`docs/VOXEL_CONSOLIDATION_PLAN_2026-09-19.md`](docs/VOXEL_CONSOLIDATION_PLAN_2026-09-19.md),
and how the folder got this shape in
[`docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md`](docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md).

## The four packages

| Package | Kind | Depends on |
|:---|:---|:---|
| `voxel_engine` | pure Dart | — |
| `voxel_scene` | Flutter + flutter_scene | `voxel_engine` |
| `sound_recipes` | Flutter + flutter_soloud | — |
| `voxel_game` | Flutter | all three |

`example/` and `packages/voxel_scene/example/` are apps, not packages. They stay
`publish_to: none` for good.

**Every package publishes in place, and none has a `.pubignore`.** Inside a git
repository pub bundles a package's own folder, filtered by the `.gitignore` files
from the git root down to it. The root holds no package, so nothing above a
package has to be hidden from it, and the repository's own files (`CLAUDE.md`,
`AGENTS.md`, this file, `README.md`, `docs/`, `tool/`, `.github/`) sit where no tarball looks.
Each package ships its `example/` whole, its runners included — they are where a
reader sees Flutter GPU turned on, one platform at a time.

Until 2026-09-23 `voxel_game` sat at the root. It needed a `.pubignore` with
`packages/` to keep the other three out of its tarball, and that same line hid the
nested three from themselves (pub applies every parent folder's ignore file up to
the git root), so they could only publish from a copy of the folder with no `.git`.
Moving `voxel_game` under `packages/` removed both. Do not put a package back at
the root.

## Before the first release

Nothing is left. Done in VR4 (2026-09-23), and after it:

- **A repository of its own**: `https://github.com/fluttely/voxel_game`. Every
  pubspec points at it, each package at its `tree/main/packages/<p>` path.

- **A license**: MIT, the same `LICENSE` in each of the four.
- **Metadata in each pubspec**: `homepage`, `repository`, `issue_tracker`,
  `topics`, and a `description` between 60 and 180 characters.
- **Real version constraints**: `^0.1.0-dev` between the four, and in the two
  example apps. (`^0.0.0` means `>=0.0.0 <0.0.1`; it only resolved because pub
  resolves workspace members locally.)
- **`0.1.0-dev` as the first version.** It says "usable, the API still moves" far
  better than `0.0.1`, and leaves `0.0.x` unused rather than spent. The `-dev`
  pre-release tag says the same thing about the number itself: nothing at
  `0.1.0-dev` has been published, so `0.1.0` stays free for the first real
  release instead of being spent on a version nobody outside this repo ever saw.
- **`publish_to: none` removed** from the four packages, kept on the two example
  apps.
- **A CI that runs the whole workspace** (VL1, 2026-10-05):
  `.github/workflows/ci.yml`, on GitHub Actions with Flutter 3.47.5 pinned, runs
  `flutter analyze`, the format check and the five suites (the four packages' and
  the minecraft app's) on every push to `dev` and `main` and on every PR. That is
  the reason the monorepo exists.

## Releasing

Always in dependency order, because a package cannot be published against
versions that do not exist yet:

```sh
# from the root
tool/publish_package.sh voxel_engine  --dry-run
tool/publish_package.sh sound_recipes --dry-run
tool/publish_package.sh voxel_scene   --dry-run
tool/publish_package.sh voxel_game    --dry-run
```

Then the same four without `--dry-run`, in that order, bumping the constraint in
each dependent to the version just released. `voxel_engine` and `sound_recipes`
do not depend on each other, so their order between themselves does not matter.

**Each package gets a tag at the release commit**, `<package>-v<version>`, pushed with
the release, so a git dependency (below) has a name to pin:

```sh
for p in voxel_engine sound_recipes voxel_scene voxel_game; do
  git tag "$p-v0.4.0-dev"
done
git push origin voxel_engine-v0.4.0-dev sound_recipes-v0.4.0-dev voxel_scene-v0.4.0-dev voxel_game-v0.4.0-dev
```

No release before `0.4.0-dev` was tagged.

**A dependent waits for its dependencies' analysis.** pub.dev analyses a version the
moment it lands, and a version published seconds earlier is not yet visible to its
analyser. `0.1.1-dev` went out four packages in thirty seconds, and `voxel_scene` and
`voxel_game` scored 50 of 160: "could not find package voxel_engine" failed every check
that resolves dependencies. `tool/publish_package.sh` now polls
`https://pub.dev/api/packages/<dep>/metrics` until the dependency's version in this tree
has been analysed, then publishes.

**The pub points, all 160.** Beyond the metadata above, three things lose them:

- **Formatting** (10): pana runs `dart format` on every file. Each package, and each
  example app, sets `formatter: page_width: 120` in its `analysis_options.yaml`, the
  width the code is written at; `tool/publish_package.sh` refuses a package that is not
  formatted.
- **Lower bounds** (20): pana runs `flutter pub downgrade` and analyses against the
  lowest version each constraint allows. A constraint's lower bound is the first version
  with every API the package calls (`gamepads: ^0.1.10`, where `NormalizedGamepadState`
  arrived), not the one that happened to be current.
- **Resolution** (up to 110): see the race above.

**One warning is expected and accepted.** `voxel_scene` and `voxel_game` pin
`flutter_scene: 0.23.0` exactly, and pub says the constraint should allow more
than one version. The pin stays: the terrain material imports
`package:flutter_scene/src/gpu/gpu.dart`, a private file outside semver, so even a
patch release of `flutter_scene` can break the build of everyone who installed the
kit. A dry run that ends with that warning and nothing else is green; so is the
"checked-in files are modified" warning while a release is still uncommitted.
Anything else is not. pub's hint that the version is "not an incremental update"
(`0.3.0-dev` to `0.4.0-dev`, where it proposes `0.4.0` or `0.3.0`) is a hint, not a
warning: the `-dev` stays while the API moves.

A published version can never be replaced, only retracted for seven days. The
dry run is not a formality.

## The version graph, and why it is short

Every breaking change in `voxel_engine` is a bump in `voxel_scene` and
`voxel_game`, and a release of all three. That is three edges. It was seven
before the packages were consolidated, which is the whole reason they were.
Keep it that way: a new package here earns its place by carrying a dependency
that its users should be able to refuse, not by being a different subject.

## The step before publishing

Publishing is not the only way to reuse these. A git dependency gives the same
code to another project of your own, with no release ceremony and no promise to
anyone:

```yaml
dependencies:
  voxel_engine:
    git:
      url: https://github.com/fluttely/voxel_game.git
      path: packages/voxel_engine   # or packages/voxel_game, packages/voxel_scene, ...
      ref: voxel_engine-v0.4.0-dev   # a tag, or a commit
```

It is a legitimate place to stop. Publishing buys discoverability and a version
contract with strangers; until someone other than you depends on these, it
mostly buys the ceremony.
