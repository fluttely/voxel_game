import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

const int _stone = 1;
const int _glass = 2;

final _table = VoxelBlockTable(const [
  VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.5),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: false, r: 0.8, g: 0.9, b: 1.0, a: 0.4),
]);

/// Jobs answered on the calling isolate: stone below y 40, air above.
class _Jobs implements ChunkJobs {
  final List<(int, int, int)> generated = [];

  /// The next generate job fails with this, once.
  Object? failNext;

  @override
  Future<Uint8List> generate(int cx, int cz, [int dimension = 0]) {
    final fail = failNext;
    if (fail != null) {
      failNext = null;
      return Future.error(fail);
    }
    generated.add((cx, cz, dimension));
    return Future.value(Uint8List(ChunkSize.volume)..fillRange(0, ChunkSize.sizeX * ChunkSize.sizeZ * 40, _stone));
  }

  @override
  Future<ChunkMeshResult> mesh(int cx, int cz, List<Uint8List?> ring) => Future.value(
      _table.mesher().build(cx, cz, ring));
}

class _Sink implements ChunkMeshSink {
  final List<ChunkPos> applied = [];
  final List<ChunkPos> removed = [];

  @override
  void apply(ChunkPos pos, ChunkMeshResult result) => applied.add(pos);

  @override
  void remove(ChunkPos pos) => removed.add(pos);
}

/// Frames until nothing is pending, in flight or waiting for the sink.
Future<void> _settle(ChunkStreamer s) async {
  for (var frame = 0; frame < 500; frame++) {
    s.update();
    await Future<void>.delayed(Duration.zero);
    if (s.isIdle) return;
  }
  fail('the streamer never went idle');
}

void main() {
  late _Jobs jobs;
  late _Sink sink;
  late ChunkStreamer s;

  setUp(() {
    jobs = _Jobs();
    sink = _Sink();
    s = ChunkStreamer(table: _table, sink: sink, loadRadius: 1)..jobs = jobs;
  });

  test('a radius-1 window meshes 9 chunks over a generated 5x5 ring', () async {
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    expect(s.meshCount, 9);
    expect(sink.applied.toSet(), {for (var z = -1; z <= 1; z++) for (var x = -1; x <= 1; x++) (x: x, z: z)});
    expect(s.loadedChunkCount, 25);
    expect(s.chunksBuilt, 9);
    expect(s.facesEmitted, greaterThan(0));
  });

  test('nothing dispatches without jobs', () async {
    s.jobs = null;
    s.updateAround((x: 0, z: 0));
    s.update();
    await Future<void>.delayed(Duration.zero);
    expect(s.pendingCount, 9);
    expect(s.loadedChunkCount, 0);
  });

  test('an opaque edit remeshes the whole 3x3 ring; a clear one inside a chunk only its own', () async {
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    expect(s.setBlock(const IVec3(8, 40, 8), _stone), isTrue);
    expect(s.remeshesQueued, 9);
    expect(s.getBlockXYZ(8, 40, 8), _stone);
    await _settle(s);
    expect(sink.applied, hasLength(18));

    expect(s.setBlock(const IVec3(8, 41, 8), _glass), isTrue);
    expect(s.remeshesQueued, 10);
    expect(s.setBlock(const IVec3(8, 41, 8), _glass), isFalse, reason: 'same id');
    expect(s.setBlock(const IVec3(8, 0, 8), _glass), isFalse, reason: 'y 0 is never edited');
    expect(s.setBlock(const IVec3(900, 50, 900), _glass), isFalse, reason: 'not generated');
  });

  test('a clear edit on a chunk border also remeshes the neighbour across it', () async {
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    s.setBlock(const IVec3(0, 41, 8), _glass);
    expect(s.remeshesQueued, 2);
  });

  test('moving the centre unloads meshes past the unload radius', () async {
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    s.updateAround((x: 10, z: 0));
    expect(sink.removed.toSet(), {for (var z = -1; z <= 1; z++) for (var x = -1; x <= 1; x++) (x: x, z: z)});
    await _settle(s);
    expect(s.meshCount, 9);
  });

  test('light reads open sky until a chunk is meshed, then the mesh job volume', () async {
    expect(s.lightAt(const IVec3(3, 20, 3)), (sky: 15, block: 0));
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    expect(s.lightAt(const IVec3(3, 20, 3)).sky, 0, reason: 'inside the stone');
    expect(s.lightAt(const IVec3(3, 60, 3)).sky, 15);
  });

  test('edits are kept per dimension and land when their chunk generates again', () async {
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    s.setBlock(const IVec3(5, 45, 5), _stone);
    s.storeEditElsewhere(1, const IVec3(2, 50, 2), _glass);
    expect(() => s.storeEditElsewhere(0, const IVec3(2, 50, 2), _glass), throwsArgumentError);

    s.switchDimension(1);
    expect(s.dimension, 1);
    expect(s.meshCount, 0);
    expect(s.editCount, 1);
    expect(s.editCountIn(0), 1);
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    expect(jobs.generated.last.$3, 1);
    expect(s.getBlockXYZ(2, 50, 2), _glass);

    s.switchDimension(0);
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    expect(s.getBlockXYZ(5, 45, 5), _stone);
    expect(s.getBlockXYZ(2, 50, 2), 0);
    expect(s.editsByDimension.keys, containsAll([0, 1]));
  });

  test('a failed job is rethrown by the next update, and the chunk is dispatched again', () async {
    jobs.failNext = StateError('generator bug');
    s.updateAround((x: 0, z: 0));
    s.update();
    await Future<void>.delayed(Duration.zero);
    expect(s.update, throwsStateError);
    await _settle(s);
    expect(s.meshCount, 9);
  });

  test('a cancelled job is not an error', () async {
    jobs.failNext = const ChunkJobCancelled('pool disposed');
    s.updateAround((x: 0, z: 0));
    s.update();
    await Future<void>.delayed(Duration.zero);
    await _settle(s);
    expect(s.meshCount, 9);
  });

  test('replaceEdits swaps every delta, the live one included', () async {
    s.replaceEdits({
      0: {(x: 0, z: 0): {ChunkSize.index(1, 60, 1): _stone}},
    });
    expect(s.editCount, 1);
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    expect(s.getBlockXYZ(1, 60, 1), _stone);
  });

  test('a world cell maps to its chunk by floor division, negative coordinates included', () {
    expect(ChunkStreamer.chunkOfXZ(0, 15), (x: 0, z: 0));
    expect(ChunkStreamer.chunkOfXZ(-1, 16), (x: -1, z: 1));
    expect(ChunkStreamer.chunkOfXZ(-16, -17), (x: -1, z: -2));
    final keys = {for (final c in [-2, -1, 0, 1, 2]) for (final d in [-2, -1, 0, 1, 2]) ChunkStreamer.keyOf(c, d)};
    expect(keys, hasLength(25));
  });

  test('block and light queries find a cell across a negative chunk border', () async {
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    expect(s.setBlock(const IVec3(-1, 50, -16), _glass), isTrue);
    expect(s.getBlockXYZ(-1, 50, -16), _glass);
    expect(s.getBlockXYZ(0, 50, -16), 0);
    expect(s.getBlockXYZ(-1, 50, -17), 0);
    expect(s.chunkAtXZ(-1, -16), same(s.chunks[(x: -1, z: -1)]));
    expect(s.lightAt(const IVec3(-1, 20, -16)).sky, 0, reason: 'inside the stone');
  });

  test('the chunk map is read-only', () async {
    s.updateAround((x: 0, z: 0));
    await _settle(s);
    expect(() => s.chunks.remove((x: 0, z: 0)), throwsUnsupportedError);
  });
}
