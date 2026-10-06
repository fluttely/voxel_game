import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import '../ui/game_screen.dart';

/// What blocks do, by their rows: a block that `falls` drops to where it
/// lands, one that loses its `support` breaks and drops, the two halves of a
/// `tall` block go together, a block with a `usedInto` turns into it when a
/// player uses it, a crop placed in the world `grows` stage by stage while it
/// has light, and a block with a `storage` keeps what is put in it and spills
/// it when it goes. It runs on every block change of the world (a
/// player's, a creature's, a blast's, its own), so what it does cascades: the
/// sand above falling sand falls next, and a torch on that sand drops.
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

  // Each dimension's crops and stores, by its number: the cells of one are
  // not the cells of another.
  final Map<int, Map<IVec3, double>> _growingBy = {};
  final Map<int, Map<IVec3, Inventory>> _storesBy = {};
  Map<IVec3, double> get _growing => _growingBy.putIfAbsent(game.world.dimension, () => {});
  Map<IVec3, Inventory> get _stores => _storesBy.putIfAbsent(game.world.dimension, () => {});
  double _growClock = 0.0;

  /// How often the crops are looked at, in seconds.
  static const growPeriod = 1.0;

  /// The crops placed in the dimension streaming since it was generated,
  /// each with the seconds of light it has had toward its next stage. A crop
  /// the world generated does not grow, nor one in a dimension the player has
  /// left.
  Map<IVec3, double> get growing => Map.unmodifiable(_growing);

  /// The crops of dimension [d], as [growing]: what a save keeps.
  Map<IVec3, double> growingIn(int d) => Map.unmodifiable(_growingBy[d] ?? const <IVec3, double>{});

  /// Puts back what [growingIn] dimension [d] held (a save read back).
  void restoreGrowing(Map<IVec3, double> growing, {int dimension = 0}) => _growingBy[dimension] = {...growing};

  /// What the stores of the dimension streaming hold, by cell. A store the
  /// world generated appears here once it is looked into.
  Map<IVec3, Inventory> get stores => Map.unmodifiable(_stores);

  /// What the stores of dimension [d] hold, as [stores]: what a save keeps.
  Map<IVec3, Inventory> storesIn(int d) => Map.unmodifiable(_storesBy[d] ?? const <IVec3, Inventory>{});

  /// What the block with a `storage` at [cell] holds. A store the world
  /// generated and nobody has looked into yet is filled from its loot now,
  /// seeded by its cell and the world, so every player finds the same.
  Inventory storeAt(IVec3 cell) {
    final kept = _stores[cell];
    if (kept != null) return kept;
    final storage = _blocks[game.world.getBlock(cell)].storage;
    if (storage == null) throw StateError('no store at $cell: ${game.world.blockNameAt(cell)}');
    return _stores[cell] = _found(cell, storage);
  }

  /// Puts back what [storesIn] dimension [d] held (a save read back): each
  /// as the slots it was saved with, a stack of an item there no longer is
  /// left out.
  void restoreStores(Map<IVec3, List<Object?>> stores, {int dimension = 0}) => _storesBy[dimension] = {
    for (final e in stores.entries) e.key: _empty(e.value.length)..fromJson(e.value, known: game.items.has),
  };

  Inventory _empty(int slots) => Inventory(
    stackSize: (id) => game.items[id].stack,
    maxDurability: (id) => game.items[id].durability,
    capacity: slots,
    hotbarSize: 0,
  );

  /// A generated store at [cell] as it is found: its structure's loot
  /// (`VoxelGameSpec.structureLoot`) with its bonus, else its block's.
  Inventory _found(IVec3 cell, Storage storage) {
    final inv = _empty(storage.slots);
    final structure = game.structureAt(cell);
    final own = structure == null ? null : game.spec.structureLoot[structure.name];
    final loot = own?.table ?? storage.loot;
    if (loot == null) return inv;
    final rng = math.Random(LootTable.seedFor(cell, game.world.generator.seed));
    for (final s in loot.roll(rng)) {
      inv.add(s.id, s.count);
    }
    final prize = own?.bonus?.roll(rng);
    if (prize != null) inv.addStack(prize);
    return inv;
  }

  /// Advances the crops by [dt]; once a step, on the authority. Every
  /// [growPeriod] seconds each one whose chunk is loaded and whose cell has
  /// its light counts that time toward its stage, and a stage served becomes
  /// the next.
  void tick(double dt) {
    _growClock += dt;
    if (_growClock < growPeriod) return;
    final lit = _growClock;
    _growClock = 0.0;
    for (final cell in _growing.keys.toList()) {
      if (!game.world.isLoaded(cell)) continue;
      final growth = _blocks[game.world.getBlock(cell)].grows;
      if (growth == null) {
        _growing.remove(cell);
        continue;
      }
      final light = game.world.lightAt(cell);
      if (math.max(light.sky, light.block) < growth.minLight) continue;
      final had = _growing[cell]! + lit;
      if (had < growth.seconds) {
        _growing[cell] = had;
      } else {
        game.world.setBlockNamed(cell, growth.into);
      }
    }
  }

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
    if (_blocks[id].grows != null) {
      _growing[cell] = 0.0;
    } else {
      _growing.remove(cell);
    }
    final had = _blocks[old].storage, has = _blocks[id].storage;
    if (had != null && has == null) {
      _spill(cell, _stores.remove(cell) ?? _found(cell, had));
    } else if (had == null && has != null) {
      _stores[cell] = _empty(has.slots);
    }
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

  /// What a store held goes on the ground where it stood, and its screen
  /// shuts.
  void _spill(IVec3 cell, Inventory held) {
    if (game.screen.value == StorageScreen(cell)) game.closeScreen();
    final at = Vector3(cell.x + 0.5, cell.y + 0.3, cell.z + 0.5);
    for (final s in held.slots) {
      if (s != null) game.dropStack(s, at);
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
