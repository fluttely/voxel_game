import 'package:voxel_engine/core.dart';

/// A client's block edits waiting for the host's ack: the bookkeeping only.
/// Each edit is numbered, and the latest on a cell owns it until its ack
/// lands, so the host's echo of that cell waits: it may be older than the
/// edit, and the ack carries what stands.
class BlockPrediction {
  int _seq = 0;
  final Map<int, ({int dimension, IVec3 cell, int id})> _pending = {};
  final Map<(int, IVec3), int> _owners = {};

  /// The edits waiting for their ack.
  int get length => _pending.length;

  /// Records the local edit of [cell] in [dimension] to [id]; returns its
  /// number.
  int predict(int dimension, IVec3 cell, int id) {
    _seq += 1;
    _pending[_seq] = (dimension: dimension, cell: cell, id: id);
    _owners[(dimension, cell)] = _seq;
    return _seq;
  }

  /// Whether a waiting edit owns [cell] of [dimension].
  bool owns(int dimension, IVec3 cell) => _owners.containsKey((dimension, cell));

  /// Settles edit [seq], after which [standing] stands at its cell. Returns
  /// the cell to roll back to [standing] when the edit was the cell's latest
  /// and predicted another id; a later edit of the cell settles it instead.
  /// An ack for no waiting edit throws: a host never sends one.
  ({int dimension, IVec3 cell})? ack(int seq, int standing) {
    final p = _pending.remove(seq);
    if (p == null) throw FormatException('an ack for edit $seq, which is not waiting');
    final key = (p.dimension, p.cell);
    if (_owners[key] != seq) return null;
    _owners.remove(key);
    return p.id == standing ? null : (dimension: p.dimension, cell: p.cell);
  }
}
