/// One ore of an [OreTable].
class OreVein {
  /// [block] below [belowY], where a vein cell's roll (0..9999) is under
  /// [upTo]. Rolls are shared: a table is read in order and the first vein
  /// whose depth and roll match wins, so `upTo` is a cumulative bound.
  const OreVein(this.block, {this.belowY = 1 << 30, required this.upTo});

  /// The ore's block id.
  final int block;

  /// The ore appears only at y < [belowY].
  final int belowY;

  /// The cumulative roll bound, out of 10000.
  final int upTo;
}

/// Ores by depth. A cell of 2 x 2 x 2 blocks rolls one vein, and a per-block
/// roll thins it to [fill] per cent, so ore comes in clumps rather than
/// specks.
class OreTable {
  /// [veins] tried in order.
  const OreTable(this.veins, {this.fill = 55});

  /// The veins, in the order they are tried.
  final List<OreVein> veins;

  /// Per cent of a vein cell's blocks that are ore.
  final int fill;

  /// The ore at height [y] given the vein cell's hash [cellHash] and the
  /// block's own [blockHash], or null for plain rock.
  int? pick(int y, int cellHash, int blockHash) {
    if (blockHash % 100 >= fill) return null;
    final r = cellHash % 10000;
    for (final v in veins) {
      if (y < v.belowY && r < v.upTo) return v.block;
    }
    return null;
  }
}
