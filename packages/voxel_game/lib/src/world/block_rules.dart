import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';

/// What blocks do, by their rows: a block that `falls` drops to where it
/// lands, one that loses its `support` breaks and drops, the two halves of a
/// `tall` block go together, and a block with a `usedInto` turns into it when
/// a player uses it. It runs on every block change of the world (a player's,
/// a creature's, a blast's, its own), so what it does cascades: the sand above
/// falling sand falls next, and a torch on that sand drops.
///
/// Only the authority runs the changes (a lone game, the host); a client
/// receives the ones it made with the host's other edits.
class BlockRules {
  /// The rules of [game]'s blocks, not yet listening: see [attach].
  BlockRules(this.game) {
    final blocks = game.blocks;
    final family = List<int>.generate(blocks.count, (i) => i);
    int root(int i) => family[i] == i ? i : family[i] = root(family[i]);
    void join(int a, int b) => family[root(a)] = root(b);
    for (var i = 0; i < blocks.count; i++) {
      final into = blocks[i].usedInto;
      if (into != null) join(i, blocks.indexOf(into));
    }
    final signals = game.spec.signals;
    for (final e in signals?.doors.entries ?? const <MapEntry<String, String>>[]) {
      join(blocks.indexOf(e.key), blocks.indexOf(e.value));
    }
    _family = [for (var i = 0; i < blocks.count; i++) root(i)];
  }

  /// The game.
  final VoxelGame game;

  /// Each block's family: itself, and the blocks a use or a signal turns it
  /// into and back. The two halves of a tall block are of one family.
  late final List<int> _family;

  bool _unpairing = false;

  BlockRegistry<BlockType> get _blocks => game.blocks;

  /// Starts answering the world's block changes.
  void attach() => game.world.addListener(_changed);

  /// Whether block [id] would stay at [cell]: what it leans on is there
  /// (`BlockType.support`), and the upper half of a tall block always stands
  /// on its lower half. A player places nothing where it would not.
  bool stands(IVec3 cell, int id) =>
      (_blocks[id].tall && lowerHalf(cell, id) != cell) || _blocks.stands(game.world, cell, id);

  /// The lower half of the tall block [id] at [cell]: [cell] itself, or the
  /// cell below it. The halves pair from the bottom of a run of the block's
  /// family, so two doors stacked are two pairs.
  IVec3 lowerHalf(IVec3 cell, int id) {
    var below = 0;
    for (var c = cell + IVec3.down; c.y >= 0 && _family[game.world.getBlock(c)] == _family[id]; c = c + IVec3.down) {
      below++;
    }
    return below.isEven ? cell : cell + IVec3.down;
  }

  /// Uses the block at [cell], turning it (both halves of a tall one) into
  /// its `usedInto`; false when it has none. A block that would turn solid
  /// around a body stays as it is, though the use is spent on it.
  bool use(IVec3 cell) {
    final id = game.world.getBlock(cell);
    final into = _blocks[id].usedInto;
    if (into == null) return false;
    final to = _blocks.indexOf(into);
    final lower = _blocks[id].tall ? lowerHalf(cell, id) : cell;
    final cells = [lower, if (_blocks[id].tall) lower + IVec3.up];
    if (_blocks[to].solid && cells.any(game.bodyIn)) return true;
    for (final c in cells) {
      game.world.setBlock(c, to);
    }
    game.playSound('door', at: Vector3(lower.x + 0.5, lower.y + 1.0, lower.z + 0.5), volumeDb: -6.0);
    return true;
  }

  void _changed(IVec3 cell, int old, int id) {
    if (_blocks[old].tall && _family[old] != _family[id] && !_unpairing) _unpair(cell, old);
    if (_blocks[id].falls) _fall(cell, id);
    final above = cell + IVec3.up;
    final up = game.world.getBlock(above);
    if (_blocks[up].falls) _fall(above, up);
    for (final n in [above, cell + IVec3.down, for (final s in IVec3.sides) cell + s]) {
      final nid = game.world.getBlock(n);
      if (nid != BlockRegistry.air && !stands(n, nid)) game.breakBlock(n);
    }
  }

  /// The other half of the tall block [old] that was at [cell] goes too, with
  /// no drop of its own: the half broken dropped the block.
  void _unpair(IVec3 cell, int old) {
    // The cells below are as they were, so the pairing is the one [cell] had.
    final twin = lowerHalf(cell, old) == cell ? cell + IVec3.up : cell + IVec3.down;
    if (_family[game.world.getBlock(twin)] != _family[old]) return;
    _unpairing = true;
    game.world.setBlock(twin, BlockRegistry.air);
    _unpairing = false;
  }

  /// Moves falling block [id] at [cell] down to where it lands, if anything
  /// lets it go.
  void _fall(IVec3 cell, int id) {
    var to = cell;
    while (to.y > 0 && _blocks.isReplaceable(game.world.getBlock(to + IVec3.down))) {
      to = to + IVec3.down;
    }
    if (to == cell) return;
    // Where it lands first: emptying the cell first lets the block above fall
    // into the landing cell ahead of this one.
    game.world.setBlock(to, id);
    game.world.setBlock(cell, BlockRegistry.air);
  }
}
