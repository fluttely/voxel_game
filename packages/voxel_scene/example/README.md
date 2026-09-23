# voxel_scene example

Sine hills with a lake and a few lamps, generated and meshed on worker isolates by
`voxel_engine` and drawn by `VoxelChunkView` under a flutter_scene sun with shadows.

```sh
cd example
flutter run -d macos
```

- macOS only. Flutter GPU is turned on in `macos/Runner/Info.plist`
  (`FLTEnableFlutterGPU`).
- The app has no `hook/build.dart`: flutter_scene compiles its own shaders, and
  voxel_scene ships its terrain shader bundle as a package asset.
- `voxel_engine` meshes wind clockwise, so the camera mirrors clip-space x
  (`MirroredCamera` in `lib/main.dart`) and the sun's shadow pass draws front faces.
