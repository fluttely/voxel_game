/// The one chunk geometry: 16 × 16 columns, 128 cells tall. A chunk volume is
/// a byte per cell, indexed x-first within z within y.
abstract final class ChunkSize {
  /// Bits of a world x that address a cell inside its chunk: `x >> shiftX`
  /// is the chunk, `x & maskX` the cell in it.
  static const int shiftX = 4;

  /// Bits of a world z that address a cell inside its chunk, as [shiftX].
  static const int shiftZ = 4;

  /// Cells along x.
  static const int sizeX = 1 << shiftX;

  /// Cells along z.
  static const int sizeZ = 1 << shiftZ;

  /// A world x masked to its cell inside its chunk.
  static const int maskX = sizeX - 1;

  /// A world z masked to its cell inside its chunk.
  static const int maskZ = sizeZ - 1;

  /// Cells along y, the world height.
  static const int sizeY = 128;

  /// Bytes in one chunk volume.
  static const int volume = sizeX * sizeZ * sizeY;

  /// The byte of chunk-local cell ([x], [y], [z]) in a chunk volume.
  static int index(int x, int y, int z) => x + sizeX * (z + sizeZ * y);
}
