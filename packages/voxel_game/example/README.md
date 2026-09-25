# voxel_game example

A small Minecraft-like in one file (`lib/main.dart`): twelve blocks, a world
of forest and plains with trees and coal, a few recipes, a player with a
pickaxe, sheep by day and zombies by night.

```bash
flutter run -d macos          # or a phone: flutter run -d <device id>
```

The macOS, Android and iOS runners turn on Flutter GPU, which `flutter_scene` draws
through (`macos/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`,
`ios/Runner/Info.plist`); the Windows and Linux ones cannot yet (`docs/LEDGER.md`, KL-005).

Click to play. WASD move, Space jump, Shift run, Ctrl sneak, mouse look, left button
mine or hit, right button place, 1-9 or the wheel pick a hotbar slot, V first or third
person, Q drop, Escape frees the mouse. A gamepad works too.

## Benchmark

`lib/benchmark.dart` runs this game as a benchmark: a fixed world, a scripted camera, the
frames measured, one JSON line printed. `dart tool/run_benchmark.dart` from the
repository's root builds it in release and runs it; the method is in
`docs/VOXEL_PERF_PLAN_2026-09-25.md`.
