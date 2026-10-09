import 'dart:typed_data';

import '../grid/chunk_size.dart';

/// Which faces of each 16-tall section of a chunk its open cells join: a cell
/// is open when its block does not occlude ([VoxelBlockTable]'s opaque flag),
/// so air, liquids and cutouts let sight through. Two faces are joined when one
/// connected group of open cells inside the section touches both.
///
/// Faces are numbered [negX], [posX], [negY], [posY], [negZ], [posZ]; a face's
/// opposite is `face ^ 1`. Six faces make 15 unordered pairs, one bit each in a
/// section's mask. [ChunkMesher] fills one per chunk; a search from the camera
/// reads it to find the sections sight cannot reach.
final class ChunkVisibility {
  /// A visibility over one mask per section, which it keeps without copying.
  ChunkVisibility(Uint16List masks) : _masks = masks {
    if (masks.length != sections) throw ArgumentError.value(masks.length, 'masks', 'one per section ($sections)');
    for (final m in masks) {
      if (m & ~allPairs != 0) throw ArgumentError.value(m, 'masks', 'a mask holds $pairs pair bits');
    }
  }

  /// Every pair joined in every section: a chunk with nothing in it to occlude.
  static final ChunkVisibility open = ChunkVisibility(Uint16List(sections)..fillRange(0, sections, allPairs));

  /// Cells in a section along y.
  static const int sectionHeight = 16;

  /// Sections in a chunk, bottom first.
  static const int sections = ChunkSize.sizeY ~/ sectionHeight;

  /// The faces, as [connects] takes them.
  static const int negX = 0, posX = 1, negY = 2, posY = 3, negZ = 4, posZ = 5;

  /// Unordered pairs of distinct faces.
  static const int pairs = 15;

  /// Every pair bit set.
  static const int allPairs = (1 << pairs) - 1;

  final Uint16List _masks;

  /// The pair mask of every section, bottom first.
  Uint16List get masks => _masks.asUnmodifiableView();

  /// Whether open cells of [section] join face [faceIn] to face [faceOut]. The
  /// two faces differ: sight that leaves by the face it came in through has
  /// turned back, which no search asks.
  bool connects(int section, int faceIn, int faceOut) {
    RangeError.checkValidIndex(section, _masks, 'section', sections);
    return _masks[section] & (1 << pairBit(faceIn, faceOut)) != 0;
  }

  /// The bit of the pair ([a], [b]) in a section's mask, either order.
  static int pairBit(int a, int b) {
    RangeError.checkValueInInterval(a, 0, 5, 'a');
    RangeError.checkValueInInterval(b, 0, 5, 'b');
    if (a == b) throw ArgumentError.value(b, 'b', 'a pair joins two different faces');
    return _pairBit[a * 6 + b];
  }

  /// The mask of every pair among [faces], a 6-bit set with bit `1 << face`
  /// per face: what one group of open cells touching those faces joins.
  static int pairsOf(int faces) => _pairsOf[faces];

  // Pair (a, b) and (b, a) share bit k, numbered over a < b; -1 on the diagonal.
  static final List<int> _pairBit = () {
    final bits = List<int>.filled(36, -1);
    var k = 0;
    for (var a = 0; a < 6; a++) {
      for (var b = a + 1; b < 6; b++) {
        bits[a * 6 + b] = bits[b * 6 + a] = k++;
      }
    }
    return bits;
  }();

  static final Uint16List _pairsOf = () {
    final table = Uint16List(64);
    for (var faces = 0; faces < 64; faces++) {
      var mask = 0;
      for (var a = 0; a < 6; a++) {
        for (var b = a + 1; b < 6; b++) {
          if (faces & (1 << a) != 0 && faces & (1 << b) != 0) mask |= 1 << _pairBit[a * 6 + b];
        }
      }
      table[faces] = mask;
    }
    return table;
  }();
}
