// The engine core without a renderer: worker isolates stream a window of sine hills,
// a sink counts the meshes, then a ray, an edit and a falling body read the world.
//
//   dart run example/core_example.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

const int stone = 1, dirt = 2, grass = 3, water = 4, lamp = 5;

/// The example's blocks; id 0 is air.
final VoxelBlockTable table = VoxelBlockTable(const [
  VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.42, g: 0.42, b: 0.45),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.45, g: 0.31, b: 0.19),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.30, g: 0.58, b: 0.22),
  VoxelBlockDef(
      shape: BlockShape.liquid, solid: false, opaque: false, r: 0.2, g: 0.42, b: 0.78, a: 0.62, liquidKind: 0, liquidSource: true),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.98, g: 0.88, b: 0.5, emission: 15),
]);

/// Rolling hills with water below [seaLevel]. Pure in the position, as a
/// generator on a worker isolate must be.
class HillsGenerator implements ChunkGenerator {
  /// The one generator; it has no state.
  const HillsGenerator();

  /// Columns whose ground ends below this fill with water up to it.
  static const int seaLevel = 38;

  /// The first air cell above the ground of column ([x], [z]).
  static int surfaceHeight(int x, int z) => 40 + (7 * math.sin(x / 9) * math.cos(z / 11)).round();

  @override
  Uint8List generateIn(int cx, int cz, int dimension) {
    final blocks = Uint8List(ChunkSize.volume);
    for (var z = 0; z < ChunkSize.sizeZ; z++) {
      for (var x = 0; x < ChunkSize.sizeX; x++) {
        final h = surfaceHeight(cx * ChunkSize.sizeX + x, cz * ChunkSize.sizeZ + z);
        for (var y = 0; y < h; y++) {
          blocks[ChunkSize.index(x, y, z)] = y < h - 3 ? stone : (y == h - 1 && h > seaLevel ? grass : dirt);
        }
        for (var y = h; y <= seaLevel; y++) {
          blocks[ChunkSize.index(x, y, z)] = water;
        }
      }
    }
    return blocks;
  }
}

/// The worker isolates build their generator with this. A top-level function:
/// the pool sends it to each isolate.
ChunkGenerator makeGenerator() => const HillsGenerator();

/// Where finished meshes would go in a renderer; here, a count.
class CountingSink implements ChunkMeshSink {
  /// Chunks that hold a mesh.
  final Set<ChunkPos> meshed = {};

  /// Faces in every mesh received, remeshes included.
  int faces = 0;

  @override
  void apply(ChunkPos pos, ChunkMeshResult result) {
    meshed.add(pos);
    faces += result.faces;
  }

  @override
  void remove(ChunkPos pos) => meshed.remove(pos);
}

/// The streamer's blocks, as physics and rays read them.
class StreamedWorld implements VoxelQuery {
  /// A view of [streamer]'s generated chunks.
  StreamedWorld(this.streamer);

  /// Holds the chunks.
  final ChunkStreamer streamer;

  @override
  VoxelBlockTable get table => streamer.table;

  @override
  int getBlockXYZ(int x, int y, int z) => streamer.getBlockXYZ(x, y, z);
}

/// Calls [ChunkStreamer.update] once a frame until nothing is left to do.
Future<void> settle(ChunkStreamer streamer) async {
  while (!streamer.isIdle) {
    streamer.update();
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

Future<void> main() async {
  final sink = CountingSink();
  final streamer = ChunkStreamer(table: table, sink: sink, loadRadius: 3);
  final pool = ChunkWorkerPool(ChunkWorkerConfig(generator: makeGenerator, table: table));
  await pool.start();
  streamer
    ..jobs = pool
    ..updateAround((x: 0, z: 0));

  final clock = Stopwatch()..start();
  await settle(streamer);
  print('${sink.meshed.length} chunks meshed on ${pool.workers} workers in ${clock.elapsedMilliseconds} ms, '
      '${sink.faces} faces');

  final world = StreamedWorld(streamer);
  final hit = VoxelRaycast.solid(world, Vector3(4.5, 100, 4.5), Vector3(0, -1, 0), 100)!;
  print('a ray straight down at (4, 4) hits block ${hit.block} (id ${world.getBlockXYZ(hit.block.x, hit.block.y, hit.block.z)}) '
      'after ${hit.distance.toStringAsFixed(2)}');

  final above = hit.block + hit.normal;
  streamer.setBlock(above, lamp);
  await settle(streamer);
  print('a lamp placed at $above queued ${streamer.remeshesQueued} remeshes; the cell beside it has block light '
      '${streamer.lightAt(above + const IVec3(1, 0, 0)).block}');

  // A save holds the edits only; the generator rebuilds everything else.
  const codec = EditDeltaCodec(magic: 0x4C58564F, version: 1, dimensions: 1);
  final bytes = codec.encode(7, streamer.editsByDimension);
  final saved = codec.decode(bytes);
  print('the edits save to ${bytes.length} bytes and read back as ${saved.edits[0]!.length} chunk with an edit');

  final body = VoxelBody()
    ..setup(world, 0.3, 1.8)
    ..position = Vector3(10.5, 80, 10.5);
  var ticks = 0;
  for (; ticks < 600 && !body.onFloor; ticks++) {
    body
      ..applyGravity(1 / 60)
      ..move(1 / 60);
  }
  print('a body dropped from y 80 at (10, 10) stands at y ${body.position.y.toStringAsFixed(3)} after $ticks ticks '
      '(ground ends at ${HillsGenerator.surfaceHeight(10, 10)})');

  pool.dispose();
}
