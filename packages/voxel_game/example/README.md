# voxel_game example

A small Minecraft-like in one file (`lib/main.dart`): twelve blocks, a world
of forest and plains with trees and coal, a few recipes, a player with a
pickaxe, sheep by day and zombies by night.

```bash
flutter run -d macos          # or a phone: flutter run -d <device id>
```

Every runner turns on Flutter GPU, which `flutter_scene` draws through
(`macos/Runner/Info.plist`, `ios/Runner/Info.plist`,
`android/app/src/main/AndroidManifest.xml`, `windows/runner/main.cpp`,
`linux/runner/my_application.cc`); the Windows and Linux settings need Flutter 3.47.1 or
later. There is no web runner: the kit does not run in a browser (see its README).

Click to play. WASD move, Space jump, Shift run, Ctrl sneak, mouse look, left button
mine or hit, right button place, 1-9 or the wheel pick a hotbar slot, V first or third
person, Q drop, Escape frees the mouse. A gamepad works too.

## Benchmark

`lib/benchmark.dart` runs this game as a benchmark: a fixed world, a scripted camera, the
frames measured, one JSON line printed. `dart tool/run_benchmark.dart` from the
repository's root builds it in release and runs it on this Mac, or with
`--android <adb serial>` on a phone; the method is in `docs/VOXEL_PERF_PLAN_2026-09-25.md`.
