/// The one chunk geometry: 16 × 16 columns, 128 cells tall. A chunk volume is
/// a byte per cell, indexed x-first within z within y.
abstract final class ChunkSize {
  /// Cells along x.
  static const int sizeX = 16;

  /// Cells along z.
  static const int sizeZ = 16;

  /// Cells along y, the world height.
  static const int sizeY = 128;

  /// Bytes in one chunk volume.
  static const int volume = sizeX * sizeZ * sizeY;

  /// The byte of chunk-local cell ([x], [y], [z]) in a chunk volume.
  static int index(int x, int y, int z) => x + sizeX * (z + sizeZ * y);
}
