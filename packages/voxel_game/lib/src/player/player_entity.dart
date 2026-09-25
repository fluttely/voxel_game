import 'dart:math' as math;

import 'package:gamepads/gamepads.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../entities/target.dart';
import '../input/voxel_action.dart';
import '../mobs/mob.dart';
import '../mobs/rig.dart';
import 'character_motor.dart';
import 'player_spec.dart';

/// The player: a body driven by [VoxelAction]s that looks, walks, swims,
/// climbs ladders, mines and places blocks, hits creatures, picks items up,
/// takes falls, burns in lava, drowns, dies and stands up again at the spawn.
class PlayerEntity extends NodeBody implements Target {
  /// A player of [spec].
  PlayerEntity(this.spec, this.inventory) : hp = spec.hp, cameraMode = spec.camera {
    halfWidth = spec.halfWidth;
    height = spec.height;
    motor = CharacterMotor(this, MotorTuning(jumpVelocity: spec.jumpVelocity));
  }

  /// What the player is.
  final PlayerSpec spec;

  /// The bag; the first `hotbarSize` slots are the hotbar.
  final Inventory inventory;

  /// Health.
  double hp;

  /// Where the player stands up after dying.
  Vector3 spawnPoint = Vector3.zero();

  /// Turned left or right, radians (0 looks down -Z).
  double yaw = 0.0;

  /// Looking up (+) or down (-), radians.
  double pitch = -0.2;

  /// The hotbar slot in hand.
  int selectedSlot = 0;

  /// The view.
  CameraMode cameraMode;

  /// The on-foot rules.
  late final CharacterMotor motor;

  /// The block under the crosshair, or null.
  RayHit? aimedBlock;

  /// The creature under the crosshair (nearer than any block), or null.
  Mob? aimedMob;

  /// 0..1 how far the aimed block is mined.
  double mineProgress = 0.0;

  /// The model (third person); null headless.
  RigInstance? rig;

  /// The outline around what the crosshair rests on; null headless.
  SelectionOutline? outline;

  /// 1 the moment the player is hurt, fading to 0: the HUD's red flash and
  /// the camera's jolt.
  double hurtFlash = 0.0;

  bool _dead = false;
  double _deadFor = 0.0;
  double _stepTimer = 0.0;
  double _digTimer = 0.0;
  bool _wasInLiquid = false;
  IVec3? _miningCell;
  double _attackCooldown = 0.0;
  double _useCooldown = 0.0;
  double _lavaTimer = 0.0;
  double _drownTimer = 0.0;
  double _invulnerable = 0.0;
  bool _placed = false;
  late VoxelGame _game;

  @override
  bool get isDead => _dead;

  /// The item in hand, or `''`.
  String get heldItem => inventory.idAt(selectedSlot);

  /// Where the eye looks, a unit vector.
  Vector3 get forward => Vector3(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch));

  /// Forward along the ground.
  Vector3 get flatForward => Vector3(-math.sin(yaw), 0, -math.cos(yaw));

  /// Right along the ground.
  Vector3 get right => Vector3(math.cos(yaw), 0, -math.sin(yaw));

  /// The eye (first person), above the feet.
  Vector3 get eyePosition => position + Vector3(0, spec.eyeHeight, 0);

  /// Whether the player has been put on the ground of a loaded chunk yet.
  bool get placed => _placed;

  /// Attaches to [game]: its world, and its visuals when not headless.
  void attach(VoxelGame game) {
    _game = game;
    setup(game.world, spec.halfWidth, spec.height);
    for (final e in spec.startingItems.entries) {
      inventory.add(e.key, e.value);
    }
    if (game.headless) return;
    final r = spec.rig.build(spec.halfWidth, spec.height);
    rig = r;
    node.add(r.root);
    final o = SelectionOutline();
    outline = o;
    game.scene!.add(o.node);
  }

  Vector3? _restoreAt;

  /// Puts the player back where a save left it (standing there once its chunk
  /// loads), with [spawn] as the respawn point.
  void restore(Vector3 at, Vector3 spawn) {
    _restoreAt = at.clone();
    spawnPoint = spawn.clone();
    position = at.clone();
  }

  /// Puts the player on the ground at column ([x], [z]) once its chunk is
  /// loaded (or where a save left it); true when placed.
  bool tryPlace(int x, int z) {
    final saved = _restoreAt;
    if (saved != null) {
      if (!_game.world.isLoaded(IVec3.floor(saved))) return false;
      position = saved.clone();
      velocity = Vector3.zero();
      _restoreAt = null;
      _placed = true;
      syncNode();
      return true;
    }
    if (!_game.world.isLoaded(IVec3(x, 0, z))) return false;
    position = Vector3(x + 0.5, _game.world.groundHeight(x, z) + 0.01, z + 0.5);
    spawnPoint = position.clone();
    velocity = Vector3.zero();
    _placed = true;
    syncNode();
    return true;
  }

  /// Adds [count] of [item] to the bag; returns what did not fit.
  int pickUp(String item, int count) {
    final left = inventory.add(item, count);
    if (left < count) _game.playSound('pickup', volumeDb: -8.0, pitch: 1.0 + _game.random.nextDouble() * 0.3);
    return left;
  }

  @override
  double takeDamage(Damage damage) {
    if (_dead || spec.creative || _invulnerable > 0.0) return 0.0;
    final taken = math.min(hp, damage.amount);
    hp -= damage.amount;
    _invulnerable = 0.4;
    hurtFlash = 1.0;
    _game.playSound('hurt', volumeDb: -3.0);
    final from = damage.from;
    if (from != null && damage.knockback > 0.0) {
      final push = position - from
        ..y = 0.0;
      if (push.length2 > 0) push.normalize();
      motor.shove(Vector3(push.x * damage.knockback, 5.0, push.z * damage.knockback));
    }
    if (hp <= 0.0) {
      hp = 0.0;
      _dead = true;
      _deadFor = 0.0;
      _game.playerDied();
    }
    return taken;
  }

  /// One step of [dt], reading [input] when [gameplay] (not in a menu).
  void tick(VoxelGame game, double dt, {required bool gameplay}) {
    final input = game.input;
    _invulnerable = math.max(_invulnerable - dt, 0.0);
    hurtFlash = math.max(hurtFlash - dt * 2.5, 0.0);
    if (_dead) {
      _deadFor += dt;
      if (_deadFor >= spec.respawnSeconds) _respawn();
      return;
    }
    if (!_game.world.isLoaded(IVec3.floor(position))) {
      velocity = Vector3.zero();
      return;
    }
    if (gameplay) {
      final look = input.takeLook(dt);
      yaw -= look.dx;
      pitch = (pitch - look.dy).clamp(-1.5, 1.5);
      final wheel = input.takeWheel();
      final hotbar = inventory.hotbarSize;
      if (wheel != 0) selectedSlot = (selectedSlot + wheel) % hotbar;
      if (selectedSlot < 0) selectedSlot += hotbar;
      final digit = input.digitPressed();
      if (digit >= 0 && digit < hotbar) selectedSlot = digit;
      if (input.justPressed(VoxelAction.toggleView)) {
        cameraMode = cameraMode == CameraMode.firstPerson ? CameraMode.thirdPerson : CameraMode.firstPerson;
      }
      if (input.justPressed(VoxelAction.drop)) _dropHeld();
      // The bag is not opened from here: `VoxelGame.step` is the one reader of
      // that button, so a press cannot open it and close it in one step.
    }
    _walk(dt, gameplay);
    _updateAim();
    _attackCooldown = math.max(_attackCooldown - dt, 0.0);
    _useCooldown = math.max(_useCooldown - dt, 0.0);
    if (gameplay && (input.down(VoxelAction.attack) || input.justPressed(VoxelAction.attack))) {
      _attack(dt, input.justPressed(VoxelAction.attack));
    } else {
      mineProgress = 0.0;
      _miningCell = null;
    }
    final usePressed = gameplay && input.justPressed(VoxelAction.use);
    if (usePressed || gameplay && input.down(VoxelAction.use) && _useCooldown <= 0.0) {
      _use();
      _useCooldown = usePressed ? 0.25 : 0.2;
    }
    syncNode();
    _animate(dt);
  }

  void _walk(double dt, bool gameplay) {
    final input = _game.input;
    final x = gameplay ? input.axis(VoxelAction.moveLeft, VoxelAction.moveRight, stick: _leftX) : 0.0;
    final y = gameplay
        ? input.axis(VoxelAction.moveForward, VoxelAction.moveBack, stick: _leftY, invertStick: true)
        : 0.0;
    var wish = flatForward * -y + right * x;
    if (wish.length > 1.0) wish = wish.normalized();
    final sneaking = gameplay && input.down(VoxelAction.sneak);
    final sprinting = gameplay && input.down(VoxelAction.sprint) && y < 0.0 && !motor.swimming;
    var speed = sprinting ? spec.sprintSpeed : (sneaking ? spec.sneakSpeed : spec.walkSpeed);
    if (motor.swimming) {
      speed = spec.swimSpeed;
    } else if (inLiquid) {
      speed *= 0.8;
    }
    final floor = _game.world.getBlockXYZ(position.x.floor(), (position.y - 0.05).floor(), position.z.floor());
    if (onFloor) speed *= _game.blocks[floor].speed;
    final events = motor.step(
      dt,
      wish: wish,
      speed: speed,
      jump: gameplay && input.down(VoxelAction.jump),
      sneak: sneaking,
      onLadder: _onLadder(),
    );
    // A step every 0.4 s on foot (0.3 running), sounding like the ground.
    final horizontal = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    if (onFloor && horizontal > 1.0) {
      _stepTimer -= dt;
      if (_stepTimer <= 0.0) {
        _stepTimer = sprinting ? 0.3 : 0.4;
        final under = _game.world.getBlockXYZ(position.x.floor(), (position.y - 0.05).floor(), position.z.floor());
        if (under != 0) _game.playSound('step_${_game.soundFamily(under)}', volumeDb: -8.0);
      }
    }
    if (inLiquid && !_wasInLiquid) _game.playSound('splash', volumeDb: -6.0);
    _wasInLiquid = inLiquid;
    if (spec.fallDamage && events.landedAfter > 4.0) {
      takeDamage(Damage(((events.landedAfter - 4.0) * 1.2).floorToDouble(), source: 'fall'));
    }
    _liquidHazards(dt);
  }

  static const _leftX = GamepadAxis.leftStickX, _leftY = GamepadAxis.leftStickY;

  bool _onLadder() {
    final w = _game.world;
    for (final dy in const [0.2, 1.0]) {
      final b = w.getBlockXYZ(position.x.floor(), (position.y + dy).floor(), position.z.floor());
      if (w.blocks[b].shape == BlockShape.ladder) return true;
    }
    return false;
  }

  void _liquidHazards(double dt) {
    final lava = _game.blocks.liquidKinds.indexOf('lava');
    if (lava >= 0 && (feetLiquid == lava || headLiquid == lava)) {
      _lavaTimer += dt;
      if (_lavaTimer > 0.4) {
        _lavaTimer = 0.0;
        takeDamage(const Damage(4.0, source: 'lava'));
      }
    }
    if (headInLiquid) {
      _drownTimer += dt;
      if (_drownTimer > 8.0) {
        takeDamage(const Damage(2.0, source: 'drowning'));
        _drownTimer = 6.5;
      }
    } else {
      _drownTimer = 0.0;
    }
  }

  void _updateAim() {
    final origin = eyePosition, dir = forward;
    final hit = VoxelRaycast.solid(_game.world, origin, dir, spec.reach);
    final clear = Reach.toBarrier(_game.world, origin, dir, spec.reach);
    final mob = Reach.nearestBody(
      _game.mobs,
      origin,
      dir,
      maxDist: spec.meleeReach,
      blockedAt: clear,
      accepts: (m) => !m.isDead,
    );
    final mobD = mob?.rayDistance(origin, dir) ?? double.infinity;
    final block = hit != null && hit.distance <= mobD;
    aimedBlock = block ? hit : null;
    aimedMob = block ? null : mob;
    final o = outline;
    if (o == null) return;
    if (block) {
      o.show(selectionBoxAt(_game.world, hit.block.x, hit.block.y, hit.block.z));
    } else if (mob != null) {
      final p = mob.position, w = mob.halfWidth;
      o.show(CollisionBox(p.x - w, p.y, p.z - w, p.x + w, p.y + mob.height, p.z + w));
    } else {
      o.hide();
    }
  }

  ItemType? get _heldType {
    final id = heldItem;
    return id.isEmpty || !_game.items.has(id) ? null : _game.items[id];
  }

  void _attack(double dt, bool pressed) {
    final mob = aimedMob;
    if (mob != null) {
      mineProgress = 0.0;
      if (_attackCooldown > 0.0) return;
      _attackCooldown = 0.45;
      _swingArm();
      final item = _heldType;
      final damage = item == null || item.tool == null ? spec.handDamage : item.damage.toDouble();
      mob.takeDamage(Damage(damage, from: position, knockback: 6.0, attacker: this));
      if (item != null && item.durability > 0) inventory.wear(selectedSlot);
      return;
    }
    final hit = aimedBlock;
    if (hit == null) {
      mineProgress = 0.0;
      if (pressed) {
        _swingArm();
        _game.playSound('swing', volumeDb: -10.0);
      }
      return;
    }
    if (_miningCell != hit.block) {
      _miningCell = hit.block;
      mineProgress = 0.0;
    }
    final block = _game.world.getBlock(hit.block);
    final type = _game.blocks[block];
    final time = spec.creative ? (type.hardness < 0 ? -1.0 : 0.0) : _game.mining.mineTime(type, _heldType);
    if (time < 0.0) return;
    if (pressed) _swingArm();
    _digTimer -= dt;
    if (_digTimer <= 0.0) {
      _digTimer = 0.25;
      _swingArm();
      _game.playSound('dig', at: Vector3(hit.block.x + 0.5, hit.block.y + 0.5, hit.block.z + 0.5), volumeDb: -10.0);
    }
    mineProgress += time == 0.0 ? 1.0 : dt / time;
    if (mineProgress < 1.0) return;
    mineProgress = 0.0;
    _miningCell = null;
    _game.breakBlock(hit.block, dropFor: spec.creative ? null : _heldType, byPlayer: true);
    if (!spec.creative) {
      final item = _heldType;
      if (item != null && item.durability > 0) inventory.wear(selectedSlot);
    }
    if (spec.creative) _attackCooldown = 0.2;
  }

  void _use() {
    final hit = aimedBlock;
    // A lever or a button is used, not built against.
    final net = _game.signals;
    if (hit != null && net != null && !_game.input.down(VoxelAction.sneak) && net.use(hit.block)) {
      _swingArm();
      _game.playSound('click', at: Vector3(hit.block.x + 0.5, hit.block.y + 0.5, hit.block.z + 0.5), volumeDb: -4.0);
      return;
    }
    // A station opens its crafting instead of taking a block against it.
    if (hit != null) {
      final aimed = _game.world.blockNameAt(hit.block);
      if (_game.stations.contains(aimed) && !_game.input.down(VoxelAction.sneak)) {
        _game.openScreen.value = aimed;
        return;
      }
    }
    final item = _heldType;
    if (hit == null || item == null || item.block == null) return;
    final cell = hit.block + hit.normal;
    final world = _game.world;
    if (!world.isLoaded(cell) || !world.blocks.isReplaceable(world.getBlock(cell))) return;
    final id = world.blocks.indexOf(item.block!);
    // Never into a body: the player's own, or a creature's.
    if (world.blocks[id].solid && _bodiesIn(cell)) return;
    if (!world.setBlock(cell, id)) return;
    _swingArm();
    _game.playSound(
      'place_${_game.soundFamily(id)}',
      at: Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5),
      volumeDb: -4.0,
    );
    if (!spec.creative) inventory.remove(item.id, 1);
    _game.spec.onBlockPlaced?.call(_game, item.block!, cell);
  }

  void _swingArm() {
    rig?.swing();
    _game.firstPerson?.swing();
  }

  bool _bodiesIn(IVec3 cell) {
    bool overlaps(VoxelBody b) =>
        b.position.x + b.halfWidth > cell.x &&
        b.position.x - b.halfWidth < cell.x + 1 &&
        b.position.z + b.halfWidth > cell.z &&
        b.position.z - b.halfWidth < cell.z + 1 &&
        b.position.y + b.height > cell.y &&
        b.position.y < cell.y + 1;
    return overlaps(this) || _game.mobs.any((m) => !m.isDead && overlaps(m));
  }

  void _dropHeld() {
    final id = heldItem;
    if (id.isEmpty) return;
    inventory.remove(id, 1);
    _game.dropItem(id, 1, eyePosition - Vector3(0, 0.3, 0), throwVelocity: forward * 5.0 + Vector3(0, 2, 0));
  }

  void _respawn() {
    _dead = false;
    hp = spec.hp;
    position = spawnPoint.clone();
    velocity = Vector3.zero();
    syncNode();
  }

  void _animate(double dt) {
    final r = rig;
    if (r == null) return;
    r.root.visible = cameraMode == CameraMode.thirdPerson;
    final speed = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    final flat = Vector3(velocity.x, 0, velocity.z);
    final face = speed > 0.5 ? math.atan2(-flat.x, -flat.z) : yaw;
    r.animate(dt, speed: speed, targetYaw: face, onFloor: onFloor);
    r.place(Vector3.zero());
  }
}
