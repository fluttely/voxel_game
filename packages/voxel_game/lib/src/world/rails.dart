import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/signals.dart';

import '../spec/signal_spec.dart';
import 'game_world.dart';

/// A game's rails, read from its blocks: a block of a rail shape
/// (`BlockShape.railNs` … `railSlopeW`) is a rail, of the kind it drops
/// (`BlockRegistry.dropOf`), so the rails one item lays are one kind and turn
/// into one another as they are laid. A powered rail's on state (a value of
/// `SignalSpec.poweredRails`) [powers] a cart along; its off state (a key)
/// [brakes] one.
///
/// Laid where the game is the authority ([attach]), a rail turns to meet the
/// rails around it and turns them to meet it (`RailGraph.place`); one taken
/// away lets them turn back (`RailGraph.removed`). What a rail turns into is
/// a rail of its own kind and state, so a kind lays both straights, and every
/// shape it has in one state it has in the other or off.
class Rails {
  /// The rails among [blocks], powered by [signals]' `poweredRails`. Throws
  /// [ArgumentError] for two rails of one kind, shape and state, for a kind
  /// that lacks a shape it turns into (a straight either way, or one it has
  /// in another state), and for a powered rail that is no rail.
  Rails(BlockRegistry<BlockType> blocks, SignalSpec? signals)
    : _on = {for (final n in signals?.poweredRails.values ?? const <String>[]) blocks.indexOf(n)},
      _off = {for (final n in signals?.poweredRails.keys ?? const <String>[]) blocks.indexOf(n)} {
    final variants = <int, RailVariant>{};
    final laid = <(String, String, bool), String>{};
    for (var i = 1; i < blocks.count; i++) {
      final shape = shapeOf(blocks[i].shape);
      if (shape == null) continue;
      final v = RailVariant(blocks.dropOf(i), shape, on: _on.contains(i));
      final twin = laid[(v.kind, shape, v.on)];
      if (twin != null) {
        throw ArgumentError.value(
          blocks[i].id,
          'blocks',
          'a second ${v.on ? 'on ' : ''}$shape rail of kind ${v.kind}: $twin is one',
        );
      }
      laid[(v.kind, shape, v.on)] = blocks[i].id;
      variants[i] = v;
    }
    for (final id in {..._on, ..._off}) {
      if (!variants.containsKey(id)) {
        throw ArgumentError.value(blocks[id].id, 'poweredRails', 'a powered rail of no rail shape');
      }
    }
    for (final v in variants.values) {
      final shapes = {
        'ns',
        'ew',
        for (final k in laid.keys)
          if (k.$1 == v.kind) k.$2,
      };
      for (final s in shapes) {
        if (!laid.containsKey((v.kind, s, v.on)) && !laid.containsKey((v.kind, s, false))) {
          throw ArgumentError.value(v.kind, 'blocks', 'the rail kind has no ${v.on ? 'on ' : ''}$s rail to turn into');
        }
      }
    }
    graph = RailGraph(variants);
  }

  /// How the rails join and lay themselves.
  late final RailGraph graph;

  final Set<int> _on, _off;

  /// Whether block [id] is a rail.
  bool isRail(int id) => graph.isRail(id);

  /// Whether rail [id] is a powered rail on: it speeds a cart up.
  bool powers(int id) => _on.contains(id);

  /// Whether rail [id] is a powered rail off: it brakes a moving cart.
  bool brakes(int id) => _off.contains(id);

  /// The `RailGraph` shape of a rail [shape], or null for a shape that is no
  /// rail.
  static String? shapeOf(BlockShape shape) => switch (shape) {
    BlockShape.railNs => 'ns',
    BlockShape.railEw => 'ew',
    BlockShape.railNe => 'ne',
    BlockShape.railNw => 'nw',
    BlockShape.railSe => 'se',
    BlockShape.railSw => 'sw',
    BlockShape.railSlopeN => 'slope_n',
    BlockShape.railSlopeE => 'slope_e',
    BlockShape.railSlopeS => 'slope_s',
    BlockShape.railSlopeW => 'slope_w',
    _ => null,
  };

  bool _laying = false;

  /// Starts laying the rails [world] gains and loses: once, where the game is
  /// the authority (a client receives the rails the host laid).
  void attach(GameWorld world) => world.addListener((cell, old, id) => _changed(world, cell, old, id));

  void _changed(GameWorld world, IVec3 cell, int old, int id) {
    // The rails it turns are changes too, and are laid already.
    if (_laying) return;
    final was = graph.isRail(old), now = graph.isRail(id);
    if (was == now) return;
    _laying = true;
    if (now) {
      graph.place(world, cell, id);
    } else {
      graph.removed(world, cell);
    }
    _laying = false;
  }
}
