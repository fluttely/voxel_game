import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart' show Inventory, ItemStack;
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../entities/target.dart';
import '../mobs/rig.dart';

/// Another player in a networked game: a body standing where its peer says,
/// drawn with the player's rig. On the host it is a [Target] the mobs hunt;
/// the damage it takes goes to its peer through [onHurt], and the drops it
/// reaches through [onGive], as far as its peer's declared [bag] takes them.
class RemotePlayer extends GameEntity implements Target {
  /// Peer [peer]'s player.
  RemotePlayer(this.peer, Vector3 at) {
    position = at.clone();
    _to = at.clone();
    halfWidth = 0.3;
    height = 1.75;
  }

  /// The peer's number.
  final int peer;

  /// The dimension its peer is in, numbered as the world's: drawn, and a
  /// target, only where it is the local player's.
  int dimension = 0;

  /// Where damage dealt to it goes (the host sends it to the peer).
  void Function(Damage damage)? onHurt;

  /// Where a stack handed to it goes (the host sends it to the peer).
  void Function(ItemStack stack)? onGive;

  /// Its peer's bag as the peer last declared it, and what the host handed
  /// it since; null until the first declaration (on the host only).
  Inventory? bag;

  /// The stack its peer holds in hand (`PlayerEntity.carried`) as the peer
  /// last declared it with its [bag]; null for an empty hand (on the host
  /// only). Not room for a pickup, but what a store edit may pay with.
  ItemStack? carried;

  /// How many of [stack] its [bag] takes, as far as the host knows: none
  /// before the peer has declared one.
  int roomFor(ItemStack stack) => bag?.roomForStack(stack) ?? 0;

  /// Takes [count] of the stacks like [kind] (its item, bonus and wear) out
  /// of what its peer declared it holds, the hand first and then the bag, so
  /// they are not spent twice before the next declaration; false, and
  /// nothing taken, when it holds fewer.
  bool spend(ItemStack kind, int count) {
    bool like(ItemStack? s) => s != null && s.id == kind.id && s.bonus == kind.bonus && s.dur == kind.dur;
    final slots = bag?.slots ?? const <ItemStack?>[];
    final held = [
      if (like(carried)) carried!,
      for (final s in slots.reversed)
        if (like(s)) s!,
    ];
    if (held.fold(0, (n, s) => n + s.count) < count) return false;
    for (final s in held) {
      final take = math.min(s.count, count);
      s.count -= take;
      count -= take;
    }
    if (carried?.count == 0) carried = null;
    for (var i = 0; i < slots.length; i++) {
      if (slots[i]?.count == 0) slots[i] = null;
    }
    return true;
  }

  /// Hands [stack] to its peer, counted in its [bag] until the peer next
  /// declares it.
  void give(ItemStack stack) {
    bag!.put(stack);
    onGive!(stack);
  }

  /// The model; null headless.
  RigInstance? rig;

  Vector3 _to = Vector3.zero();
  double _yaw = 0.0;
  double _speed = 0.0;
  bool _dead = false;
  String _held = '';

  @override
  bool get isDead => _dead;

  /// The yaw its peer faces.
  double get yaw => _yaw;

  /// The item in its hand (`''` for none), as its peer last said.
  String get heldItem => _held;

  /// Where the peer says its player is, in which dimension, looking where,
  /// holding what (`''` for nothing), alive or not.
  void setPose(Vector3 at, double yaw, {required String held, bool dead = false, int dimension = 0}) {
    if (dimension != this.dimension) position = at.clone(); // across dimensions it does not walk
    this.dimension = dimension;
    _to = at.clone();
    _yaw = yaw;
    _held = held;
    _dead = dead;
  }

  @override
  void attached(VoxelGame game) {
    setup(game.world, 0.3, 1.75);
    if (game.headless) return;
    final r = game.spec.player.rig.build(0.3, 1.75);
    rig = r;
    node.add(r.root);
  }

  @override
  void tick(VoxelGame game, double dt) {
    final before = position.clone();
    position = position + (_to - position) * math.min(1.0, dt * 12.0);
    final moved = position - before
      ..y = 0;
    _speed = lerpd(_speed, moved.length / math.max(dt, 1e-6), math.min(1.0, dt * 8.0));
    final r = rig;
    if (r != null) {
      r.root.visible = !_dead && dimension == game.world.dimension;
      if (r.canHold) r.hold(_held.isEmpty ? null : game.itemModel(_held));
      r.animate(dt, speed: _speed, targetYaw: _yaw, onFloor: true);
      r.place(Vector3.zero());
    }
    syncNode(yaw: r?.yaw);
  }

  @override
  double takeDamage(Damage damage) {
    if (_dead) return 0.0;
    onHurt?.call(damage);
    return damage.amount;
  }
}
