# voxel_game

A voxel sandbox kit for Flutter, in four packages. A game declares its blocks, world,
player and creatures in one `VoxelGameSpec` and calls `runVoxelGame`; the 3D world is drawn
with [`flutter_scene`](https://pub.dev/packages/flutter_scene) (Flutter GPU / Impeller).

| Package | Kind | What it is | Depends on |
|:---|:---|:---|:---|
| [`voxel_game`](packages/voxel_game) | Flutter | `VoxelGameSpec`, loop, input, player, cameras, mobs, HUD, save, host / join — what a game imports | all three |
| [`voxel_scene`](packages/voxel_scene) | flutter_scene | chunk views, terrain material, rigs, outlines, sky | `voxel_engine` |
| [`voxel_engine`](packages/voxel_engine) | pure Dart | core · worldgen · content · signals · net | — |
| [`sound_recipes`](packages/sound_recipes) | flutter_soloud | sounds synthesised from recipes, no audio files | — |

It targets macOS, iOS, Android, Windows and Linux (macOS and Android are the measured ones),
from Flutter 3.47.1 with Flutter GPU turned on in each runner ([the table](packages/voxel_game/README.md#install)), and not on
the web: worlds are streamed on isolates, multiplayer is TCP sockets and saves are files.

A game needs only `voxel_game`: start at [its README](packages/voxel_game/README.md) and
[its example](packages/voxel_game/example/lib/main.dart).

## Layout

```
pubspec.yaml     the pub workspace — not a package, never published
packages/        the four packages, each with its own example
tool/            publish_package.sh
docs/            the plans and the architecture ledger
CLAUDE.md        the rules the code is held to (AGENTS.md is the same file)
PUBLISHING.md    the release checklist and order
```

## Working on the kit

One `flutter pub get` at the root resolves the whole workspace. The suite, from the root:

```sh
flutter analyze                                         # zero issues, all four packages
(cd packages/voxel_game    && flutter test)
(cd packages/voxel_engine  && dart test)                # pure Dart
(cd packages/voxel_scene   && flutter test)
(cd packages/sound_recipes && flutter test)
```

`cd packages/voxel_game/example && flutter run -d macos` plays the kit's example. Releasing
is [`PUBLISHING.md`](PUBLISHING.md).
