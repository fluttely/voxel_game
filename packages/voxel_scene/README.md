# voxel_scene

Draws `voxel_engine` worlds with [flutter_scene](https://pub.dev/packages/flutter_scene):
one scene node per chunk, a terrain material with its own shaders, a day
and night sky, block models and the selection outline.

> **Status: 0.1.0**, the first release. The API can still change.

## Features

- `VoxelChunkView`: a `ChunkMeshSink` that turns each mesh into a scene node.
- `TerrainMaterial`: the terrain shader (lit, fogged, shadowed).
- `MirroredCamera`: the camera that shows `voxel_engine`'s winding the right way round.
- `DayNightSky`, `SelectionOutline`, `VoxelModelMesh`, `RigPart`, `NodeBody`.

## Install

```yaml
dependencies:
  voxel_scene: ^0.1.0
```

Dart SDK `^3.13.0`.

- **macOS for now.** Turn Flutter GPU on in `macos/Runner/Info.plist`:

  ```xml
  <key>FLTEnableFlutterGPU</key>
  <true/>
  ```

- `flutter_scene` is pinned to `0.23.0`: the terrain material uses its private GPU layer.
- The shaders ship compiled in `assets/shaders/`. After a Flutter upgrade or a
  shader edit, rebuild them with `dart tool/build_shaders.dart`.

## Usage

1. **Load the resources** before the first frame.

   ```dart
   WidgetsFlutterBinding.ensureInitialized();
   await Scene.initializeStaticResources();
   await TerrainMaterial.loadLibrary(); // before the first TerrainMaterial
   ```

2. **Put a chunk view in a scene.**

   ```dart
   final scene = Scene();
   final view = VoxelChunkView();
   scene.add(view.root);
   ```

3. **Stream `voxel_engine` chunks into it.** The view is the streamer's sink.

   ```dart
   final streamer = ChunkStreamer(table: table, sink: view, loadRadius: 6)..jobs = pool;
   streamer.updateAround(ChunkStreamer.chunkOfXZ(0, 0));
   ```

4. **Show it** with a `MirroredCamera`, calling `streamer.update()` every tick.

   ```dart
   SceneView(scene,
       cameraBuilder: (elapsed) => MirroredCamera(position: eye, target: target),
       onTick: (elapsed, dt) => streamer.update());
   ```

5. **Shadows:** give the `SunLight` `shadowCasterFaces: MirroredCamera.shadowCasterFaces`.

## Example

```sh
cd example
flutter run -d macos
```

[`example/lib/main.dart`](example/lib/main.dart) draws sine hills with a lake
and lamps under a sun with shadows, from a camera that circles them.
