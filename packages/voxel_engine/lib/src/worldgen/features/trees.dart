import 'dart:math' as math;

import 'tree_canvas.dart';

/// The blocks a tree is drawn with.
class TreeBlocks {
  /// A tree of [log] and [leaves]; [vines] only for the shapes that hang them.
  const TreeBlocks({required this.log, required this.leaves, this.vines = 0});

  /// The trunk and limb block.
  final int log;

  /// The crown block.
  final int leaves;

  /// The block that hangs from a crown's rim (jungle), 0 for none.
  final int vines;
}

/// Tree shapes drawn on a [TreeCanvas] at the stump ([x], [y], [z]), where
/// [y] is the first air cell above the ground. `hsh` is the tree's own roll
/// (a scatter grid's spot hash), so the same tree is drawn in every chunk.
///
/// Every shape joins its blocks by faces: a diagonal step is taken one axis
/// at a time, because two blocks that meet at an edge hold nothing and the
/// canvas's flood fill would drop the far one.
abstract final class Trees {
  /// The eight directions a limb or a frond can take.
  static const List<(int, int)> compass = [
    (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1), //
  ];

  /// A rounded crown: a ball of [leaves] [r] wide, squashed in y and frayed at
  /// the rim so no two look stamped from the same mould. Its centre block is
  /// always laid, which is what hangs the ball on the trunk it surrounds.
  static void crown(TreeCanvas c, int x, int y, int z, int r, int leaves) {
    final rim = r * r + r;
    for (var dy = -r; dy <= r; dy++) {
      for (var dz = -r; dz <= r; dz++) {
        for (var dx = -r; dx <= r; dx++) {
          final d2 = dx * dx + dz * dz + dy * dy * 2;
          if (d2 > rim) continue;
          if (d2 > rim - r && c.hash(x + dx, y + dy, z + dz) % 4 == 0) continue;
          c.ink(x + dx, y + dy, z + dz, leaves);
        }
      }
    }
  }

  /// A limb: [len] steps out along ([dx], [dz]), rising every other one, with a
  /// small crown on its end.
  static void limb(TreeCanvas c, int x, int y, int z, int dx, int dz, int len, int log, int leaves) {
    var lx = x, ly = y, lz = z;
    for (var i = 0; i < len; i++) {
      if (dx != 0) {
        lx += dx;
        c.ink(lx, ly, lz, log);
      }
      if (dz != 0) {
        lz += dz;
        c.ink(lx, ly, lz, log);
      }
      if (i.isOdd) {
        ly++;
        c.ink(lx, ly, lz, log);
      }
    }
    crown(c, lx, ly + 1, lz, 2, leaves);
  }

  /// The oak: a bare trunk [trunk] blocks tall, two limbs near the top and a
  /// rounded crown over them; nothing of it hangs at head height.
  static void oak(TreeCanvas c, int x, int y, int z, int trunk, int hsh, TreeBlocks b) {
    final top = y + trunk;
    for (var i = 0; i < 2; i++) {
      final dir = compass[((hsh >> (4 + i * 3)) + i * 3) % 8];
      limb(c, x, top - 3 + i, z, dir.$1, dir.$2, 2, b.log, b.leaves);
    }
    crown(c, x, top - 1, z, 3, b.leaves);
    for (var i = 0; i <= trunk; i++) {
      c.ink(x, y + i, z, b.log);
    }
  }

  /// The forest giant: a 2 x 2 trunk, four limbs and a crown five blocks wide.
  static void bigOak(TreeCanvas c, int x, int y, int z, int trunk, int hsh, TreeBlocks b) {
    final top = y + trunk;
    crown(c, x, top, z, 5, b.leaves);
    crown(c, x + 1, top - 2, z + 1, 4, b.leaves);
    for (var i = 0; i < 4; i++) {
      final dir = compass[(i * 2 + (hsh >> 6) % 2) % 8];
      final bx = x + (dir.$1 > 0 ? 1 : 0), bz = z + (dir.$2 > 0 ? 1 : 0);
      limb(c, bx, top - 5 + i % 2, bz, dir.$1, dir.$2, 3, b.log, b.leaves);
    }
    for (var i = 0; i <= trunk; i++) {
      for (var dz = 0; dz <= 1; dz++) {
        for (var dx = 0; dx <= 1; dx++) {
          c.ink(x + dx, y + i, z + dz, b.log);
        }
      }
    }
  }

  /// The spruce: a tall bare trunk under tiers that widen downward.
  static void spruce(TreeCanvas c, int x, int y, int z, int trunk, TreeBlocks b) {
    final bare = math.max(5, trunk ~/ 3);
    for (var dy = bare; dy <= trunk; dy++) {
      final fromTop = trunk - dy;
      var r = math.min(4, 1 + fromTop ~/ 4);
      if (fromTop % 3 == 2) r -= 1; // the skirts pinch in between the tiers
      for (var dz = -r; dz <= r; dz++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx * dx + dz * dz > r * r + 1) continue;
          c.ink(x + dx, y + dy, z + dz, b.leaves);
        }
      }
    }
    c.ink(x, y + trunk + 1, z, b.leaves);
    for (var i = 0; i < trunk; i++) {
      c.ink(x, y + i, z, b.log);
    }
  }

  /// The willow: a wide flat canopy whose rim droops in hanging leaf columns.
  static void willow(TreeCanvas c, int x, int y, int z, int trunk, int hsh, TreeBlocks b) {
    final top = y + trunk;
    for (var layer = 0; layer < 2; layer++) {
      final ly = top - layer;
      for (var dz = -4; dz <= 4; dz++) {
        for (var dx = -4; dx <= 4; dx++) {
          if (dx * dx + dz * dz > (layer == 0 ? 12 : 18)) continue;
          c.ink(x + dx, ly, z + dz, b.leaves);
        }
      }
    }
    for (var dz = -4; dz <= 4; dz++) {
      for (var dx = -4; dx <= 4; dx++) {
        final d2 = dx * dx + dz * dz;
        if (d2 < 10 || d2 > 18 || c.hash(x + dx, 5, z + dz) % 3 == 0) continue;
        for (var i = 1; i <= 2 + (c.hash(x + dx, 6, z + dz) % 3); i++) {
          c.ink(x + dx, top - 1 - i, z + dz, b.leaves);
        }
      }
    }
    final dir = compass[(hsh >> 7) % 8];
    limb(c, x, top - 3, z, dir.$1, dir.$2, 2, b.log, b.leaves);
    for (var i = 0; i <= trunk; i++) {
      c.ink(x, y + i, z, b.log);
    }
  }

  /// The jungle giant: a 2 x 2 trunk, a crown at the top, a second halfway up,
  /// and vines falling from both rims.
  static void jungle(TreeCanvas c, int x, int y, int z, int trunk, int hsh, TreeBlocks b) {
    final top = y + trunk;
    crown(c, x, top, z, 4, b.leaves);
    crown(c, x + 1, top - 6, z + 1, 3, b.leaves);
    for (var i = 0; i < 2; i++) {
      final dir = compass[((hsh >> (5 + i * 4)) + i * 4) % 8];
      final bx = x + (dir.$1 > 0 ? 1 : 0), bz = z + (dir.$2 > 0 ? 1 : 0);
      limb(c, bx, top - 7, bz, dir.$1, dir.$2, 2, b.log, b.leaves);
    }
    vineFall(c, x, top - 2, z, 4, hsh, b.vines);
    vineFall(c, x + 1, top - 7, z + 1, 3, hsh ^ 0x5f5f, b.vines);
    for (var i = 0; i <= trunk; i++) {
      for (var dz = 0; dz <= 1; dz++) {
        for (var dx = 0; dx <= 1; dx++) {
          c.ink(x + dx, y + i, z + dz, b.log);
        }
      }
    }
  }

  /// Vines falling 2-6 blocks from the rim of a crown [r] wide, only where the
  /// canvas already holds a leaf to hang them on.
  static void vineFall(TreeCanvas c, int x, int y, int z, int r, int hsh, int vines) {
    for (var dz = -r; dz <= r; dz++) {
      for (var dx = -r; dx <= r; dx++) {
        final d2 = dx * dx + dz * dz;
        if (d2 < (r - 1) * (r - 1) || d2 > r * r + 1) continue;
        if (c.inked(x + dx, y, z + dz) == 0) continue;
        final vh = c.hash(x + dx, 8, z + dz) ^ hsh;
        if (vh % 5 < 2) continue;
        for (var i = 1; i <= 2 + ((vh >> 4) % 5); i++) {
          c.ink(x + dx, y - i, z + dz, vines);
        }
      }
    }
  }

  /// The palm: a bare leaning trunk under a star of fronds. The lean steps one
  /// axis at a time, so the trunk climbs by faces.
  static void palm(TreeCanvas c, int x, int y, int z, int trunk, int hsh, TreeBlocks b) {
    final lean = compass[(hsh >> 9) % 8];
    var tx = x, tz = z;
    for (var i = 0; i <= trunk; i++) {
      if (i > 4 && i % 5 == 0) {
        if (lean.$1 != 0) {
          tx += lean.$1;
          c.ink(tx, y + i - 1, tz, b.log);
        }
        if (lean.$2 != 0) {
          tz += lean.$2;
          c.ink(tx, y + i - 1, tz, b.log);
        }
      }
      c.ink(tx, y + i, tz, b.log);
    }
    final top = y + trunk;
    c.ink(tx, top + 1, tz, b.leaves);
    for (var d = 0; d < 8; d++) {
      final dir = compass[d];
      frond(c, tx, top + 1, tz, dir.$1, dir.$2, 2 + ((hsh >> (d * 2)) % 2), b.leaves);
    }
  }

  /// One frond of a palm: leaves stepping out a face at a time from the
  /// crown's heart, drooping by one block at the tip.
  static void frond(TreeCanvas c, int x, int y, int z, int dx, int dz, int len, int leaves) {
    var fx = x, fy = y, fz = z;
    for (var i = 1; i <= len; i++) {
      if (dx != 0) {
        fx += dx;
        c.ink(fx, fy, fz, leaves);
      }
      if (dz != 0) {
        fz += dz;
        c.ink(fx, fy, fz, leaves);
      }
      if (i == len) {
        fy -= 1;
        c.ink(fx, fy, fz, leaves);
      }
    }
  }
}
