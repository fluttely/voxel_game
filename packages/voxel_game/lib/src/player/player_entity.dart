import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:gamepads/gamepads.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../entities/target.dart';
import '../input/input_map.dart';
import '../input/voxel_action.dart';
import '../mobs/mob.dart';
import '../mobs/rig.dart';
import '../ui/game_screen.dart';
import 'character_motor.dart';
import 'player_spec.dart';

/// The player: a body driven by [VoxelAction]s that looks, walks, swims,
/// climbs ladders, mines and places blocks, hits creatures, picks items up,
/// takes falls, burns in lava, drowns, dies and stands up again at the spawn.
///
/// It survives by what its [spec] declares: it gets hungry and eats
/// ([PlayerSpec.hunger], `ItemType.food`), wears armour (`ItemType.armor`),
/// carries status effects ([effects]) and gains experience ([PlayerSpec.xp]).
/// The effects bend four stats by name: [speedStat], [damageStat],
/// [miningStat] (multipliers) and [armorStat] (points added).
class PlayerEntity extends NodeBody implements Target {
  /// A player of [spec] with [inventory] as its bag, carrying [effects].
  PlayerEntity(this.spec, this.inventory, this.effects)
    : hp = spec.hp,
      hunger = spec.hunger?.max ?? 0.0,
      cameraMode = spec.camera {
    halfWidth = spec.halfWidth;
    height = spec.height;
    motor = CharacterMotor(this, MotorTuning(jumpVelocity: spec.jumpVelocity));
  }

  /// What the player is.
  final PlayerSpec spec;

  /// The bag; the first `hotbarSize` slots are the hotbar.
  final Inventory inventory;

  /// The status effects on the player.
  final StatusEffects effects;

  /// The effects' stat that multiplies the speed on foot and swimming.
  static const speedStat = 'speed';

  /// The effects' stat that multiplies the damage of a hit.
  static const damageStat = 'damage';

  /// The effects' stat that multiplies how fast blocks are mined.
  static const miningStat = 'mining';

  /// The effects' stat that adds armour points.
  static const armorStat = 'armor';

  /// Health.
  double hp;

  /// The hunger bar, 0 (starving) to [HungerSpec.max]; 0 and unused without
  /// [PlayerSpec.hunger].
  double hunger;

  /// Experience points toward the next [level].
  int xp = 0;

  /// The experience level, from 0.
  int level = 0;

  /// The most health: [PlayerSpec.hp], raised by each [level].
  double get maxHp => spec.hp + level * (spec.xp?.hpPerLevel ?? 0.0);

  final Map<String, ItemStack> _worn = {};

  /// What is worn, by [PlayerSpec.armorSlots] slot.
  Map<String, ItemStack> get worn => Map.unmodifiable(_worn);

  /// Armour points: what is worn, plus what the effects add.
  double get armor {
    var points = effects.bonus(armorStat);
    for (final s in _worn.values) {
      points += _game.items[s.id].armor!.points;
    }
    return points;
  }

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
  double _bodyTimer = 0.0;
  bool _placed = false;
  late VoxelGame _game;

  @override
  bool get isDead => _dead;

  /// Seconds since the player died; 0 while alive.
  double get deadSeconds => _dead ? _deadFor : 0.0;

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

  /// The eye as this frame draws it: above the feet where the node stands,
  /// between the last two steps.
  Vector3 get drawnEye => drawnPosition + Vector3(0, spec.eyeHeight, 0);

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
      syncNode(snap: true);
      return true;
    }
    if (!_game.world.isLoaded(IVec3(x, 0, z))) return false;
    position = Vector3(x + 0.5, _game.world.groundHeight(x, z) + 0.01, z + 0.5);
    spawnPoint = position.clone();
    velocity = Vector3.zero();
    _placed = true;
    syncNode(snap: true);
    return true;
  }

  /// Adds [count] of [item] to the bag; returns what did not fit.
  int pickUp(String item, int count) {
    final left = inventory.add(item, count);
    if (left < count) _game.playSound('pickup', volumeDb: -8.0, pitch: 1.0 + _game.random.nextDouble() * 0.3);
    return left;
  }

  /// Takes [damage], less what [armor] turns aside: [PlayerSpec.armorPerPoint]
  /// a point, never below [PlayerSpec.armorFloor] of the blow. An internal
  /// hurt is neither turned aside nor stopped by the moment of grace a blow
  /// leaves.
  @override
  double takeDamage(Damage damage) {
    if (_dead || spec.creative) return 0.0;
    if (!damage.internal && _invulnerable > 0.0) return 0.0;
    final amount = damage.internal
        ? damage.amount
        : math.max(damage.amount - armor * spec.armorPerPoint, damage.amount * spec.armorFloor);
    final taken = math.min(hp, amount);
    hp -= amount;
    if (!damage.internal) _invulnerable = 0.4;
    hurtFlash = 1.0;
    _game.playSound('hurt', volumeDb: -3.0);
    final from = damage.from;
    if (from != null && damage.knockback > 0.0) {
      final push = position - from
        ..y = 0.0;
      if (push.length2 > 0) push.normalize();
      motor.shove(Vector3(push.x * damage.knockback, 5.0, push.z * damage.knockback));
    }
    if (hp <= 0.0) kill();
    return taken;
  }

  /// Kills the player where it stands, whatever it wears or is: what a blow
  /// that takes the last of its health does, and a save that left it dead.
  void kill() {
    if (_dead) throw StateError('the player is already dead');
    hp = 0.0;
    _dead = true;
    _deadFor = 0.0;
    _game.playerDied();
  }

  /// Turns the view by [look] radians (yaw right and pitch down positive):
  /// what `VoxelGame.frame` drains from the input once a frame, so the view
  /// turns at the display's rate. Dropped while dead or not yet placed.
  void look(Offset look) {
    if (_dead || !_placed) return;
    yaw -= look.dx;
    pitch = (pitch - look.dy).clamp(-1.5, 1.5);
  }

  /// One step of [dt], reading [input] when [gameplay] (not in a menu). The
  /// look is not read here: [look] takes it once a frame.
  void tick(VoxelGame game, double dt, {required bool gameplay}) {
    final input = game.input;
    _invulnerable = math.max(_invulnerable - dt, 0.0);
    hurtFlash = math.max(hurtFlash - dt * 2.5, 0.0);
    if (_dead) {
      _deadFor += dt;
      return;
    }
    _survive(dt);
    if (_dead) return;
    if (!_game.world.isLoaded(IVec3.floor(position))) {
      velocity = Vector3.zero();
      return;
    }
    if (gameplay) {
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
      _use(pressed: usePressed);
      _useCooldown = usePressed ? 0.25 : 0.2;
    }
    _animate(dt);
    syncNode(yaw: rig?.yaw);
  }

  void _walk(double dt, bool gameplay) {
    final input = _game.input;
    final x = gameplay
        ? input.axis(VoxelAction.moveLeft, VoxelAction.moveRight, stick: _leftX, touch: TouchAxis.x)
        : 0.0;
    final y = gameplay
        ? input.axis(
            VoxelAction.moveForward,
            VoxelAction.moveBack,
            stick: _leftY,
            invertStick: true,
            touch: TouchAxis.y,
          )
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
    speed *= effects.multiplier(speedStat);
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

  /// The body's clock: the effects tick, hunger empties, and a full bar heals
  /// while an empty one starves.
  void _survive(double dt) {
    for (final e in effects.tick(dt)) {
      if (e.damage > 0.0) takeDamage(Damage(e.damage, source: e.id, internal: true));
      if (e.heal > 0.0) hp = math.min(hp + e.heal, maxHp);
    }
    final h = spec.hunger;
    if (h == null || spec.creative) return;
    hunger = math.max(hunger - dt / h.secondsPerPoint, 0.0);
    final starving = hunger <= 0.0;
    final healing = !starving && hunger >= h.regenAbove && hp < maxHp;
    if (!starving && !healing) {
      _bodyTimer = 0.0;
      return;
    }
    _bodyTimer += dt;
    if (starving && _bodyTimer >= h.starveSeconds) {
      _bodyTimer = 0.0;
      takeDamage(Damage(h.starveDamage, source: 'starving', internal: true));
    } else if (healing && _bodyTimer >= h.regenSeconds) {
      _bodyTimer = 0.0;
      hp = math.min(hp + h.regenAmount, maxHp);
    }
  }

  /// Adds [amount] experience, levelling up while it is enough.
  void gainXp(int amount) {
    final curve = spec.xp;
    if (curve == null) throw StateError('the player gains experience only with PlayerSpec.xp declared');
    assert(amount >= 0);
    xp += amount;
    while (xp >= curve.toNext(level)) {
      xp -= curve.toNext(level);
      level++;
      hp += curve.hpPerLevel;
      _game.playSound('levelup', volumeDb: -4.0);
    }
  }

  /// Whether eating [item] now would do something: fill hunger that is not
  /// full, heal health that is not full, or start its effect.
  bool canEat(ItemType item) {
    final food = item.food;
    if (food == null) return false;
    if (food.effect != null) return true;
    if (food.heal > 0.0 && hp < maxHp) return true;
    final h = spec.hunger;
    return food.hunger > 0 && h != null && !spec.creative && hunger < h.max;
  }

  /// Eats one of the item in hand; false (nothing eaten) when it is not food
  /// or would do nothing ([canEat]).
  bool eatHeld() {
    final item = _heldType;
    if (item == null || !canEat(item)) return false;
    final food = item.food!;
    inventory.takeFromSlot(selectedSlot, 1);
    final h = spec.hunger;
    if (h != null) hunger = math.min(hunger + food.hunger, h.max);
    hp = math.min(hp + food.heal, maxHp);
    final effect = food.effect;
    if (effect != null) effects.apply(effect, food.seconds, food.power);
    final leaves = food.leaves;
    if (leaves != null) _keep(leaves, 1);
    _game.playSound('eat', volumeDb: -6.0);
    return true;
  }

  /// Puts on the armour in hand, taking off (into the hand) what was worn in
  /// its slot; false when the item in hand is not armour.
  bool wearHeld() {
    final item = _heldType;
    final piece = item?.armor;
    if (piece == null) return false;
    final stack = inventory.takeFromSlot(selectedSlot, 1)!;
    final before = _worn[piece.slot];
    _worn[piece.slot] = stack;
    if (before != null) {
      if (inventory.isEmptySlot(selectedSlot)) {
        inventory.setSlot(selectedSlot, before);
      } else if (!inventory.addStack(before)) {
        _game.dropItem(before.id, before.count, eyePosition - Vector3(0, 0.3, 0));
      }
    }
    _game.playSound('click', volumeDb: -4.0);
    return true;
  }

  /// Takes off what is worn in [slot] into the bag; false when nothing is
  /// worn there or the bag has no empty slot (it stays worn).
  bool takeOff(String slot) {
    final stack = _worn[slot];
    if (stack == null || !inventory.addStack(stack)) return false;
    _worn.remove(slot);
    return true;
  }

  /// Wears [stack] in [slot] with no item in hand: a save read back.
  void putOn(String slot, ItemStack stack) {
    final piece = _game.items[stack.id].armor;
    if (piece == null || piece.slot != slot) throw ArgumentError.value(stack.id, slot, 'not armour for this slot');
    _worn[slot] = stack.copy();
  }

  /// An empty [bucket] in hand scoops the first liquid source along the aim
  /// that it [Bucket.fills]; false when there is none in reach.
  bool _scoop(Bucket bucket) {
    final world = _game.world;
    final cell = VoxelRaycast.liquid(world, eyePosition, forward, spec.reach);
    if (cell == null) return false;
    final id = world.getBlock(cell);
    final full = bucket.fills[world.blocks.liquidOf(id)];
    if (full == null || !world.blocks[id].liquidSource) return false;
    if (!world.setBlock(cell, BlockRegistry.air)) return false;
    _swapHeld(full);
    _game.playSound('splash', at: Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5), volumeDb: -10.0);
    return true;
  }

  /// A full [bucket] in hand pours its liquid's source against the aimed
  /// block; false when that cell would not take it.
  bool _pour(Bucket bucket, RayHit? hit) {
    if (hit == null) return false;
    final world = _game.world;
    final cell = hit.block + hit.normal;
    if (!world.isLoaded(cell) || !world.blocks.isReplaceable(world.getBlock(cell))) return false;
    if (!world.setBlockNamed(cell, bucket.liquid!)) return false;
    _swapHeld(bucket.empties!);
    _game.playSound('splash', at: Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5), volumeDb: -10.0);
    return true;
  }

  /// One of the item in hand becomes one [into]: in the hand when it was the
  /// last, else in the bag.
  void _swapHeld(String into) {
    inventory.takeFromSlot(selectedSlot, 1);
    if (inventory.isEmptySlot(selectedSlot)) {
      inventory.setSlot(selectedSlot, ItemStack(into, 1));
    } else {
      _keep(into, 1);
    }
  }

  /// [count] of [item] into the bag, what does not fit on the ground.
  void _keep(String item, int count) {
    final left = inventory.add(item, count);
    if (left > 0) _game.dropItem(item, left, eyePosition - Vector3(0, 0.3, 0));
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
    // A finger's tap swings at a creature in reach and uses anything else, as
    // a mouse's two buttons would.
    _game.input.touchTapPrimary = aimedMob != null;
    final o = outline;
    if (o == null) return;
    if (block) {
      o.show(selectionBoxAt(_game.world, hit.block.x, hit.block.y, hit.block.z));
    } else if (mob == null) {
      o.hide();
    }
  }

  /// Puts the outline around the aimed creature where the creature is drawn
  /// this frame; a block's is set by the step, where blocks change.
  void drawOutline() {
    final o = outline, mob = aimedMob;
    if (o == null || mob == null) return;
    final p = mob.drawnPosition, w = mob.halfWidth;
    o.show(CollisionBox(p.x - w, p.y, p.z - w, p.x + w, p.y + mob.height, p.z + w));
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
      final base = item == null || item.tool == null ? spec.handDamage : item.damage.toDouble();
      final damage = base * effects.multiplier(damageStat);
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
    final time = spec.creative
        ? (type.hardness < 0 ? -1.0 : 0.0)
        : _game.mining.mineTime(type, _heldType) / effects.multiplier(miningStat);
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

  /// Uses a lever, a store, a station or a block that turns (a door) under
  /// the crosshair, else scoops or pours with the bucket in hand, works the aimed
  /// block with the tool in hand (`BlockType.turnsWith`), eats or puts on the
  /// item in hand, else places its block. What turns, fills, pours, is worked,
  /// eaten or put on is used on a [pressed] only: holding the button does not
  /// flap a door or eat a stack.
  void _use({required bool pressed}) {
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
      final sneaking = _game.input.down(VoxelAction.sneak);
      // A store opens beside the bag; a client has none to open (the host
      // keeps them, VA16), so it builds against it.
      if (_game.world.blocks[_game.world.getBlock(hit.block)].storage != null && !sneaking && _game.authority) {
        if (pressed) _game.openScreen(StorageScreen(hit.block));
        return;
      }
      if (_game.stations.contains(aimed) && !sneaking) {
        if (pressed) _game.openScreen(BagScreen(station: aimed));
        return;
      }
      // A door is opened, not built against, unless the player sneaks.
      if (_game.world.blocks[_game.world.getBlock(hit.block)].usedInto != null &&
          !_game.input.down(VoxelAction.sneak)) {
        if (pressed && _game.blockRules.use(hit.block)) _swingArm();
        return;
      }
    }
    final item = _heldType;
    if (item == null) return;
    final bucket = item.bucket;
    if (bucket != null) {
      if (pressed && (bucket.isFull ? _pour(bucket, hit) : _scoop(bucket))) _swingArm();
      return;
    }
    // A tool the aimed block turns with works it: a hoe tills.
    final tool = item.tool;
    final worked = hit == null || tool == null
        ? null
        : _game.world.blocks[_game.world.getBlock(hit.block)].turnsWith[tool];
    if (worked != null) {
      if (!pressed || !_game.world.setBlockNamed(hit!.block, worked)) return;
      _swingArm();
      _game.playSound('dig', at: Vector3(hit.block.x + 0.5, hit.block.y + 1.0, hit.block.z + 0.5), volumeDb: -8.0);
      if (!spec.creative && item.durability > 0) inventory.wear(selectedSlot);
      return;
    }
    if (item.food != null || item.armor != null) {
      if (!pressed) return;
      if (eatHeld() || wearHeld()) _swingArm();
      return;
    }
    if (hit == null || item.block == null) return;
    final cell = hit.block + hit.normal;
    final world = _game.world;
    if (!world.isLoaded(cell) || !world.blocks.isReplaceable(world.getBlock(cell))) return;
    var id = world.blocks.indexOf(item.block!);
    final wall = world.blocks[id].onWall;
    if (wall != null && hit.normal.y == 0) id = world.blocks.indexOf(wall);
    final facing = world.blocks[id].facing;
    if (facing != null) id = world.blocks.indexOf(facing.toward(flatForward.x, flatForward.z));
    final type = world.blocks[id];
    final cells = [cell, if (type.tall) cell + IVec3.up];
    // Never where it would not stand, nor into a body: the player's own, or a
    // creature's. A tall block needs the cell above as well.
    if (!_game.blockRules.stands(cell, id)) return;
    for (final c in cells.skip(1)) {
      if (!world.isLoaded(c) || !world.blocks.isReplaceable(world.getBlock(c))) return;
    }
    if (type.solid && cells.any(_game.bodyIn)) return;
    for (final c in cells) {
      if (!world.setBlock(c, id)) return;
    }
    _swingArm();
    _game.playSound(
      'place_${_game.soundFamily(id)}',
      at: Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5),
      volumeDb: -4.0,
    );
    if (!spec.creative) inventory.remove(item.id, 1);
    _game.spec.onBlockPlaced?.call(_game, world.blocks.idOf(id), cell);
  }

  void _swingArm() {
    rig?.swing();
    _game.firstPerson?.swing();
  }

  void _dropHeld() {
    final id = heldItem;
    if (id.isEmpty) return;
    inventory.remove(id, 1);
    _game.dropItem(id, 1, eyePosition - Vector3(0, 0.3, 0), throwVelocity: forward * 5.0 + Vector3(0, 2, 0));
  }

  /// Stands the dead player up at [spawnPoint], whole, fed and with no
  /// effects on it. `VoxelGame.respawn` calls it as the death screen closes.
  void respawn() {
    if (!_dead) throw StateError('only the dead stand up again');
    _dead = false;
    hp = maxHp;
    hunger = spec.hunger?.max ?? 0.0;
    effects.rows.clear();
    _bodyTimer = 0.0;
    position = spawnPoint.clone();
    velocity = Vector3.zero();
    // Put there, not fallen there: a spawn below where the player died is no fall.
    motor.resetFall();
    syncNode(snap: true);
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
