import 'dart:typed_data';

import '../streaming/chunk_streamer.dart';

/// Every dimension's edit delta: dimension -> chunk -> (cell index -> id).
typedef EditsByDimension = Map<int, Map<ChunkPos, Map<int, int>>>;

/// The binary form of a world's edits: what a generated world needs on top of
/// its seed to be the world the player left. Little-endian throughout:
///
///     u32 magic · u32 version · i64 seed
///     per dimension 0..[dimensions]-1:
///       u32 chunk count
///       per chunk: i64 cx · i64 cz · u32 edit count · per edit: u32 cell index · u8 id
///
/// [legacySingleDimensionVersion], when given, is an older version whose file
/// holds dimension 0 only, still accepted by [decode].
class EditDeltaCodec {
  /// A codec for one game's files: its own [magic] and [version], and the
  /// number of [dimensions] every file holds.
  const EditDeltaCodec({
    required this.magic,
    required this.version,
    required this.dimensions,
    this.legacySingleDimensionVersion,
  });

  /// The first four bytes of every file this codec writes and reads.
  final int magic;

  /// The version written, and the one [decode] expects.
  final int version;

  /// Dimensions in a file, numbered 0 to [dimensions] - 1.
  final int dimensions;

  /// An older version holding dimension 0 only, still read; null for none.
  final int? legacySingleDimensionVersion;

  static const int _headerBytes = 4 + 4 + 8;

  /// The file for [edits] made against [seed]. A dimension missing from
  /// [edits] is written as zero chunks; a dimension past [dimensions] is not
  /// written.
  Uint8List encode(int seed, EditsByDimension edits) {
    var size = _headerBytes;
    for (var dim = 0; dim < dimensions; dim++) {
      size += 4;
      for (final e in (edits[dim] ?? const <ChunkPos, Map<int, int>>{}).values) {
        size += 8 + 8 + 4 + e.length * 5;
      }
    }
    final d = ByteData(size);
    var o = 0;
    d.setUint32(o, magic, Endian.little);
    o += 4;
    d.setUint32(o, version, Endian.little);
    o += 4;
    d.setInt64(o, seed, Endian.little);
    o += 8;
    for (var dim = 0; dim < dimensions; dim++) {
      final all = edits[dim] ?? const <ChunkPos, Map<int, int>>{};
      d.setUint32(o, all.length, Endian.little);
      o += 4;
      for (final e in all.entries) {
        d.setInt64(o, e.key.x, Endian.little);
        o += 8;
        d.setInt64(o, e.key.z, Endian.little);
        o += 8;
        d.setUint32(o, e.value.length, Endian.little);
        o += 4;
        for (final b in e.value.entries) {
          d.setUint32(o, b.key, Endian.little);
          o += 4;
          d.setUint8(o, b.value);
          o += 1;
        }
      }
    }
    return d.buffer.asUint8List();
  }

  /// The seed the edits were made against and the edits. Throws a
  /// [FormatException] when the bytes are not this format: another magic, an
  /// unknown version, cut short, or bytes left over.
  ({int seed, EditsByDimension edits}) decode(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    var o = 0;
    void need(int n) {
      if (o + n > bytes.length) throw FormatException('edit delta cut short', bytes, o);
    }

    need(_headerBytes);
    if (d.getUint32(o, Endian.little) != magic) throw FormatException('not an edit delta: wrong magic', bytes, o);
    o += 4;
    final fileVersion = d.getUint32(o, Endian.little);
    final legacy = legacySingleDimensionVersion != null && fileVersion == legacySingleDimensionVersion;
    if (fileVersion != version && !legacy) throw FormatException('unknown edit delta version $fileVersion', bytes, o);
    o += 4;
    final seed = d.getInt64(o, Endian.little);
    o += 8;
    final edits = <int, Map<ChunkPos, Map<int, int>>>{};
    for (var dim = 0; dim < (legacy ? 1 : dimensions); dim++) {
      final all = <ChunkPos, Map<int, int>>{};
      need(4);
      final n = d.getUint32(o, Endian.little);
      o += 4;
      for (var c = 0; c < n; c++) {
        need(8 + 8 + 4);
        final cx = d.getInt64(o, Endian.little);
        o += 8;
        final cz = d.getInt64(o, Endian.little);
        o += 8;
        final count = d.getUint32(o, Endian.little);
        o += 4;
        need(count * 5);
        final cells = <int, int>{};
        for (var e = 0; e < count; e++) {
          final i = d.getUint32(o, Endian.little);
          o += 4;
          cells[i] = d.getUint8(o);
          o += 1;
        }
        all[(x: cx, z: cz)] = cells;
      }
      edits[dim] = all;
    }
    if (o != bytes.length) throw FormatException('${bytes.length - o} bytes after the edit delta', bytes, o);
    return (seed: seed, edits: edits);
  }
}
