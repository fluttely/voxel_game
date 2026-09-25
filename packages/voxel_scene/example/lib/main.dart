// voxel_scene without a game: sine hills streamed by voxel_core's worker isolates
// and drawn by VoxelChunkView under a flutter_scene sun, from an orbiting camera.
//
//   cd example && flutter run -d macos
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Scene.initializeStaticResources();
  // Before the first TerrainMaterial is built, or the view draws stock PBR.
  await TerrainMaterial.loadLibrary();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: HillsView()));
}

const int stone = 1, dirt = 2, grass = 3, water = 4, lamp = 5;

/// The example's blocks; id 0 is air.
final VoxelBlockTable table = VoxelBlockTable(const [
  VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.42, g: 0.42, b: 0.45),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.45, g: 0.31, b: 0.19),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.30, g: 0.58, b: 0.22),
  VoxelBlockDef(
    shape: BlockShape.liquid,
    solid: false,
    opaque: false,
    r: 0.2,
    g: 0.42,
    b: 0.78,
    a: 0.62,
    liquidKind: 0,
    liquidSource: true,
  ),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.98, g: 0.88, b: 0.5, emission: 15),
]);

/// Rolling hills, water below [seaLevel], a lamp every 24 blocks. Pure in the
/// position, as a generator on a worker isolate must be.
class HillsGenerator implements ChunkGenerator {
  const HillsGenerator();

  static const int seaLevel = 38;

  /// The first air cell above the ground of column ([x], [z]).
  static int surfaceHeight(int x, int z) => 40 + (7 * math.sin(x / 9) * math.cos(z / 11)).round();

  @override
  Uint8List generateIn(int cx, int cz, int dimension) {
    final blocks = Uint8List(ChunkSize.volume);
    for (var z = 0; z < ChunkSize.sizeZ; z++) {
      for (var x = 0; x < ChunkSize.sizeX; x++) {
        final wx = cx * ChunkSize.sizeX + x, wz = cz * ChunkSize.sizeZ + z;
        final h = surfaceHeight(wx, wz);
        for (var y = 0; y < h; y++) {
          blocks[ChunkSize.index(x, y, z)] = y < h - 3 ? stone : (y == h - 1 && h > seaLevel ? grass : dirt);
        }
        for (var y = h; y <= seaLevel; y++) {
          blocks[ChunkSize.index(x, y, z)] = water;
        }
        if (h > seaLevel && wx % 24 == 8 && wz % 24 == 8) blocks[ChunkSize.index(x, h, z)] = lamp;
      }
    }
    return blocks;
  }
}

/// The worker isolates build their generator with this. A top-level function:
/// the pool sends it to each isolate.
ChunkGenerator makeGenerator() => const HillsGenerator();

class HillsView extends StatefulWidget {
  const HillsView({super.key});

  @override
  State<HillsView> createState() => _HillsViewState();
}

class _HillsViewState extends State<HillsView> {
  final Scene _scene = Scene();
  final VoxelChunkView _view = VoxelChunkView();
  late final ChunkStreamer _streamer = ChunkStreamer(table: table, sink: _view, loadRadius: 6);
  final ValueNotifier<String> _stats = ValueNotifier('starting the workers');
  final vm.Vector3 _target = vm.Vector3(8, 44, 8);
  ChunkWorkerPool? _pool;
  double _angle = 0.0;
  double _statsClock = 0.0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _light();
    _scene.add(_view.root);
    _start();
  }

  void _light() {
    final horizon = vm.Vector3(0.62, 0.78, 0.92);
    final sky = GradientSkySource(sunSharpness: 600.0)
      ..zenithColor = vm.Vector3(0.20, 0.42, 0.85)
      ..horizonColor = horizon
      ..groundColor = horizon * 0.9
      ..sunDirection = vm.Vector3(0.4, 0.75, 0.55).normalized()
      ..sunColor = vm.Vector3(1.0, 0.95, 0.85) * 2.9;
    _scene
      ..skybox = Skybox(sky)
      ..sunLight =
          (SunLight(
              sky,
              castsShadow: true,
              shadowMaxDistance: 140.0,
              shadowMapResolution: 2048,
              shadowCascadeCount: 4,
              shadowSoftness: 0.04,
              shadowDepthBias: 0.02,
              shadowNormalBias: 0.06,
              // voxel_core meshes wind clockwise; MirroredCamera shows them the right
              // way round, and the unmirrored shadow pass draws their front faces.
              shadowCasterFaces: MirroredCamera.shadowCasterFaces,
            )
            ..color = vm.Vector3(1.0, 0.95, 0.85)
            ..intensity = 2.5)
      ..toneMapping = ToneMappingMode.aces
      ..environment = EnvironmentMap.constantDiffuse(vm.Vector3(0.80, 0.84, 0.92) * 0.5);
    _scene.fog
      ..enabled = true
      ..mode = FogMode.exponential
      ..density = 0.006
      ..color = horizon
      ..skyColorInfluence = 1.0
      ..maxOpacity = 0.9;
  }

  Future<void> _start() async {
    final pool = ChunkWorkerPool(ChunkWorkerConfig(generator: makeGenerator, table: table));
    await pool.start();
    if (_disposed) {
      pool.dispose();
      return;
    }
    _pool = pool;
    _streamer
      ..jobs = pool
      ..updateAround(ChunkStreamer.chunkOfXZ(_target.x.floor(), _target.z.floor()));
  }

  void _tick(double dt) {
    _angle += 0.08 * dt;
    final pool = _pool;
    if (pool == null) return;
    _streamer.update();
    _statsClock += dt;
    if (_statsClock >= 0.5) {
      _statsClock = 0.0;
      _stats.value =
          '${_streamer.meshCount} chunks, ${_streamer.facesEmitted} faces, '
          '${pool.workers} workers${_streamer.isIdle ? '' : ', streaming'}';
    }
  }

  Camera _camera() => MirroredCamera(
    position: _target + vm.Vector3(math.cos(_angle) * 56, 30, math.sin(_angle) * 56),
    target: _target,
    fovRadiansY: 65 * math.pi / 180,
    fovNear: 0.1,
    fovFar: 500,
  );

  @override
  void dispose() {
    _disposed = true;
    _streamer.jobs = null;
    _pool?.dispose();
    _stats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      SceneView(_scene, cameraBuilder: (elapsed) => _camera(), onTick: (elapsed, dt) => _tick(dt)),
      Positioned(
        left: 12,
        top: 12,
        child: ValueListenableBuilder<String>(
          valueListenable: _stats,
          builder: (context, text, _) => Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              shadows: [Shadow(offset: Offset(1, 1))],
            ),
          ),
        ),
      ),
    ],
  );
}
