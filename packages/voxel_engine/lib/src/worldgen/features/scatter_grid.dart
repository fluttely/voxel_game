import '../core/world_math.dart';

/// At most one feature per [patch] x [patch] square, placed by hash, never
/// closer than [inset] to the square's border. Two features of one grid
/// therefore stand at least `2 * inset + 1` blocks apart, and every chunk
/// agrees where each one is from the position alone.
class ScatterGrid {
  /// A grid of [patch]-wide squares, spots [inset] in from their borders,
  /// rolled with [salt].
  const ScatterGrid({required this.patch, this.inset = 0, required this.salt}) : assert(patch > 2 * inset);

  /// The side of a square, in blocks.
  final int patch;

  /// How far a spot stays from its square's border.
  final int inset;

  /// The y salt of the square's hash, so two grids of one seed roll apart.
  final int salt;

  /// The spot of the square holding ([wx], [wz]) and the square's hash. A
  /// feature stands at ([wx], [wz]) when both equal the spot; the hash is its
  /// roll (does it grow, which kind, how tall).
  ({int x, int z, int hash}) spotOf(int seed, int wx, int wz) {
    final span = patch - 2 * inset;
    final px = floorDiv(wx, patch), pz = floorDiv(wz, patch);
    final h = worldHash(seed, px, salt, pz);
    return (x: px * patch + inset + (h >> 8) % span, z: pz * patch + inset + (h >> 16) % span, hash: h);
  }
}
