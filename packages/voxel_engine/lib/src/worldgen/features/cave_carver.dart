import '../noise/fast_noise_lite.dart';

/// Caves carved out of the ground by two 3D noises: cheese caves anywhere in
/// the rock, wider caverns in the deep, and cave mouths near the surface only
/// where the cave noise runs strong. Pure in the position, so a tree or a
/// structure can ask about a cell of another chunk.
class CaveCarver {
  /// A carver over [cave] and [cavern] noise with the default shape.
  CaveCarver({
    required this.cave,
    required this.cavern,
    required this.seaLevel,
    this.caveThreshold = 0.44,
    this.minDepth = 3,
    this.cavernBelowY = 40,
    this.cavernThreshold = 0.55,
    this.cavernMinDepth = 6,
    this.mouthThreshold = 0.60,
    this.mouthAboveSea = 2,
  });

  /// The cheese-cave field, sampled with y stretched by 1.5.
  final FastNoiseLite cave;

  /// The cavern field, sampled with y stretched by 2.
  final FastNoiseLite cavern;

  /// Mouths open only on ground higher than this plus [mouthAboveSea].
  final int seaLevel;

  /// Cave noise above this opens a cave...
  final double caveThreshold;

  /// ...deeper than this many blocks under the surface.
  final int minDepth;

  /// Caverns only below this height...
  final int cavernBelowY;

  /// ...where the cavern noise is above this...
  final double cavernThreshold;

  /// ...deeper than this.
  final int cavernMinDepth;

  /// Cave noise above this opens a mouth in the top [minDepth] blocks.
  final double mouthThreshold;

  /// See [seaLevel].
  final int mouthAboveSea;

  /// True where the block at ([wx], [wy], [wz]), under a surface at [surface]
  /// (the first air cell of the column), is carved away.
  bool carved(int wx, int wy, int wz, int surface) {
    final depth = surface - wy;
    final c = cave.getNoise3(wx.toDouble(), wy * 1.5, wz.toDouble());
    if (c > caveThreshold && depth > minDepth) return true;
    if (wy < cavernBelowY &&
        depth > cavernMinDepth &&
        cavern.getNoise3(wx.toDouble(), wy * 2.0, wz.toDouble()) > cavernThreshold) {
      return true;
    }
    return c > mouthThreshold && depth <= minDepth && surface > seaLevel + mouthAboveSea;
  }
}
