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
import 'remote_player.dart';

List<double> _v(Vector3 v) => [v.x, v.y, v.z];

Vector3 _vec(Object? o) {
  final l = [for (final e in o! as List<Object?>) (e! as num).toDouble()];
  return Vector3(l[0], l[1], l[2]);
}

IVec3 _cell(Object? o) {
  final l = [for (final e in o! as List<Object?>) (e! as num).toInt()];
  return IVec3(l[0], l[1], l[2]);
}

/// A networked game's side of the conversation, ticked with the game.
abstract class GameSession implements GameSystem {
  /// Stops talking.
  Future<void> close();

  /// The local player hit mob replica [mob] (a client asks the host).
  void hitMob(Mob mob, Damage damage) {}

  /// The other players, by peer.
  final Map<int, RemotePlayer> players = {};
}

/// The authoritative side. Clients join with a hello (the seed and every edit
/// so far); the host sends every block edit, and 20 times a second the
/// players and the mobs. A client's edits, poses and hits come back to it; a
/// remote player is a target its mobs hunt, and the damage it takes goes to
/// its peer.
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
  final VoxelGame game;

  /// The network.
  final NetHost net;

  double _clock = 0.0;

  void _join(NetPeer peer) {
    final puppet = RemotePlayer(peer.id, game.player.spawnPoint)
      ..onHurt = (d) =>
          peer.send({'t': 'hurt', 'dmg': d.amount, if (d.from != null) 'from': _v(d.from!), 'kb': d.knockback});
    players[peer.id] = puppet;
    game.add(puppet);
    peer.send({
      't': 'hello',
      'peer': peer.id,
      'seed': game.world.generator.seed,
      'edits': base64Encode(WorldSaves.codec.encode(game.world.generator.seed, game.world.edits)),
      'time': game.time,
      'tod': game.timeOfDay,
      'spawn': _v(game.player.spawnPoint),
    });
  }

  void _message(NetPeer peer, NetMessage m) {
    final puppet = players[peer.id];
    switch (m['t']) {
      case 'pose':
        puppet?.setPose(_vec(m['p']), (m['yaw']! as num).toDouble(), dead: m['dead'] == true);
      case 'set':
        game.world.storeEdit(_cell(m['c']), (m['b']! as num).toInt());
      case 'hit':
        final n = (m['n']! as num).toInt();
        for (final mob in game.mobs) {
          if (mob.netId == n) {
            mob.takeDamage(
              Damage(
                (m['dmg']! as num).toDouble(),
                from: m['from'] == null ? null : _vec(m['from']),
                knockback: (m['kb'] as num?)?.toDouble() ?? 6.0,
                attacker: puppet,
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

  void _edited(IVec3 cell, int old, int id) => net.broadcast({
    't': 'set',
    'c': [cell.x, cell.y, cell.z],
    'b': id,
  });

  @override
  void tick(VoxelGame game, double dt) {
    _clock += dt;
    if (_clock < 0.05) return;
    _clock = 0.0;
    final p = game.player;
    net.broadcast({
      't': 'state',
      'time': game.time,
      'tod': game.timeOfDay,
      'players': [
        {'id': 1, 'p': _v(p.position), 'yaw': p.yaw, 'dead': p.isDead},
        for (final r in players.values) {'id': r.peer, 'p': _v(r.position), 'yaw': r.yaw, 'dead': r.isDead},
      ],
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
/// hello), its edits go to the host and come back as the host's, the host's
/// mobs are replicas it draws, and its hits and the host's hurts cross over.
class ClientSession extends GameSession {
  /// A client of [game] on [connection], known to the host as [peer].
  ClientSession(this.game, this.connection, this.peer) {
    game.world.addListener(_edited);
    connection.listen(_message);
  }

  /// The game joined.
  final VoxelGame game;

  /// The connection to the host.
  final NetConnection connection;

  /// This client's number.
  final int peer;

  final Map<int, Mob> _mobs = {};
  bool _applying = false;
  double _clock = 0.0;

  void _edited(IVec3 cell, int old, int id) {
    if (_applying) return;
    connection.send({
      't': 'set',
      'c': [cell.x, cell.y, cell.z],
      'b': id,
    });
  }

  void _message(NetMessage m) {
    switch (m['t']) {
      case 'set':
        _applying = true;
        game.world.storeEdit(_cell(m['c']), (m['b']! as num).toInt());
        _applying = false;
      case 'state':
        game.time = (m['time']! as num).toDouble();
        game.timeOfDay = (m['tod']! as num).toDouble();
        _players(m['players']! as List<Object?>);
        _mobsState(m['mobs']! as List<Object?>);
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
      puppet.setPose(at, (r['yaw']! as num).toDouble(), dead: r['dead'] == true);
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
  });

  @override
  void tick(VoxelGame game, double dt) {
    _clock += dt;
    if (_clock < 0.05) return;
    _clock = 0.0;
    final p = game.player;
    connection.send({'t': 'pose', 'p': _v(p.position), 'yaw': p.yaw, 'dead': p.isDead});
  }

  @override
  Future<void> close() async {
    game.world.removeListener(_edited);
    await connection.close();
  }
}

/// Joins the host at [address]:[port]: says hello and waits for the host's
/// world. Returns the hello, whose seed and edits start the client's world.
Future<({NetConnection connection, int peer, SavedWorld world, Vector3 spawn})> joinHost(
  String address, {
  int port = 7777,
}) async {
  final c = await connectToHost(address, port: port);
  final m = await c.next().timeout(const Duration(seconds: 15));
  if (m['t'] != 'hello') throw StateError('the host answered ${m['t']} before hello');
  final seed = (m['seed']! as num).toInt();
  final edits = WorldSaves.codec.decode(base64Decode(m['edits']! as String)).edits;
  return (
    connection: c,
    peer: (m['peer']! as num).toInt(),
    world: SavedWorld(seed, edits, {'time': m['time'], 'timeOfDay': m['tod']}),
    spawn: _vec(m['spawn']),
  );
}
