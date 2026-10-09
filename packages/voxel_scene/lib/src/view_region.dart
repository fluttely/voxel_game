import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

/// What tells two regions of a view apart: their side in chunks and their
/// position in regions of that side. A 2 × 2 and a 4 × 4 at one corner differ.
typedef ViewRegionKey = ({int chunks, ChunkPos at});

/// A region of `VoxelChunkView`: the [chunks] × [chunks] chunks from
/// [origin], drawn by [node], one child per surface or part of one. A region
/// carries its own size, so the view holds regions of two sizes at once (the
/// 2 × 2s it builds and the 4 × 4s they settle into).
final class ViewRegion {
  /// The region at [at], counted in regions of [chunks] chunks, drawn by [node].
  ViewRegion(this.at, this.chunks, this.node) : assert(chunks >= 1, 'a region holds at least one chunk');

  /// The region's position, in regions of its own size.
  final ChunkPos at;

  /// Chunks along each side.
  final int chunks;

  /// Its node under the view's root.
  final Node node;

  /// Its key in the view's map.
  ViewRegionKey get key => (chunks: chunks, at: at);

  /// Its first chunk, the corner its [node] sits at.
  ChunkPos get origin => (x: at.x * chunks, z: at.z * chunks);

  /// Where [node] sits: [origin] in metres.
  Vector3 get position => Vector3(origin.x * ChunkSize.sizeX.toDouble(), 0, origin.z * ChunkSize.sizeZ.toDouble());

  /// Its chunks' positions, row by row along z.
  Iterable<ChunkPos> get members sync* {
    final o = origin;
    for (var dx = 0; dx < chunks; dx++) {
      for (var dz = 0; dz < chunks; dz++) {
        yield (x: o.x + dx, z: o.z + dz);
      }
    }
  }

  /// Its box in its own frame, from the heights its vertices span.
  Aabb3 bounds(double minY, double maxY) => Aabb3.minMax(
    Vector3(0, minY, 0),
    Vector3(chunks * ChunkSize.sizeX.toDouble(), maxY, chunks * ChunkSize.sizeZ.toDouble()),
  );
}
