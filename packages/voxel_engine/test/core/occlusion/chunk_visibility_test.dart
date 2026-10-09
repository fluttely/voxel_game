import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

const _air = 0, _stone = 1, _water = 2, _grass = 3;

/// Air, an opaque cube, a liquid and a cutout plant: the last two occlude
/// nothing.
ChunkMesher _mesher() => ChunkMesher(
  palette: Float32List(4 * 4),
  shape: Uint8List.fromList([
    BlockShape.cube.index,
    BlockShape.cube.index,
    BlockShape.liquid.index,
    BlockShape.cross.index,
  ]),
  opaque: Uint8List.fromList([0, 1, 0, 0]),
  emission: Uint8List(4),
);

ChunkVisibility _visibility(Uint8List c, [ChunkMesher? mesher]) =>
    (mesher ?? _mesher()).build(0, 0, [c, ...ChunkMesher.noNeighbours]).visibility;

Uint8List _solid() => Uint8List(ChunkSize.volume)..fillRange(0, ChunkSize.volume, _stone);

/// The mask joining the given face pairs.
int _pairs(List<(int, int)> pairs) => pairs.fold(0, (m, p) => m | 1 << ChunkVisibility.pairBit(p.$1, p.$2));

/// [mask] in section [section], nothing joined anywhere else.
List<int> _only(int section, int mask) => [for (var s = 0; s < ChunkVisibility.sections; s++) s == section ? mask : 0];

const _negX = ChunkVisibility.negX, _posX = ChunkVisibility.posX;
const _negY = ChunkVisibility.negY, _posY = ChunkVisibility.posY;
const _negZ = ChunkVisibility.negZ, _posZ = ChunkVisibility.posZ;

void main() {
  group('ChunkVisibility', () {
    test('a chunk is eight sections of 16', () {
      expect(ChunkVisibility.sectionHeight, 16);
      expect(ChunkVisibility.sections, 8);
    });

    test('the fifteen pairs have fifteen bits, the same either order', () {
      final bits = <int>{};
      for (var a = 0; a < 6; a++) {
        for (var b = a + 1; b < 6; b++) {
          expect(ChunkVisibility.pairBit(a, b), ChunkVisibility.pairBit(b, a));
          bits.add(ChunkVisibility.pairBit(a, b));
        }
      }
      expect(bits, {for (var k = 0; k < ChunkVisibility.pairs; k++) k});
    });

    test('a face is no pair with itself', () {
      expect(() => ChunkVisibility.pairBit(_posY, _posY), throwsArgumentError);
      expect(() => ChunkVisibility.open.connects(0, _negX, _negX), throwsArgumentError);
    });

    test('pairsOf joins every two faces of a set, and nothing for one face', () {
      expect(ChunkVisibility.pairsOf(0), 0);
      expect(ChunkVisibility.pairsOf(1 << _negZ), 0);
      expect(ChunkVisibility.pairsOf(1 << _negX | 1 << _posY), _pairs([(_negX, _posY)]));
      expect(ChunkVisibility.pairsOf(63), ChunkVisibility.allPairs);
    });

    test('open joins every pair of every section', () {
      expect(ChunkVisibility.open.masks, List.filled(8, ChunkVisibility.allPairs));
      expect(ChunkVisibility.open.connects(7, _negY, _posZ), isTrue);
    });

    test('takes one mask per section of fifteen bits, and hands out no way to change it', () {
      expect(() => ChunkVisibility(Uint16List(7)), throwsArgumentError);
      expect(() => ChunkVisibility(Uint16List(8)..[3] = 1 << 15), throwsArgumentError);
      expect(() => ChunkVisibility.open.masks[0] = 0, throwsUnsupportedError);
      expect(() => ChunkVisibility.open.connects(8, _negX, _posX), throwsRangeError);
    });
  });

  group('ChunkMesher fills it', () {
    test('all air joins every pair', () {
      final v = _visibility(Uint8List(ChunkSize.volume));
      expect(v.masks, List.filled(8, ChunkVisibility.allPairs));
    });

    test('all stone joins none, whatever the air past its borders', () {
      expect(_visibility(_solid()).masks, List.filled(8, 0));
    });

    test('a sealed pocket joins none', () {
      final c = _solid();
      for (var y = 20; y < 23; y++) {
        for (var z = 5; z < 8; z++) {
          for (var x = 5; x < 8; x++) {
            c[ChunkSize.index(x, y, z)] = _air;
          }
        }
      }
      expect(_visibility(c).masks, List.filled(8, 0));
    });

    test('a straight x tunnel joins only -x and +x, in its own section', () {
      final c = _solid();
      for (var x = 0; x < 16; x++) {
        c[ChunkSize.index(x, 20, 8)] = _air;
      }
      final v = _visibility(c);
      expect(v.masks, _only(1, _pairs([(_negX, _posX)])));
      expect(v.connects(1, _posX, _negX), isTrue);
      expect(v.connects(1, _negX, _posZ), isFalse);
    });

    test('an L tunnel joins only its two faces', () {
      final c = _solid();
      for (var x = 0; x <= 8; x++) {
        c[ChunkSize.index(x, 40, 8)] = _air;
      }
      for (var z = 8; z < 16; z++) {
        c[ChunkSize.index(8, 40, z)] = _air;
      }
      expect(_visibility(c).masks, _only(2, _pairs([(_negX, _posZ)])));
    });

    test('two tunnels that never meet join their own faces; a hole between them joins all four', () {
      final c = _solid();
      for (var i = 0; i < 16; i++) {
        c[ChunkSize.index(i, 70, 2)] = _air;
        c[ChunkSize.index(12, 72, i)] = _air;
      }
      expect(_visibility(c).masks, _only(4, _pairs([(_negX, _posX), (_negZ, _posZ)])));
      c[ChunkSize.index(12, 71, 2)] = _air;
      expect(
        _visibility(c).masks,
        _only(4, ChunkVisibility.pairsOf(1 << _negX | 1 << _posX | 1 << _negZ | 1 << _posZ)),
      );
    });

    test('liquid and a cutout plant are open; stone in their place closes the tunnel', () {
      final c = _solid();
      for (var x = 0; x < 16; x++) {
        c[ChunkSize.index(x, 100, 8)] = _air;
      }
      c[ChunkSize.index(4, 100, 8)] = _water;
      c[ChunkSize.index(9, 100, 8)] = _grass;
      expect(_visibility(c).masks, _only(6, _pairs([(_negX, _posX)])));
      c[ChunkSize.index(9, 100, 8)] = _stone;
      expect(_visibility(c).masks, List.filled(8, 0));
    });

    test('a vertical shaft through two sections joins -y and +y in both', () {
      final c = _solid();
      for (var y = 16; y < 48; y++) {
        c[ChunkSize.index(8, y, 8)] = _air;
      }
      final pair = _pairs([(_negY, _posY)]);
      expect(_visibility(c).masks, [0, pair, pair, 0, 0, 0, 0, 0]);
    });

    test('re-meshing an edited chunk changes the mask, and meshing it back restores it', () {
      final mesher = _mesher();
      final c = _solid();
      expect(_visibility(c, mesher).masks, List.filled(8, 0));
      for (var x = 0; x < 16; x++) {
        c[ChunkSize.index(x, 120, 3)] = _air;
      }
      expect(_visibility(c, mesher).masks, _only(7, _pairs([(_negX, _posX)])));
      c[ChunkSize.index(7, 120, 3)] = _stone;
      expect(_visibility(c, mesher).masks, List.filled(8, 0));
    });
  });
}
