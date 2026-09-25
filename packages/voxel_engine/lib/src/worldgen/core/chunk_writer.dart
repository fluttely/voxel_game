import 'dart:typed_data';

import 'package:voxel_engine/core.dart';

/// One chunk's block array, written in world coordinates. Everything outside
/// the chunk is silently skipped, which is the point: a feature (a tree, a
/// village) is drawn whole by every chunk it touches, and each keeps its own
/// part, so the pieces meet at the borders without any chunk seeing another.
class ChunkWriter {
  /// A writer over [blocks], the volume of chunk ([chunkX], [chunkZ]).
  ChunkWriter(this.blocks, this.chunkX, this.chunkZ) : ox = chunkX * ChunkSize.sizeX, oz = chunkZ * ChunkSize.sizeZ;

  /// Row 0 is the bedrock floor: [put] never writes below this.
  static const int minY = 1;

  /// The chunk's blocks, `ChunkSize.index` order.
  final Uint8List blocks;

  /// The chunk's coordinates.
  final int chunkX, chunkZ;

  /// World x and z of the chunk's first column.
  final int ox, oz;

  /// Writes [id] at world ([wx], [wy], [wz]) when that cell is in this chunk
  /// and at or above [minY].
  void put(int wx, int wy, int wz, int id) {
    final x = wx - ox, z = wz - oz;
    if (x < 0 || x >= ChunkSize.sizeX || z < 0 || z >= ChunkSize.sizeZ || wy < minY || wy >= ChunkSize.sizeY) return;
    blocks[ChunkSize.index(x, wy, z)] = id;
  }

  /// The block at world ([wx], [wy], [wz]), or null outside this chunk (or
  /// below [minY]).
  int? get(int wx, int wy, int wz) {
    final x = wx - ox, z = wz - oz;
    if (x < 0 || x >= ChunkSize.sizeX || z < 0 || z >= ChunkSize.sizeZ || wy < minY || wy >= ChunkSize.sizeY) {
      return null;
    }
    return blocks[ChunkSize.index(x, wy, z)];
  }

  /// Writes [id] at chunk-local ([x], [y], [z]) where the cell is air, where
  /// [id] is air, or where [over] says the block there gives way (a trunk
  /// through a canopy). Outside the chunk, nothing.
  void place(int x, int y, int z, int id, {bool Function(int current)? over}) {
    if (x < 0 || x >= ChunkSize.sizeX || z < 0 || z >= ChunkSize.sizeZ || y < 0 || y >= ChunkSize.sizeY) return;
    final i = ChunkSize.index(x, y, z);
    final cur = blocks[i];
    if (cur == 0 || id == 0) {
      blocks[i] = id;
    } else if (over != null && over(cur)) {
      blocks[i] = id;
    }
  }

  /// Sits a structure's floor on a slope: fills column ([wx], [wz]) with
  /// [fill] from its [ground] (the first air cell) up to below [floorY], and
  /// clears it to air from above [floorY] up to [clearTo].
  void levelColumn(int wx, int wz, int ground, int floorY, int clearTo, int fill) {
    for (var y = ground - 1; y < floorY; y++) {
      put(wx, y, wz, fill);
    }
    for (var y = floorY + 1; y <= clearTo; y++) {
      put(wx, y, wz, 0);
    }
  }
}
