# Publishing these packages

Nothing here is published yet, but all four packages are ready to be: each is at
`0.1.0-dev` under the MIT license, with its metadata and real version ranges, and the
four dry runs pass (`docs/VOXEL_RELAYOUT_PLAN_2026-09-21.md`, VR4). They resolve
each other through the pub workspace declared in this folder's `pubspec.yaml`:
`voxel_game` is both the workspace root and a published package, and the other
three live under `packages/`. The reasoning behind the four-package split is in
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

**`.pubignore` is a requirement, not a tidy-up.** `voxel_game` sits at the root of
the folder that holds the other three packages, and `pub publish` bundles every
file under the package it is not told to ignore. Without the `.pubignore` beside
`pubspec.yaml` (`packages/`, `build/`, `.dart_tool/`, `example/macos/`,
`example/build/`), every release of `voxel_game` would ship `voxel_engine`,
`voxel_scene` and `sound_recipes` inside its own tarball. It also keeps out what
belongs to the repository and not to the package: `CLAUDE.md`, `AGENTS.md`, this
file, `docs/` and `tool/`. And since a `.pubignore` replaces `.gitignore` for its
folder, it repeats the `.gitignore` lines. Read the file list the dry run prints
for `voxel_game` every time.

**That same `packages/` line is why the other three cannot publish in place.**
Inside a git repository, pub applies the ignore files of every folder from the git
root down to the package, so a nested package's own files match the root's
`packages/` and its archive comes out empty ("the pubspec is hidden"). A nested
`.pubignore` cannot re-include them. Outside git, pub reads only the package's
folders — so `tool/publish_package.sh` publishes a nested package from a copy of
this folder with no `.git` in it. Running `pub publish` inside `packages/<p>` by
mistake fails safe: pub refuses to publish an empty package.

## Before the first release

Still to do:

1. **A repository of its own — the next thing that happens.** This folder is
   laid out to be that repository as it stands: moved out whole, its root is the
   package you install, and nothing in it reaches outside it. Every pubspec
   already points at it: `https://github.com/fluttely/voxel_game`, the nested
   three at their `tree/main/packages/<p>` path. Until the move, those links lead
   nowhere.
2. **A CI that runs the whole workspace** — `dart analyze`, `dart test`,
   `flutter test` — on one push. That is the reason the monorepo exists.

Done in VR4 (2026-09-23):

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

## Releasing

Always in dependency order, because a package cannot be published against
versions that do not exist yet:

```sh
# from this folder
tool/publish_package.sh voxel_engine  --dry-run   # from a git-less copy
tool/publish_package.sh sound_recipes --dry-run   # from a git-less copy
tool/publish_package.sh voxel_scene   --dry-run   # from a git-less copy
tool/publish_package.sh voxel_game    --dry-run   # in place
```

Then the same four without `--dry-run`, in that order, bumping the constraint in
each dependent to the version just released. `voxel_engine` and `sound_recipes`
do not depend on each other, so their order between themselves does not matter.

**One warning is expected and accepted.** `voxel_scene` and `voxel_game` pin
`flutter_scene: 0.23.0` exactly, and pub says the constraint should allow more
than one version. The pin stays: the terrain material imports
`package:flutter_scene/src/gpu/gpu.dart`, a private file outside semver, so even a
patch release of `flutter_scene` can break the build of everyone who installed the
kit. A dry run that ends with that warning and nothing else is green; so is the
"checked-in files are modified" warning while a release is still uncommitted.
Anything else is not.

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
      path: packages/voxel_engine   # voxel_game itself has no path: it is the root
      ref: <a tag or a commit>
```

It is a legitimate place to stop. Publishing buys discoverability and a version
contract with strangers; until someone other than you depends on these, it
mostly buys the ceremony.
