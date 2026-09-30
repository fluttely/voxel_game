import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';

/// What blocks do on their own, by their rows: a block that `falls` drops to
/// where it lands, and one that loses its `support` breaks and drops. It runs
/// on every block change of the world (a player's, a creature's, a blast's,
/// its own), so what it does cascades: the sand above falling sand falls
/// next, and a torch on that sand drops.
///
/// Only the authority runs it (a lone game, the host); a client receives the
/// changes it made with the host's other edits.
class BlockRules {
  /// The rules of [game]'s blocks, not yet listening: see [attach].
  BlockRules(this.game);

  /// The game.
  final VoxelGame game;

  BlockRegistry<BlockType> get _blocks => game.blocks;

  /// Starts answering the world's block changes.
  void attach() => game.world.addListener(_changed);

  /// Whether block [id] would stay at [cell]: what it leans on is there
  /// (`BlockType.support`). A player places nothing where it would not.
  bool stands(IVec3 cell, int id) => _blocks.stands(game.world, cell, id);

  void _changed(IVec3 cell, int old, int id) {
    final t = _blocks[id];
    if (t.falls) _fall(cell, id);
    final above = cell + IVec3.up;
    final up = game.world.getBlock(above);
    if (_blocks[up].falls) _fall(above, up);
    for (final n in [above, cell + IVec3.down, for (final s in IVec3.sides) cell + s]) {
      final nid = game.world.getBlock(n);
      if (nid != BlockRegistry.air && !stands(n, nid)) game.breakBlock(n);
    }
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
