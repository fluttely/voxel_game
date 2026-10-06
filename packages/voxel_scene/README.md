# voxel_scene

Draws `voxel_engine` worlds with [flutter_scene](https://pub.dev/packages/flutter_scene):
chunks drawn a region at a time, a terrain material with its own shaders, a day
and night sky, block models and the selection outline.

> **Status: 0.4.0-dev**, beta. The API can still change.

## Features

- `VoxelChunkView`: a `ChunkMeshSink` that draws chunks in regions (2 × 2 by
  default), one geometry per surface a region, so the terrain costs few draws, and
  its lit surfaces in a packed 16-byte vertex (the engine's is 72) with a vertex
  shader of its own. It rebuilds the regions that changed once a frame, nearest
  first, within a time budget, so a burst of chunks is drawn over a few frames.
- `TerrainMaterial`: the terrain shader (lit, fogged, shadowed).
- `MirroredCamera`: the camera that shows `voxel_engine`'s winding the right way round.
- `SelectionOutline`: the edges of the aimed box, one mesh, one draw; `BoxMesh`, boxes as
  one mesh wound the engine's way, which it is made of.
- `ResizeSafeScene`: a `Scene` to render with when the sun caches its static shadows,
  as `DayNightSky`'s does. It drops the cache on the frame the view changes size, which
  keeps Impeller's Vulkan backend from beginning a render pass on a freed depth texture
  (flutter/flutter#192538), a crash seen on Adreno phones as a game turns to landscape.
- `GpuPacedScene`: a `ResizeSafeScene` whose frames reach the screen only once the GPU has
  finished them, so text over the scene stays readable on a busy GPU under Metal; the
  scene shows one frame late and renders only when the last one is done (`ScenePacer`).
- `ItemMesh`: one mesh per `ItemModel`, shared by everything that draws the item.
- `DayNightSky`: the sun's day, the weather's grey and lightning (`overcast`, `flash`), a
  dimension's own sunless sky (`StillSky`) and a fog of one colour from the eye (`Haze`,
  water's); the numbers are `SkyLook`'s, checked with no GPU.
- `WeatherParticles` (rain and snow around a point) and `DebrisParticles` (chips and
  embers thrown out of one), each one `ParticleSystem`, so one draw.
- `VoxelModelMesh`, with one shared material a tint (`tinted`, see-through under an alpha
  of 1) and a white one for a hit (`flash`); `RigPart`, `NodeBody`.

## Install

```yaml
dependencies:
  voxel_scene: ^0.4.0-dev
```

Dart SDK `^3.13.0`.

- **Flutter 3.47.1 or later**, with Flutter GPU turned on in each runner: `flutter_scene`
  draws through it, and it is off by default. macOS and iOS take
  `<key>FLTEnableFlutterGPU</key><true/>` in `Runner/Info.plist`, Android the
  `io.flutter.embedding.android.EnableFlutterGPU` meta-data in its manifest, Windows
  `project.set_enable_flutter_gpu(true);` in `runner/main.cpp` and Linux
  `fl_dart_project_set_enable_flutter_gpu(project, TRUE);` in `runner/my_application.cc`
  (the last two exist from Flutter 3.47.1). `voxel_game`'s README has the table.
- **Not the web.** `voxel_engine` streams chunks on worker isolates and talks over TCP
  sockets (`dart:isolate`, `dart:io`), which a browser does not have.

- `flutter_scene` is pinned to `0.23.0`: the terrain material and geometry use its
  private GPU layer and its geometry's stream binding.
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

4. **Show it** with a `MirroredCamera`, calling `streamer.update()` and then
   `view.rebuild(centre)` every tick: the streamer hands the view its meshes, and the
   view draws the regions they changed, nearest `centre` first, within its budget.

   ```dart
   SceneView(scene,
       cameraBuilder: (elapsed) => MirroredCamera(position: eye, target: target),
       onTick: (elapsed, dt) {
         streamer.update();
         view.rebuild(ChunkStreamer.chunkOfXZ(0, 0));
       });
   ```

5. **Shadows:** give the `SunLight` `shadowCasterFaces: MirroredCamera.shadowCasterFaces`.

## Example

```sh
cd example
flutter run -d macos
```

[`example/lib/main.dart`](example/lib/main.dart) draws sine hills with a lake
and lamps under a sun with shadows, from a camera that circles them.
