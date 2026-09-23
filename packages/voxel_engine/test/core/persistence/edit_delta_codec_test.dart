import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel_engine/core.dart';

const _codec = EditDeltaCodec(magic: 0x4342574F, version: 2, dimensions: 2, legacySingleDimensionVersion: 1);

void main() {
  final EditsByDimension edits = {
    0: {
      (x: 0, z: 0): {ChunkSize.index(3, 40, 7): 1, ChunkSize.index(15, 64, 0): 21},
      (x: -1, z: 2): {ChunkSize.index(7, 12, 8): 19},
    },
    1: {
      (x: 6, z: -2): {ChunkSize.index(4, 30, 12): 20},
    },
  };

  test('encode then decode returns the seed and every dimension, cell for cell', () {
    final bytes = _codec.encode(-4242424242, edits);
    final back = _codec.decode(bytes);
    expect(back.seed, -4242424242);
    expect(back.edits, edits);
  });

  test('the layout is the documented one: header, then per dimension its chunks', () {
    final bytes = _codec.encode(42, edits);
    final d = ByteData.sublistView(bytes);
    expect(d.getUint32(0, Endian.little), 0x4342574F);
    expect(d.getUint32(4, Endian.little), 2);
    expect(d.getInt64(8, Endian.little), 42);
    expect(d.getUint32(16, Endian.little), 2, reason: 'two chunks in dimension 0');
    // 16 header + 4 + (20 + 2*5) + (20 + 5) for dimension 0, then 4 + (20 + 5) for dimension 1.
    expect(bytes, hasLength(16 + 4 + 30 + 25 + 4 + 25));
  });

  test('a dimension with no edits is written as zero chunks and read back empty', () {
    final back = _codec.decode(_codec.encode(7, {0: edits[0]!}));
    expect(back.edits[1], isEmpty);
  });

  test('a version-1 file holds dimension 0 only and still loads', () {
    const v1 = EditDeltaCodec(magic: 0x4342574F, version: 1, dimensions: 1);
    final back = _codec.decode(v1.encode(9, {0: edits[0]!}));
    expect(back.seed, 9);
    expect(back.edits.keys, [0]);
    expect(back.edits[0], edits[0]);
  });

  test('not this format throws a FormatException', () {
    expect(() => _codec.decode(Uint8List(8)), throwsFormatException);
    final wrongMagic = _codec.encode(1, edits)..[0] ^= 0xFF;
    expect(() => _codec.decode(wrongMagic), throwsFormatException);
    const v3 = EditDeltaCodec(magic: 0x4342574F, version: 3, dimensions: 2);
    expect(() => _codec.decode(v3.encode(1, edits)), throwsFormatException);
    final whole = _codec.encode(1, edits);
    expect(() => _codec.decode(Uint8List.sublistView(whole, 0, whole.length - 3)), throwsFormatException,
        reason: 'cut inside the last edit');
    expect(() => _codec.decode(Uint8List.fromList([...whole, 0])), throwsFormatException, reason: 'a byte left over');
  });
}
