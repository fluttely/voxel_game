import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:gamepads/gamepads.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/game_event.dart';
import '../core/voxel_game.dart';
import '../entities/target.dart';
import '../input/input_map.dart';
import '../input/voxel_action.dart';
import '../mobs/mob.dart';
import '../mobs/mob_spec.dart';
import '../mobs/rig.dart';
import '../ui/game_screen.dart';
import '../camera/first_person_view.dart';
import '../fishing/angler.dart';
import '../fishing/bobber.dart';
import '../fishing/fishing_spec.dart';
import '../vehicles/minecart.dart';
import '../vehicles/rideable.dart';
import '../vehicles/vehicle.dart';
import '../vehicles/vehicle_spec.dart';
import 'character_motor.dart';
import 'player_spec.dart';

/// The player: a body driven by [VoxelAction]s that looks, walks, swims,
/// climbs ladders, mines and places blocks, hits creatures, tames and rides
/// them (a use with what tames one in hand; sneak to get off), puts vehicles
/// down, rides them and breaks them (`VoxelGameSpec.vehicles`), picks items
/// up, takes falls, burns in lava, drowns, dies and stands up again at the
/// spawn.
///
/// It survives by what its [spec] declares: it gets hungry and eats
/// ([PlayerSpec.hunger], `ItemType.food`), wears armour (`ItemType.armor`),
/// carries status effects ([effects]) and gains experience ([PlayerSpec.xp]).
/// The effects bend four stats by name: [speedStat], [damageStat],
/// [miningStat] (multipliers) and [armorStat] (points added).
class PlayerEntity extends NodeBody implements Target, Angler {
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

  /// The stack in hand while the bag's screen is open: picked out of a slot
  /// ([clickSlot]) and not yet put down; null when the hand is empty. A
  /// networked game reaches it too: a store edit the host refuses takes back
  /// what it gave the hand and returns what it took.
  ItemStack? carried;

  /// A click on slot [i] of [inv] (the bag or an open store): an empty hand
  /// picks the slot's stack up, or half of it when [one]; a full one puts
  /// it down (one of it when [one]), tops up a stack of the same item, or
  /// swaps with a different one.
  void clickSlot(Inventory inv, int i, {required bool one}) {
    final slot = inv.slots[i];
    final held = carried;
    if (held == null) {
      if (slot != null) carried = inv.takeFromSlot(i, one ? (slot.count + 1) ~/ 2 : slot.count);
      return;
    }
    if (slot == null) {
      final put = one ? 1 : held.count;
      inv.setSlot(i, held.copy()..count = put);
      held.count -= put;
      if (held.count <= 0) carried = null;
      return;
    }
    if (slot.id == held.id && slot.bonus == held.bonus && slot.dur < 0 && held.dur < 0) {
      final room = inv.stackSize(slot.id) - slot.count;
      final put = (one ? 1 : held.count).clamp(0, room);
      slot.count += put;
      held.count -= put;
      if (held.count <= 0) carried = null;
      inv.emitChanged();
      return;
    }
    inv.setSlot(i, held);
    carried = slot;
  }

  /// Throws the stack in hand, or one of it when [one], into the world.
  void throwCarried({required bool one}) {
    final held = carried;
    if (held == null) return;
    final out = held.copy()..count = one ? 1 : held.count;
    held.count -= out.count;
    if (held.count <= 0) carried = null;
    throwStack(out);
  }

  /// Puts the stack in hand back into the bag as the screen shuts, and
  /// throws what does not fit: nothing in hand is lost.
  void stowCarried() {
    final held = carried;
    if (held == null) return;
    carried = null;
    final left = inventory.put(held);
    if (left > 0) throwStack(held..count = left);
  }

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

  /// The creature under the crosshair (nearer than any block or vehicle), or
  /// null.
  Mob? aimedMob;

  /// The vehicle under the crosshair (nearer than any block or creature), or
  /// null; never the one ridden.
  Vehicle? aimedVehicle;

  /// What the player rides, a mount or a vehicle, or null: it moves by the
  /// player's input, and sneak gets off ([dismount]).
  Rideable? riding;

  /// Whether the player flies (creative only): no gravity and no fall, jump
  /// rises and sneak sinks. A press of `VoxelAction.fly` flips it; riding,
  /// dying and a world that is not creative end it. Throws when set on while
  /// the player is not creative, dead or riding.
  bool get flying => _flying;
  bool _flying = false;
  set flying(bool on) {
    if (on && !spec.creative) throw StateError('only a creative player flies');
    if (on && (_dead || riding != null)) throw StateError('the dead and the riding do not fly');
    _flying = on;
  }

  /// Whether the player glided this step: glide held in the air with a
  /// [glider] in the bag.
  bool get gliding => motor.gliding;

  /// What the player glides with: the first item in the bag that glides
  /// (`ItemType.glider`), or null for none.
  Glider? get glider {
    for (final s in inventory.slots) {
      if (s == null) continue;
      if (_game.items[s.id].glider case final g?) return g;
    }
    return null;
  }

  /// The float of the line the player has out (`VoxelGameSpec.fishing`), or
  /// null. It is reeled in when the rod leaves the hand, when the player is
  /// twice the cast's reach from it, and when the player dies.
  Bobber? get bobber => _bobber;
  Bobber? _bobber;

  /// 0..1 how far the aimed block is mined.
  double mineProgress = 0.0;

  /// The model (third person); null headless.
  RigInstance? rig;

  /// The outline around what the crosshair rests on; null headless.
  SelectionOutline? outline;

  /// 1 the moment the player is hurt, fading to 0: the HUD's red flash.
  double hurtFlash = 0.0;

  /// Seconds a blow shakes the camera for.
  static const double shakeSeconds = 0.15;

  /// Metres the camera shakes by now, either way across the view: a blow's
  /// damage over 10, at most 0.3, dying out over [shakeSeconds]. A hurt from
  /// within (an effect's tick, hunger) does not shake it. The aim never moves.
  double get shake => _shakeAmp * (_shakeLeft / shakeSeconds);
  double _shakeLeft = 0.0;
  double _shakeAmp = 0.0;

  /// Whether the model's pose holds now (third person): a blow's hit-stop,
  /// `Mob.hitStop`.
  bool get frozen => _freeze > 0.0;
  double _freeze = 0.0;

  /// Whether the model shows white now: a blow's `Mob.hitFlash`.
  bool get flashing => _flash > 0.0;
  double _flash = 0.0;

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

  /// Takes the player off the ground to wait at [at] while a world loads
  /// around it (a trip to another dimension): [placed] is false, so it
  /// neither steps nor turns, until [placeAt].
  void hold(Vector3 at) {
    position = at.clone();
    velocity = Vector3.zero();
    _restoreAt = null;
    _placed = false;
    syncNode(snap: true);
  }

  /// Stands the player at [at], at rest, a fall forgotten: the end of a
  /// [hold].
  void placeAt(Vector3 at) {
    position = at.clone();
    velocity = Vector3.zero();
    motor.resetFall();
    _placed = true;
    syncNode(snap: true);
  }

  /// Puts [stack] in the bag (`Inventory.put`: a fresh one tops up stacks, a
  /// worn or bonused one takes an empty slot whole), tells the player what
  /// went in (`VoxelGame.notices`) and raises an [ItemPickedUp] of it;
  /// returns how many did not fit.
  int pickUpStack(ItemStack stack) {
    final left = inventory.put(stack);
    if (left < stack.count) {
      _game.playSound('pickup', volumeDb: -8.0, pitch: 1.0 + _game.random.nextDouble() * 0.3);
      _game.notices.picked(stack.id, _game.items[stack.id].name, stack.count - left);
      _game.raise(ItemPickedUp(stack.id, stack.count - left));
    }
    return left;
  }

  /// Crafts [recipe] once from the bag (`RecipeBook.craft`) and raises an
  /// [ItemCrafted]; false (nothing changed) when an ingredient is missing.
  bool craft(Recipe recipe) {
    if (!_game.recipes.craft(recipe, inventory)) return false;
    _game.raise(ItemCrafted(recipe));
    return true;
  }

  /// [count] new [item] into the bag, as [pickUpStack].
  int pickUp(String item, int count) => pickUpStack(ItemStack(item, count));

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
    if (!damage.internal) {
      _invulnerable = 0.4;
      _shakeLeft = shakeSeconds;
      _shakeAmp = math.min(amount / 10.0, 0.3);
      _freeze = Mob.hitStop;
      _flash = Mob.hitFlash;
    }
    hurtFlash = 1.0;
    _game.playSound('hurt', volumeDb: -3.0);
    final from = damage.from;
    if (from != null && damage.knockback > 0.0) {
      final push = position - from
        ..y = 0.0;
      if (push.length2 > 0) push.normalize();
      motor.shove(Vector3(push.x * damage.knockback, 5.0, push.z * damage.knockback));
    }
    if (hp <= 0.0) kill(by: damage);
    return taken;
  }

  /// Kills the player where it stands, whatever it wears or is: what a blow
  /// that takes the last of its health does ([by] it), and a save that left
  /// it dead.
  void kill({Damage? by}) {
    if (_dead) throw StateError('the player is already dead');
    if (riding != null) dismount();
    if (_bobber != null) _reelIn();
    hp = 0.0;
    _dead = true;
    _flying = false;
    _deadFor = 0.0;
    _game.playerDied(by);
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
    _shakeLeft = math.max(_shakeLeft - dt, 0.0);
    _freeze = math.max(_freeze - dt, 0.0);
    _flash = math.max(_flash - dt, 0.0);
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
      if (input.justPressed(VoxelAction.fly) && spec.creative && riding == null) flying = !_flying;
      // The bag is not opened from here: `VoxelGame.step` is the one reader of
      // that button, so a press cannot open it and close it in one step.
    }
    if (riding?.gone ?? false) dismount();
    if (riding != null) {
      _ride(dt, gameplay);
    } else {
      _walk(dt, gameplay);
    }
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
    _tendLine();
    _animate(dt);
    syncNode(yaw: rig?.yaw);
  }

  /// The move's two axes, right and back positive; nothing out of gameplay.
  (double, double) _moveAxes(bool gameplay) {
    if (!gameplay) return (0.0, 0.0);
    final input = _game.input;
    return (
      input.axis(VoxelAction.moveLeft, VoxelAction.moveRight, stick: _leftX, touch: TouchAxis.x),
      input.axis(VoxelAction.moveForward, VoxelAction.moveBack, stick: _leftY, invertStick: true, touch: TouchAxis.y),
    );
  }

  void _walk(double dt, bool gameplay) {
    final input = _game.input;
    final (x, y) = _moveAxes(gameplay);
    var wish = flatForward * -y + right * x;
    if (wish.length > 1.0) wish = wish.normalized();
    final sneaking = gameplay && input.down(VoxelAction.sneak);
    final sprinting = gameplay && input.down(VoxelAction.sprint) && y < 0.0 && !motor.swimming;
    if (_flying) {
      final run = sprinting ? spec.sprintSpeed / spec.walkSpeed : 1.0;
      motor.fly(
        dt,
        wish: wish,
        speed: spec.flySpeed * run * effects.multiplier(speedStat),
        rise: gameplay && input.down(VoxelAction.jump),
        sink: sneaking,
      );
      return;
    }
    var speed = sprinting ? spec.sprintSpeed : (sneaking ? spec.sneakSpeed : spec.walkSpeed);
    if (motor.swimming) {
      speed = spec.swimSpeed;
    } else if (inLiquid) {
      speed *= 0.8;
    }
    speed *= effects.multiplier(speedStat);
    final floor = _game.world.getBlockXYZ(position.x.floor(), (position.y - 0.05).floor(), position.z.floor());
    if (onFloor) speed *= _game.blocks[floor].speed;
    // A glide sails toward the look, steered by the move, whatever the walk was.
    final glide = gameplay && input.down(VoxelAction.glide) && motor.canGlide ? glider : null;
    if (glide != null) {
      if (wish.length2 < 0.01) wish = flatForward;
      speed = glide.speed;
    }
    final events = motor.step(
      dt,
      wish: wish,
      speed: speed,
      jump: gameplay && input.down(VoxelAction.jump),
      sneak: sneaking,
      onLadder: _onLadder(),
      glide: glide != null,
      glideFall: glide?.fall,
      accel: glide?.steer,
    );
    // A step every 0.4 s on foot (0.3 running), sounding like the ground.
    final horizontal = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    if (onFloor && horizontal > 1.0) {
      _stepTimer -= dt;
      if (_stepTimer <= 0.0) {
        _stepTimer = sprinting ? 0.3 : 0.4;
        final under = _game.world.getBlockXYZ(position.x.floor(), (position.y - 0.05).floor(), position.z.floor());
        if (under != 0) _game.playSound(_game.stepSound(under), volumeDb: -8.0);
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

  /// One step in the saddle or the seat: the move goes to what is ridden
  /// ([Rideable.carry]: the move along the ground, its two axes, sprint and
  /// jump), and the player sits on its seat; a press of sneak gets off.
  void _ride(double dt, bool gameplay) {
    final seat = riding!;
    final input = _game.input;
    if (gameplay && input.justPressed(VoxelAction.sneak)) {
      dismount();
      return;
    }
    final (x, y) = _moveAxes(gameplay);
    var wish = flatForward * -y + right * x;
    if (wish.length > 1.0) wish = wish.normalized();
    seat.carry(dt, (
      wish: wish,
      forward: -y,
      turn: x,
      sprint: gameplay && input.down(VoxelAction.sprint) && y < 0.0,
      jump: gameplay && input.down(VoxelAction.jump),
    ));
    position = seat.seat();
    velocity = seat.velocity.clone();
    motor.resetFall();
  }

  /// Gets on [seat]: one that [Rideable.takes] the player (their own tamed
  /// mount, a vehicle nobody rides), while they ride nothing. Throws
  /// otherwise.
  void ride(Rideable seat) {
    if (riding != null) throw StateError('one rider, one seat: the player rides already');
    if (!seat.takes(this)) throw StateError('the ${seat.name.toLowerCase()} does not take the player');
    riding = seat;
    seat.rider = this;
    _flying = false;
    mineProgress = 0.0;
    _miningCell = null;
    position = seat.seat();
    velocity = Vector3.zero();
    _game.notify('Riding the ${seat.name.toLowerCase()}: sneak to get off');
  }

  /// Gets off what is ridden: beside it, on its right, where that is clear,
  /// else where it stands.
  void dismount() {
    final seat = riding;
    if (seat == null) throw StateError('the player rides nothing');
    riding = null;
    seat.rider = null;
    final side = seat.position + right * (seat.halfWidth + halfWidth + 0.2);
    final cell = IVec3.floor(side + Vector3(0, 0.1, 0));
    final w = _game.world;
    position = !w.isSolid(cell) && !w.isSolid(cell + IVec3.up) ? side : seat.position.clone();
    velocity = Vector3.zero();
    motor.resetFall();
  }

  /// Whether a use on [mob] does something: the item in hand tames it, or it
  /// is the player's own mount, no one rides it and the player rides nothing
  /// ([Mob.takes]). On a client the host's creatures are tamed by asking the
  /// host, and its own pet's replica is ridden at once.
  bool usableOn(Mob mob) {
    if (mob.isDead) return false;
    if (!mob.tamed) return mob.spec.tameWith.contains(heldItem);
    return riding == null && mob.takes(this);
  }

  /// Uses the item in hand on [mob] ([usableOn]): one of what tames it,
  /// which may take (`MobSpec.tameChance`), or a ride. A replica's taming is
  /// the host's roll (`GameSession.tameMob`), the item spent here.
  void _useOn(Mob mob) {
    _swingArm();
    if (mob.tamed) {
      ride(mob);
      _game.raise(Mounted(mob));
      return;
    }
    final item = heldItem;
    final paid = spec.creative ? null : inventory.takeFromSlot(selectedSlot, 1);
    if (mob.replica) {
      _game.session!.tameMob(mob, item, paid: paid);
      return;
    }
    final took = _game.random.nextDouble() < mob.spec.tameChance;
    if (took) mob.tame(this);
    tamingTried(mob.spec, took: took);
  }

  /// Says whether the taming of a [spec] creature [took]: here, or on the
  /// host for a client.
  void tamingTried(MobSpec spec, {required bool took}) {
    if (took) _game.raise(Tamed(spec));
    final name = spec.name.toLowerCase();
    _game.notify(took ? 'The $name is tamed' : 'The $name is not won over yet');
  }

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
      _game.raise(LevelGained(level));
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
    _game.raise(FoodEaten(item.id));
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
        _game.dropStack(before, eyePosition - Vector3(0, 0.3, 0));
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
      accepts: (m) => !m.isDead && !identical(m, riding),
    );
    final vehicle = Reach.nearestBody(
      _game.vehicles,
      origin,
      dir,
      maxDist: spec.meleeReach,
      blockedAt: clear,
      accepts: (v) => !v.gone && !identical(v, riding),
    );
    final mobD = mob?.rayDistance(origin, dir) ?? double.infinity;
    final vehicleD = vehicle?.rayDistance(origin, dir) ?? double.infinity;
    final block = hit != null && hit.distance <= math.min(mobD, vehicleD);
    aimedBlock = block ? hit : null;
    aimedMob = !block && mobD <= vehicleD ? mob : null;
    aimedVehicle = !block && mobD > vehicleD ? vehicle : null;
    // A finger's tap swings at a creature in reach and uses anything else (a
    // vehicle is boarded), as a mouse's two buttons would.
    _game.input.touchTapPrimary = aimedMob != null && !usableOn(aimedMob!);
    final o = outline;
    if (o == null) return;
    if (block) {
      o.show(selectionBoxAt(_game.world, hit.block.x, hit.block.y, hit.block.z));
    } else if (aimedMob == null && aimedVehicle == null) {
      o.hide();
    }
  }

  /// Puts the outline around the aimed creature or vehicle where it is drawn
  /// this frame; a block's is set by the step, where blocks change.
  void drawOutline() {
    final o = outline, body = aimedMob ?? aimedVehicle;
    if (o == null || body == null) return;
    final p = body.drawnPosition, w = body.halfWidth;
    o.show(CollisionBox(p.x - w, p.y, p.z - w, p.x + w, p.y + body.height, p.z + w));
  }

  ItemType? get _heldType {
    final id = heldItem;
    return id.isEmpty || !_game.items.has(id) ? null : _game.items[id];
  }

  /// [damage] of a blow of the player's, rolled for a critical one
  /// ([PlayerSpec.critChance]): [PlayerSpec.critMultiplier] times it, rounded.
  /// With no chance declared nothing is rolled.
  ({double amount, bool crit}) critical(double damage) {
    final chance = spec.critChance;
    if (chance <= 0.0 || _game.random.nextDouble() >= chance) return (amount: damage, crit: false);
    return (amount: (damage * spec.critMultiplier).roundToDouble(), crit: true);
  }

  void _attack(double dt, bool pressed) {
    final vehicle = aimedVehicle;
    if (vehicle != null) {
      mineProgress = 0.0;
      if (_attackCooldown > 0.0) return;
      _attackCooldown = 0.4;
      _swingArm();
      // One swing breaks one nobody rides; the host breaks its own.
      if (vehicle.rider == null) {
        if (vehicle.replica) {
          _game.session!.breakVehicle(vehicle, drop: !spec.creative);
        } else {
          vehicle.breakApart(drop: !spec.creative);
        }
      }
      return;
    }
    final mob = aimedMob;
    if (mob != null) {
      mineProgress = 0.0;
      if (_attackCooldown > 0.0) return;
      _attackCooldown = 0.45;
      _swingArm();
      final item = _heldType;
      final base = item == null || item.tool == null ? spec.handDamage : item.damage.toDouble();
      final (:amount, :crit) = critical(base * effects.multiplier(damageStat));
      mob.takeDamage(Damage(amount, from: position, knockback: 6.0, attacker: this, crit: crit));
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
      _game.chip(hit.block, block, count: 2, speed: 0.7);
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

  /// Uses the creature under the crosshair when the item in hand tames it
  /// or it is the player's mount to ride ([usableOn]), or rides the vehicle
  /// under it when it takes the player ([Vehicle.takes]; a replica once the
  /// host says so, `GameSession.boardVehicle`); else a lever, a store,
  /// a station or a block that turns (a door) under the crosshair, else lights a portal's frame with its lighter in hand
  /// (`PortalSpec.lighter`), scoops or pours with the bucket in hand, works the aimed
  /// block with the tool in hand (`BlockType.turnsWith`), eats or puts on the
  /// item in hand, puts down the vehicle it is ([_placeVehicle]), else places
  /// its block. What turns, fills, pours, is worked, eaten, put on or put down
  /// is used on a [pressed] only: holding the button does not flap a door or
  /// eat a stack.
  void _use({required bool pressed}) {
    final mob = aimedMob;
    if (mob != null && usableOn(mob)) {
      if (pressed) _useOn(mob);
      return;
    }
    final vehicle = aimedVehicle;
    if (vehicle != null && riding == null && vehicle.takes(this)) {
      if (pressed) {
        _swingArm();
        if (vehicle.replica) {
          _game.session!.boardVehicle(vehicle);
        } else {
          ride(vehicle);
          _game.raise(Boarded(vehicle));
        }
      }
      return;
    }
    final hit = aimedBlock;
    // A lever or a button is used, not built against.
    if (hit != null && !_game.input.down(VoxelAction.sneak) && _game.useSignal(hit.block)) {
      _swingArm();
      _game.playSound('click', at: Vector3(hit.block.x + 0.5, hit.block.y + 0.5, hit.block.z + 0.5), volumeDb: -4.0);
      return;
    }
    // A station opens its crafting instead of taking a block against it.
    if (hit != null) {
      final aimed = _game.world.blockNameAt(hit.block);
      final sneaking = _game.input.down(VoxelAction.sneak);
      // A store opens beside the bag; a client away from the host has none
      // to open (the host keeps them, and steps only its own dimension), so
      // it builds against it.
      if (_game.world.blocks[_game.world.getBlock(hit.block)].storage != null && !sneaking && _game.storesHere) {
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
    // A portal's lighter lights the frame whose hollow is in front of the aimed face.
    if (_game.portals.lights(item.id)) {
      if (!pressed || hit == null || !_game.portals.lightWith(item.id, hit.block + hit.normal)) return;
      _swingArm();
      _game.playSound('click', at: Vector3(hit.block.x + 0.5, hit.block.y + 0.5, hit.block.z + 0.5), volumeDb: -4.0);
      if (!spec.creative && item.durability > 0) inventory.wear(selectedSlot);
      return;
    }
    final fishing = _game.spec.fishing;
    if (fishing != null && item.id == fishing.rod) {
      if (pressed) _fish(fishing);
      return;
    }
    final vehicleSpec = _game.vehicleFor(item.id);
    if (vehicleSpec != null) {
      if (pressed) _placeVehicle(vehicleSpec);
      return;
    }
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
    _game.raise(BlockPlaced(world.blocks.idOf(id), cell));
  }

  /// Puts a vehicle of [vehicle] down where its kind goes along the aim (a
  /// boat on water, a minecart on a rail), pointing the way the player looks, one of its item used up (not in
  /// creative); tells the player where it goes when there is no such place.
  /// A client's goes to the host (`VoxelGame.placeVehicle`).
  void _placeVehicle(VehicleSpec vehicle) {
    final at = switch (vehicle) {
      BoatSpec() => _boatPlace(),
      CartSpec() => _cartPlace(),
    };
    if (at == null) {
      _game.notify(switch (vehicle) {
        BoatSpec() => 'A ${vehicle.name.toLowerCase()} goes on water',
        CartSpec() => 'A ${vehicle.name.toLowerCase()} goes on rails',
      });
      return;
    }
    _swingArm();
    _game.placeVehicle(vehicle.item, at, facing: yaw);
    _game.playSound('place_${vehicle.sound}', at: at, volumeDb: -4.0);
    if (!spec.creative) inventory.takeFromSlot(selectedSlot, 1);
  }

  /// Where a boat goes: on the surface of the first liquid along the aim
  /// within reach (the bucket's ray), at the top of its column, with room
  /// over it; null when there is none.
  Vector3? _boatPlace() {
    final world = _game.world;
    final found = VoxelRaycast.liquid(world, eyePosition, forward, spec.reach);
    if (found == null) return null;
    var top = found;
    while (world.table.isLiquid(world.getBlock(top + IVec3.up))) {
      top = top + IVec3.up;
    }
    if (world.isSolid(top + IVec3.up)) return null;
    return Vector3(top.x + 0.5, top.y + 0.9, top.z + 0.5);
  }

  /// Where a minecart goes: on the rail under the crosshair, its feet on the
  /// bars; null when no rail is aimed at.
  Vector3? _cartPlace() {
    final c = aimedBlock?.block;
    if (c == null || !_game.rails.isRail(_game.world.getBlock(c))) return null;
    return Vector3(c.x + 0.5, c.y + Minecart.railTop, c.z + 0.5);
  }

  /// A use with the rod: a line out is landed when something bites and
  /// reeled in empty when nothing does; else one is cast at the first liquid
  /// of [fishing]'s along the aim within its reach, or the player is told
  /// where it goes.
  void _fish(FishingSpec fishing) {
    final b = _bobber;
    if (b != null) {
      if (b.biting) {
        _land(fishing, b);
      } else {
        _reelIn();
        _game.notify('Reeled in');
      }
      return;
    }
    final at = _castPlace(fishing);
    if (at == null) {
      _game.notify('Cast at ${fishing.liquids.join(' or ')}');
      return;
    }
    _swingArm();
    _game.playSound('swing', volumeDb: -12.0, pitch: 1.3);
    _bobber = _game.add(Bobber(fishing, this, _handAt(position, eyePosition), at));
  }

  /// Where a float lands: on the surface of the first liquid along the aim
  /// within [fishing]'s reach, at the top of its column, when it is one of
  /// [fishing]'s liquids; null otherwise.
  Vector3? _castPlace(FishingSpec fishing) {
    final world = _game.world;
    final found = VoxelRaycast.liquid(world, eyePosition, forward, fishing.reach);
    if (found == null || !fishing.liquids.contains(world.blocks.liquidOf(world.getBlock(found)))) return null;
    var top = found;
    while (world.table.isLiquid(world.getBlock(top + IVec3.up))) {
      top = top + IVec3.up;
    }
    return Vector3(top.x + 0.5, top.y + 0.85, top.z + 0.5);
  }

  /// Lands what bit [b]: one roll of the catches into the bag (what does not
  /// fit on the ground), the experience, and the line in.
  void _land(FishingSpec fishing, Bobber b) {
    final caught = fishing.catches.roll(_game.random);
    for (final s in caught) {
      final left = pickUp(s.id, s.count);
      if (left > 0) _game.dropItem(s.id, left, centre());
    }
    if (caught.isEmpty) _game.notify('Nothing on the line');
    _game.raise(Caught([for (final s in caught) ItemStack(s.id, s.count)]));
    _game.playSound('splash', at: b.position, volumeDb: -6.0, pitch: 1.2);
    _swingArm();
    if (fishing.xp > 0) gainXp(fishing.xp);
    _reelIn();
  }

  void _reelIn() {
    _bobber!.removed = true;
    _bobber = null;
  }

  /// Reels the line in once the rod is out of the hand or the player is twice
  /// the reach from it; forgets one the world took away (a trip).
  void _tendLine() {
    final b = _bobber;
    if (b == null) return;
    if (b.removed) {
      _bobber = null;
    } else if (heldItem != b.spec.rod || b.position.distanceTo(position) > b.spec.reach * 2.0) {
      _reelIn();
    }
  }

  /// Where the hand that holds the item is drawn this frame, near enough for
  /// a line to hang from: the fist in front of the eye in first person
  /// (`FirstPersonView`), at the body's right in third.
  @override
  Vector3 get drawnHand => _handAt(drawnPosition, drawnEye);

  Vector3 _handAt(Vector3 feet, Vector3 eye) {
    final r = right;
    if (cameraMode == CameraMode.firstPerson) {
      final f = forward;
      return eye + r * 0.44 - r.cross(f).normalized() * 0.38 + f * FirstPersonView.reach;
    }
    final sunk = riding == null ? 0.0 : rig?.seatDrop ?? 0.0;
    return feet + Vector3(0, height * 0.55 - sunk, 0) + r * 0.35 + flatForward * 0.3;
  }

  void _swingArm() {
    rig?.swing();
    _game.firstPerson?.swing();
  }

  void _dropHeld() {
    final one = inventory.takeFromSlot(selectedSlot, 1);
    if (one != null) throwStack(one);
  }

  /// Throws [stack] out ahead, the way a press of drop throws one of the
  /// held stack; the bag throws what is let go outside it the same way.
  void throwStack(ItemStack stack) =>
      _game.dropStack(stack, eyePosition - Vector3(0, 0.3, 0), throwVelocity: forward * 5.0 + Vector3(0, 2, 0));

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
    final id = heldItem;
    if (r.canHold) r.hold(id.isEmpty ? null : _game.itemModel(id));
    // Seated a humanoid sits, drawn lower, and faces the way the seat points.
    final seat = riding;
    final seated = seat != null;
    final speed = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    final flat = Vector3(velocity.x, 0, velocity.z);
    final face = seat != null
        ? seat.facing
        : speed > 0.5
        ? math.atan2(-flat.x, -flat.z)
        : yaw;
    // The hit-stop: the pose holds, the body still moves.
    if (!frozen) {
      r.animate(
        dt,
        speed: seated ? 0.0 : speed,
        targetYaw: face,
        onFloor: seated || onFloor || _flying,
        seated: seated,
        gliding: gliding,
      );
    }
    r.paint(flashing ? VoxelModelMesh.flash() : VoxelModelMesh.material());
    r.place(Vector3(0, seated ? -r.seatDrop : 0.0, 0));
  }
}
