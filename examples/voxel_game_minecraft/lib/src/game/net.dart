import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';

import '../core/blocks.dart';
import '../core/items.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_engine/net.dart';
import '../core/species.dart';
import '../entities/boat.dart';
import '../entities/bobber.dart';
import '../entities/item_drop.dart';
import '../entities/minecart.dart';
import '../entities/mob.dart';
import '../entities/remote_player.dart';
import 'game.dart';
import '../ui/hud.dart';
import 'game_state.dart';
import 'inventory.dart';
import 'weather.dart';

enum NetMode { solo, host, client }

/// A client's predicted block edits waiting for the host's ack (stage 25): the
/// bookkeeping only, so it is testable without a socket.
class BlockPrediction {
  int _seq = 0;

  /// seq -> the cell and the id the client predicted.
  final Map<int, (IVec3, int)> pending = {};

  /// The cell each pending edit owns, so a host broadcast for it waits for the ack.
  final Map<IVec3, int> _at = {};

  /// Records a local edit and returns its sequence number.
  int predict(IVec3 b, int id) {
    _seq += 1;
    pending[_seq] = (b, id);
    _at[b] = _seq;
    return _seq;
  }

  /// Whether a prediction owns [b] until its ack lands.
  bool owns(IVec3 b) => _at.containsKey(b);

  /// Settles edit [seq]; true when the id that stands differs from what the
  /// world shows now (the caller rolls back to [finalId]).
  bool ack(int seq, IVec3 b, int finalId, int current) {
    pending.remove(seq);
    if (_at[b] == seq) _at.remove(b);
    return current != finalId;
  }
}

/// Multiplayer probe (stage 15), on TCP newline-delimited JSON instead of
/// ENet. The host runs the whole simulation: mobs, projectile hits, block
/// edits. A client sends requests (block edit, shot) and receives what to
/// draw: player poses, mob puppets, projectile replicas that never damage, and
/// the host's clock. Stage 21b adds drops, chests, weather, mounts and status
/// effects on the same terms. Stage 25: drop and boat poses stream from the
/// host (replicas lerp, never simulate), a client's bag overflow comes back as
/// a drop, chest edits are gated on "open on the host" and checked against the
/// peer's declared bag, boats and bobbers are replicated, the flow tick sends
/// one batched block message, and a client's block edit is predicted and
/// rolled back on the host's ack.
class Net {
  Net._();
  static final Net instance = Net._();

  static const int port = 7777;

  NetMode mode = NetMode.solo;
  Game? main;
  Uint8List pendingEdits = Uint8List(0);
  final Map<int, RemotePlayer> _puppets = {};
  final Map<int, Mob> _mobPuppets = {};
  double _poseTimer = 0.0;
  double _mobTimer = 0.0;
  double _timeTimer = 0.0;
  bool connected = false;
  bool _applying = false;
  bool _mobPacketSeen = false;

  /// The transport: `voxel_engine`'s TCP layer. The host owns a [NetHost] (it
  /// numbers peers from 2 and frames the JSON lines); a client owns the single
  /// [NetConnection] to it. Everything above this pair is Dawnforge's protocol.
  NetHost? _host;
  NetConnection? _conn;

  /// Stage 21b: the drops the host owns, and the replicas a client draws.
  final Map<int, ItemDrop> _drops = {};
  final Map<int, ItemDrop> dropReplicas = {};
  int _nextDropId = 1;

  /// Chest views a client has open, and the peers watching each chest on the host.
  final Map<IVec3, Inventory> _chestViews = {};
  final Map<IVec3, Set<int>> _chestWatchers = {};

  /// Mounts ridden by a peer's puppet on the host.
  final Map<int, Mob> _mounts = {};

  /// The last item handed to a peer, read by the probe: (peer, item, count).
  (int, String, int)? lastGive;

  /// Stage 25 — drop poses stream at 10 Hz; boats and bobbers are host-owned
  /// like drops.
  double _dropTimer = 0.0;
  double _bobberTimer = 0.0;
  double _bagTimer = 0.0;
  bool _bobberWasCast = false;
  final Map<int, Boat> _boats = {};
  final Map<int, Boat> _boatReplicas = {};
  final Map<int, Boat> boatDrivers = {};
  final Map<int, Bobber> _bobberReplicas = {};
  int _nextBoatId = 1;

  /// Stage 28 — minecarts are host-owned like boats.
  final Map<int, Minecart> _carts = {};
  final Map<int, Minecart> _cartReplicas = {};
  final Map<int, Minecart> cartRiders = {};
  int _nextCartId = 1;

  /// Host: each peer's bag as it last declared it, and the items a peer took
  /// out of an open chest and has not put back (its cursor, in escrow).
  final Map<int, Inventory> _peerBags = {};
  final Map<int, Map<String, int>> _chestEscrow = {};

  /// Client: predicted block edits waiting for the host's ack.
  final BlockPrediction prediction = BlockPrediction();

  /// Host: block edits collected during a flow tick, sent as one `blocks`
  /// message (flat x, y, z, id quads).
  final List<int> _batch = [];
  bool _batching = false;

  /// Probe: `--reject-one` makes the host refuse the first client edit it receives.
  bool rejectOne = false;

  /// Counters read by the `--stage25` probe on either side (Godot's names).
  final Map<String, Object> stats = {
    'drop_pose_rpcs': 0, 'give_rest_spawned': 0, 'chest_rejected': 0, 'chest_accepted': 0,
    'flow_batch_rpcs': 0, 'flow_batch_cells': 0, 'rejected_seq': -1, 'flow_cells_seen': 0, 'bobber_seen': false,
    'predicted': 0, 'rollbacks': 0, 'bag_got': 0, 'boat_replica_poses': 0, 'boat_boarded': false, 'chest_states': 0,
  };

  void _bump(String key, [int by = 1]) => stats[key] = (stats[key] as int) + by;

  /// Rows per pose message. Godot keeps an unreliable ENet packet under the
  /// MTU with 40; a TCP line has no MTU, the split is kept for the same counts.
  static const int poseRowsPerPacket = 40;

  /// Cells per `blocks` message (Godot's reliable packet size; same note).
  static const int blocksPerPacket = 200;

  /// Set by a hello that arrives before the world exists.
  void Function()? onHelloBeforeWorld;

  /// Stage 29: the dimension this peer's world holds (0 before a world exists).
  int get _dim => main?.world.dimension ?? 0;

  bool get isHost => mode == NetMode.host;
  bool get isClient => mode == NetMode.client;

  Future<bool> host() async {
    final NetHost h;
    try {
      h = await NetHost.bind(port: port);
    } catch (e) {
      debugPrint('[net] could not open port $port: $e');
      return false;
    }
    _host = h;
    mode = NetMode.host;
    h
      ..onJoin = (peer) {
        debugPrint('[net] peer ${peer.id} joined');
        _onPeerJoined(peer);
      }
      ..onMessage = ((peer, m) => _onHostMessage(peer.id, m))
      ..onLeave = ((peer) => _onPeerLeft(peer.id));
    return true;
  }

  Future<bool> join(String ip) async {
    final NetConnection c;
    try {
      c = await connectToHost(ip, port: port);
    } catch (e) {
      debugPrint('[net] join failed: $e');
      return false;
    }
    _conn = c;
    mode = NetMode.client;
    GameState.instance.worldName = 'client_${DateTime.now().millisecondsSinceEpoch % 100000}';
    GameState.instance.freshWorld = true;
    c.listen(_onClientMessage);
    unawaited(c.done.then((_) {
      debugPrint('[net] server disconnected');
      main?.notify('Host left');
    }));
    return true;
  }

  void _broadcast(NetMessage m) => _host?.broadcast(m);

  void _toHost(NetMessage m) => _conn?.send(m);

  void _toPeer(int id, NetMessage m) => _host?.peers[id]?.send(m);

  static List<double> _v(Vector3 v) => [v.x, v.y, v.z];
  static Vector3 _vec(dynamic l) {
    final a = (l as List<dynamic>).map((e) => (e as num).toDouble()).toList();
    return Vector3(a[0], a[1], a[2]);
  }

  static Map<String, Object> _stackJson(ItemStack? s) => s?.toJson() ?? <String, Object>{};

  void _onPeerJoined(NetPeer peer) {
    final m = main;
    if (m == null) return;
    m.saveGame();
    final bytes = m.world.editsToBytes();
    peer.send({'t': 'hello', 'seed': m.world.seedValue, 'time': m.timeOfDay, 'edits': base64Encode(bytes)});
    for (final e in _drops.entries) {
      final d = e.value;
      peer.send({'t': 'drop', 'id': e.key, 'item': d.itemId, 'n': d.count, 'pos': _v(d.position), 'vel': _v(d.velocity)});
    }
    for (final e in _boats.entries) {
      peer.send({'t': 'boat', 'id': e.key, 'pos': _v(e.value.position), 'yaw': e.value.yaw});
    }
    for (final c in _carts.values) {
      peer.send(_cartSpawnMessage(c));
    }
    peer.send({'t': 'weather', 'kind': m.weather.kind.index, 'target': m.weather.target});
  }

  void _onPeerLeft(int id) {
    final p = _puppets.remove(id);
    if (p != null) p.removed = true;
    _releaseMount(id);
    _releaseBoat(id);
    _releaseCart(id);
    _peerBags.remove(id);
    _chestEscrow.remove(id);
    for (final w in _chestWatchers.values) {
      w.remove(id);
    }
    _freeBobberReplica(id);
  }

  void _onHostMessage(int sender, Map<String, dynamic> msg) {
    final m = main;
    if (m == null) return;
    switch (msg['t']) {
      case 'block_req':
        _onBlockRequest(sender, msg);
      case 'pose':
        _onPose(sender, msg);
      case 'fire':
        final owner = _puppets[sender] ?? m.player;
        m.spawnProjectile(_vec(msg['from']), _vec(msg['vel']), (msg['dmg'] as num).toDouble(), owner, msg['kind'] as String,
            (msg['radius'] as num).toDouble(), (msg['kb'] as num).toDouble());
      case 'melee':
        final attacker = _puppets[sender] ?? m.player;
        m.meleeStrike(_vec(msg['dir']), (msg['dmg'] as num).toDouble(), (msg['follow'] as num).toDouble(), attacker);
      case 'drop_req':
        m.spawnDrop(_vec(msg['pos']), msg['item'] as String, msg['n'] as int, _vec(msg['vel']), 1.5);
      case 'give_rest':
        _onGiveRest(sender, msg['item'] as String, msg['n'] as int, msg['bonus'] as int);
      case 'bag':
        (_peerBags[sender] ??= Inventory()).fromJson(msg['data'] as List<dynamic>);
      case 'chest_open':
        final at = IVec3.parse(msg['at'] as String);
        _chestWatchers.putIfAbsent(at, () => <int>{}).add(sender);
        _toPeer(sender, {'t': 'chest_state', 'at': at.key, 'data': m.chestInventory(at).toJson()});
      case 'chest_close':
        _chestWatchers[IVec3.parse(msg['at'] as String)]?.remove(sender);
        _chestEscrow.remove(sender); // the cursor went back to the peer's bag
      case 'chest_set':
        _onChestSet(sender, IVec3.parse(msg['at'] as String), msg['slot'] as int,
            msg['stack'] as Map<String, dynamic>, msg['from_bag'] == true);
      case 'mount_req':
        _onMountRequest(sender, msg['net'] as int);
      case 'dismount_req':
        _releaseMount(sender);
      case 'boat_req':
        m.spawnBoat(_vec(msg['pos']), (msg['yaw'] as num).toDouble());
      case 'board_req':
        _onBoardRequest(sender, msg['net'] as int);
      case 'unboard_req':
        _releaseBoat(sender);
      case 'break_boat_req':
        final b = _boats[msg['net'] as int];
        if (b == null || b.removed || b.driver != null) return;
        m.spawnDrop(b.position + Vector3(0, 0.5, 0), 'boat', 1);
        b.removed = true;
      case 'cart_req':
        m.spawnMinecart(IVec3.parse(msg['cell'] as String), msg['kind'] as String);
      case 'cart_board_req':
        _onCartBoardRequest(sender, msg['net'] as int);
      case 'cart_unboard_req':
        _releaseCart(sender);
      case 'break_cart_req':
        final c = _carts[msg['net'] as int];
        if (c == null || c.removed || c.rider != null) return;
        m.breakMinecart(c);
      case 'bobber':
        _onBobberPose(sender, _vec(msg['pos']));
      case 'bobber_gone':
        _freeBobberReplica(sender);
      case 'travel_req':
        _onTravelRequest(sender, msg['d'] as int);
    }
  }

  void _onClientMessage(Map<String, dynamic> msg) {
    switch (msg['t']) {
      case 'hello':
        GameState.instance.seedValue = msg['seed'] as int;
        pendingEdits = base64Decode(msg['edits'] as String);
        connected = true;
        debugPrint('[net] hello from host: seed ${msg['seed']}, ${pendingEdits.length} edit bytes');
        final m = main;
        if (m == null) {
          onHelloBeforeWorld?.call();
        } else {
          m.timeOfDay = (msg['time'] as num).toDouble();
          if (m.world.seedValue != msg['seed']) {
            m.world.setWorldSeed(msg['seed'] as int).then((_) {
              m.world.reset();
              m.world.updateAround(m.player.position);
              applyPendingEdits();
            });
          } else {
            applyPendingEdits();
          }
        }
      case 'block':
        final m = main;
        if (m == null) return;
        final b = IVec3(msg['x'] as int, msg['y'] as int, msg['z'] as int);
        final dim = (msg['dim'] as int?) ?? 0;
        if (dim != m.world.dimension) {
          m.world.storeEdit(dim, b, msg['id'] as int); // stage 29: waits in the other dimension's delta
          return;
        }
        if (m.world.getBlock(b) == msg['id']) return;
        if (prediction.owns(b)) return; // a prediction owns this cell until its ack lands
        _applying = true;
        m.world.setBlock(b, msg['id'] as int);
        _applying = false;
      case 'blocks':
        _onBlocks(msg['cells'] as List<dynamic>, (msg['dim'] as int?) ?? 0);
      case 'block_ack':
        _onBlockAck(msg['seq'] as int, IVec3(msg['x'] as int, msg['y'] as int, msg['z'] as int), msg['id'] as int);
      case 'pose':
        _onPose(1, msg);
      case 'time':
        main?.timeOfDay = (msg['v'] as num).toDouble();
      case 'mobs':
        _onMobs(msg);
      case 'replica':
        main?.spawnReplica(_vec(msg['from']), _vec(msg['vel']), msg['kind'] as String, (msg['radius'] as num).toDouble());
      case 'hurt':
        main?.player.takeDamage((msg['amount'] as num).toDouble(), msg['source'] as String,
            msg['from'] == null ? null : _vec(msg['from']));
      case 'dmg':
        main?.spawnDamageNumber(_vec(msg['at']), (msg['amount'] as num).toDouble(), _vec(msg['color']), msg['crit'] == true);
      case 'drop':
        _onDropSpawn(msg);
      case 'drop_poses':
        _onDropPoses(msg);
      case 'drop_free':
        dropReplicas.remove(msg['id'] as int)?.removed = true;
      case 'give':
        _onGive(msg['item'] as String, msg['n'] as int, msg['bonus'] as int);
      case 'chest_state':
        _bump('chest_states');
        final at = IVec3.parse(msg['at'] as String);
        _chestViews[at]?.fromJson(msg['data'] as List<dynamic>);
      case 'weather':
        main?.weather.follow(WeatherKind.values[msg['kind'] as int], (msg['target'] as num).toDouble());
      case 'effect':
        main?.player.applyEffect(msg['id'] as String, (msg['seconds'] as num).toDouble());
      case 'boat':
        _onBoatSpawn(msg['id'] as int, _vec(msg['pos']), (msg['yaw'] as num).toDouble());
      case 'boat_poses':
        _onBoatPoses(msg);
      case 'boat_free':
        _onBoatFree(msg['id'] as int);
      case 'cart':
        _onCartSpawn(msg);
      case 'cart_poses':
        _onCartPoses(msg);
      case 'cart_free':
        _onCartFree(msg['id'] as int);
      case 'bobber':
        _onBobberPose(1, _vec(msg['pos']));
      case 'bobber_gone':
        _freeBobberReplica(1);
      case 'set_dim':
        main?.travelToDimension(msg['d'] as int);
    }
  }

  /// Called by the game once its world exists (client side).
  void applyPendingEdits() {
    final m = main;
    if (m == null || pendingEdits.isEmpty) return;
    m.world.loadEditsFromBytes(pendingEdits);
    m.world.refresh();
    pendingEdits = Uint8List(0);
  }

  // --- blocks ------------------------------------------------------------------

  void onBlockChanged(IVec3 b, int old, int id) {
    if (_applying) return;
    if (mode == NetMode.host) {
      if (_batching) {
        _batch.addAll([b.x, b.y, b.z, id]);
      } else {
        _broadcast({'t': 'block', 'x': b.x, 'y': b.y, 'z': b.z, 'id': id, 'dim': _dim});
      }
    } else if (mode == NetMode.client) {
      // Stage 25: the edit is already applied locally (the prediction); the
      // host's ack confirms it or hands back the id that stands.
      final seq = prediction.predict(b, id);
      _toHost({'t': 'block_req', 'seq': seq, 'x': b.x, 'y': b.y, 'z': b.z, 'id': id, 'dim': _dim});
    }
  }

  void _onBlockRequest(int sender, Map<String, dynamic> msg) {
    final m = main!;
    final seq = msg['seq'] as int;
    final b = IVec3(msg['x'] as int, msg['y'] as int, msg['z'] as int);
    final id = msg['id'] as int;
    if (rejectOne) {
      rejectOne = false;
      stats['rejected_seq'] = seq;
      debugPrint('[net] refused edit seq $seq from peer $sender at $b (probe)');
    } else if (((msg['dim'] as int?) ?? 0) != m.world.dimension) {
      // Stage 29: an edit in a dimension the host does not hold is kept in that
      // dimension's delta (it lands when the host travels there) and passed on
      // to the peers, unchecked.
      final dim = msg['dim'] as int;
      m.world.storeEdit(dim, b, id);
      _broadcast({'t': 'block', 'x': b.x, 'y': b.y, 'z': b.z, 'id': id, 'dim': dim});
      _toPeer(sender, {'t': 'block_ack', 'seq': seq, 'x': b.x, 'y': b.y, 'z': b.z, 'id': id});
      return;
    } else {
      m.world.setBlock(b, id);
      // A client planted: the host grows it (stage 25).
      if (id != Blocks.air && Blocks.idOf(id) == 'wheat_0') m.plantCrop(b);
    }
    _toPeer(sender, {'t': 'block_ack', 'seq': seq, 'x': b.x, 'y': b.y, 'z': b.z, 'id': m.world.getBlock(b)});
  }

  /// Client: the id that stands at [b] after edit [seq] was handled.
  void _onBlockAck(int seq, IVec3 b, int finalId) {
    final m = main;
    if (m == null) return;
    if (!prediction.ack(seq, b, finalId, m.world.getBlock(b))) {
      _bump('predicted');
      return;
    }
    _bump('rollbacks');
    debugPrint('[net] rollback seq $seq at $b -> $finalId');
    _applying = true;
    m.world.setBlock(b, finalId);
    _applying = false;
  }

  /// Host: the flow tick's edits are collected between these two calls and
  /// sent as one message.
  void beginBlockBatch() {
    if (mode == NetMode.host) _batching = true;
  }

  void endBlockBatch() {
    if (!_batching) return;
    _batching = false;
    if (_batch.isEmpty) return;
    final total = _batch.length ~/ 4;
    for (var start = 0; start < total; start += blocksPerPacket) {
      final stop = math.min(start + blocksPerPacket, total);
      _broadcast({'t': 'blocks', 'cells': _batch.sublist(start * 4, stop * 4), 'dim': _dim});
      _bump('flow_batch_rpcs');
    }
    _bump('flow_batch_cells', total);
    _batch.clear();
  }

  void _onBlocks(List<dynamic> cells, int dim) {
    final m = main;
    if (m == null) return;
    _bump('flow_cells_seen', cells.length ~/ 4);
    _applying = true;
    for (var i = 0; i + 3 < cells.length; i += 4) {
      final b = IVec3(cells[i] as int, cells[i + 1] as int, cells[i + 2] as int);
      if (dim != m.world.dimension) {
        m.world.storeEdit(dim, b, cells[i + 3] as int);
      } else if (!prediction.owns(b)) {
        m.world.setBlock(b, cells[i + 3] as int);
      }
    }
    _applying = false;
  }

  // --- stage 29: dimensions ------------------------------------------------------
  // Travel is host-owned: a client that stood in a portal asks, the host answers
  // with the dimension to load, and the client runs the same arrival as the host
  // would (its own chunks, its own safe spot, its return portal as predicted
  // edits). Mobs exist in the host's dimension only.

  void requestTravel(int d) => _toHost({'t': 'travel_req', 'd': d});

  void _onTravelRequest(int sender, int d) {
    final m = main;
    if (mode != NetMode.host || m == null) return;
    var ok = true;
    final puppet = _puppets[sender];
    if (puppet != null && puppet.dimension == m.world.dimension) {
      // In the host's own dimension the request is checked: the puppet's feet must be in a portal.
      final at = puppet.position;
      final feet = IVec3(at.x.floor(), (at.y + 0.3).floor(), at.z.floor());
      final id = m.world.getBlock(feet);
      ok = id != Blocks.air && Blocks.idOf(id) == 'portal';
    }
    debugPrint('[net] travel request from peer $sender to dimension $d: ${ok ? 'granted' : 'refused'}');
    if (ok) _toPeer(sender, {'t': 'set_dim', 'd': d});
  }


  // --- players -------------------------------------------------------------------

  void process(double dt) {
    final m = main;
    if (mode == NetMode.solo || m == null) return;
    _poseTimer += dt;
    if (_poseTimer >= 0.05) {
      _poseTimer = 0.0;
      final p = m.player;
      final h = p.mount;
      final boat = p.riding;
      final riding = h != null && h.puppet;
      final rowing = boat != null && boat.replica;
      final cart = p.cart;
      final carting = cart != null && cart.replica;
      final pose = {
        't': 'pose',
        'pos': _v(p.position),
        'yaw': p.model.yaw,
        'held': p.heldItem(),
        'cls': p.playerClass,
        'dim': m.world.dimension, // stage 29
        if (riding) 'ride': _v(h.rideInput),
        if (riding) 'sprint': h.rideSprint,
        if (riding && h.rideJump) 'jump': true,
        // Stage 25: the host's boat rows (x = steer, z = throttle).
        if (rowing) 'ride': [boat.steer, 0.0, boat.throttle],
        // Stage 28: the host drives the cart (z = push).
        if (carting) 'ride': [0.0, 0.0, cart.push],
      };
      // A puppet never consumes the jump; the host's horse does.
      if (riding) h.rideJump = false;
      if (mode == NetMode.host) {
        _broadcast(pose);
      } else {
        _toHost(pose);
      }
    }
    _bobberTimer += dt;
    if (_bobberTimer >= 0.2) {
      _bobberTimer = 0.0;
      _sendBobber();
    }
    for (final b in _bobberReplicas.values) {
      b.update(dt);
    }
    if (mode == NetMode.client && m.player.bagDirty) {
      _bagTimer += dt;
      if (_bagTimer >= 0.2) {
        _bagTimer = 0.0;
        m.player.bagDirty = false;
        sendBagSnapshot();
      }
    }
    if (mode == NetMode.host) {
      _mobTimer += dt;
      if (_mobTimer >= 0.1) {
        _mobTimer = 0.0;
        _broadcastMobs();
      }
      _dropTimer += dt;
      if (_dropTimer >= 0.1) {
        _dropTimer = 0.0;
        _broadcastDropPoses();
        _broadcastBoatPoses();
        _broadcastCartPoses();
      }
      _timeTimer += dt;
      if (_timeTimer >= 2.0) {
        _timeTimer = 0.0;
        _broadcast({'t': 'time', 'v': m.timeOfDay});
      }
    }
  }

  void _onPose(int id, Map<String, dynamic> msg) {
    final m = main;
    if (m == null) return;
    var puppet = _puppets[id];
    if (puppet == null) {
      puppet = RemotePlayer()..peerId = id;
      puppet.setupPuppet(msg['cls'] as String, 'Player $id');
      _puppets[id] = puppet;
      m.addPuppet(puppet);
    }
    puppet.setPose(_vec(msg['pos']), (msg['yaw'] as num).toDouble(), msg['held'] as String);
    puppet.dimension = (msg['dim'] as int?) ?? 0;
    final h = _mounts[id];
    final boat = boatDrivers[id];
    final cart = cartRiders[id];
    if (h != null && !h.removed && h.ridden) {
      h.rideInput = msg['ride'] == null ? Vector3.zero() : _vec(msg['ride']);
      h.rideSprint = msg['sprint'] == true;
      h.rideJump = h.rideJump || msg['jump'] == true;
    } else if (boat != null && !boat.removed) {
      final ride = msg['ride'] == null ? Vector3.zero() : _vec(msg['ride']);
      boat.steer = ride.x;
      boat.throttle = ride.z;
    } else if (cart != null && !cart.removed) {
      final ride = msg['ride'] == null ? Vector3.zero() : _vec(msg['ride']);
      cart.push = ride.z.clamp(-1.0, 1.0);
    }
  }

  // --- mobs: host simulates, clients draw puppets -----------------------------------

  void _broadcastMobs() {
    final m = main!;
    final rows = <List<Object>>[];
    for (final mob in [...m.mobs, ...m.pets]) {
      if (mob.puppet || mob.state == MobState.dead || !m.isHere(mob)) continue;
      rows.add([mob.instanceId, mob.species.id, mob.position.x, mob.position.y, mob.position.z, mob.modelYaw(),
        mob.hp, mob.maxHp, mob.mobLevel, mob.tamed, mob.riddenBy]);
    }
    _broadcast({'t': 'mobs', 'time': m.timeOfDay, 'rows': rows, 'dim': m.world.dimension});
  }

  void _onMobs(Map<String, dynamic> msg) {
    final m = main;
    if (m == null) return;
    final rows = msg['rows'] as List<dynamic>;
    if (!_mobPacketSeen) {
      _mobPacketSeen = true;
      debugPrint('[net] first mob packet: ${rows.length} mobs, host time ${msg['time']}');
    }
    m.timeOfDay = (msg['time'] as num).toDouble();
    // Stage 29: the host's mobs are hidden from another dimension.
    final sameDim = ((msg['dim'] as int?) ?? 0) == m.world.dimension;
    final seen = <int>{};
    for (final r in rows) {
      final row = r as List<dynamic>;
      final key = row[0] as int;
      seen.add(key);
      var mob = _mobPuppets[key];
      if (mob == null) {
        mob = Mob();
        mob.setupMob(m.world, m, m.player, Species.def(row[1] as String));
        mob.puppet = true;
        mob.position = Vector3((row[2] as num).toDouble(), (row[3] as num).toDouble(), (row[4] as num).toDouble());
        mob.scaleToLevel((row[8] as num).toInt());
        mob.netId = key;
        _mobPuppets[key] = mob;
        m.addMob(mob);
      }
      mob.setPuppetState(Vector3((row[2] as num).toDouble(), (row[3] as num).toDouble(), (row[4] as num).toDouble()),
          (row[5] as num).toDouble(), (row[6] as num).toDouble(), (row[7] as num).toDouble());
      mob.setPuppetFlags(row[9] == true, (row[10] as num).toInt());
      mob.node.visible = sameDim;
    }
    for (final key in _mobPuppets.keys.toList()) {
      if (!seen.contains(key)) _mobPuppets.remove(key)!.removed = true;
    }
    // A puppet whose peer rides a horse sits on that horse's puppet.
    for (final p in _puppets.values) {
      p.mountedOn = null;
    }
    for (final h in _mobPuppets.values) {
      if (h.riddenBy != 0) _puppets[h.riddenBy]?.mountedOn = h;
    }
  }

  // --- projectiles: host owns the hit, everyone sees a replica ------------------------

  void requestFire(Vector3 from, Vector3 vel, double dmg, String kind, double radius, double kb) =>
      _toHost({'t': 'fire', 'from': _v(from), 'vel': _v(vel), 'dmg': dmg, 'kind': kind, 'radius': radius, 'kb': kb});

  void broadcastReplica(Vector3 from, Vector3 vel, String kind, double radius) {
    if (mode == NetMode.host) _broadcast({'t': 'replica', 'from': _v(from), 'vel': _v(vel), 'kind': kind, 'radius': radius});
  }

  // --- melee: the host runs the reach check for a client's swing ----------------------

  void requestMelee(Vector3 dir, double dmg, double followUp) =>
      _toHost({'t': 'melee', 'dir': _v(dir), 'dmg': dmg, 'follow': followUp});

  // --- damage: the host decides, the peer's own body applies it -----------------------

  void hurtPeer(int id, double amount, String source, Vector3? from) {
    if (mode != NetMode.host) return;
    _toPeer(id, {'t': 'hurt', 'amount': amount, 'source': source, 'from': from == null ? null : _v(from)});
  }

  /// Stage 32: the crit rides the damage-number message as one extra bool.
  void broadcastDamageNumber(Vector3 at, double amount, Vector3 color, [bool crit = false]) {
    if (mode == NetMode.host) _broadcast({'t': 'dmg', 'at': _v(at), 'amount': amount, 'color': _v(color), 'crit': crit});
  }

  // --- drops: the host owns every drop, a client draws replicas and is handed
  // what it picks up ------------------------------------------------------------

  void requestDrop(Vector3 at, String id, int count, Vector3 vel) =>
      _toHost({'t': 'drop_req', 'pos': _v(at), 'item': id, 'n': count, 'vel': _v(vel)});

  /// Host: a drop was created; give it a net id and tell every client to draw it.
  void onDropSpawned(ItemDrop drop) {
    if (mode != NetMode.host) return;
    drop.netId = _nextDropId++;
    _drops[drop.netId] = drop;
    _broadcast({'t': 'drop', 'id': drop.netId, 'item': drop.itemId, 'n': drop.count,
      'pos': _v(drop.position), 'vel': _v(drop.velocity)});
  }

  /// Host: a drop left the world (picked up or aged out); clients free the replica.
  void onDropGone(ItemDrop drop) {
    if (mode != NetMode.host || drop.netId == 0) return;
    if (_drops.remove(drop.netId) == null) return;
    _broadcast({'t': 'drop_free', 'id': drop.netId});
  }

  void _onDropSpawn(Map<String, dynamic> msg) {
    final m = main;
    final id = msg['id'] as int;
    if (m == null || dropReplicas.containsKey(id)) return;
    final drop = ItemDrop()..replica = true;
    drop.setupDrop(m.world, msg['item'] as String, msg['n'] as int, m.player, 0.0);
    drop.position = _vec(msg['pos']);
    drop.velocity = _vec(msg['vel']);
    drop.netId = id;
    drop.syncNode();
    dropReplicas[id] = drop;
    m.drops.add(drop);
    m.entities.add(drop.node);
  }

  /// Host, 10 Hz: the drops that moved more than 5 cm since their last send.
  void _broadcastDropPoses() {
    final ids = <int>[];
    final poses = <List<double>>[];
    for (final e in _drops.entries) {
      final d = e.value;
      final last = d.lastSent;
      if (d.removed || (last != null && (d.position - last).length <= 0.05)) continue;
      d.lastSent = d.position.clone();
      ids.add(e.key);
      poses.add(_v(d.position));
    }
    for (var start = 0; start < ids.length; start += poseRowsPerPacket) {
      final stop = math.min(start + poseRowsPerPacket, ids.length);
      _broadcast({'t': 'drop_poses', 'ids': ids.sublist(start, stop), 'poses': poses.sublist(start, stop)});
      _bump('drop_pose_rpcs');
    }
  }

  void _onDropPoses(Map<String, dynamic> msg) {
    final ids = msg['ids'] as List<dynamic>;
    final poses = msg['poses'] as List<dynamic>;
    for (var i = 0; i < ids.length; i++) {
      final d = dropReplicas[ids[i] as int];
      if (d != null && !d.removed) d.setNetPose(_vec(poses[i]));
    }
  }

  List<ItemDrop> liveDropReplicas() => [for (final d in dropReplicas.values) if (!d.removed) d];

  /// Host: a puppet reached a drop; the peer's own inventory receives it.
  void givePeer(int id, String item, int count, int bonus) {
    if (mode != NetMode.host || _host?.peers[id] == null) return;
    lastGive = (id, item, count);
    debugPrint('[net] gave peer $id $item x$count');
    _toPeer(id, {'t': 'give', 'item': item, 'n': count, 'bonus': bonus});
  }

  /// Client: the host handed an item over; what does not fit goes back.
  void _onGive(String item, int count, int bonus) {
    final m = main;
    if (m == null) return;
    if (bonus > 0) {
      if (m.player.inventory.addStack(ItemStack(item, count, bonus: bonus))) {
        m.player.notify('+ ${Hud.itemLabel(item, bonus)}');
      } else {
        _toHost({'t': 'give_rest', 'item': item, 'n': count, 'bonus': bonus});
      }
      return;
    }
    final left = m.player.pickUp(item, count);
    _bump('bag_got', count - left);
    // Stage 25: no room, the host drops the rest.
    if (left > 0) _toHost({'t': 'give_rest', 'item': item, 'n': left, 'bonus': 0});
  }

  /// Host: what did not fit in the peer's bag lands at its puppet's feet.
  void _onGiveRest(int sender, String item, int count, int bonus) {
    final m = main!;
    final puppet = _puppets[sender];
    if (puppet == null) return;
    final at = puppet.position + Vector3(0, 0.4, 0);
    _bump('give_rest_spawned');
    debugPrint('[net] peer $sender had no room for $item x$count: dropped at its feet');
    final drop = m.spawnDrop(at, item, count, Vector3(0, 1.5, 0), 2.0);
    if (drop != null && bonus > 0) drop.bonus = bonus;
  }

  /// Client: the bag as the host should know it (room checks before a pull,
  /// chest validation).
  void sendBagSnapshot() {
    final m = main;
    if (mode == NetMode.client && m != null) _toHost({'t': 'bag', 'data': m.player.inventory.toJson()});
  }

  /// Host: whether the peer's declared bag has room for any of [count] [item]
  /// (a peer that never declared a bag is assumed to have room; a bonus item
  /// needs an empty slot).
  bool peerHasRoom(int id, String item, int count, int bonus) {
    final bag = _peerBags[id];
    if (bag == null) return true;
    if (bonus > 0) return bag.hasEmptySlot;
    return bag.roomFor(item, count) > 0;
  }

  /// Host (probe): the bag peer [id] last declared, if any.
  Inventory? declaredBag(int id) => _peerBags[id];

  // --- chests: the inventory lives on the host, a client sees a copy and sends
  // its edits ------------------------------------------------------------------

  /// Client: the view of a chest, filled once the host answers.
  Inventory openChest(IVec3 at) {
    final view = _chestViews.putIfAbsent(at, Inventory.new);
    _toHost({'t': 'chest_open', 'at': at.key});
    return view;
  }

  void closeChest(IVec3 at) {
    if (mode != NetMode.client) return;
    _chestViews.remove(at);
    _toHost({'t': 'chest_close', 'at': at.key});
  }

  /// One slot of a chest changed. A client sends the slot plus where the
  /// items came from and the host validates it (stage 25); the host
  /// re-broadcasts its own edit to whoever has the chest open.
  void chestSlotChanged(IVec3 at, int slot, ItemStack? stack, bool fromBag) {
    if (mode == NetMode.client) {
      _toHost({'t': 'chest_set', 'at': at.key, 'slot': slot, 'stack': _stackJson(stack), 'from_bag': fromBag});
    } else if (mode == NetMode.host) {
      _sendChestState(at, main!.chestInventory(at).toJson());
    }
  }

  void _sendChestState(IVec3 at, List<Object?> data) {
    for (final id in _chestWatchers[at] ?? const <int>{}) {
      _toPeer(id, {'t': 'chest_state', 'at': at.key, 'data': data});
    }
  }

  bool _chestOpenBy(IVec3 at, int id) => _chestWatchers[at]?.contains(id) ?? false;

  /// Host: one slot of a chest changed by a peer. Accepted only when the peer
  /// has that chest open here, and only when the items it adds are accounted
  /// for: from its declared bag (debited from the snapshot so it cannot be
  /// spent twice before the next one) or from what it took out of this chest
  /// and still holds (the escrow). Anything else is refused and the peer is
  /// sent the state that stands.
  void _onChestSet(int id, IVec3 at, int slot, Map<String, dynamic> stack, bool fromBag) {
    final chest = main!.chestInventory(at);
    if (!_chestOpenBy(at, id) || slot < 0 || slot >= Inventory.size) {
      _bump('chest_rejected');
      debugPrint('[net] chest $at edit from peer $id refused: not open here');
      _toPeer(id, {'t': 'chest_state', 'at': at.key, 'data': chest.toJson()});
      return;
    }
    final verdict = chestEditVerdict(chest.slots[slot], stack, fromBag, _peerBags[id], _chestEscrow.putIfAbsent(id, () => {}));
    if (!verdict) {
      _bump('chest_rejected');
      debugPrint('[net] chest $at edit from peer $id refused: ${stack['id']} not accounted for (from_bag $fromBag)');
      _toPeer(id, {'t': 'chest_state', 'at': at.key, 'data': chest.toJson()});
      return;
    }
    final item = (stack['id'] ?? '').toString();
    chest.setSlot(slot, item == '' || !Items.has(item)
        ? null
        : ItemStack(item, (stack['count'] as num).toInt(),
            bonus: stack['bonus'] == null ? 0 : (stack['bonus'] as num).toInt(),
            dur: stack['dur'] == null ? -1 : (stack['dur'] as num).toInt()));
    _bump('chest_accepted');
    _sendChestState(at, chest.toJson());
  }

  /// The accounting half of a chest edit, pure so it is unit-tested: what
  /// leaves the slot goes into the peer's escrow; what enters must be paid
  /// from the declared [bag] (when [fromBag]) or from the [escrow]. Mutates
  /// both on success; true when the edit is accepted.
  static bool chestEditVerdict(ItemStack? before, Map<String, dynamic> stack, bool fromBag, Inventory? bag,
      Map<String, int> escrow) {
    final newItem = (stack['id'] ?? '').toString();
    final newCount = newItem != '' ? (stack['count'] as num? ?? 0).toInt() : 0;
    final oldItem = before?.id ?? '';
    final oldCount = before?.count ?? 0;
    final removed = oldCount - (newItem == oldItem ? newCount : 0);
    final added = newCount - (newItem == oldItem ? oldCount : 0);
    if (added > 0) {
      var paid = false;
      if (fromBag) {
        if (bag != null && bag.countOf(newItem) >= added) {
          bag.remove(newItem, added);
          paid = true;
        }
      } else if ((escrow[newItem] ?? 0) >= added) {
        escrow[newItem] = escrow[newItem]! - added;
        paid = true;
      }
      if (!paid) return false;
    }
    if (removed > 0) escrow[oldItem] = (escrow[oldItem] ?? 0) + removed;
    return true;
  }

  // --- weather: the host rolls, clients follow ---------------------------------

  void broadcastWeather(WeatherKind kind, double target) {
    if (mode == NetMode.host) _broadcast({'t': 'weather', 'kind': kind.index, 'target': target});
  }

  // --- mounts: a client rides a horse the host owns ----------------------------

  void requestMount(int netId) => _toHost({'t': 'mount_req', 'net': netId});

  void requestDismount() => _toHost({'t': 'dismount_req'});

  void _onMountRequest(int sender, int netId) {
    final m = main;
    if (m == null) return;
    Mob? horse;
    for (final mob in [...m.mobs, ...m.pets]) {
      if (mob.instanceId == netId) horse = mob;
    }
    if (horse == null || !horse.tamed || !horse.isMount || horse.ridden || horse.isDead) {
      debugPrint('[net] peer $sender asked to mount $netId: refused');
      return;
    }
    _releaseMount(sender);
    horse.ridden = true;
    horse.riddenBy = sender;
    horse.rideInput = Vector3.zero();
    _mounts[sender] = horse;
    _puppets[sender]?.mountedOn = horse;
    debugPrint('[net] peer $sender mounted ${horse.species.id} $netId');
  }

  void _releaseMount(int id) {
    final h = _mounts.remove(id);
    if (h == null) return;
    if (!h.removed) {
      h.ridden = false;
      h.riddenBy = 0;
      h.rideInput = Vector3.zero();
      h.rideSprint = false;
    }
    _puppets[id]?.mountedOn = null;
  }

  // --- boats: the host owns every boat; a client draws replicas and asks to
  // row one (stage 25) -----------------------------------------------------------

  void requestBoat(Vector3 at, double heading) => _toHost({'t': 'boat_req', 'pos': _v(at), 'yaw': heading});

  void requestBoard(int netId) => _toHost({'t': 'board_req', 'net': netId});

  void requestUnboard() => _toHost({'t': 'unboard_req'});

  void requestBreakBoat(int netId) => _toHost({'t': 'break_boat_req', 'net': netId});

  /// Host: a boat was created; give it a net id and tell every client to draw it.
  void onBoatSpawned(Boat boat) {
    if (mode != NetMode.host) return;
    boat.netId = _nextBoatId++;
    _boats[boat.netId] = boat;
    _broadcast({'t': 'boat', 'id': boat.netId, 'pos': _v(boat.position), 'yaw': boat.yaw});
  }

  void onBoatGone(Boat boat) {
    if (mode != NetMode.host || boat.netId == 0 || _boats.remove(boat.netId) == null) return;
    boatDrivers.removeWhere((_, b) => identical(b, boat));
    _broadcast({'t': 'boat_free', 'id': boat.netId});
  }

  void _onBoatSpawn(int id, Vector3 pos, double yaw) {
    final m = main;
    if (m == null || _boatReplicas.containsKey(id)) return;
    final b = Boat()
      ..replica = true
      ..netId = id;
    b.setupBoat(m.world, m, pos, yaw);
    _boatReplicas[id] = b;
    m.boats.add(b);
    m.entities.add(b.node);
  }

  void _onBoatFree(int id) {
    final b = _boatReplicas.remove(id);
    if (b == null) return;
    final m = main;
    if (m != null && identical(m.player.riding, b)) m.player.leaveBoat();
    b.removed = true;
  }

  void _broadcastBoatPoses() {
    final ids = <int>[];
    final poses = <List<double>>[];
    final yaws = <double>[];
    for (final e in _boats.entries) {
      final b = e.value;
      final last = b.lastSent;
      if (b.removed || (last != null && (b.position - last).length <= 0.02 && (b.yaw - b.lastSentYaw).abs() <= 0.01)) {
        continue;
      }
      b.lastSent = b.position.clone();
      b.lastSentYaw = b.yaw;
      ids.add(e.key);
      poses.add(_v(b.position));
      yaws.add(b.yaw);
    }
    if (ids.isNotEmpty) _broadcast({'t': 'boat_poses', 'ids': ids, 'poses': poses, 'yaws': yaws});
  }

  void _onBoatPoses(Map<String, dynamic> msg) {
    final ids = msg['ids'] as List<dynamic>;
    final poses = msg['poses'] as List<dynamic>;
    final yaws = msg['yaws'] as List<dynamic>;
    for (var i = 0; i < ids.length; i++) {
      final b = _boatReplicas[ids[i] as int];
      if (b == null || b.removed) continue;
      b.setNetPose(_vec(poses[i]), (yaws[i] as num).toDouble());
      _bump('boat_replica_poses');
    }
  }

  void _onBoardRequest(int id, int netId) {
    final b = _boats[netId];
    final puppet = _puppets[id];
    if (b == null || b.removed || b.driver != null || puppet == null) {
      debugPrint('[net] peer $id asked to board boat $netId: refused');
      return;
    }
    _releaseBoat(id);
    b.driver = puppet;
    b.steer = 0.0;
    b.throttle = 0.0;
    boatDrivers[id] = b;
    stats['boat_boarded'] = true;
    debugPrint('[net] peer $id boarded boat $netId');
  }

  void _releaseBoat(int id) {
    final b = boatDrivers.remove(id);
    if (b == null) return;
    b.driver = null;
    b.throttle = 0.0;
    b.steer = 0.0;
  }

  List<Boat> boatReplicas() => [for (final b in _boatReplicas.values) if (!b.removed) b];

  // --- minecarts: host-owned like boats; a client asks for one, boards a
  // replica, breaks one (stage 28) ----------------------------------------------

  void requestCart(IVec3 cell, String kind) => _toHost({'t': 'cart_req', 'cell': cell.key, 'kind': kind});

  void requestCartBoard(int netId) => _toHost({'t': 'cart_board_req', 'net': netId});

  void requestCartUnboard() => _toHost({'t': 'cart_unboard_req'});

  void requestBreakCart(int netId) => _toHost({'t': 'break_cart_req', 'net': netId});

  Map<String, Object> _cartSpawnMessage(Minecart c) =>
      {'t': 'cart', 'id': c.netId, 'kind': c.kind, 'cell': c.cell.key, 'pos': _v(c.position), 'yaw': c.yaw};

  /// Host: a cart was created; give it a net id and tell every client to draw it.
  void onCartSpawned(Minecart cart) {
    if (mode != NetMode.host) return;
    cart.netId = _nextCartId++;
    _carts[cart.netId] = cart;
    _broadcast(_cartSpawnMessage(cart));
  }

  void onCartGone(Minecart cart) {
    if (mode != NetMode.host || cart.netId == 0 || _carts.remove(cart.netId) == null) return;
    cartRiders.removeWhere((_, c) => identical(c, cart));
    _broadcast({'t': 'cart_free', 'id': cart.netId});
  }

  void _onCartSpawn(Map<String, dynamic> msg) {
    final m = main;
    final id = msg['id'] as int;
    if (m == null || _cartReplicas.containsKey(id)) return;
    final c = Minecart()
      ..replica = true
      ..netId = id;
    c.setupCart(m.world, IVec3.parse(msg['cell'] as String), msg['kind'] as String);
    c.setNetPose(_vec(msg['pos']), (msg['yaw'] as num).toDouble());
    _cartReplicas[id] = c;
    m.carts.add(c);
    m.entities.add(c.node);
  }

  void _onCartFree(int id) {
    final c = _cartReplicas.remove(id);
    if (c == null) return;
    final m = main;
    if (m != null && identical(m.player.cart, c)) m.player.leaveCart();
    c.removed = true;
  }

  void _broadcastCartPoses() {
    final ids = <int>[];
    final poses = <List<double>>[];
    final yaws = <double>[];
    for (final e in _carts.entries) {
      final c = e.value;
      final last = c.lastSent;
      if (c.removed || (last != null && (c.position - last).length <= 0.02 && (c.yaw - c.lastSentYaw).abs() <= 0.01)) {
        continue;
      }
      c.lastSent = c.position.clone();
      c.lastSentYaw = c.yaw;
      ids.add(e.key);
      poses.add(_v(c.position));
      yaws.add(c.yaw);
    }
    if (ids.isNotEmpty) _broadcast({'t': 'cart_poses', 'ids': ids, 'poses': poses, 'yaws': yaws});
  }

  void _onCartPoses(Map<String, dynamic> msg) {
    final ids = msg['ids'] as List<dynamic>;
    final poses = msg['poses'] as List<dynamic>;
    final yaws = msg['yaws'] as List<dynamic>;
    for (var i = 0; i < ids.length; i++) {
      final c = _cartReplicas[ids[i] as int];
      if (c == null || c.removed) continue;
      c.setNetPose(_vec(poses[i]), (yaws[i] as num).toDouble());
    }
  }

  void _onCartBoardRequest(int id, int netId) {
    final c = _carts[netId];
    final puppet = _puppets[id];
    if (c == null || c.removed || c.rider != null || c.cargo != null || puppet == null) {
      debugPrint('[net] peer $id asked to board cart $netId: refused');
      return;
    }
    _releaseCart(id);
    c.rider = puppet;
    c.push = 0.0;
    cartRiders[id] = c;
    debugPrint('[net] peer $id boarded cart $netId');
  }

  void _releaseCart(int id) {
    final c = cartRiders.remove(id);
    if (c == null) return;
    c.rider = null;
    c.push = 0.0;
  }

  List<Minecart> cartReplicas() => [for (final c in _cartReplicas.values) if (!c.removed) c];

  // --- bobbers: a cast line is drawn on every other peer at that peer's puppet
  // (stage 25) -----------------------------------------------------------------

  /// Every peer, 5 Hz: its own bobber's position while cast, one "gone" when
  /// it is reeled in. A client only knows the host's puppet, so the host does
  /// not relay one client's bobber to another.
  void _sendBobber() {
    final m = main!;
    final b = m.player.bobber;
    Map<String, Object?>? msg;
    if (b != null) {
      _bobberWasCast = true;
      msg = {'t': 'bobber', 'pos': _v(b.position)};
    } else if (_bobberWasCast) {
      _bobberWasCast = false;
      msg = {'t': 'bobber_gone'};
    }
    if (msg == null) return;
    if (mode == NetMode.host) {
      _broadcast(msg);
    } else {
      _toHost(msg);
    }
  }

  void _onBobberPose(int id, Vector3 pos) {
    final m = main;
    final puppet = _puppets[id];
    if (m == null || puppet == null) return;
    var rep = _bobberReplicas[id];
    if (rep == null) {
      rep = Bobber.replica(m.world, puppet.model.handWorldPosition, pos);
      m.entities.add(rep.node);
      m.entities.add(rep.lineNode);
      _bobberReplicas[id] = rep;
      stats['bobber_seen'] = true;
    }
    rep.setNetPose(pos);
  }

  void _freeBobberReplica(int id) {
    final rep = _bobberReplicas.remove(id);
    final m = main;
    if (rep == null || m == null) return;
    m.entities.remove(rep.node);
    m.entities.remove(rep.lineNode);
  }

  int bobberReplicaCount() => _bobberReplicas.length;

  // --- status effects: the host decides, the peer's own body wears it ----------

  void effectPeer(int id, String effect, double seconds) {
    if (mode != NetMode.host) return;
    _toPeer(id, {'t': 'effect', 'id': effect, 'seconds': seconds});
  }

  List<RemotePlayer> puppetBodies() => _puppets.values.toList();

  List<(int, Vector3)> puppetPositions() => [for (final e in _puppets.entries) (e.key, e.value.position)];

  void shutdown() {
    final h = _host;
    final c = _conn;
    _host = null;
    _conn = null;
    if (h != null) unawaited(h.close());
    if (c != null) unawaited(c.close());
    mode = NetMode.solo;
  }
}
