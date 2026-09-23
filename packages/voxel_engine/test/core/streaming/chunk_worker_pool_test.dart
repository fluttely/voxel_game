import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

/// Stone below [height], air above, plus a stone column at (0, 0) whose extra
/// height stamps which job made the volume. Every byte is a valid id (0 or 1):
/// an id past the table would throw inside the worker isolate.
class _FlatGenerator implements ChunkGenerator {
  _FlatGenerator(this.height);
  final int height;

  static int stamp(int cx, int cz, int dimension) => (cx * 16 + cz + dimension * 100) % 80;

  /// Chunk x that makes the job throw, and chunk x that kills its worker.
  static const int throws = 13;
  static const int kills = 666;

  @override
  Uint8List generateIn(int cx, int cz, int dimension) {
    if (cx == throws) throw StateError('no terrain at x $throws');
    if (cx == kills) Isolate.current.kill(priority: Isolate.immediate);
    final v = Uint8List(ChunkSize.volume);
    v.fillRange(0, ChunkSize.sizeX * ChunkSize.sizeZ * height, 1);
    for (var y = height; y < height + stamp(cx, cz, dimension); y++) {
      v[ChunkSize.index(0, y, 0)] = 1;
    }
    return v;
  }
}

/// Made in a top-level function, so the closure captures only [height].
ChunkGeneratorFactory _flatFactory(int height) => () => _FlatGenerator(height);

ChunkGenerator _brokenFactory() => throw StateError('the generator could not be built');

final _table = VoxelBlockTable(const [
  VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  VoxelBlockDef(shape: BlockShape.cube, solid: true, opaque: true, r: 0.5, g: 0.5, b: 0.5),
]);

void main() {
  late ChunkWorkerPool pool;

  setUp(() async {
    pool = ChunkWorkerPool(ChunkWorkerConfig(generator: _flatFactory(40), table: _table), workers: 2);
    await pool.start();
  });

  tearDown(() => pool.dispose());

  test('the generator factory crosses Isolate.spawn and generates per job', () async {
    final a = await pool.generate(1, 2);
    final b = await pool.generate(0, 3, 1);
    expect(a, hasLength(ChunkSize.volume));
    expect(a[ChunkSize.index(5, 39, 5)], 1);
    expect(a[ChunkSize.index(5, 40, 5)], 0);
    // Stamps: (1, 2, dim 0) = 18 cells above 40; (0, 3, dim 1) = 103 % 80 = 23.
    expect([a[ChunkSize.index(0, 57, 0)], a[ChunkSize.index(0, 58, 0)]], [1, 0]);
    expect([b[ChunkSize.index(0, 62, 0)], b[ChunkSize.index(0, 63, 0)]], [1, 0]);
  });

  test('a mesh job on a worker equals the same mesh built here', () async {
    final ring = [for (var i = 0; i < 9; i++) await pool.generate(i % 3 - 1, i ~/ 3 - 1)];
    final remote = await pool.mesh(0, 0, ring);
    final local = _table.mesher().build(0, 0, ring);
    expect(remote.faces, local.faces);
    expect(remote.solid.positions, local.solid.positions);
    expect(remote.solid.indices, local.solid.indices);
    expect(remote.sky, local.sky);
    expect(remote.aoVerts, local.aoVerts);
  });

  test('jobs run concurrently and inflight drains to zero', () async {
    final jobs = [for (var i = 0; i < 8; i++) pool.generate(i, -i)];
    expect(pool.inflight, 8);
    await Future.wait(jobs);
    expect(pool.inflight, 0);
  });

  test('dispose cancels the jobs still waiting', () async {
    final pending = pool.generate(9, 9);
    pool.dispose();
    await expectLater(pending, throwsA(isA<ChunkJobCancelled>()));
  });

  test('a job that throws fails with the worker error, and the worker keeps serving', () async {
    await expectLater(
        pool.generate(_FlatGenerator.throws, 0),
        throwsA(isA<RemoteError>().having((e) => e.toString(), 'message', contains('no terrain at x 13'))));
    expect(pool.inflight, 0);
    expect(await pool.generate(1, 2), hasLength(ChunkSize.volume));
  });

  test('a worker that dies fails its jobs and leaves the pool; the other keeps serving', () async {
    await expectLater(pool.generate(_FlatGenerator.kills, 0), throwsStateError);
    expect(pool.inflight, 0);
    for (var i = 0; i < 4; i++) {
      expect(await pool.generate(i, 0), hasLength(ChunkSize.volume));
    }
  });

  test('a generator factory that throws makes start throw instead of hanging', () async {
    final broken = ChunkWorkerPool(ChunkWorkerConfig(generator: _brokenFactory, table: _table), workers: 1);
    await expectLater(broken.start(), throwsA(isA<RemoteError>()));
    broken.dispose();
  });
}
