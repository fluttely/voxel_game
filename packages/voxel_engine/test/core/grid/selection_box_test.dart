import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

const int _stone = 1;
const int _fence = 2;

VoxelBlockDef _def(BlockShape shape, {bool solid = true, bool opaque = false}) =>
    VoxelBlockDef(shape: shape, solid: solid, opaque: opaque, r: 0.5, g: 0.5, b: 0.5);

/// Air, stone, a fence, then one block of every shape from id 3 on.
final _table = VoxelBlockTable([
  const VoxelBlockDef(shape: BlockShape.cube, solid: false, opaque: false, r: 0, g: 0, b: 0, a: 0),
  _def(BlockShape.cube, opaque: true),
  _def(BlockShape.fence),
  for (final s in BlockShape.values) _def(s, solid: s != BlockShape.liquid),
]);

int _idOf(BlockShape s) => 3 + s.index;

/// A few chunks, read both by the mesher and as a [VoxelQuery].
class _World implements VoxelQuery {
  final Map<(int, int), Uint8List> chunks = {};

  void set(int x, int y, int z, int id) {
    final cx = (x / ChunkSize.sizeX).floor(), cz = (z / ChunkSize.sizeZ).floor();
    final c = chunks.putIfAbsent((cx, cz), () => Uint8List(ChunkSize.volume));
    c[ChunkSize.index(x - cx * ChunkSize.sizeX, y, z - cz * ChunkSize.sizeZ)] = id;
  }

  @override
  VoxelBlockTable get table => _table;

  @override
  int getBlockXYZ(int x, int y, int z) {
    final cx = (x / ChunkSize.sizeX).floor(), cz = (z / ChunkSize.sizeZ).floor();
    final c = chunks[(cx, cz)];
    if (c == null || y < 0 || y >= ChunkSize.sizeY) return 0;
    return c[ChunkSize.index(x - cx * ChunkSize.sizeX, y, z - cz * ChunkSize.sizeZ)];
  }

  /// The world-space bounds of every vertex the mesher lays down for chunk
  /// ([cx], [cz]); its neighbours are read, never meshed.
  CollisionBox meshBounds(int cx, int cz) {
    final mesher = ChunkMesher(
      palette: _table.palette,
      shape: _table.shapes,
      opaque: _table.opaque,
      emission: _table.emission,
    );
    Uint8List? at(int dx, int dz) => chunks[(cx + dx, cz + dz)];
    // ChunkStreamer.ring order: c, nx, px, nz, pz, nxnz, pxnz, nxpz, pxpz.
    final ring = [
      chunks[(cx, cz)]!,
      at(-1, 0),
      at(1, 0),
      at(0, -1),
      at(0, 1),
      at(-1, -1),
      at(1, -1),
      at(-1, 1),
      at(1, 1),
    ];
    final r = mesher.build(cx, cz, ring);
    final lo = [double.infinity, double.infinity, double.infinity];
    final hi = [double.negativeInfinity, double.negativeInfinity, double.negativeInfinity];
    for (final s in [r.solid, r.liquid, r.cutout, r.glow]) {
      for (var i = 0; i < s.positions.length; i++) {
        lo[i % 3] = math.min(lo[i % 3], s.positions[i]);
        hi[i % 3] = math.max(hi[i % 3], s.positions[i]);
      }
    }
    // The mesher writes chunk-local positions.
    final ox = (cx * ChunkSize.sizeX).toDouble(), oz = (cz * ChunkSize.sizeZ).toDouble();
    return CollisionBox(lo[0] + ox, lo[1], lo[2] + oz, hi[0] + ox, hi[1], hi[2] + oz);
  }
}

void _expectBox(CollisionBox actual, CollisionBox expected, String reason) {
  for (var axis = 0; axis < 3; axis++) {
    expect(
      actual.min(axis),
      closeTo(expected.min(axis), 1e-5),
      reason: '$reason: min ${'xyz'[axis]} of $actual vs $expected',
    );
    expect(
      actual.max(axis),
      closeTo(expected.max(axis), 1e-5),
      reason: '$reason: max ${'xyz'[axis]} of $actual vs $expected',
    );
  }
}

void main() {
  const y = 40;

  group('the outline box is the bounds of what the mesher draws', () {
    for (final shape in BlockShape.values) {
      // A liquid is never aimed; a door's knob pokes past its panel and is
      // left out on purpose (checked below); the leaning shapes are checked
      // against each wall below.
      if (const [
        BlockShape.liquid,
        BlockShape.panelX,
        BlockShape.panelZ,
        BlockShape.wallTorch,
        BlockShape.ladder,
      ].contains(shape)) {
        continue;
      }
      test(shape.name, () {
        final w = _World()..set(7, y, 9, _idOf(shape));
        final box = selectionBoxAt(w, 7, y, 9), mesh = w.meshBounds(0, 0);
        if (!shape.name.startsWith('rail')) {
          _expectBox(box, mesh, shape.name);
          return;
        }
        // A rail is outlined by its whole footprint: its ties stop a
        // sixteenth short of two edges, which a box would only make look
        // lopsided on a curve. The height is the mesh's.
        _expectBox(box, CollisionBox(7, mesh.y0, 9, 8, mesh.y1, 10), shape.name);
        expect(mesh.x0 >= box.x0 && mesh.x1 <= box.x1 && mesh.z0 >= box.z0 && mesh.z1 <= box.z1, isTrue);
      });
    }
  });

  test('a wall torch and a ladder: the box is the mesh, on each of the four walls', () {
    // The shape sits on the chunk's border and its wall in the neighbour
    // chunk, which the mesher reads but does not draw.
    for (final (x, z, wx, wz) in [(0, 7, -1, 7), (15, 7, 16, 7), (7, 0, 7, -1), (7, 15, 7, 16)]) {
      for (final shape in [BlockShape.wallTorch, BlockShape.ladder]) {
        final w = _World()
          ..set(x, y, z, _idOf(shape))
          ..set(wx, y, wz, _stone);
        final box = selectionBoxAt(w, x, y, z);
        _expectBox(box, w.meshBounds(0, 0), '${shape.name} against ($wx, $wz)');
        final thin = wx != x ? box.x1 - box.x0 : box.z1 - box.z0;
        expect(thin, lessThanOrEqualTo(0.2), reason: '${shape.name} stands off the wall at ($wx, $wz)');
      }
    }
  });

  test('a door is outlined by its panel, not by the knob that pokes past it', () {
    final w = _World()..set(7, y, 9, _idOf(BlockShape.panelZ));
    final mesh = w.meshBounds(0, 0);
    final box = selectionBoxAt(w, 7, y, 9);
    expect(box.z0 - mesh.z0, closeTo(0.04, 1e-5));
    expect(mesh.z1 - box.z1, closeTo(0.04, 1e-5));
    _expectBox(box, const CollisionBox(7, y + 0.0, 9, 8, y + 1.0, 9.1875), 'panelZ');
  });

  test('a plant is outlined where its jitter put it, in any chunk, on either side of zero', () {
    for (final (cx, cz) in [(0, 0), (3, 1), (-2, -1)]) {
      for (final shape in [BlockShape.cross, BlockShape.flower]) {
        for (var lx = 0; lx < 5; lx++) {
          final x = cx * 16 + lx, z = cz * 16 + 2 * lx;
          final w = _World()..set(x, y, z, _idOf(shape));
          _expectBox(selectionBoxAt(w, x, y, z), w.meshBounds(cx, cz), '${shape.name} at ($x, $z)');
        }
      }
    }
  });

  test('a fence reaches toward the fences and walls it joins, and only those', () {
    final w = _World()
      ..set(7, y, 9, _fence)
      ..set(8, y, 9, _fence)
      ..set(7, y, 8, _stone)
      ..set(6, y, 9, _idOf(BlockShape.torch)); // not opaque, not a fence
    _expectBox(selectionBoxAt(w, 7, y, 9), const CollisionBox(7.375, y + 0.0, 9, 8, y + 1.0, 9.625), 'fence');
  });
}
