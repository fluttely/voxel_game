import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart' show Inventory, ItemStack;
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/net.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../entities/item_pickup.dart';
import '../entities/target.dart';
import '../mobs/mob.dart';
import '../ui/game_screen.dart';
import '../weather/weather.dart';
import '../weather/weather_kind.dart';
import '../world/world_save.dart';
import 'block_prediction.dart';
import 'remote_player.dart';

List<double> _v(Vector3 v) => [v.x, v.y, v.z];

Vector3 _vec(Object? o) {
  final l = [for (final e in o! as List<Object?>) (e! as num).toDouble()];
  return Vector3(l[0], l[1], l[2]);
}

List<int> _c(IVec3 c) => [c.x, c.y, c.z];

IVec3 _cell(Object? o) {
  final l = [for (final e in o! as List<Object?>) e! as int];
  if (l.length != 3) throw FormatException('a cell of ${l.length} numbers');
  return IVec3(l[0], l[1], l[2]);
}

/// Whether [a] and [b] are stacks alike: the same item, bonus and wear.
bool _like(ItemStack a, ItemStack b) => a.id == b.id && a.bonus == b.bonus && a.dur == b.dur;

/// Whether slots [a] and [b] hold the same: both empty, or alike and as many.
bool _same(ItemStack? a, ItemStack? b) => a == null ? b == null : b != null && _like(a, b) && a.count == b.count;

/// What an edit of a slot from [before] to [after] took [out] of it and put
/// [into] it: the difference of a stack topped up or taken from, or both
/// stacks whole when they are not alike (a swap).
({ItemStack? out, ItemStack? into}) _moved(ItemStack? before, ItemStack? after) {
  if (before != null && after != null && _like(before, after)) {
    final more = after.count - before.count;
    return (
      out: more < 0 ? (before.copy()..count = -more) : null,
      into: more > 0 ? (after.copy()..count = more) : null,
    );
  }
  return (out: before?.copy(), into: after?.copy());
}

/// A client's edit of a slot of the store it has open, sent and not yet
/// settled: its number, the opening of the store it was made in, the slot,
/// and what the slot held before and after it.
typedef _StoreEdit = ({int n, int opening, int slot, ItemStack? before, ItemStack? after});

/// A networked game's side of the conversation, ticked last in every step of
/// the game. The block edits of a step leave together at its end, a message
/// per dimension, in the order they were made: the host's as `edits` (x, y, z
/// and id per edit), a client's as `requests` (its number, x, y, z, the id it
/// replaced and the id it wrote), which the host answers with one `acks` (the
/// number and the id that stands, per edit). The host owns every item on the
/// ground: each has a number, `drops` makes it (on a client, a replica),
/// `drop_poses` moves it, `drops_gone` takes it; a client's drop is a `drop`
/// request, the host hands a peer what its player reached with `give`, and
/// the peer sends back what did not fit as `give_rest`, having declared its
/// bag and the stack in its hand (`bag`) when they changed. The host keeps
/// the stores: a client opens one with `store_open` and shuts it with
/// `store_close`; the host sends it (`store`) then and at each change, and
/// shuts a store gone (`store_shut`); each slot a client edits is a
/// `store_set` (its number, the slot, what it held before and after), which
/// the host answers with the store and a `store_ack` (the number, and
/// whether it stood). The host's sky goes out as `weather` (its spell, its
/// last rain or storm, the intensity it eases toward and the one it stands
/// at) with the hello and when it turns. Every peer runs
/// the same spec, so a dimension's number
/// is the same everywhere, and a message no peer of that spec would send
/// throws.
abstract class GameSession implements GameSystem {
  /// Stops talking.
  Future<void> close();

  /// The game on this side.
  VoxelGame get game;

  /// The local player hit mob replica [mob] (a client asks the host).
  void hitMob(Mob mob, Damage damage) {}

  /// Takes the drop of [stack] at [at], moving at [velocity], that the game
  /// is making: true when it went to the host (a client where the host is),
  /// false when the game makes it here.
  bool handOffDrop(ItemStack stack, Vector3 at, Vector3 velocity) => false;

  /// The other players, by peer.
  final Map<int, RemotePlayer> players = {};

  /// Whether the host is in the dimension this side's player is in: always,
  /// on the host.
  bool get hostHere => true;

  /// The store at [cell] as this side sees it while its screen is open: the
  /// game's own, on the host.
  Inventory storeAt(IVec3 cell) => game.blockRules.storeAt(cell);

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

  /// [d], which a peer sent as a dimension's number.
  int _dimension(int d) {
    final n = game.spec.dimensionIds.length;
    if (d < 0 || d >= n) throw FormatException('dimension $d, of $n');
    return d;
  }

  /// The stack a peer sent as [o].
  ItemStack _stack(Object? o) {
    final s = ItemStack.fromJson(o! as Map<String, Object?>);
    if (!game.items.has(s.id)) throw FormatException('item ${s.id}, which the spec does not declare');
    if (s.count <= 0) throw FormatException('a stack of ${s.count} ${s.id}');
    return s;
  }

  /// The slot a peer sent as [o]: null for an empty one.
  ItemStack? _slot(Object? o) => (o! as Map<String, Object?>).isEmpty ? null : _stack(o);

  /// [i], which a peer sent as a weather's.
  static WeatherKind _weatherKind(int i) {
    if (i < 0 || i >= WeatherKind.values.length) throw FormatException('weather $i');
    return WeatherKind.values[i];
  }

  /// A `weather` message of [weather]'s sky.
  static NetMessage _weatherMessage(Weather weather) => {
    't': 'weather',
    's': weather.spell.index,
    'w': weather.wet.index,
    'i': weather.target,
    'now': weather.intensity,
  };

  /// [weather] follows the sky of a `weather` message.
  static void _follow(Weather weather, NetMessage m) => weather.follow(
    _weatherKind(m['s']! as int),
    wet: _weatherKind(m['w']! as int),
    target: (m['i']! as num).toDouble(),
    intensity: (m['now']! as num).toDouble(),
  );

  /// A `store` message of [store], which stands at [cell].
  static NetMessage _storeMessage(IVec3 cell, Inventory store) => {'t': 'store', 'c': _c(cell), 's': store.toJson()};

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
/// dimensions, every edit so far and the items on the ground); the host sends
/// each step's block edits and new and gone drops, 10 times a second the
/// drops that moved, and 20 times a second the players (each with its
/// dimension) and the mobs (of the host's dimension, where they live). A
/// client's edits are requests it settles by compare-and-set; its drops are
/// made here, in the host's dimension (one from another, where the host steps
/// no world, goes back to the peer's bag); its poses and hits come back to
/// it; a remote player in the host's dimension is a target its mobs hunt, and
/// the damage it takes goes to its peer, as do the drops it reaches. A
/// client follows the host's sky. A client opens the stores of the host's dimension only, and its edit of a
/// slot stands only on the slot it saw (compare-and-set) and when what it
/// puts in is paid for: out of what it took from that store since it opened
/// it, then out of what it last declared it holds.
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
  double _dropClock = 0.0;
  final Map<int, List<int>> _edits = {};
  int _nextDrop = 1;
  final Map<int, ItemPickup> _drops = {};
  final Map<int, Vector3> _dropSent = {};
  final List<ItemPickup> _announce = [];
  // The store each peer has open, by peer: the store itself, which a break,
  // a store placed anew or the host's trip replaces in its rules; what the
  // peer took out of it since it opened it, by kind of stack (the escrow);
  // and each open store as last sent.
  final Map<int, ({NetPeer peer, IVec3 cell, Inventory store})> _open = {};
  final Map<int, Map<String, int>> _escrow = {};
  final Map<Inventory, String> _storeSent = {};
  String _weatherSent = '';

  static String _kind(ItemStack s) => '${s.id}/${s.bonus}/${s.dur}';

  /// Numbers the drops the game made since the last call: each its own
  /// number, announced at the end of the step.
  void _trackDrops() {
    for (final e in game.entities) {
      if (e is! ItemPickup || e.netId != 0 || e.removed) continue;
      e.netId = _nextDrop++;
      _drops[e.netId] = e;
      _dropSent[e.netId] = e.position.clone();
      _announce.add(e);
    }
  }

  /// A `drops` message of [drops], those not gone, in the host's dimension.
  NetMessage _dropsMessage(Iterable<ItemPickup> drops) => {
    't': 'drops',
    'd': game.world.dimension,
    'l': [
      for (final d in drops)
        if (!d.removed) {'n': d.netId, 's': d.stack.toJson(), 'p': _v(d.position)},
    ],
  };

  /// Hands [stack] back to [peer] as it is, its bag's account untouched: a
  /// drop of a dimension the host steps no world in.
  void _handBack(NetPeer peer, ItemStack stack) => peer.send({'t': 'give', 's': stack.toJson()});

  void _queueEdit(int dimension, IVec3 cell, int id) => (_edits[dimension] ??= [])
    ..add(cell.x)
    ..add(cell.y)
    ..add(cell.z)
    ..add(id);

  void _join(NetPeer peer) {
    final puppet = RemotePlayer(peer.id, game.player.spawnPoint)
      ..onHurt = ((d) =>
          peer.send({'t': 'hurt', 'dmg': d.amount, if (d.from != null) 'from': _v(d.from!), 'kb': d.knockback}))
      ..onGive = ((s) => peer.send({'t': 'give', 's': s.toJson()}));
    players[peer.id] = puppet;
    game.add(puppet);
    _trackDrops();
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
      'drops': _dropsMessage(_drops.values),
      if (game.weather.spec != null) 'weather': GameSession._weatherMessage(game.weather),
    });
  }

  void _message(NetPeer peer, NetMessage m) {
    final puppet = players[peer.id];
    switch (m['t']) {
      case 'pose':
        final before = puppet!.dimension;
        puppet.setPose(
          _vec(m['p']),
          (m['yaw']! as num).toDouble(),
          held: m['held']! as String,
          dead: m['dead'] == true,
          dimension: _dimension(m['d']! as int),
        );
        // A peer arriving where the host is draws the drops there.
        if (puppet.dimension != before && puppet.dimension == game.world.dimension) {
          _trackDrops();
          peer.send(_dropsMessage(_drops.values));
        }
      case 'bag':
        puppet!.carried = m['c'] == null ? null : _stack(m['c']);
        final slots = m['b']! as List<Object?>;
        final own = game.player.inventory;
        if (slots.length != own.capacity) throw FormatException('a bag of ${slots.length} slots, not ${own.capacity}');
        for (final o in slots) {
          if ((o! as Map<String, Object?>).isNotEmpty) _stack(o);
        }
        (puppet.bag ??= Inventory(
          stackSize: own.stackSize,
          maxDurability: own.maxDurability,
          capacity: own.capacity,
          hotbarSize: own.hotbarSize,
        )).fromJson(slots);
      case 'drop':
        final stack = _stack(m['s']);
        if (_dimension(m['d']! as int) == game.world.dimension) {
          game.dropStack(stack, _vec(m['p']), throwVelocity: _vec(m['v']));
        } else {
          _handBack(peer, stack);
        }
      case 'give_rest':
        // What did not fit lands at the puppet's feet, a while out of reach:
        // the peer's next bag reaches the host first.
        final stack = _stack(m['s']);
        if (puppet!.dimension == game.world.dimension) {
          game.add(
            ItemPickup(stack, puppet.position + Vector3(0, 0.4, 0), throwVelocity: Vector3(0, 1.5, 0), wait: 2.0),
          );
        } else {
          _handBack(peer, stack);
        }
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
      case 'store_open':
        _openStore(peer, _dimension(m['d']! as int), _cell(m['c']));
      case 'store_close':
        _closeStore(peer.id);
      case 'store_set':
        _storeSet(peer, puppet!, m);
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

  /// [peer] opens the store at [cell] in [dimension]: sent to it, or shut
  /// at once where the host keeps none (another dimension, a block broken
  /// meanwhile, a chunk the host has not loaded).
  void _openStore(NetPeer peer, int dimension, IVec3 cell) {
    _closeStore(peer.id);
    if (dimension != game.world.dimension || game.blocks[game.world.getBlock(cell)].storage == null) {
      peer.send({'t': 'store_shut', 'c': _c(cell)});
      return;
    }
    final store = game.blockRules.storeAt(cell);
    _open[peer.id] = (peer: peer, cell: cell, store: store);
    _escrow[peer.id] = {};
    _storeSent.putIfAbsent(store, () => jsonEncode(store.toJson()));
    peer.send(GameSession._storeMessage(cell, store));
  }

  void _closeStore(int peer) {
    _open.remove(peer);
    _escrow.remove(peer);
  }

  /// Settles [peer]'s edit of a slot of the store it has open: it stands
  /// when the slot holds what the peer saw there and [_pay] pays for it.
  /// The peer hears the store as it stands, then the verdict; an edit that
  /// crossed the store's shutting has no store and is refused.
  void _storeSet(NetPeer peer, RemotePlayer puppet, NetMessage m) {
    final i = m['i']! as int;
    final before = _slot(m['b']), after = _slot(m['a']);
    final open = _open[peer.id];
    var stood = false;
    if (open != null) {
      final store = open.store;
      if (i < 0 || i >= store.capacity) throw FormatException('slot $i of a store of ${store.capacity}');
      if (after != null && after.count > store.stackSize(after.id)) {
        throw FormatException('a slot of ${after.count} ${after.id}, past its stack');
      }
      stood = _same(store.slots[i], before) && _pay(peer.id, puppet, before, after);
      if (stood) store.setSlot(i, after);
      peer.send(GameSession._storeMessage(open.cell, store));
    }
    peer.send({'t': 'store_ack', 'n': m['n']! as int, 'ok': stood});
  }

  /// The account of [peer]'s edit of a slot from [before] to [after]: what
  /// it puts in is paid out of what it took from this store since it opened
  /// it, the rest out of what [puppet] declared it holds (spent there until
  /// the next declaration); what it takes out goes to its escrow. False, and
  /// nothing spent, when the peer holds too little.
  bool _pay(int peer, RemotePlayer puppet, ItemStack? before, ItemStack? after) {
    final escrow = _escrow[peer]!;
    final (:out, :into) = _moved(before, after);
    if (into != null) {
      final kind = _kind(into), kept = escrow[kind] ?? 0;
      if (into.count > kept && !puppet.spend(into, into.count - kept)) return false;
      escrow[kind] = math.max(0, kept - into.count);
    }
    if (out != null) escrow.update(_kind(out), (n) => n + out.count, ifAbsent: () => out.count);
    return true;
  }

  /// Each open store that changed goes to whoever has it open; one gone
  /// (broken, placed anew, or left behind in the dimension the host left)
  /// shuts their screens.
  void _storesTick() {
    if (_open.isEmpty) {
      _storeSent.clear();
      return;
    }
    final stores = game.blockRules.stores;
    for (final e in _open.entries.toList()) {
      final o = e.value;
      if (identical(stores[o.cell], o.store)) continue;
      _closeStore(e.key);
      o.peer.send({'t': 'store_shut', 'c': _c(o.cell)});
    }
    final watched = {for (final o in _open.values) o.store};
    _storeSent.removeWhere((store, _) => !watched.contains(store));
    for (final store in watched) {
      final now = jsonEncode(store.toJson());
      if (_storeSent[store] == now) continue;
      _storeSent[store] = now;
      for (final o in _open.values) {
        if (identical(o.store, store)) o.peer.send(GameSession._storeMessage(o.cell, store));
      }
    }
  }

  void _leave(NetPeer peer) {
    _closeStore(peer.id);
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
    _dropsTick(dt);
    _storesTick();
    _weatherTick();
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

  /// The sky goes out when it turned: a new spell, a new last rain or a new
  /// intensity to ease toward. The intensity it stands at goes with it, so a
  /// sky set at once is at once everywhere.
  void _weatherTick() {
    final w = game.weather;
    if (w.spec == null) return;
    final said = '${w.spell} ${w.wet} ${w.target}';
    if (said == _weatherSent) return;
    _weatherSent = said;
    net.broadcast(GameSession._weatherMessage(w));
  }

  /// The drops made in this step go out, then those gone (a drop made and
  /// taken in one step is never drawn); 10 times a second, the drops that
  /// moved more than 5 cm since they were last sent.
  void _dropsTick(double dt) {
    _trackDrops();
    if (_announce.isNotEmpty) {
      final made = _dropsMessage(_announce);
      _announce.clear();
      if ((made['l']! as List<Object?>).isNotEmpty) net.broadcast(made);
    }
    final gone = [
      for (final e in _drops.entries)
        if (e.value.removed) e.key,
    ];
    if (gone.isNotEmpty) {
      for (final n in gone) {
        _drops.remove(n);
        _dropSent.remove(n);
      }
      net.broadcast({'t': 'drops_gone', 'n': gone});
    }
    _dropClock += dt;
    if (_dropClock < 0.1) return;
    _dropClock = 0.0;
    final moved = <int>[];
    final at = <double>[];
    for (final e in _drops.entries) {
      final p = e.value.position;
      if (p.distanceTo(_dropSent[e.key]!) <= 0.05) continue;
      _dropSent[e.key] = p.clone();
      moved.add(e.key);
      at.addAll(_v(p));
    }
    if (moved.isNotEmpty) net.broadcast({'t': 'drop_poses', 'n': moved, 'p': at});
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
/// stood by another id. The host's mobs and drops are replicas it draws (in
/// the host's dimension, where they are), and its hits and the host's hurts
/// cross over. Its drops are requests the host makes, where the host is;
/// elsewhere the host steps no world, and the client keeps its drops itself.
/// What the host hands its player goes in the bag, the rest back to the host,
/// and the bag and the stack in hand are declared to the host when they
/// change, at most 5 times a second. A store it opens is the host's, seen
/// as the host last sent it with this client's unsettled edits over it; an
/// edit the host refuses is undone, the hand's share of it too, and a store
/// the host shuts closes its screen. Its sky is the host's: each turn of it
/// starts where the host's stands and eases as the host's does.
class ClientSession extends GameSession {
  /// A client of [game] on [connection], known to the host as [peer], the
  /// host's [drops] drawn and its [weather] followed (the hello's; no
  /// weather for a spec that declares none).
  ClientSession(this.game, this.connection, this.peer, {required NetMessage drops, NetMessage? weather})
    : _hostDimension = drops['d']! as int {
    game.world.addListener(_edited);
    game.screen.addListener(_screenChanged);
    connection.listen(_message);
    _dropsIn(drops);
    if ((weather == null) != (game.weather.spec == null)) throw FormatException('a hello with weather $weather');
    if (weather != null) GameSession._follow(game.weather, weather);
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

  /// The store edits sent and not yet settled by the host.
  int get pendingStoreEdits => _storeEdits.length;

  /// The store edits the host refused, each undone.
  int get storeRefusals => _storeRefusals;
  int _storeRefusals = 0;

  final Map<int, Mob> _mobs = {};
  final Map<int, ItemPickup> _drops = {};
  int _hostDimension;
  String _bagSent = '';
  double _bagClock = 0.0;
  // The store open on this side: its cell, its opening's number, the store
  // the screen edits, the host's as last sent, what the screen's should hold
  // (the host's with the unsettled edits over it), and those edits.
  IVec3? _storeCell;
  int _storeOpening = 0;
  Inventory? _store;
  List<ItemStack?> _storeHost = const [];
  List<ItemStack?> _storeSeen = const [];
  final List<_StoreEdit> _storeEdits = [];
  int _nextStoreEdit = 1;
  bool _storeShowing = false;
  final BlockPrediction _prediction = BlockPrediction();
  final Map<int, List<int>> _requests = {};
  bool _applying = false;
  double _clock = 0.0;

  @override
  bool get hostHere => _hostDimension == game.world.dimension;

  @override
  Inventory storeAt(IVec3 cell) {
    if (cell != _storeCell) throw StateError('the store open is at $_storeCell, not $cell');
    return _store!;
  }

  /// A store's screen opened or shut: the host is told, and an opened one
  /// starts empty until the host sends it.
  void _screenChanged() {
    final cell = switch (game.screen.value) {
      StorageScreen(:final cell) => cell,
      _ => null,
    };
    if (cell == _storeCell) return;
    if (_storeCell != null) connection.send({'t': 'store_close'});
    _storeCell = cell;
    _store = null;
    if (cell == null) return;
    _storeOpening += 1;
    final slots = game.blocks[game.world.getBlock(cell)].storage!.slots;
    _store = Inventory(
      stackSize: (id) => game.items[id].stack,
      maxDurability: (id) => game.items[id].durability,
      capacity: slots,
      hotbarSize: 0,
    )..listeners.add(_storeEdited);
    _storeHost = List.filled(slots, null);
    _storeSeen = List.filled(slots, null);
    connection.send({'t': 'store_open', 'd': game.world.dimension, 'c': _c(cell)});
  }

  /// The screen edited the store: each slot that differs from what it
  /// should hold is an edit sent to the host.
  void _storeEdited() {
    if (_storeShowing) return;
    final store = _store!;
    for (var i = 0; i < store.capacity; i++) {
      final now = store.slots[i];
      if (_same(now, _storeSeen[i])) continue;
      final edit = (n: _nextStoreEdit++, opening: _storeOpening, slot: i, before: _storeSeen[i], after: now?.copy());
      _storeEdits.add(edit);
      _storeSeen[i] = edit.after;
      connection.send({
        't': 'store_set',
        'n': edit.n,
        'i': i,
        'b': edit.before?.toJson() ?? const <String, Object>{},
        'a': edit.after?.toJson() ?? const <String, Object>{},
      });
    }
  }

  /// The store the screen edits becomes the host's as last sent, with the
  /// unsettled edits made in this opening over it.
  void _storeShow() {
    final seen = [for (final s in _storeHost) s?.copy()];
    for (final e in _storeEdits) {
      if (e.opening == _storeOpening) seen[e.slot] = e.after?.copy();
    }
    _storeSeen = seen;
    final store = _store!;
    _storeShowing = true;
    for (var i = 0; i < seen.length; i++) {
      store.slots[i] = seen[i]?.copy();
    }
    store.emitChanged();
    _storeShowing = false;
  }

  /// The player's share of [edit], which the host refused, undone: what it
  /// took out of the slot leaves the player again (the hand first, then the
  /// bag; what the player has thrown away since is gone already), and what
  /// it put in comes back (to the hand while it is free or holds the like,
  /// else to the bag, and what does not fit is thrown).
  void _undoStoreEdit(_StoreEdit edit) {
    final player = game.player;
    final (:out, :into) = _moved(edit.before, edit.after);
    if (out != null) {
      var owed = out.count;
      final held = player.carried;
      if (held != null && _like(held, out)) {
        final take = math.min(held.count, owed);
        held.count -= take;
        owed -= take;
        if (held.count == 0) player.carried = null;
      }
      final bag = player.inventory;
      for (var i = bag.capacity - 1; i >= 0 && owed > 0; i--) {
        final s = bag.slots[i];
        if (s == null || !_like(s, out)) continue;
        final take = math.min(s.count, owed);
        s.count -= take;
        owed -= take;
        if (s.count == 0) bag.slots[i] = null;
      }
      bag.emitChanged();
    }
    if (into == null) return;
    final held = player.carried;
    final screen = game.screen.value;
    if (held == null && (screen is BagScreen || screen is StorageScreen)) {
      player.carried = into;
    } else if (held != null &&
        _like(held, into) &&
        held.dur < 0 &&
        held.count + into.count <= game.items[into.id].stack) {
      held.count += into.count;
    } else {
      final left = player.inventory.put(into);
      if (left > 0) player.throwStack(into..count = left);
    }
  }

  @override
  bool handOffDrop(ItemStack stack, Vector3 at, Vector3 velocity) {
    if (!hostHere) return false;
    connection.send({'t': 'drop', 'd': game.world.dimension, 's': stack.toJson(), 'p': _v(at), 'v': _v(velocity)});
    return true;
  }

  /// The host's drops of a `drops` message, drawn where the client is in the
  /// host's dimension; one drawn already stays as it is.
  void _dropsIn(NetMessage m) {
    _hostDimension = _dimension(m['d']! as int);
    if (!hostHere) return;
    for (final o in m['l']! as List<Object?>) {
      final r = o! as Map<String, Object?>;
      final n = (r['n']! as num).toInt();
      if (_drops[n] case final d? when !d.removed) continue;
      _drops[n] = game.add(
        ItemPickup(_stack(r['s']), _vec(r['p']))
          ..replica = true
          ..netId = n,
      );
    }
  }

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
      case 'drops':
        _dropsIn(m);
      case 'drop_poses':
        // A drop not drawn here is the host's elsewhere, or made before the
        // client came back to the host's dimension and sent again since.
        final n = GameSession._ints(m, 'n', 1);
        final p = [for (final o in m['p']! as List<Object?>) (o! as num).toDouble()];
        if (p.length != n.length * 3) throw FormatException('${n.length} drops moved to ${p.length} numbers');
        for (var i = 0; i < n.length; i++) {
          _drops[n[i]]?.setNetPose(Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]));
        }
      case 'drops_gone':
        for (final n in GameSession._ints(m, 'n', 1)) {
          _drops.remove(n)?.removed = true;
        }
      case 'give':
        final stack = _stack(m['s']);
        final left = game.player.pickUpStack(stack);
        if (left == 0) return;
        final rest = stack..count = left;
        if (hostHere) {
          connection.send({'t': 'give_rest', 's': rest.toJson()});
        } else {
          game.dropStack(rest, game.player.position + Vector3(0, 0.4, 0), throwVelocity: Vector3(0, 1.5, 0));
        }
      case 'state':
        _hostDimension = _dimension(m['d']! as int);
        game.time = (m['time']! as num).toDouble();
        game.timeOfDay = (m['tod']! as num).toDouble();
        _players(m['players']! as List<Object?>);
        // The host's mobs live in its dimension: elsewhere there are none.
        _mobsState(m['d'] == game.world.dimension ? m['mobs']! as List<Object?> : const []);
      case 'weather':
        GameSession._follow(game.weather, m);
      case 'store':
        // A store shut here since the host sent it is no longer seen.
        if (_cell(m['c']) != _storeCell) return;
        final slots = m['s']! as List<Object?>;
        final capacity = _store!.capacity;
        if (slots.length != capacity) throw FormatException('a store of ${slots.length}, not $capacity');
        _storeHost = [for (final o in slots) _slot(o)];
        _storeShow();
      case 'store_ack':
        final n = m['n']! as int;
        final at = _storeEdits.indexWhere((e) => e.n == n);
        if (at < 0) throw FormatException('an ack of store edit $n, which is not unsettled');
        final edit = _storeEdits.removeAt(at);
        if (m['ok'] != true) {
          _undoStoreEdit(edit);
          _storeRefusals += 1;
        }
        if (_store != null) _storeShow();
      case 'store_shut':
        if (game.screen.value == StorageScreen(_cell(m['c']))) game.closeScreen();
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
    // A trip took the replicas of the dimension left.
    _drops.removeWhere((_, d) => d.removed);
    _bagClock += dt;
    if (_bagClock >= 0.2) {
      _bagClock = 0.0;
      final held = game.player.carried;
      final bag = {'t': 'bag', 'b': game.player.inventory.toJson(), if (held != null) 'c': held.toJson()};
      final said = jsonEncode(bag);
      if (said != _bagSent) {
        connection.send(bag);
        _bagSent = said;
      }
    }
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
    game.screen.removeListener(_screenChanged);
    await connection.close();
  }
}

/// Joins the host at [address]:[port]: says hello and waits for the host's
/// world. Returns the hello, whose seed and edits start the client's world;
/// its edits are numbered as the host's dimensions, which the client's spec
/// must declare (`SavedWorld.editsFor` throws otherwise). Its [drops] are the
/// items on the ground where the host is, a `drops` message for
/// [ClientSession], and its [weather] the host's sky as it stands, a
/// `weather` message (null where the spec declares none).
Future<({NetConnection connection, int peer, SavedWorld world, Vector3 spawn, NetMessage drops, NetMessage? weather})>
joinHost(String address, {int port = 7777}) async {
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
    drops: m['drops']! as NetMessage,
    weather: m['weather'] as NetMessage?,
  );
}
