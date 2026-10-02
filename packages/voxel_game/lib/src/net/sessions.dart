import 'dart:async';
import 'dart:convert';

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/net.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../entities/target.dart';
import '../mobs/mob.dart';
import '../world/world_save.dart';
import 'block_prediction.dart';
import 'remote_player.dart';

List<double> _v(Vector3 v) => [v.x, v.y, v.z];

Vector3 _vec(Object? o) {
  final l = [for (final e in o! as List<Object?>) (e! as num).toDouble()];
  return Vector3(l[0], l[1], l[2]);
}

/// A networked game's side of the conversation, ticked last in every step of
/// the game. The block edits of a step leave together at its end, a message
/// per dimension, in the order they were made: the host's as `edits` (x, y, z
/// and id per edit), a client's as `requests` (its number, x, y, z, the id it
/// replaced and the id it wrote), which the host answers with one `acks` (the
/// number and the id that stands, per edit). Every peer runs the same spec, so
/// a dimension's number is the same everywhere, and a message no peer of that
/// spec would send throws.
abstract class GameSession implements GameSystem {
  /// Stops talking.
  Future<void> close();

  /// The game on this side.
  VoxelGame get game;

  /// The local player hit mob replica [mob] (a client asks the host).
  void hitMob(Mob mob, Damage damage) {}

  /// The other players, by peer.
  final Map<int, RemotePlayer> players = {};

  /// The numbers [m] carries under [key], [stride] to an entry.
  static List<int> _ints(NetMessage m, String key, int stride) {
    final l = [for (final o in m[key]! as List<Object?>) o! as int];
    if (l.length % stride != 0) throw FormatException('a ${m['t']} of ${l.length} numbers, not $stride to an entry');
    return l;
  }

  /// [id], which a peer sent as a block's.
  int _block(int id) {
    if (id < 0 || id >= game.blocks.count) throw FormatException('block $id, of ${game.blocks.count}');
    return id;
  }

  /// Calls [edit] with each edit of an `edits` message, in order.
  void _forEachEdit(NetMessage m, void Function(int dimension, IVec3 cell, int id) edit) {
    final d = m['d']! as int;
    final e = _ints(m, 'e', 4);
    for (var i = 0; i < e.length; i += 4) {
      edit(d, IVec3(e[i], e[i + 1], e[i + 2]), _block(e[i + 3]));
    }
  }
}

/// The authoritative side. Clients join with a hello (the seed, the
/// dimensions and every edit so far); the host sends each step's block edits,
/// and 20 times a second the players (each with its dimension) and the mobs
/// (of the host's dimension, where they live). A client's edits are requests
/// it settles by compare-and-set; its poses and hits come back to it; a
/// remote player in the host's dimension is a target its mobs hunt, and the
/// damage it takes goes to its peer.
class HostSession extends GameSession {
  /// Hosts [game] on [net].
  HostSession(this.game, this.net) {
    net
      ..onJoin = _join
      ..onMessage = _message
      ..onLeave = _leave;
    game.world.addListener(_edited);
  }

  /// The game hosted.
  @override
  final VoxelGame game;

  /// The network.
  final NetHost net;

  double _clock = 0.0;
  final Map<int, List<int>> _edits = {};

  void _queueEdit(int dimension, IVec3 cell, int id) => (_edits[dimension] ??= [])
    ..add(cell.x)
    ..add(cell.y)
    ..add(cell.z)
    ..add(id);

  void _join(NetPeer peer) {
    final puppet = RemotePlayer(peer.id, game.player.spawnPoint)
      ..onHurt = (d) =>
          peer.send({'t': 'hurt', 'dmg': d.amount, if (d.from != null) 'from': _v(d.from!), 'kb': d.knockback});
    players[peer.id] = puppet;
    game.add(puppet);
    peer.send({
      't': 'hello',
      'peer': peer.id,
      'seed': game.world.generators.seed,
      'dimensions': game.spec.dimensionIds,
      'edits': base64Encode(
        WorldSaves.codecFor(game.spec.dimensionIds.length).encode(game.world.generators.seed, game.world.edits),
      ),
      'time': game.time,
      'tod': game.timeOfDay,
      'spawn': _v(game.player.spawnPoint),
    });
  }

  void _message(NetPeer peer, NetMessage m) {
    final puppet = players[peer.id];
    switch (m['t']) {
      case 'pose':
        puppet?.setPose(
          _vec(m['p']),
          (m['yaw']! as num).toDouble(),
          held: m['held']! as String,
          dead: m['dead'] == true,
          dimension: m['d']! as int,
        );
      case 'requests':
        final d = m['d']! as int;
        final e = GameSession._ints(m, 'e', 6);
        peer.send({
          't': 'acks',
          'a': [
            for (var i = 0; i < e.length; i += 6) ...[
              e[i],
              _storeClientEdit(d, IVec3(e[i + 1], e[i + 2], e[i + 3]), _block(e[i + 4]), _block(e[i + 5])),
            ],
          ],
        });
      case 'hit':
        final n = (m['n']! as num).toInt();
        // A copy: a death may split into new creatures.
        for (final mob in List.of(game.mobs)) {
          if (mob.netId == n) {
            mob.takeDamage(
              Damage(
                (m['dmg']! as num).toDouble(),
                from: m['from'] == null ? null : _vec(m['from']),
                knockback: (m['kb'] as num?)?.toDouble() ?? 6.0,
                attacker: puppet,
                crit: m['crit'] == true,
              ),
            );
          }
        }
    }
  }

  void _leave(NetPeer peer) {
    players.remove(peer.id)?.removed = true;
    net.broadcast({'t': 'bye', 'peer': peer.id});
  }

  void _edited(IVec3 cell, int old, int id) => _queueEdit(game.world.dimension, cell, id);

  /// Settles a client's edit of [cell] in [dimension] from [old] to [id];
  /// returns the id that stands there after it. Where the host has the
  /// chunk, the edit lands only on [old] (two players on one cell: the second
  /// is refused), and the write runs the listeners, [_edited] passing it on.
  /// Where it has not (or the edit is of a dimension the host is not in),
  /// there is nothing to compare: the edit is recorded for when the chunk
  /// generates there and passed on here, or the other clients would never
  /// hear of it.
  int _storeClientEdit(int dimension, IVec3 cell, int old, int id) {
    final world = game.world;
    if (dimension != world.dimension || !world.isLoaded(cell)) {
      world.storeEditIn(dimension, cell, id);
      _queueEdit(dimension, cell, id);
      return id;
    }
    if (world.getBlock(cell) == old) world.setBlock(cell, id);
    return world.getBlock(cell);
  }

  @override
  void tick(VoxelGame game, double dt) {
    for (final e in _edits.entries) {
      net.broadcast({'t': 'edits', 'd': e.key, 'e': e.value});
    }
    _edits.clear();
    _clock += dt;
    if (_clock < 0.05) return;
    _clock = 0.0;
    final p = game.player;
    net.broadcast({
      't': 'state',
      'time': game.time,
      'tod': game.timeOfDay,
      'players': [
        {'id': 1, 'p': _v(p.position), 'yaw': p.yaw, 'held': p.heldItem, 'dead': p.isDead, 'd': game.world.dimension},
        for (final r in players.values)
          {'id': r.peer, 'p': _v(r.position), 'yaw': r.yaw, 'held': r.heldItem, 'dead': r.isDead, 'd': r.dimension},
      ],
      'd': game.world.dimension,
      'mobs': [
        for (final m in game.mobs)
          {'n': m.netId, 's': m.spec.id, 'p': _v(m.position), 'yaw': m.facing, 'hp': m.hp, 'dead': m.isDead},
      ],
    });
  }

  @override
  Future<void> close() async {
    game.world.removeListener(_edited);
    await net.close();
  }
}

/// The joining side: its world is the host's (seed and edits from the
/// hello). Its own edits show at once and go to the host as requests, each
/// owning its cell until the host's ack, which rolls it back when the host
/// stood by another id. The host's mobs are replicas it draws, and its hits
/// and the host's hurts cross over.
class ClientSession extends GameSession {
  /// A client of [game] on [connection], known to the host as [peer].
  ClientSession(this.game, this.connection, this.peer) {
    game.world.addListener(_edited);
    connection.listen(_message);
  }

  /// The game joined.
  @override
  final VoxelGame game;

  /// The connection to the host.
  final NetConnection connection;

  /// This client's number.
  final int peer;

  /// The edits sent and not yet settled by the host.
  int get pendingEdits => _prediction.length;

  /// The edits the host stood against, each rolled back to its id.
  int get rollbacks => _rollbacks;
  int _rollbacks = 0;

  final Map<int, Mob> _mobs = {};
  final BlockPrediction _prediction = BlockPrediction();
  final Map<int, List<int>> _requests = {};
  bool _applying = false;
  double _clock = 0.0;

  void _edited(IVec3 cell, int old, int id) {
    if (_applying) return;
    final d = game.world.dimension;
    (_requests[d] ??= []).addAll([_prediction.predict(d, cell, id), cell.x, cell.y, cell.z, old, id]);
  }

  void _message(NetMessage m) {
    switch (m['t']) {
      case 'edits':
        // An edit of a cell a prediction owns is older than its ack.
        _applying = true;
        _forEachEdit(m, (d, cell, id) {
          if (!_prediction.owns(d, cell)) game.world.storeEditIn(d, cell, id);
        });
        _applying = false;
      case 'acks':
        final a = GameSession._ints(m, 'a', 2);
        _applying = true;
        for (var i = 0; i < a.length; i += 2) {
          final standing = _block(a[i + 1]);
          final back = _prediction.ack(a[i], standing);
          if (back == null) continue;
          game.world.storeEditIn(back.dimension, back.cell, standing);
          _rollbacks += 1;
        }
        _applying = false;
      case 'state':
        game.time = (m['time']! as num).toDouble();
        game.timeOfDay = (m['tod']! as num).toDouble();
        _players(m['players']! as List<Object?>);
        // The host's mobs live in its dimension: elsewhere there are none.
        _mobsState(m['d'] == game.world.dimension ? m['mobs']! as List<Object?> : const []);
      case 'hurt':
        game.player.takeDamage(
          Damage(
            (m['dmg']! as num).toDouble(),
            from: m['from'] == null ? null : _vec(m['from']),
            knockback: (m['kb'] as num?)?.toDouble() ?? 0.0,
          ),
        );
      case 'bye':
        players.remove((m['peer']! as num).toInt())?.removed = true;
    }
  }

  void _players(List<Object?> rows) {
    final seen = <int>{};
    for (final o in rows) {
      final r = o! as Map<String, Object?>;
      final id = (r['id']! as num).toInt();
      if (id == peer) continue;
      seen.add(id);
      final at = _vec(r['p']);
      final puppet = players[id] ??= game.add(RemotePlayer(id, at));
      puppet.setPose(
        at,
        (r['yaw']! as num).toDouble(),
        held: r['held']! as String,
        dead: r['dead'] == true,
        dimension: r['d']! as int,
      );
    }
    for (final id in players.keys.where((k) => !seen.contains(k)).toList()) {
      players.remove(id)!.removed = true;
    }
  }

  void _mobsState(List<Object?> rows) {
    final seen = <int>{};
    for (final o in rows) {
      final r = o! as Map<String, Object?>;
      final n = (r['n']! as num).toInt();
      seen.add(n);
      var mob = _mobs[n];
      final at = _vec(r['p']);
      if (mob == null) {
        mob = Mob(game.mobSpec(r['s']! as String), at)
          ..replica = true
          ..netId = n;
        _mobs[n] = game.add(mob);
      }
      mob.applyNetState(at, (r['yaw']! as num).toDouble(), (r['hp']! as num).toDouble(), dead: r['dead'] == true);
    }
    for (final n in _mobs.keys.where((k) => !seen.contains(k)).toList()) {
      _mobs.remove(n)!.removed = true;
    }
  }

  @override
  void hitMob(Mob mob, Damage damage) => connection.send({
    't': 'hit',
    'n': mob.netId,
    'dmg': damage.amount,
    if (damage.from != null) 'from': _v(damage.from!),
    'kb': damage.knockback,
    if (damage.crit) 'crit': true,
  });

  @override
  void tick(VoxelGame game, double dt) {
    for (final e in _requests.entries) {
      connection.send({'t': 'requests', 'd': e.key, 'e': e.value});
    }
    _requests.clear();
    _clock += dt;
    if (_clock < 0.05) return;
    _clock = 0.0;
    final p = game.player;
    connection.send({
      't': 'pose',
      'p': _v(p.position),
      'yaw': p.yaw,
      'held': p.heldItem,
      'dead': p.isDead,
      'd': game.world.dimension,
    });
  }

  @override
  Future<void> close() async {
    game.world.removeListener(_edited);
    await connection.close();
  }
}

/// Joins the host at [address]:[port]: says hello and waits for the host's
/// world. Returns the hello, whose seed and edits start the client's world;
/// its edits are numbered as the host's dimensions, which the client's spec
/// must declare (`SavedWorld.editsFor` throws otherwise).
Future<({NetConnection connection, int peer, SavedWorld world, Vector3 spawn})> joinHost(
  String address, {
  int port = 7777,
}) async {
  final c = await connectToHost(address, port: port);
  final m = await c.next().timeout(const Duration(seconds: 15));
  if (m['t'] != 'hello') throw StateError('the host answered ${m['t']} before hello');
  final seed = (m['seed']! as num).toInt();
  final dimensions = [for (final d in m['dimensions']! as List<Object?>) d! as String];
  final edits = WorldSaves.codecFor(dimensions.length).decode(base64Decode(m['edits']! as String)).edits;
  return (
    connection: c,
    peer: (m['peer']! as num).toInt(),
    world: SavedWorld(seed, edits, {'time': m['time'], 'timeOfDay': m['tod']}, dimensions: dimensions),
    spawn: _vec(m['spawn']),
  );
}
