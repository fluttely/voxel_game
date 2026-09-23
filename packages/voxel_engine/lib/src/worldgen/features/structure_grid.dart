import 'package:voxel_engine/core.dart';

import '../core/world_math.dart';

/// One structure candidate per region of [regionChunks] x [regionChunks]
/// chunks, rolled from the region's hash, so every chunk agrees where it is.
/// A chunk asks the 3 x 3 regions [around] it, because a structure near a
/// region border reaches into its neighbours.
class StructureGrid {
  /// A grid of [regionChunks]-wide regions whose hash is
  /// `worldHash(seed, rx * primeX, salt, rz * primeZ)`.
  const StructureGrid({required this.regionChunks, required this.primeX, required this.salt, required this.primeZ});

  /// The side of a region, in chunks.
  final int regionChunks;

  /// The x multiplier of the region hash.
  final int primeX;

  /// The y salt of the region hash, so grids of one seed roll apart.
  final int salt;

  /// The z multiplier of the region hash.
  final int primeZ;

  /// The side of a region, in blocks.
  int get span => regionChunks * ChunkSize.sizeX;

  /// The region holding chunk coordinate [chunk] (x or z).
  int regionOf(int chunk) => floorDiv(chunk, regionChunks);

  /// Region ([rx], [rz])'s hash under [seed]: its candidate's position and
  /// roll are read from its bits.
  int hashOf(int seed, int rx, int rz) => worldHash(seed, rx * primeX, salt, rz * primeZ);

  /// The 3 x 3 regions around chunk ([chunkX], [chunkZ]), rows of z then x.
  Iterable<(int, int)> around(int chunkX, int chunkZ) sync* {
    final rx = regionOf(chunkX), rz = regionOf(chunkZ);
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        yield (rx + dx, rz + dz);
      }
    }
  }
}
