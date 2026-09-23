import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../core/blocks.dart';
import '../game/settings.dart';
import '../core/items.dart';
import 'package:voxel_engine/core.dart';
import '../entities/boat.dart';
import '../entities/minecart.dart';
import '../entities/bobber.dart';
import '../entities/mob.dart';
import '../entities/hand_view.dart';
import '../entities/player_model.dart';
import '../entities/target.dart';
import '../entities/scene_body.dart';
import '../game/achievements.dart';
import '../game/effects.dart';
import '../core/recipes.dart';
import '../game/game.dart';
import '../game/game_state.dart';
import '../game/tutorial.dart';

import '../game/input.dart';
import '../game/inventory.dart';
import '../game/net.dart';
import '../game/rails.dart';
import '../game/sfx.dart';
import '../game/talents.dart';
import 'package:voxel_game/voxel_game.dart' show CharacterMotor, MotorTuning, ShoulderOrbit, ViewBob;
import 'package:voxel_scene/voxel_scene.dart';
import '../world/voxel_world.dart';

class PlayerClass {
  const PlayerClass(this.name, this.hp, this.stamina, this.mana, this.shirtR, this.shirtG, this.shirtB, this.weapon,
      this.damageMult, this.ability, this.ability2, this.mana2);
  final String name;
  final double hp, stamina, mana;
  final double shirtR, shirtG, shirtB;
  final String weapon;
  final double damageMult;
  final String ability;

  /// Stage 23: the Q ability and its mana price (through `manaCost`).
  final String ability2;
  final double mana2;
  Vector3 get shirt => Vector3(shirtR, shirtG, shirtB);
}

/// The hero: third person orbit camera (V toggles first person), sweep body,
/// mine / place / attack, climb, swim, glide, sprint, stats and levelling.
class Player extends SceneBody implements Target {
  static const double walkSpeed = 4.6;
  static const double sprintSpeed = 7.6;
  static const double sneakSpeed = 2.0;
  static const double swimSpeed = 3.0;
  static const double jumpVelocity = 8.6;

  /// Fly mode (F5) moves this many times faster than walking.
  static const double flySpeedScale = 2.5;
  static const double climbSpeed = 3.2;
  static const double reach = 5.0;
  static const double meleeReach = 3.6;
  static const double eyeHeight = 1.62;

  /// Where the third-person eye sits when nothing is in the way: this far
  /// behind the head, over the right shoulder and a hand above it. Shoulder
  /// and rise ease in with the distance, so an eye pulled all the way in ends
  /// up on the head itself and never off to one side of it, inside whatever
  /// the head is standing against.
  static const double orbitDistance = 4.8;
  static const double orbitShoulder = 0.55;
  static const double orbitRise = 0.15;

  /// The body hides once the eye is nearer than this to the head.
  static const double modelHideDistance = 1.1;
  static const double mouseSensitivity = 0.0022;
  static double sensitivityScale = 1.0;
  static double baseFov = 72.0;

  static const Map<String, PlayerClass> classes = {
    'warrior': PlayerClass('Warrior', 30, 100, 20, 0.72, 0.22, 0.20, 'stone_sword', 1.25, 'Whirlwind', 'Shield Bash', 10.0),
    'ranger': PlayerClass('Ranger', 22, 120, 30, 0.20, 0.55, 0.28, 'bow', 1.0, 'Arrow Volley', 'Volley', 10.0),
    'mage': PlayerClass('Mage', 18, 80, 100, 0.35, 0.28, 0.75, 'staff', 1.0, 'Fire Nova', 'Frost Nova', 25.0),
    'rogue': PlayerClass('Rogue', 24, 140, 30, 0.25, 0.25, 0.30, 'dagger', 1.1, 'Shadow Dash', 'Smoke Bomb', 15.0),
  };

  final Inventory inventory = Inventory();
  int selectedSlot = 0;
  String playerClass = 'warrior';
  double hp = 30.0;
  double maxHp = 30.0;
  double stamina = 100.0;
  double maxStamina = 100.0;
  double mana = 50.0;
  double maxMana = 50.0;
  double hunger = 20.0;
  int xp = 0;
  int level = 1;
  int armor = 0;
  double abilityCooldown = 0.0;

  /// Stage 23: the Q ability.
  double ability2Cooldown = 0.0;
  bool firstPerson = false;
  @override
  bool isDead = false;
  bool gliding = false;
  bool climbing = false;
  Vector3 spawnPoint = Vector3.zero();
  Boat? riding;
  Mob? mount;
  Minecart? cart; // stage 28: the minecart the player sits in
  Bobber? bobber;
  double sleeping = 0.0;
  final StatusEffects effects = StatusEffects();
  int talentPoints = 0;
  final Map<String, int> talents = {};
  double _invulnerable = 0.0;
  double _dodge = 0.0;
  Vector3 _dodgeDir = Vector3(0, 0, -1);
  double _dodgeCd = 0.0;

  final PlayerModel model = PlayerModel();

  /// Stage 40: the playground is a showroom — nothing runs out there, so every
  /// ability can be tried one after the other. It reads the world's own flag,
  /// so it holds in a saved playground as in a fresh one.
  static bool get endlessStats => GameState.instance.playground;

  /// Does [have] cover [cost]? In the playground, always.
  static bool canSpend(double have, double cost) => endlessStats || have >= cost;

  /// What is left of [have] once [cost] is paid, never under zero. In the
  /// playground nothing is paid.
  static double afterSpending(double have, double cost) => endlessStats ? have : math.max(have - cost, 0.0);

  /// Is there [cost] stamina to spend?
  bool hasStamina(double cost) => canSpend(stamina, cost);

  /// Is there [cost] mana to spend?
  bool hasMana(double cost) => canSpend(mana, cost);

  /// Pays [cost] stamina.
  void spendStamina(double cost) => stamina = afterSpending(stamina, cost);

  /// Pays [cost] mana.
  void spendMana(double cost) => mana = afterSpending(mana, cost);

  /// The forearm and item drawn in front of the eye in first person; the body
  /// [model] is hidden then, so this is the only part of the player on screen.
  final HandView handView = HandView();
  late Game main;

  IVec3 aimedBlock = IVec3.zero;
  IVec3 aimedNormal = IVec3.zero;
  bool isAiming = false;
  Mob? aimedMob;

  /// How far the crosshair's line stays clear of anything that stops a body,
  /// or [double.infinity] when it stays clear the whole way. Everything the
  /// crosshair acts on — a creature, a boat, a cart, a mount — must stand
  /// nearer than this: nothing is reached through a wall.
  double aimClearDistance = double.infinity;
  double mineProgress = 0.0;
  IVec3 _mineTarget = const IVec3(999999, 0, 0);

  double yaw = 0.0;
  double pitch = -0.35;
  /// The third-person seat, pulled in by walls (the kit's).
  final ShoulderOrbit orbit = ShoulderOrbit(distance: orbitDistance, shoulder: orbitShoulder, rise: orbitRise);
  double get camDistance => orbit.current;
  double fov = 72.0;
  /// The skeleton around the aimed block or mob.
  final SelectionOutline outline = SelectionOutline();
  Node get highlight => outline.node;
  late final Node crack;
  late final UnlitMaterial _crackMat;
  late final PointLight torchLight;
  final Node _torchNode = Node();
  double _attackCooldown = 0.0;
  double _hungerTimer = 0.0;
  double _regenTimer = 0.0;
  double damageFlash = 0.0;
  double _useCooldown = 0.0;
  double _lavaTimer = 0.0;
  double _drownTimer = 0.0;
  Vector3 _lastMoveDir = Vector3(0, 0, -1);
  Vector3 _moveWish = Vector3.zero(); // where the input pushed last tick, backward included
  double _stepTimer = 0.0;
  bool _wasInWater = false;
  bool _sprintHeld = false;

  // Stage 32: the hit is felt, footsteps have a voice, mining cracks the block.
  double _shakeTime = 0.0; // camera shake left, seconds
  double _shakeAmp = 0.0; // its amplitude in metres
  Vector3 _shake = Vector3.zero(); // this frame's jolt, added to the camera only
  final ViewBob _bob = ViewBob()
    ..amplitude = bobAmplitude
    ..swayRatio = bobSwayRatio; // the walk's sway of the eye, camera only
  double _mineFxTimer = 0.0; // swing + chips + dig voice while mining
  final List<Node> crackLines = []; // the four crack stages, six faces each (stage * 6 + face)
  int stepsTaken = 0; // footsteps played (for the probe)
  // The 2D game's player `footstep_interval`, a little quicker sprinting.
  static const double footstepInterval = 0.4;
  static const double footstepIntervalSprint = 0.3;
  /// VK5.1: the on-foot rules (gravity, swimming, jumps, auto steps, the
  /// launch out of water, the fall's height, the knockback window) are the
  /// kit's, shared with its creatures.
  late final CharacterMotor motor = CharacterMotor(this, const MotorTuning(jumpVelocity: jumpVelocity, climbSpeed: climbSpeed));

  /// The player's own tones; the shirt is the class colour.
  static final Vector3 skinTone = Vector3(0.93, 0.76, 0.62);
  static final Vector3 pantsTone = Vector3(0.24, 0.31, 0.50);
  static final Vector3 hairTone = Vector3(0.36, 0.22, 0.12);

  /// The 2D game's ground kind (`Sfx.stepKinds`) a block's footstep sounds
  /// like: snow, sand, water and mud, grass and leaves; bare ground (stone,
  /// wood, dirt, metal) is the lava land's dirt walk.
  static String stepKind(int block) {
    final id = Blocks.idOf(block);
    if (id.contains('snow') || id.contains('ice')) return 'snow';
    if (id.contains('sand') || id.contains('gravel')) return 'desert';
    if (Blocks.isLiquid(block) || id.contains('mud') || id.contains('clay') || id.contains('lily')) return 'swamp';
    final family = Blocks.materialFamily(block);
    if (family == 'plant' || id.contains('grass') || id.contains('leaves') || id.contains('moss') || id.contains('hay')) return 'forest';
    return 'lava';
  }
  static const double shakeSeconds = 0.15;
  static const double mineFxPeriod = 0.35;

  /// Stage 32: the crack stage (0..3) mining [progress] (0..1) shows, and the
  /// darkening box's alpha for it.
  static int crackStage(double progress) => (progress * 4.0).toInt().clamp(0, 3);
  static double crackAlphaFor(double progress) => 0.16 * (crackStage(progress) + 1);

  PlayerClass get classDef => classes[playerClass]!;

  void setupPlayer(VoxelWorld w, Game mainGame, String cls) {
    setup(w, 0.3, 1.75);
    main = mainGame;
    playerClass = cls;
    final c = classDef;
    maxHp = c.hp;
    hp = maxHp;
    maxStamina = c.stamina;
    stamina = maxStamina;
    maxMana = c.mana;
    mana = maxMana;
    fov = baseFov;

    model.build(skinTone, c.shirt, pantsTone, hairTone);
    node.add(model.root);
    handView.build(skinTone, c.shirt);
    handView.visible = firstPerson;

    _crackMat = UnlitMaterial()
      ..baseColorFactor = Vector4(0, 0, 0, 0)
      ..alphaMode = AlphaMode.blend;
    crack = MirroredCamera.primitiveNode(Mesh(CuboidGeometry(Vector3(1.01, 1.01, 1.01)), _crackMat), castsShadows: false)
      ..visible = false;
    _buildCrackStages();

    torchLight = PointLight(color: Vector3(1.0, 0.8, 0.5), intensity: 0.0, range: 9.0);
    _torchNode.position = Vector3(0, 1.4, 0);
    _torchNode.addComponent(PointLightComponent(torchLight));
    node.add(_torchNode);
    inventory.listeners.add(_refreshArmor);
    inventory.listeners.add(() => bagDirty = true);
    _giveStartingKit();
  }

  /// Stage 25: a client re-declares its bag to the host when set.
  bool bagDirty = false;

  /// Probe (stage 25): every slot full, except one that leaves room for exactly
  /// one more [id].
  void probeFillBag(String id) {
    for (var i = 0; i < Inventory.size; i++) {
      inventory.setSlot(i, ItemStack('stone', Items.stackSize('stone')));
    }
    inventory.setSlot(Inventory.size - 1, ItemStack(id, Items.stackSize(id) - 1));
  }

  void _giveStartingKit() {
    final c = classDef;
    inventory.add(c.weapon, 1);
    inventory.add('wooden_pickaxe', 1);
    inventory.add('wooden_axe', 1);
    inventory.add('apple', 5);
    inventory.add('torch', 8);
    if (playerClass == 'ranger') inventory.add('arrow', 48);
    if (playerClass == 'mage') inventory.add('health_potion', 2);
  }

  void notify(String text) => main.notify(text);

  void setLook(double y, double p) {
    yaw = y;
    pitch = p;
    Tutorial.instance.event('look');
  }

  void setFirstPerson(bool fp) {
    firstPerson = fp;
    model.visible = !fp;
    handView.visible = fp;
    if (!fp) orbit.current = orbit.clearFrom(pivot: pivotPosition, right: rightVec, up: upVec, back: backVec, jitter: _shake + _bob.offset, cellIsClear: _cellIsClear);
  }

  String heldItem() => inventory.idAt(selectedSlot);

  int pickUp(String id, int n) {
    final left = inventory.add(id, n);
    if (left < n) {
      main.hud.addPickup(id, n - left); // stage 32: a stacking toast instead of a note
      Sfx.play('pickup', -8.0);
      main.quests.onPickup(id, n - left);
      if (id == 'diamond') Achievements.instance.unlock('diamonds');
      if (id == 'underworld_heart') Achievements.instance.unlock('heart'); // stage 29: the win token
    }
    return left;
  }

  // --- camera -----------------------------------------------------------------

  Vector3 get forward => Vector3(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch));
  Vector3 get flatForward => flatForwardFor(yaw);
  // Godot's right-handed basis (`player.gd`: `right := Vector3(cos(_yaw), 0,
  // -sin(_yaw))`); `MirroredCamera` renders that handedness, so +X is screen-right
  // at yaw 0 and D strafes toward it.
  Vector3 get rightVec => rightFor(yaw);
  Vector3 get upVec => Vector3(math.sin(pitch) * math.sin(yaw), math.cos(pitch), math.sin(pitch) * math.cos(yaw));
  Vector3 get backVec => -forward;

  static Vector3 flatForwardFor(double yaw) => Vector3(-math.sin(yaw), 0, -math.cos(yaw));
  static Vector3 rightFor(double yaw) => Vector3(math.cos(yaw), 0, -math.sin(yaw));

  /// The yaw after a mouse motion of [dx] logical pixels (Godot: `_yaw -=
  /// relative.x * ...`, so moving the mouse right turns right).
  static double yawAfterMouse(double yaw, double dx, double scale) => yaw - dx * scale;

  /// Swimming proper: in a liquid and off the floor, or with the head under.
  /// A body standing in a one-block puddle is [wading] — it walks, jumps and
  /// falls under full gravity, which is what stops shallow water from turning
  /// the swim rules on and off under a walking player.
  bool get swimming => inLiquid && !wading;

  Vector3 get pivotPosition => position + Vector3(0, firstPerson ? eyeHeight : 1.5, 0);

  Vector3 get cameraPosition {
    if (firstPerson) return pivotPosition;
    return pivotPosition + orbit.offset(rightVec, upVec, backVec, orbit.current);
  }

  /// Where the near plane actually sits this frame: the orbit seat plus the
  /// jolt and the sway. [_updateCamera] keeps *this* point out of the rock,
  /// not the seat, because a wall does not care which of the three put the eye
  /// inside it.
  Vector3 get eyePosition => cameraPosition + _shake + _bob.offset;

  PerspectiveCamera camera() => MirroredCamera(
        position: eyePosition,
        target: eyePosition + forward + upVec * _bob.pitch,
        up: upVec + rightVec * _bob.roll,
        fovRadiansY: fov * math.pi / 180.0,
        fovNear: 0.05,
        fovFar: 700.0,
      );

  Vector3 aimOrigin() => firstPerson ? cameraPosition : pivotPosition + rightVec * orbitShoulder;
  Vector3 aimDirection() => forward;

  /// One swing, in the body and in the first-person hand at once. Every attack,
  /// dig and place goes through here so the two can never fall out of step.
  void swingArm() {
    model.swing();
    handView.swing();
  }

  void _updateCamera(double dt) {
    _shake = _shakeOffset(dt);
    _updateBob(dt);
    _updateHandView(dt);
    if (firstPerson) return;
    // The box the eye really occupies is swept along the exact segment it
    // will travel, jolt and sway included: a bare ray from the shoulder left
    // the rise, the near plane and the jitter out, and each of them put the
    // near plane inside a wall, which shows every cave behind it.
    orbit.settle(dt, pivot: pivotPosition, right: rightVec, up: upVec, back: backVec, jitter: _shake + _bob.offset, cellIsClear: _cellIsClear);
    model.visible = orbit.current > modelHideDistance;
  }

  bool _cellIsClear(int x, int y, int z) => y >= 0 && !blocksCamera(world.getBlockXYZ(x, y, z));

  /// A cell the eye may not enter: anything drawn as a full opaque cube (from
  /// the inside it is not drawn at all) and anything that stops a body — a
  /// pane of glass, a shut door, a fence. Grass, flowers, torches, rails and
  /// water are none of those, and the camera passes through them.
  static bool blocksCamera(int block) => Blocks.isOpaque(block) || Blocks.isSolid(block);

  /// Stage 32: a random jolt in the camera plane that dies out over
  /// [shakeSeconds], scaled by the damage taken (the aim never moves).
  Vector3 _shakeOffset(double dt) {
    if (_shakeTime <= 0.0) return Vector3.zero();
    _shakeTime = math.max(_shakeTime - dt, 0.0);
    final k = _shakeAmp * (_shakeTime / shakeSeconds);
    final rng = main.random;
    return rightVec * ((rng.nextDouble() * 2.0 - 1.0) * k) + upVec * ((rng.nextDouble() * 2.0 - 1.0) * k);
  }

  /// Stage 32: the camera is shaking (for the probe).
  bool shakeActive() => _shakeTime > 0.0;

  /// Minecraft's view bobbing: the eye drops by `|cos|` of the walk phase,
  /// sways sideways by `sin` at a fraction of that width, and picks up a
  /// breath of roll and nose-up on each footfall. The drop is the whole of the
  /// effect and the sway is a hint of one — a bob of equal width in both reads
  /// as a lurch from side to side.
  ///
  /// It is a nudge and nothing more. A camera that swings enough to be
  /// *noticed* is a camera that makes people ill, because the eye is the one
  /// thing a player cannot look away from; what carries the sense of walking in
  /// first person is the hand in the corner of the screen ([HandView]), which
  /// sways several times as far and lags this by a fifth of a step.
  ///
  /// The cycle is advanced by distance covered rather than by time, so it keeps
  /// step with the feet at any speed instead of needing a rate per gait, and
  /// sprinting bobs both wider and faster from the one weight. It moves the eye
  /// only: [aimOrigin] and [aimDirection] are untouched, so a bobbing head
  /// never misses a block. Third person bobs too, as Minecraft's does — the
  /// whole view is bobbed before the camera swings out behind the shoulder.
  ///
  /// In the saddle it is the same sway and nothing else: a horse's gait is the
  /// walk's shape turned up, so riding never grew a second camera to keep in
  /// step with this one. The four numbers below are the whole difference, in
  /// both first and third person, and tuning the trot means tuning them.
  ///
  /// [trotAmplitude] is how much wider the saddle throws the rider than a
  /// footfall does, [trotCadence] how much of the walk's cycle-per-metre a
  /// horse spends (it covers more ground per beat, so fewer cycles per metre),
  /// [trotRoll] how much harder the view leans into each beat, and
  /// [gallopBoost] what a sprinting mount adds on top — the speed alone cannot
  /// say it, because a horse is already past the clamp at a standing trot.
  /// How far the eye drops at the bottom of a full-speed footfall, in blocks.
  /// This is deliberately small. The eye is the one thing a player cannot look
  /// away from, so a wide bob on it is read by the inner ear as the ground
  /// moving and makes people ill; Minecraft keeps it to a nudge and puts the
  /// visible motion in the hand instead ([HandView]).
  static const double bobAmplitude = 0.05;

  /// The sideways sway, as a fraction of the drop. A head rises and falls as it
  /// walks and hardly moves across; anything near a half reads as a stagger.
  static const double bobSwayRatio = 0.16;

  static const double trotAmplitude = 2.0;
  static const double trotCadence = 0.55;
  static const double trotRoll = 1.6;
  static const double gallopBoost = 1.3;

  /// The width this frame's sway is multiplied by: 1 on foot, the trot in the
  /// saddle, the gallop when the mount is sprinting.
  static double gaitAmplitude({required bool mounted, required bool sprinting}) =>
      !mounted ? 1.0 : trotAmplitude * (sprinting ? gallopBoost : 1.0);

  void _updateBob(double dt) {
    // A mounted rider is carried, so the gait is the horse's: its velocity and
    // its feet, not the rider's own, which sit frozen on the saddle.
    final h = mount;
    final vel = h?.velocity ?? velocity;
    final speed = math.sqrt(vel.x * vel.x + vel.z * vel.z);
    final grounded = h?.onFloor ?? onFloor;
    // Only on foot or in the saddle: airborne, swimming, a boat, a minecart,
    // gliding and climbing have no footfalls to answer to.
    final walking = grounded && !gliding && !climbing && riding == null && cart == null && speed > 0.6;
    final gait = gaitAmplitude(mounted: h != null, sprinting: h?.rideSprint ?? false);
    _bob.update(dt,
        walking: walking,
        speed: speed,
        walkSpeed: walkSpeed,
        right: rightVec,
        up: upVec,
        enabled: Settings.instance.viewBob,
        cadence: h == null ? 1.0 : trotCadence,
        gait: gait,
        rollScale: h == null ? 1.0 : trotRoll);
  }

  /// The sway the camera carries this frame (for the probe).
  Vector3 viewBobOffset() => _bob.offset;

  /// Puts the first-person hand back in front of the eye. The camera has no
  /// view pass of its own here, so the hand is an ordinary world-space node
  /// rebuilt against the camera basis every frame — the same basis [camera]
  /// hands the renderer, roll and all, or the arm would slide across the screen
  /// whenever the view leaned.
  void _updateHandView(double dt) {
    if (!firstPerson) return;
    handView.setHeld(heldItem());
    final f = (forward + upVec * _bob.pitch).normalized();
    var u = upVec + rightVec * _bob.roll;
    final r = f.cross(u).normalized();
    u = r.cross(f).normalized();
    handView.update(
      dt: dt,
      eye: cameraPosition + _shake + _bob.offset,
      right: r,
      up: u,
      forward: f,
      phase: _bob.phase,
      weight: _bob.weight,
    );
  }

  /// VP1.9: voxel_core's grid traversal over this world.
  RayHit? voxelRaycast(Vector3 origin, Vector3 direction, double reachDist) =>
      VoxelRaycast.solid(world, origin, direction, reachDist);

  void _updateAim() {
    final origin = aimOrigin();
    final dir = aimDirection();
    final hit = voxelRaycast(origin, dir, reach);
    // Reach: nothing is acted on through what stands in front of it. A
    // creature is out of reach behind anything that stops a body — a wall, a
    // closed door — but not behind what a body walks through: grass, a flower,
    // the gap between two fence posts.
    aimClearDistance = Reach.toBarrier(world, origin, dir, reach);
    final mob = Reach.nearestBody(main.mobs, origin, dir, maxDist: meleeReach, blockedAt: aimClearDistance);
    aimedMob = mob;
    // Of the block and the creature, the crosshair mines and places at
    // whichever is nearer; a creature behind the block is not in the way of it.
    final mobDist = mob?.rayDistance(origin, dir) ?? double.infinity;
    isAiming = hit != null && hit.distance <= mobDist;
    // A tap on the screen has no button to tell attack from use, so the
    // crosshair tells it: the nearest thing in reach decides (see
    // [GameInput.touchTapAttacks]).
    main.input.touchTapAttacks = mob != null && !isAiming;
    if (isAiming) {
      aimedBlock = hit!.block;
      aimedNormal = hit.normal;
      outline.show(selectionBoxAt(world, hit.block.x, hit.block.y, hit.block.z));
    } else if (mob != null) {
      outline.show(mobBox(mob));
    } else {
      outline.hide();
    }
  }

  /// A mob's outline box: its collider, the box the crosshair ray hits.
  static CollisionBox mobBox(Mob m) {
    final p = m.position, w = m.halfWidth;
    return CollisionBox(p.x - w, p.y, p.z - w, p.x + w, p.y + m.height, p.z + w);
  }

  // --- the tick --------------------------------------------------------------------

  void _handleOneShots(double dt, GameInput input, bool gameplay) {
    if (!gameplay) return;
    final look = input.takeLookDelta(dt);
    if (look != Offset.zero) {
      Tutorial.instance.event('look');
      yaw = yawAfterMouse(yaw, look.dx, mouseSensitivity * sensitivityScale);
      pitch = (pitch - look.dy * mouseSensitivity * sensitivityScale).clamp(-1.45, 1.45);
    }
    final wheel = input.takeWheel();
    if (wheel != 0) selectedSlot = (selectedSlot + wheel + 9) % 9;
    final digit = input.hotbarPressed();
    if (digit >= 0) selectedSlot = digit;
    if (input.justPressed(GameAction.toggleView)) setFirstPerson(!firstPerson);
    if (input.justPressed(GameAction.dropItem)) _dropHeld();
    if (input.justPressed(GameAction.eat)) _eatHeld();
    if (input.justPressed(GameAction.attack)) _attackPressed();
    if (input.justPressed(GameAction.use)) _usePressed();
    if (input.justPressed(GameAction.ability)) _useAbility();
    if (input.justPressed(GameAction.ability2)) _useAbility2();
    if (input.justPressed(GameAction.dodge)) _dodgePressed();
    if (input.justPressed(GameAction.interact)) {
      final m = aimedMob;
      if (m != null && m.species.trader) {
        main.trade(m);
      } else {
        _interactPressed();
      }
    }
  }

  void physicsProcess(double dt, GameInput input, bool gameplay) {
    if (isDead) return;
    // Stage 29: like a mob, the body waits for its chunk (a save in the
    // underworld puts the player over a cavern; an unloaded chunk reads as air
    // and the fall lands anywhere).
    if (!world.isLoaded(IVec3.floor(position))) {
      velocity = Vector3.zero();
      return;
    }
    _handleOneShots(dt, input, gameplay);
    _sprintHeld = gameplay && input.down(GameAction.sprint);
    _tickStats(dt);
    _attackCooldown = math.max(_attackCooldown - dt, 0.0);
    _useCooldown = math.max(_useCooldown - dt, 0.0);
    abilityCooldown = math.max(abilityCooldown - dt, 0.0);
    ability2Cooldown = math.max(ability2Cooldown - dt, 0.0);
    if (sleeping > 0.0) {
      _sleepTick(dt);
      return;
    }
    model.tiltX = lerpd(model.tiltX, 0.0, dt * 8.0);
    model.posY = lerpd(model.posY, 0.0, dt * 8.0);
    model.dashing = false;
    _tendBobber();
    bobber?.update(dt);
    if (riding != null) {
      _rideTick(dt, input, gameplay);
      return;
    }
    if (mount != null) {
      _mountTick(dt, input, gameplay);
      return;
    }
    if (cart != null) {
      _cartTick(dt, input, gameplay);
      return;
    }

    var inputX = 0.0, inputY = 0.0;
    if (gameplay) {
      inputX = input.moveAxisX();
      inputY = input.moveAxisY();
    }
    final fwd = flatForward;
    final right = rightVec;
    var wish = fwd * -inputY + right * inputX;
    if (_probeWalk.length2 > 0.0) wish = _probeWalk.clone();
    if (wish.length > 1.0) wish = wish.normalized();
    if (wish.length > 0.1) Tutorial.instance.event('move');
    final sprinting = gameplay && input.down(GameAction.sprint) && stamina > 1.0 && inputY < 0.0 && !swimming;
    final sneaking = gameplay && input.down(GameAction.sneak);
    var speed = sprinting ? sprintSpeed : (sneaking ? sneakSpeed : walkSpeed);
    if (swimming) {
      speed = swimSpeed;
    } else if (inLiquid) {
      speed *= 0.8; // wading: slowed, but still walking
    }
    speed *= effects.speedMultiplier() * (1.0 + 0.05 * talentRank('swiftness'));
    // Stage 29: soul sand under the feet.
    if (onFloor) speed *= Blocks.speedMult(world.getBlockXYZ(position.x.floor(), (position.y - 0.05).floor(), position.z.floor()));
    if (sprinting) spendStamina(6.0 * dt);

    final jumpHeld = gameplay && input.down(GameAction.jump);
    // Fly mode (F5): no gravity, vertical on jump / sneak.
    if (main.flyMode) {
      speed *= flySpeedScale;
      motor.fly(dt, wish: wish, speed: speed, rise: jumpHeld, sink: sneaking);
      // Flying is walking on the air: the body turns and strides as on foot,
      // never the glide's open arms.
      gliding = false;
      climbing = false;
      _faceAndAnimate(dt, input, gameplay, fwd, wish, true, stride: 1.0 / flySpeedScale);
      model.setHeld(heldItem());
      _finishTick(dt, input, gameplay, fwd, wish, sprinting);
      return;
    }
    // Climbing: push into a wall while holding jump. Behind the
    // `climbWalls` setting, off by default. The motor climbs it as a ladder.
    final wallClimb =
        Settings.instance.climbWalls && jumpHeld && wish.length > 0.1 && wallAhead(wish) && !inLiquid && stamina > 0.5;
    if (wallClimb) spendStamina(10.0 * dt);
    if (jumpHeld && onFloor && !wallClimb && !_onLadder() && !swimming) Tutorial.instance.event('jump');

    // Gliding: hold G in the air with a glider in the inventory.
    gliding = false;
    if (gameplay && input.down(GameAction.glide) && motor.canGlide && inventory.countOf('glider') > 0) {
      gliding = true;
      Achievements.instance.unlock('glider');
      wish = wish.length < 0.1 ? fwd : wish;
      speed = 11.0;
    }

    // Dodge dash: a short burst with invulnerability, the body leaning into
    // it with the arms thrown back.
    double? accel = gliding ? 3.0 : null;
    if (_dodge > 0.0) {
      _dodge -= dt;
      wish = _dodgeDir;
      speed = 13.0;
      accel = 40.0;
      model.dashing = true;
    }

    final posBefore = position.clone();
    final events = motor.step(dt,
        wish: wish,
        speed: speed,
        jump: jumpHeld,
        sneak: sneaking,
        onLadder: wallClimb || _onLadder(),
        glide: gliding,
        accel: accel);
    climbing = motor.climbing;
    if (onFloor) {
      // Stage 30: the stats block's metres walked (the ground displacement).
      final d = position - posBefore;
      GameState.instance.distanceWalked += math.sqrt(d.x * d.x + d.z * d.z);
    }
    // Fall damage.
    final fall = events.landedAfter;
    if (fall > 4.0) takeDamage(((fall - 4.0) * 1.2).floorToDouble(), 'fall');
    if (inLava) {
      effects.apply('burning', 3.0);
      _lavaTimer += dt;
      if (_lavaTimer > 0.4) {
        _lavaTimer = 0.0;
        takeDamage(4.0, 'lava');
      }
    }
    if (headInLiquid) {
      _drownTimer += dt;
      if (_drownTimer > 8.0) {
        takeDamage(2.0, 'drowning');
        _drownTimer = 6.5;
      }
    } else {
      _drownTimer = 0.0;
    }

    final horizontalSpeed = _faceAndAnimate(dt, input, gameplay, fwd, wish, onFloor);
    if (onFloor && horizontalSpeed > 1.0) {
      _stepTimer -= dt;
      if (_stepTimer <= 0.0) {
        // A footstep every `footstepInterval` seconds, a 2D game recording of
        // the ground under the feet.
        _stepTimer = sprinting ? footstepIntervalSprint : footstepInterval;
        final under = world.getBlockXYZ(position.x.floor(), (position.y - 0.05).floor(), position.z.floor());
        Sfx.playStep(stepKind(under), -6.0);
        stepsTaken += 1;
      }
    }
    if (inLiquid && !_wasInWater) Sfx.play('splash', -8.0);
    _wasInWater = inLiquid;
    model.setHeld(heldItem());
    _finishTick(dt, input, gameplay, fwd, wish, sprinting);
  }

  /// Turns the model and plays its limbs for this tick, on foot or in the
  /// air; [grounded] strides, off it the airborne pose blends in. [stride]
  /// scales the pace the legs are played at. Returns the horizontal speed.
  double _faceAndAnimate(double dt, GameInput input, bool gameplay, Vector3 fwd, Vector3 wish, bool grounded,
      {double stride = 1.0}) {
    // Face the movement direction (or the camera when aiming/attacking). A
    // step with a backward part (more than 90 degrees from the camera) walks
    // backward like Minecraft: the body faces the opposite way, still looking
    // ahead, instead of turning around.
    if (wish.length > 0.1) {
      var d = math.atan2(-wish.x, -wish.z) - yaw;
      d = (d + math.pi) % (math.pi * 2) - math.pi;
      final backward = d.abs() > math.pi / 2 + 0.01;
      _lastMoveDir = backward ? -wish : wish.clone();
    }
    _moveWish = wish.clone();
    var face = _lastMoveDir;
    if (firstPerson || (gameplay && (input.down(GameAction.attack) || input.down(GameAction.use))) || gliding) face = fwd;
    // A dash faces where it goes, backward too, and turns there at once.
    final dashing = _dodge > 0.0 && !firstPerson;
    if (dashing) face = _dodgeDir;
    final targetYaw = math.atan2(-face.x, -face.z);
    model.yaw = lerpAngle(model.yaw, targetYaw, dt * (dashing ? 30.0 : 12.0));
    final horizontalSpeed = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    model.animate(dt, horizontalSpeed * stride, grounded, gliding, climbing);
    return horizontalSpeed;
  }

  void _finishTick(double dt, GameInput input, bool gameplay, Vector3 fwd, Vector3 wish, bool sprinting) {
    final held = heldItem();
    torchLight.intensity = (held == 'torch' || held == 'lamp') ? 10.0 : 0.0;
    fov = lerpd(fov, baseFov + (sprinting ? 8.0 : 0.0), dt * 6.0);
    syncNode();
    _updateCamera(dt);
    _updateAim();
    if (gameplay && input.down(GameAction.attack)) {
      _attackTick(dt);
    } else {
      _resetMining();
    }
    if (gameplay && input.down(GameAction.use) && _useCooldown <= 0.0 && _useRepeats()) _usePressed();
    damageFlash = math.max(damageFlash - dt * 3.0, 0.0);
    world.updateAround(position);
  }

  bool _onLadder() {
    final feet = world.getBlockXYZ(position.x.floor(), (position.y + 0.2).floor(), position.z.floor());
    final mid = world.getBlockXYZ(position.x.floor(), (position.y + 1.0).floor(), position.z.floor());
    return (feet != Blocks.air && Blocks.idOf(feet) == 'ladder') || (mid != Blocks.air && Blocks.idOf(mid) == 'ladder');
  }

  void _refreshArmor() {
    armor = 0;
    for (final s in inventory.slots) {
      if (s == null) continue;
      final d = Items.def(s.id);
      if (d.armor > 0) armor = math.max(armor, d.armor);
    }
  }

  void _tickStats(double dt) {
    _hungerTimer += dt;
    if (_hungerTimer > 1.0) {
      _hungerTimer = 0.0;
      if (!GameState.instance.creative) hunger = math.max(hunger - 1.0 / 45.0, 0.0); // stage 30: creative never gets hungry
    }
    if (hunger <= 0.0 && !GameState.instance.creative) {
      _regenTimer += dt;
      if (_regenTimer > 4.0) {
        _regenTimer = 0.0;
        takeDamage(1.0, 'starving');
      }
    } else if (hp < maxHp && hunger >= 6.0) {
      _regenTimer += dt;
      if (_regenTimer > 3.0) {
        _regenTimer = 0.0;
        hp = math.min(hp + 1.0, maxHp);
      }
    }
    if (!_sprintHeld && !climbing) {
      stamina = math.min(stamina + 14.0 * (1.0 + 0.25 * talentRank('endurance')) * dt, maxStamina);
    }
    mana = math.min(mana + 2.5 * (1.0 + 0.25 * talentRank('arcana')) * dt, maxMana);
    _invulnerable = math.max(_invulnerable - dt, 0.0);
    _dodgeCd = math.max(_dodgeCd - dt, 0.0);
    if (inLiquid && effects.has('burning')) effects.clear('burning');
    for (final ev in effects.tick(dt)) {
      if (ev.damage > 0.0) {
        takeDamage(ev.damage, ev.id);
      } else if (hp < maxHp) {
        hp = math.min(hp + ev.heal, maxHp);
        main.spawnDamageNumber(centre() + Vector3(0, 0.6, 0), ev.heal, StatusEffects.def(ev.id).color);
      }
    }
  }

  // --- actions ----------------------------------------------------------------------

  void _attackPressed() {
    if (_attackCooldown > 0.0) return;
    final item = heldItem();
    final style = weaponStyle();
    if (style == 'bow' || style == 'staff') {
      _rangedFire(item, style, false);
      return;
    }
    if (aimedMob == null && (_tryBreakBoat() || _tryBreakCart())) return;
    swingArm();
    Sfx.play('swing', -10.0);
    _attackCooldown = style == 'melee_fast' ? 0.28 : 0.5;
    // The camera's aimedMob only decides whether to swing at a boat; the hit
    // itself is a reach check the simulation runs: the host resolves it, a
    // client asks for it.
    final dmg = _meleeDamage(item);
    final followUp = style == 'melee_fast' && main.random.nextDouble() < 0.3 ? dmg * 0.5 : 0.0;
    main.meleeStrike(aimDirection(), dmg, followUp, this);
    _wearHeld();
  }

  /// Stage 26: a right click on whatever is aimed (the parrot probe feeds seeds
  /// through the real use path).
  void probeUse() {
    _useCooldown = 0.0;
    _usePressed();
  }

  void probeStrike() {
    _attackCooldown = 0.0;
    _attackPressed();
  }

  void probeFire(bool secondary) {
    final style = weaponStyle();
    if (style == 'bow' || style == 'staff') _rangedFire(heldItem(), style, secondary);
  }

  String weaponStyle() {
    final item = heldItem();
    return item != '' && Items.kind(item) == ItemKind.weapon ? Items.styleOf(item) : 'melee';
  }

  /// Holding the attack button: ranged weapons keep firing at their own rate
  /// (the staff spray); everything else mines the aimed block.
  void _attackTick(double dt) {
    final style = weaponStyle();
    if (style == 'bow' || style == 'staff') {
      _resetMining();
      if (_attackCooldown <= 0.0) _rangedFire(heldItem(), style, false);
      return;
    }
    _mineTick(dt);
  }

  double _meleeDamage(String item) {
    var base = 1.0;
    if (item != '') {
      final k = Items.kind(item);
      if (k == ItemKind.weapon || k == ItemKind.tool) base = Items.damageOf(item).toDouble();
    }
    base += inventory.bonusAt(selectedSlot);
    return (base * classDef.damageMult * (1.0 + (level - 1) * 0.08) * damageMultiplier()).roundToDouble();
  }

  static const double staffBoltMana = 4.0;
  static const double staffArcMana = 18.0;
  static const double bowShotStamina = 3.0;
  static const double bowFanStamina = 14.0;

  double _rangedDamage(String item, double mult) =>
      ((Items.damageOf(item) + inventory.bonusAt(selectedSlot)) * mult * classDef.damageMult * (1.0 + (level - 1) * 0.08) * damageMultiplier() * (1.0 + 0.12 * talentRank('eagle_eye')))
          .roundToDouble();

  Vector3 _rotated(Vector3 v, Vector3 axis, double angle) => Quaternion.axisAngle(axis, angle).rotated(v);

  Vector3 _fanDirection(int index, int count, double totalAngle) {
    final dir = aimDirection();
    if (count <= 1) return dir;
    final t = index / (count - 1) - 0.5;
    final axis = dir.y.abs() < 0.9 ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
    return _rotated(dir, axis, t * totalAngle).normalized();
  }

  Vector3 _muzzle() => aimOrigin() + aimDirection() * 0.8 + Vector3(0, -0.15, 0);

  void _rangedFire(String item, String style, bool secondary) {
    if (style == 'staff') {
      if (secondary) {
        _castArc(item);
      } else {
        _castBolt(item);
      }
    } else {
      if (secondary) {
        _shootFan(item);
      } else {
        _shootArrow(item);
      }
    }
  }

  void _shootArrow(String bow) {
    if (inventory.countOf('arrow') <= 0) {
      notify('No arrows!');
      _attackCooldown = 0.3;
      return;
    }
    if (!hasStamina(bowShotStamina)) {
      notify('Too tired to draw');
      _attackCooldown = 0.3;
      return;
    }
    inventory.remove('arrow', 1);
    spendStamina(bowShotStamina);
    Sfx.play('shoot', -6.0);
    swingArm();
    _attackCooldown = Items.tierOf(bow) < 3 ? 0.5 : 0.4;
    final dir = _rotated(aimDirection(), Vector3(0, 1, 0), (main.random.nextDouble() - 0.5) * 0.02);
    main.spawnProjectile(_muzzle(), dir * 36.0, _rangedDamage(bow, 1.0), this, 'arrow', 0.05, 5.0);
    _wearHeld();
  }

  /// Fan shot (right button with a bow): three arrows across a 24° fan.
  void _shootFan(String bow) {
    if (inventory.countOf('arrow') < 3) {
      notify('Need 3 arrows');
      _useCooldown = 0.3;
      return;
    }
    if (!hasStamina(bowFanStamina)) {
      notify('Too tired to draw');
      _useCooldown = 0.3;
      return;
    }
    inventory.remove('arrow', 3);
    spendStamina(bowFanStamina);
    Sfx.play('shoot', -4.0);
    swingArm();
    _attackCooldown = 0.7;
    _useCooldown = 1.4;
    for (var i = 0; i < 3; i++) {
      main.spawnProjectile(_muzzle(), _fanDirection(i, 3, 24.0 * math.pi / 180.0) * 34.0, _rangedDamage(bow, 0.85), this, 'arrow', 0.05, 5.0);
    }
    _wearHeld();
  }

  /// Staff spray (hold the attack button): a fast stream of thick bolts, cheap on mana.
  void _castBolt(String staff) {
    if (!hasMana(manaCost(staffBoltMana))) {
      notify('Not enough mana');
      _attackCooldown = 0.3;
      return;
    }
    spendMana(manaCost(staffBoltMana));
    Sfx.play('bolt', -9.0);
    swingArm();
    _attackCooldown = Items.tierOf(staff) < 3 ? 0.22 : 0.17;
    final rng = main.random;
    var dir = _rotated(aimDirection(), Vector3(0, 1, 0), (rng.nextDouble() - 0.5) * 0.08);
    dir = _rotated(dir, Vector3(1, 0, 0), (rng.nextDouble() - 0.5) * 0.04);
    main.spawnProjectile(_muzzle(), dir * 26.0, _rangedDamage(staff, 0.6), this, 'bolt', 0.35, 3.0);
  }

  /// Arc (right button with a staff): a cone of five bolts across 50°.
  void _castArc(String staff) {
    if (!hasMana(manaCost(staffArcMana))) {
      notify('Not enough mana');
      _useCooldown = 0.3;
      return;
    }
    spendMana(manaCost(staffArcMana));
    Sfx.play('bolt', -3.0);
    swingArm();
    _attackCooldown = 0.6;
    _useCooldown = 1.1;
    main.spawnEffect(_muzzle(), Vector3(1, 0.55, 0.2), 1.0);
    for (var i = 0; i < 5; i++) {
      main.spawnProjectile(_muzzle(), _fanDirection(i, 5, 50.0 * math.pi / 180.0) * 22.0, _rangedDamage(staff, 0.9), this, 'bolt', 0.4, 6.0);
    }
  }

  /// Sleeping: the model lies on the bed while the night is skipped.
  void startSleep() {
    sleeping = 2.4;
    velocity = Vector3.zero();
  }

  void _sleepTick(double dt) {
    sleeping -= dt;
    model.tiltX = lerpd(model.tiltX, -1.5, dt * 6.0);
    model.posY = lerpd(model.posY, 0.35, dt * 6.0);
    model.animate(dt, 0.0, true, false, false);
    syncNode();
    _updateCamera(dt);
    if (sleeping <= 0.0) notify('Good morning!');
  }

  void _toggleBoat() {
    if (riding != null) {
      leaveBoat();
      return;
    }
    Boat? best;
    var bestD = 3.0;
    for (final boat in main.boats) {
      final d = (boat.position - position).length;
      if (boat.driver == null && d < bestD) {
        best = boat;
        bestD = d;
      }
    }
    if (best != null) boardBoat(best);
  }

  /// Sit in [b]. A replica (stage 25) is the host's boat: the host is asked to
  /// seat this peer's puppet and the steer input rides in the pose; the seat
  /// follows the streamed pose.
  void boardBoat(Boat b) {
    riding = b;
    Achievements.instance.unlock('sailor');
    if (b.replica) {
      Net.instance.requestBoard(b.netId);
    } else {
      b.driver = this;
    }
    notify('Rowing. [F] to get off');
  }

  void leaveBoat() {
    final b = riding;
    if (b == null) return;
    riding = null;
    if (b.replica) {
      Net.instance.requestUnboard();
    } else {
      b.driver = null;
    }
    b.throttle = 0.0;
    b.steer = 0.0;
    position = b.position + Vector3(-math.sin(yaw + math.pi * 0.5), 0.6, -math.cos(yaw + math.pi * 0.5)) * 1.2; // Godot's offset, to the left
    velocity = Vector3.zero();
  }

  void _rideTick(double dt, GameInput input, bool gameplay) {
    final boat = riding!;
    var inputX = 0.0, inputY = 0.0;
    if (gameplay) {
      inputX = input.moveAxisX();
      inputY = input.moveAxisY();
    }
    // A probe rows forward through probeWalk, as Godot's headless probe does.
    if (_probeWalk.length2 > 0.0) {
      inputX = 0.0;
      inputY = -1.0;
    }
    boat.throttle = -inputY;
    boat.steer = inputX;
    position = boat.seat();
    velocity = boat.velocity.clone();
    model.animate(dt, 0.0, true, false, false);
    model.yaw = lerpAngle(model.yaw, boat.yaw, dt * 8.0);
    model.setHeld(heldItem());
    syncNode();
    _updateCamera(dt);
    _updateAim();
    if (gameplay && input.down(GameAction.attack) && _attackCooldown <= 0.0) _attackPressed();
    world.updateAround(position);
  }

  // --- stage 28: minecarts --------------------------------------------------------

  static const double cartReach = 2.0;

  /// F near a cart: sit in a plain one, open a chest cart's slots. False when
  /// none is in reach.
  bool _toggleCart() {
    Minecart? best;
    var bestD = cartReach;
    for (final c in main.carts) {
      final d = (c.position - position).length;
      if (!c.removed && c.rider == null && d < bestD) {
        best = c;
        bestD = d;
      }
    }
    if (best == null) return false;
    if (best.cargo != null) {
      main.openCartCargo(best);
    } else {
      boardCart(best);
    }
    return true;
  }

  /// Sit in [c]. A replica is the host's cart: the host is asked to seat this
  /// peer's puppet and the push rides in the pose; the seat follows the
  /// streamed pose.
  void boardCart(Minecart c) {
    if (c.cargo != null || riding != null || mount != null) return;
    cart = c;
    if (c.replica) {
      Net.instance.requestCartBoard(c.netId);
    } else {
      c.rider = this;
    }
    c.push = 0.0;
    notify('Riding. [W]/[S] push, [F] to get off');
  }

  void leaveCart() {
    final c = cart;
    if (c == null) return;
    cart = null;
    if (c.replica) {
      Net.instance.requestCartUnboard();
    } else {
      c.rider = null;
    }
    c.push = 0.0;
    position = c.position + Vector3(-math.sin(yaw + math.pi * 0.5), 0.6, -math.cos(yaw + math.pi * 0.5)) * 1.2;
    velocity = Vector3.zero();
  }

  void _cartTick(double dt, GameInput input, bool gameplay) {
    final c = cart!;
    if (c.removed) {
      cart = null;
      return;
    }
    var inputY = 0.0;
    if (gameplay) inputY = input.moveAxisY();
    var push = -inputY;
    if (_probeWalk.length2 > 0.0) {
      // A headless probe pushes along or against the cart's own heading.
      final h = c.heading();
      final dot = _probeWalk.x * h.x + _probeWalk.z * h.z;
      push = dot < 0.0 ? -1.0 : 1.0;
    }
    c.push = push.clamp(-1.0, 1.0);
    position = c.seat();
    velocity = Vector3.zero();
    model.animate(dt, 0.0, true, false, false);
    model.yaw = lerpAngle(model.yaw, c.yaw, dt * 8.0);
    model.setHeld(heldItem());
    syncNode();
    _updateCamera(dt);
    _updateAim();
    if (gameplay && input.down(GameAction.attack) && _attackCooldown <= 0.0) _attackPressed();
    world.updateAround(position);
  }

  /// A melee swing at an empty cart puts it back in the bag as its item.
  bool _tryBreakCart() {
    final within = math.min(4.0, aimClearDistance);
    for (final c in main.carts) {
      if (!c.removed && c.rider == null && (c.position - position).length < 4.0 && c.rayHits(aimOrigin(), aimDirection(), within)) {
        if (c.replica) {
          Net.instance.requestBreakCart(c.netId);
        } else {
          main.breakMinecart(c);
        }
        swingArm();
        Sfx.play('break', -6.0);
        _attackCooldown = 0.4;
        return true;
      }
    }
    return false;
  }

  bool _tryBreakBoat() {
    final b = Reach.nearestBody(main.boats, aimOrigin(), aimDirection(),
        maxDist: 4.0, blockedAt: aimClearDistance, inflate: 0.2, accepts: (boat) => boat.driver == null);
    if (b == null) return false;
    if (b.replica) {
      // The host drops the item and frees it (stage 25).
      Net.instance.requestBreakBoat(b.netId);
    } else {
      main.spawnDrop(b.position + Vector3(0, 0.5, 0), 'boat', 1);
      b.removed = true;
    }
    swingArm();
    Sfx.play('break', -6.0);
    _attackCooldown = 0.4;
    return true;
  }

  void toggleDoor(IVec3 at) {
    var lower = at;
    if (Blocks.idOf(world.getBlock(at + IVec3.down)).startsWith('door_')) lower = at + IVec3.down;
    final id = Blocks.idOf(world.getBlock(lower));
    final flipped = id.endsWith('_open') ? id.substring(0, id.length - 5) : '${id}_open';
    final bid = Blocks.indexOf(flipped);
    if (Blocks.isSolid(bid) && (overlapsBlock(lower) || overlapsBlock(lower + IVec3.up))) return;
    world.setBlock(lower, bid);
    world.setBlock(lower + IVec3.up, bid);
    Sfx.play('door', -6.0);
  }

  /// [base] is "door" or "iron_door" (stage 27); the panel faces the placer.
  bool _placeDoor(IVec3 target, [String base = 'door']) {
    if (!Blocks.isReplaceable(world.getBlock(target + IVec3.up)) || !Blocks.isSolid(world.getBlock(target + IVec3.down))) return false;
    final d = aimDirection();
    final bid = Blocks.indexOf(base + (d.x.abs() > d.z.abs() ? '_x' : '_z'));
    if (overlapsBlock(target) || overlapsBlock(target + IVec3.up)) return false;
    world.setBlock(target, bid);
    world.setBlock(target + IVec3.up, bid);
    return true;
  }

  void _useAbility() {
    if (abilityCooldown > 0.0) {
      notify('${classDef.ability} ready in ${abilityCooldown.round()}s');
      return;
    }
    switch (playerClass) {
      case 'warrior':
        if (!hasStamina(25.0)) {
          notify('Too tired');
          return;
        }
        spendStamina(25.0);
        swingArm();
        final dmg = _meleeDamage(heldItem()) * 1.5;
        for (final b in List.of(main.mobs)) {
          if ((b.position - position).length < 4.0) {
            b.takeDamage(dmg, position, 9.0, this);
            main.spawnDamageNumber(b.centre(), dmg, Vector3(1, 0.5, 0.2));
          }
        }
        main.spawnEffect(centre(), Vector3(1, 0.6, 0.2), 4.0);
        abilityCooldown = 8.0 * (1.0 - 0.2 * talentRank('rage'));
      case 'ranger':
        if (inventory.countOf('arrow') < 8) {
          notify('Need 8 arrows');
          return;
        }
        if (!hasStamina(25.0)) {
          notify('Too tired');
          return;
        }
        inventory.remove('arrow', 8);
        spendStamina(25.0);
        swingArm();
        Sfx.play('shoot', -2.0);
        final bow = weaponStyle() == 'bow' ? heldItem() : 'bow';
        for (var i = 0; i < 8; i++) {
          final dir = _rotated(Vector3(0, 0, -1), Vector3(0, 1, 0), i * math.pi * 2 / 8.0);
          main.spawnProjectile(centre() + dir * 0.6, dir * 30.0 + Vector3(0, 2.0, 0), _rangedDamage(bow, 1.2), this, 'arrow', 0.05, 6.0);
        }
        main.spawnEffect(centre(), Vector3(0.6, 0.9, 0.5), 2.0);
        abilityCooldown = 7.0;
      case 'mage':
        if (!hasMana(30.0)) {
          notify('Not enough mana');
          return;
        }
        spendMana(30.0);
        for (final b in List.of(main.mobs)) {
          if ((b.position - position).length < 6.0) {
            final dmg = 8.0 + level * 2;
            b.takeDamage(dmg, position, 7.0, this);
            main.spawnDamageNumber(b.centre(), dmg, Vector3(1, 0.4, 0.1));
          }
        }
        main.spawnEffect(centre(), Vector3(1, 0.35, 0.1), 6.0);
        abilityCooldown = 10.0;
      case 'rogue':
        if (!hasStamina(20.0)) {
          notify('Too tired');
          return;
        }
        spendStamina(20.0);
        final dir = _lastMoveDir.length > 0.1 ? _lastMoveDir.clone() : forward;
        dir.y = 0.0;
        velocity += dir.normalized() * 22.0;
        velocity.y = 3.0;
        main.spawnEffect(centre(), Vector3(0.4, 0.3, 0.7), 2.0);
        abilityCooldown = 3.0;
    }
  }

  /// Stage 23: one use off the held tool or weapon; at zero it breaks and the
  /// slot empties.
  void _wearHeld() {
    final item = heldItem();
    if (item == '' || Items.durabilityOf(item) <= 0) return;
    if (inventory.wear(selectedSlot)) {
      Sfx.play('break', -2.0, 0.6);
      notify('Your ${Items.displayName(item)} broke!');
    }
  }

  /// Stage 23: the Q ability, one per class, paid in mana (`mana2`, through
  /// `manaCost`).
  void _useAbility2() {
    final c = classDef;
    if (ability2Cooldown > 0.0) {
      notify('${c.ability2} ready in ${ability2Cooldown.round()}s');
      return;
    }
    final cost = manaCost(c.mana2);
    if (!hasMana(cost)) {
      notify('Not enough mana');
      return;
    }
    var fwd = aimDirection().clone()..y = 0.0;
    if (fwd.length < 0.1) {
      fwd = Vector3(-math.sin(yaw), 0, -math.cos(yaw));
    }
    fwd.normalize();
    switch (playerClass) {
      case 'warrior':
        // Shield Bash: a 3 m lunge; every mob in the 3.5 m half-space ahead is
        // struck and stunned.
        velocity += fwd * 12.0;
        velocity.y = math.max(velocity.y, 2.0);
        _lastMoveDir = fwd.clone();
        swingArm();
        final dmg = _meleeDamage(heldItem()) * 0.8;
        for (final b in List.of(main.mobs)) {
          final to = b.position - position;
          if (to.length < 3.5 && to.normalized().dot(fwd) > 0.3) {
            b.takeDamage(dmg, position, 6.0, this);
            b.stun(2.0);
            main.spawnDamageNumber(b.centre(), dmg, Vector3(1, 0.9, 0.4));
          }
        }
        main.spawnEffect(centre() + fwd * 1.5, Vector3(1, 0.9, 0.4), 2.0);
        Sfx.play('hit', -2.0, 0.8);
        ability2Cooldown = 6.0;
      case 'ranger':
        // Volley: five arrows across a 40 degree fan.
        if (inventory.countOf('arrow') < 5) {
          notify('Need 5 arrows');
          return;
        }
        inventory.remove('arrow', 5);
        swingArm();
        Sfx.play('shoot', -2.0);
        final bow = weaponStyle() == 'bow' ? heldItem() : 'bow';
        for (var i = 0; i < 5; i++) {
          main.spawnProjectile(_muzzle(), _fanDirection(i, 5, 40.0 * math.pi / 180.0) * 34.0, _rangedDamage(bow, 0.9), this, 'arrow', 0.05, 5.0);
        }
        ability2Cooldown = 5.0;
      case 'mage':
        // Frost Nova: every mob within 5 m is slowed for 4 s and takes 4.
        for (final b in List.of(main.mobs)) {
          if ((b.position - position).length < 5.0) {
            b.takeDamage(4.0, position, 3.0, this);
            b.slow(4.0);
            main.spawnDamageNumber(b.centre(), 4.0, Vector3(0.5, 0.7, 1.0));
          }
        }
        main.spawnEffect(centre(), Vector3(0.5, 0.75, 1.0), 5.0);
        Sfx.play('bolt', -4.0, 1.4);
        ability2Cooldown = 9.0;
      case 'rogue':
        // Smoke Bomb: 3 s untouchable and swift; every mob within 12 m forgets
        // the player.
        _invulnerable = 3.0;
        effects.apply('speed', 3.0);
        for (final b in main.mobs) {
          if ((b.position - position).length < 12.0) b.loseTarget(3.0);
        }
        main.spawnEffect(centre(), Vector3(0.3, 0.3, 0.35), 4.0);
        Sfx.play('splash', -6.0, 0.6);
        ability2Cooldown = 12.0;
    }
    spendMana(cost);
  }

  /// Probes: fire the R ability with its cooldown cleared.
  void probeAbility() {
    abilityCooldown = 0.0;
    _useAbility();
  }

  /// Probes: fire the Q ability with its cooldown cleared.
  void probeAbility2() {
    ability2Cooldown = 0.0;
    _useAbility2();
  }

  /// Probes: switch class in place (stats to the class maximums, its weapon in
  /// hand).
  void probeSetClass(String cls) {
    final c = classes[cls];
    if (c == null) throw ArgumentError('unknown class $cls');
    playerClass = cls;
    maxHp = c.hp;
    hp = maxHp;
    maxStamina = c.stamina;
    stamina = maxStamina;
    maxMana = c.mana;
    mana = maxMana;
    if (inventory.find(c.weapon) < 0) inventory.add(c.weapon, 1);
    selectedSlot = inventory.find(c.weapon);
  }

  void _mineTick(double dt) {
    if (!isAiming) {
      _resetMining();
      return;
    }
    if (aimedBlock != _mineTarget) {
      _mineTarget = aimedBlock;
      mineProgress = 0.0;
    }
    final id = world.getBlock(aimedBlock);
    var t = Items.mineTime(heldItem(), id);
    if (t > 0.0) t /= effects.mineMultiplier();
    if (t < 0.0) {
      crack.visible = false;
      return;
    }
    mineProgress += dt / t;
    // Stage 32: every 0.35 s of mining swings the held item, chips two cubes of
    // the block's colour off it and plays the family's dig voice.
    _mineFxTimer -= dt;
    if (_mineFxTimer <= 0.0) {
      _mineFxTimer = mineFxPeriod;
      swingArm();
      final c = Blocks.def(id);
      main.spawnDebris(aimedBlock.centre, Vector3(c.r, c.g, c.b), 2, 0.7);
      Sfx.play('place_${Blocks.materialFamily(id)}', -10.0, 0.8);
    }
    _updateCrack(aimedBlock, mineProgress);
    if (mineProgress >= 1.0) {
      _breakBlock(aimedBlock, id);
      _resetMining();
      _attackCooldown = 0.15;
    }
  }

  void _resetMining() {
    mineProgress = 0.0;
    _mineTarget = const IVec3(999999, 0, 0);
    _mineFxTimer = 0.0;
    crack.visible = false;
    for (final l in crackLines) {
      l.visible = false;
    }
  }

  /// Stage 32: four crack stages, each a jagged dark line set over the six faces
  /// of a cube a hair larger than the block; stage k shows the lines of stages
  /// 0..k and the box darkens in four steps. Built once (a line geometry uploads
  /// at construction), then only shown, hidden and moved.
  void _buildCrackStages() {
    final rng = math.Random(32);
    double range(double a, double b) => a + rng.nextDouble() * (b - a);
    Vector3 facePoint(int axis, double side, double u, double v) =>
        axis == 0 ? Vector3(side, u, v) : (axis == 1 ? Vector3(u, side, v) : Vector3(u, v, side));
    final mat = UnlitMaterial()
      ..baseColorFactor = Vector4(0.05, 0.05, 0.05, 0.9)
      ..alphaMode = AlphaMode.blend;
    for (var stage = 0; stage < 4; stage++) {
      for (var face = 0; face < 6; face++) {
        final segs = <double>[];
        final axis = face ~/ 2;
        final side = face % 2 == 0 ? -0.006 : 1.006;
        // Two jagged polylines per face per stage, starting from a random point.
        for (var k = 0; k < 2; k++) {
          var u = rng.nextDouble();
          var v = rng.nextDouble();
          for (var seg = 0; seg < 4; seg++) {
            final nu = (u + range(-0.3, 0.3)).clamp(0.0, 1.0);
            final nv = (v + range(-0.3, 0.3)).clamp(0.0, 1.0);
            final a = facePoint(axis, side, u, v), b = facePoint(axis, side, nu, nv);
            segs.addAll([a.x, a.y, a.z, b.x, b.y, b.z]);
            u = nu;
            v = nv;
          }
        }
        // One node per face: flutter_scene's lines draw over the terrain, so a
        // face turned away from the camera is hidden rather than seen through
        // the block (Godot's depth test does that for free).
        crackLines.add(Node(mesh: Mesh(LineSegmentsGeometry(LineSegmentData(positions: Float32List.fromList(segs)), width: 0.025), mat))
          ..visible = false
          ..castsShadows = false);
      }
    }
  }

  /// Stage 32: the overlay for [progress] (0..1) on [cell]: the box darkens in
  /// four steps and the crack lines of every reached stage show. Returns the box
  /// alpha (the probe's proof).
  double _updateCrack(IVec3 cell, double progress) {
    final stage = crackStage(progress);
    final alpha = crackAlphaFor(progress);
    crack.visible = true;
    crack.position = cell.centre;
    _crackMat.baseColorFactor = Vector4(0, 0, 0, alpha);
    final eye = cameraPosition;
    final lo = [cell.x.toDouble(), cell.y.toDouble(), cell.z.toDouble()];
    final at = [eye.x, eye.y, eye.z];
    for (var i = 0; i < crackLines.length; i++) {
      final face = i % 6, axis = face ~/ 2;
      final facing = face % 2 == 0 ? at[axis] < lo[axis] : at[axis] > lo[axis] + 1.0;
      crackLines[i].visible = i ~/ 6 <= stage && facing;
      crackLines[i].position = cell.toVector3();
    }
    return alpha;
  }

  double crackAlpha() => crack.visible ? _crackMat.baseColorFactor.w : 0.0;

  /// Probe: show the overlay at [progress] on [cell] without holding the button.
  double probeCrack(IVec3 cell, double progress) {
    mineProgress = progress;
    _mineTarget = cell;
    return _updateCrack(cell, progress);
  }

  /// Probe (stage 32): break [cell] the way a finished mine would.
  void probeBreakAt(IVec3 cell) {
    _breakBlock(cell, world.getBlock(cell));
    _resetMining();
  }

  /// Stage 29: the probe breaks a block the way a finished mining swing does.
  void probeBreak(IVec3 b, int id) => _breakBlock(b, id);

  /// Stage 29: an arrival puts the body down; the fall starts there.
  void resetFall() => motor.resetFall();

  void _breakBlock(IVec3 b, int id) {
    // Stage 29: the fortress core only gives way once the Underworld Lord of its fortress is dead.
    if (Blocks.idOf(id) == 'fortress_core' && main.coreLocked(b)) {
      notify('The core is sealed while the Underworld Lord lives');
      return;
    }
    if (!world.setBlock(b, Blocks.air)) return;
    var drop = Blocks.dropOf(id);
    final held = heldItem();
    if (Blocks.toolOf(id) != ToolType.none && Blocks.minTier(id) > 0) {
      final ok = held != '' && Items.toolOf(held) == Blocks.toolOf(id) && Items.tierOf(held) >= Blocks.minTier(id);
      if (!ok) drop = '';
    }
    final rng = main.random;
    if (Blocks.idOf(id) == 'gravel' && rng.nextDouble() < 0.15) drop = 'flint';
    if (Blocks.idOf(id) == 'oak_leaves' && rng.nextDouble() < 0.06) drop = 'apple';
    if (Blocks.idOf(id) == 'tall_grass') {
      drop = rng.nextDouble() < 0.35 ? 'wheat_seeds' : (rng.nextDouble() < 0.15 ? 'string' : '');
    }
    if (Items.isLeaves(id) && held != '' && Items.toolOf(held) == ToolType.shears) drop = Blocks.idOf(id);
    // Stage 26: a melon breaks into several slices; stage 29: glowstone into 2-4 dust.
    if (drop != '') {
      var n = 1;
      if (drop == 'melon_slice') {
        n = 3 + rng.nextInt(3);
      } else if (drop == 'glowstone_dust') {
        n = 2 + rng.nextInt(3);
      }
      main.spawnDrop(b.toVector3() + Vector3(0.5, 0.3, 0.5), drop, n);
    }
    main.onBlockBroken(b, id);
    if (held != '' && Items.kind(held) == ItemKind.tool && Blocks.hardness(id) > 0.0) _wearHeld();
    // Plants above a removed block fall off.
    final above = world.getBlock(b + IVec3.up);
    if (above != Blocks.air && Blocks.isPlant(above)) world.setBlock(b + IVec3.up, Blocks.air);
  }

  void _usePressed() {
    final item = heldItem();
    final style = weaponStyle();
    if (style == 'bow' || style == 'staff') {
      _rangedFire(item, style, true);
      return;
    }
    if (item == 'fishing_rod') {
      _useCooldown = 0.4;
      final b = bobber;
      if (b != null) {
        if (b.isBiting) {
          catchFish();
        } else {
          reelIn(true);
        }
        return;
      }
      final water = liquidRaycast(aimOrigin(), aimDirection(), fishingReach);
      if (water == null) {
        notify('Cast at water');
      } else {
        castFishing(water);
      }
      return;
    }
    final mob = aimedMob;
    if (mob != null && item != '') {
      if (!mob.tamed && mob.species.tameWith.contains(item)) {
        inventory.takeFromSlot(selectedSlot, 1);
        if (main.random.nextDouble() < mob.species.tameChance) {
          mob.tame(this);
          main.spawnEffect(mob.centre(), Vector3(1, 0.7, 0.9), 1.5);
        } else {
          notify('The ${mob.species.name.toLowerCase()} sniffs the ${Items.displayName(item).toLowerCase()}...');
        }
        _useCooldown = 0.5;
        return;
      }
      if (item == 'shears' && mob.species.id == 'sheep' && !mob.sheared) {
        shearMob(mob);
        _useCooldown = 0.4;
        return;
      }
      if (item == 'bucket' && mob.species.id == 'cow') {
        inventory.setSlot(selectedSlot, ItemStack('milk_bucket', 1));
        notify('Milked the cow');
        Sfx.play('splash', -12.0, 1.3);
        _useCooldown = 0.5;
        return;
      }
    }
    if (item == 'bucket') {
      final cell = liquidRaycast(aimOrigin(), aimDirection(), reach);
      if (cell != null && scoopLiquid(cell)) {
        _useCooldown = 0.4;
        return;
      }
    }
    if (item == 'flint_and_steel' && isAiming) {
      // Stage 29: lights the hollow of an obsidian frame into a portal (or nothing happens).
      _useCooldown = 0.5;
      final lit = main.tryLightPortal(aimedBlock + aimedNormal);
      if (lit > 0) {
        swingArm();
        Sfx.play('bolt', -6.0, 1.4);
      } else {
        notify('Aim inside an obsidian frame (4 wide, 5 tall)');
      }
      return;
    }
    if (item != '' && Items.liquidOf(item) != '' && isAiming) {
      if (pourLiquid(aimedBlock + aimedNormal)) _useCooldown = 0.4;
      return;
    }
    if (isAiming) {
      final targetId = world.getBlock(aimedBlock);
      final tid = Blocks.idOf(targetId);
      if (tid == 'tnt') {
        main.igniteTnt(aimedBlock);
        _useCooldown = 0.5;
        return;
      }
      if (tid == 'bed') {
        main.sleepInBed(aimedBlock);
        _useCooldown = 0.6;
        return;
      }
      if (tid.startsWith('door_')) {
        toggleDoor(aimedBlock);
        _useCooldown = 0.35;
        return;
      }
      if (tid.startsWith('lever_') || tid.startsWith('button')) {
        // Stage 27: the flip is a block edit; the host's circuit tick does the rest.
        if (world.circuits.useBlock(aimedBlock)) Sfx.play('click', -4.0, 0.8);
        _useCooldown = 0.35;
        return;
      }
      if (tid == 'enchanting_table') {
        main.enchantHeld();
        _useCooldown = 0.5;
        return;
      }
      if (tid == 'wheat_2') {
        world.setBlock(aimedBlock, Blocks.air);
        final rng = main.random;
        main.spawnDrop(aimedBlock.toVector3() + Vector3(0.5, 0.3, 0.5), 'wheat', 1 + rng.nextInt(3));
        main.spawnDrop(aimedBlock.toVector3() + Vector3(0.5, 0.3, 0.5), 'wheat_seeds', 1 + rng.nextInt(2));
        _useCooldown = 0.3;
        return;
      }
      if (item != '' && Items.toolOf(item) == ToolType.hoe && (tid == 'dirt' || tid == 'grass') && aimedNormal == IVec3.up) {
        world.setBlock(aimedBlock, Blocks.indexOf('farmland'));
        Sfx.play('dig', -8.0);
        _useCooldown = 0.3;
        return;
      }
      if (item == 'wheat_seeds' && tid == 'farmland' && aimedNormal == IVec3.up && world.getBlock(aimedBlock + IVec3.up) == Blocks.air) {
        world.setBlock(aimedBlock + IVec3.up, Blocks.indexOf('wheat_0'));
        main.plantCrop(aimedBlock + IVec3.up);
        _consumeHeld();
        Sfx.play('place', -10.0);
        _useCooldown = 0.3;
        return;
      }
      if (tid == 'waypoint') {
        main.openJournal(3);
        _useCooldown = 0.5;
        return;
      }
      if (tid == 'crafting_table' || tid == 'furnace' || tid == 'chest' || tid == 'brewing_stand') {
        main.openStation(tid, aimedBlock);
        _useCooldown = 0.4;
        return;
      }
    }
    if (item == '') return;
    if (Items.kind(item) == ItemKind.food) {
      _eatHeld();
      _useCooldown = 0.5;
      return;
    }
    if (item == 'minecart' || item == 'chest_minecart') {
      // Stage 28: a cart goes on the rail the player aims at.
      _useCooldown = 0.5;
      if (isAiming && Rails.isRailAt(world, aimedBlock)) {
        main.spawnMinecart(aimedBlock, item);
        _consumeHeld();
        return;
      }
      notify('Minecarts go on rails');
      return;
    }
    if (item == 'boat') {
      _useCooldown = 0.5;
      final spot = aimOrigin() + aimDirection() * 3.0;
      final cell = IVec3.floor(spot);
      for (var dy = 0; dy < 3; dy++) {
        final c = cell + IVec3(0, -dy, 0);
        if (world.isLiquid(c)) {
          main.spawnBoat(c.toVector3() + Vector3(0.5, 0.9, 0.5), yaw);
          _consumeHeld();
          return;
        }
      }
      notify('Boats go on water');
      return;
    }
    if (Items.isBlock(item) && isAiming) {
      final target = aimedBlock + aimedNormal;
      final current = world.getBlock(target);
      if (!Blocks.isReplaceable(current)) return;
      var bid = Items.blockOf(item);
      if (item == 'torch' && aimedNormal.y == 0 && !Blocks.isSolid(world.getBlock(target + IVec3.down))) {
        bid = Blocks.indexOf('wall_torch');
      }
      if (item == 'door' || item == 'iron_door') {
        if (_placeDoor(target, item)) {
          _consumeHeld();
          swingArm();
          Sfx.play('place', -10.0);
          _useCooldown = 0.3;
        }
        return;
      }
      if (Blocks.isStairs(bid)) {
        final f = flatForward;
        bid = Blocks.stairsFacing(bid, f.x, f.z);
      } else if (Blocks.isPiston(bid)) {
        final f = flatForward;
        bid = Blocks.pistonFacing(bid, f.x, f.z); // stage 27: pushes the way the placer looks
      }
      if (Blocks.isSolid(bid) && overlapsBlock(target)) return;
      for (final mob in main.mobs) {
        if (Blocks.isSolid(bid) && mob.overlapsBlock(target)) return;
      }
      if ((Blocks.isPlant(bid) || Blocks.isWire(bid) || Blocks.isRail(bid)) && !Blocks.isSolid(world.getBlock(target + IVec3.down))) {
        return;
      }
      if (Blocks.isRail(bid)) {
        // Stage 28: the rail takes its orientation from its neighbours and turns them to meet it.
        bid = Rails.place(world, target, bid);
        _consumeHeld();
        swingArm();
        main.onBlockPlaced(target, bid);
        _useCooldown = 0.22;
        return;
      }
      if (world.setBlock(target, bid)) {
        _consumeHeld();
        swingArm();
        main.onBlockPlaced(target, bid);
        _useCooldown = 0.22;
      }
    }
  }

  void _eatHeld() {
    final item = heldItem();
    if (item == '' || Items.kind(item) != ItemKind.food) return;
    final d = Items.def(item);
    if (d.effect != '') {
      inventory.takeFromSlot(selectedSlot, 1);
      drink(d.effect, d.seconds);
      if (d.heal > 0.0) hp = (hp + d.heal).clamp(1.0, maxHp);
      if (d.container != '' && inventory.add(d.container, 1) > 0) {
        main.spawnDrop(centre(), d.container, 1);
      }
      notify('Drank ${d.name}');
      Tutorial.instance.event('eat');
      Sfx.play('eat', -6.0);
      Achievements.instance.unlock('brewer');
      return;
    }
    if (hunger >= 20.0 && d.heal <= 0.0) {
      notify('Not hungry');
      return;
    }
    inventory.takeFromSlot(selectedSlot, 1);
    hunger = math.min(hunger + d.hunger, 20.0);
    hp = (hp + d.heal).clamp(1.0, maxHp);
    if (d.hunger >= 5) effects.apply('well_fed', 20.0);
    Sfx.play('eat', -6.0);
    notify('Ate ${d.name}');
    Tutorial.instance.event('eat');
  }

  void _dropHeld() {
    final stack = inventory.takeFromSlot(selectedSlot, 1);
    if (stack == null) return;
    final dir = forward;
    main.spawnDrop(position + Vector3(0, 1.4, 0) + dir * 0.6, stack.id, stack.count, dir * 6.0 + Vector3(0, 2, 0), 1.5);
  }

  /// The local player is never a peer's puppet.
  @override
  int get peerId => 0;

  @override
  void takeDamage(double amount, String source, [Vector3? from]) {
    if (isDead || amount <= 0.0 || GameState.instance.creative) return; // stage 30: a creative body is never hurt
    // An effect's own tick always lands: dodging out of poison would be free.
    final isTick = StatusEffects.defs.containsKey(source);
    if (_invulnerable > 0.0 && !isTick && source != 'starving') return;
    final totalArmor = armor + effects.armorBonus() + talentRank('toughness');
    final reduced = isTick ? amount : math.max(amount - totalArmor * 0.4, amount * 0.35);
    hp -= reduced;
    damageFlash = 1.0;
    Sfx.play('hurt', -3.0);
    main.spawnDamageNumber(centre() + Vector3(0, 0.6, 0), reduced,
        isTick ? StatusEffects.def(source).color : Vector3(1, 0.3, 0.3));
    if (!isTick) {
      // Stage 32: the hit is felt: camera shake by damage, a 100 ms white flash,
      // a 60 ms hold of the pose, and the HUD's red vignette.
      _shakeTime = shakeSeconds;
      _shakeAmp = math.min(reduced / 10.0, 0.3);
      motor.stagger = Mob.staggerSeconds;
      model.flash(0.1);
      model.freeze(0.06);
      main.hud.onPlayerHurt();
    }
    if (from != null) {
      final push = position - from;
      push.y = 0.0;
      if (push.length2 > 0) push.normalize();
      velocity += push * Mob.knockbackSpeed + Vector3(0, Mob.knockbackUp, 0);
    }
    if (hp <= 0.0) {
      hp = 0.0;
      isDead = true;
      main.onPlayerDied();
    }
  }

  void gainXp(int amount) {
    xp += amount;
    var need = xpToNext();
    while (xp >= need) {
      xp -= need;
      level += 1;
      maxHp += 3.0;
      hp = maxHp;
      maxStamina += 5.0;
      maxMana += 5.0;
      talentPoints += 1;
      notify('Level $level! Talent point earned (J)');
      final ach = Achievements.instance;
      if (level >= 5) ach.unlock('level_5');
      if (level >= 10) ach.unlock('level_10');
      Sfx.play('levelup');
      main.quests.onLevel(level);
      main.spawnEffect(centre(), Vector3(1, 0.9, 0.3), 3.0);
      need = xpToNext();
    }
  }

  int xpToNext() => (40.0 * math.pow(level.toDouble(), 1.45)).toInt();

  void respawn() {
    isDead = false;
    if (mount != null) dismount();
    if (cart != null) leaveCart();
    hp = maxHp;
    hunger = 20.0;
    stamina = maxStamina;
    mana = maxMana;
    effects.rows.clear();
    velocity = Vector3.zero();
    position = spawnPoint.clone();
    syncNode();
  }

  Map<String, Object> toJson() => {
        'pos': [position.x, position.y, position.z],
        'yaw': yaw,
        'pitch': pitch,
        'class': playerClass,
        'hp': hp,
        'max_hp': maxHp,
        'stamina': stamina,
        'max_stamina': maxStamina,
        'mana': mana,
        'max_mana': maxMana,
        'hunger': hunger,
        'xp': xp,
        'level': level,
        'inventory': inventory.toJson(),
        'slot': selectedSlot,
        'first_person': firstPerson,
        'spawn': [spawnPoint.x, spawnPoint.y, spawnPoint.z],
        'effects': effects.toJson(),
        'talent_points': talentPoints,
        'talents': talents,
      };

  void fromJson(Map<String, dynamic> d) {
    final p = (d['pos'] as List<dynamic>).map((e) => (e as num).toDouble()).toList();
    position = Vector3(p[0], p[1], p[2]);
    yaw = (d['yaw'] as num?)?.toDouble() ?? 0.0;
    pitch = (d['pitch'] as num?)?.toDouble() ?? -0.3;
    hp = (d['hp'] as num?)?.toDouble() ?? maxHp;
    maxHp = (d['max_hp'] as num?)?.toDouble() ?? maxHp;
    stamina = (d['stamina'] as num?)?.toDouble() ?? maxStamina;
    maxStamina = (d['max_stamina'] as num?)?.toDouble() ?? maxStamina;
    mana = (d['mana'] as num?)?.toDouble() ?? maxMana;
    maxMana = (d['max_mana'] as num?)?.toDouble() ?? maxMana;
    hunger = (d['hunger'] as num?)?.toDouble() ?? 20.0;
    xp = (d['xp'] as num?)?.toInt() ?? 0;
    level = (d['level'] as num?)?.toInt() ?? 1;
    inventory.fromJson(d['inventory'] as List<dynamic>? ?? const []);
    selectedSlot = (d['slot'] as num?)?.toInt() ?? 0;
    setFirstPerson(d['first_person'] == true);
    final s = (d['spawn'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? p;
    spawnPoint = Vector3(s[0], s[1], s[2]);
    effects.fromJson(d['effects'] as Map<String, dynamic>? ?? const {});
    talentPoints = (d['talent_points'] as num?)?.toInt() ?? 0;
    talents.clear();
    for (final e in (d['talents'] as Map<String, dynamic>? ?? const {}).entries) {
      talents[e.key] = (e.value as num).toInt();
    }
    syncNode();
  }

  // --- stage 20: mounts, fishing, shears, buckets -----------------------------------

  static const double fishingReach = 8.0;
  static const double mountReach = 3.5;
  /// How far the rider's feet sit below the mount's back. The model's hips are
  /// 0.66 up from its feet, so a shade more than that buries the legs in the
  /// barrel and leaves the torso above the saddle — a Minecraft rider straddles
  /// a horse, it does not stand on one.
  static const double saddleSink = 0.72;

  /// Where a rider's feet go on [h].
  static Vector3 saddlePosition(Mob h) => h.position + Vector3(0, h.backHeight - saddleSink, 0);

  /// F: leave what is ridden, else mount the tamed horse in front, else board
  /// or leave a boat.
  void _interactPressed() {
    if (mount != null) {
      dismount();
      return;
    }
    if (riding != null) {
      _toggleBoat();
      return;
    }
    if (cart != null) {
      leaveCart();
      return;
    }
    final horse = _findMount();
    if (horse != null) {
      mountHorse(horse);
      return;
    }
    final m = aimedMob;
    if (m != null && m.isMount && !m.tamed) {
      notify('This ${m.species.name.toLowerCase()} is wild. Tame it with wheat or an apple');
      return;
    }
    if (_toggleCart()) return;
    _toggleBoat();
  }

  /// The nearest tamed, unridden mount the camera ray touches within
  /// [mountReach].
  Mob? _findMount() => Reach.nearestBody(main.pets, aimOrigin(), aimDirection(),
      maxDist: mountReach,
      blockedAt: aimClearDistance,
      inflate: 0.4,
      accepts: (m) => m.isMount && m.tamed && !m.ridden && !m.isDead);

  void mountHorse(Mob h) {
    if (!h.tamed || !h.isMount) throw StateError('only a tamed mount can be ridden');
    if (mount != null || riding != null) return;
    mount = h;
    h.ridden = true;
    h.riddenBy = 1;
    h.rideInput = Vector3.zero();
    velocity = Vector3.zero();
    // The host's horse carries the rider (stage 21b).
    if (Net.instance.isClient) Net.instance.requestMount(h.netId);
    _resetMining();
    notify('Riding. [F] to get off');
    Achievements.instance.unlock('rider');
  }

  void dismount() {
    final h = mount;
    if (h == null) return;
    mount = null;
    h.ridden = false;
    h.riddenBy = 0;
    h.rideInput = Vector3.zero();
    h.rideSprint = false;
    if (Net.instance.isClient) Net.instance.requestDismount();
    if (!h.removed) {
      position = h.position + Vector3(-math.sin(yaw + math.pi * 0.5), 0.3, -math.cos(yaw + math.pi * 0.5)) * 1.2;
    }
    velocity = Vector3.zero();
    motor.resetFall();
  }

  bool isMounted() => mount != null;

  /// Mounted: the rider's wish goes to the horse, the rider sits on its back
  /// and the camera follows.
  void _mountTick(double dt, GameInput input, bool gameplay) {
    final h = mount!;
    if (h.removed || h.isDead) {
      dismount();
      return;
    }
    var inputX = 0.0, inputY = 0.0;
    if (gameplay) {
      inputX = input.moveAxisX();
      inputY = input.moveAxisY();
    }
    var wish = flatForward * -inputY + rightVec * inputX;
    // A headless probe steers the mount the way it rows a boat.
    if (_probeWalk.length2 > 0.0) wish = _probeWalk.clone();
    if (wish.length > 1.0) wish = wish.normalized();
    h.rideInput = wish;
    final forward = inputY < 0.0 || _probeWalk.length2 > 0.0;
    h.rideSprint = gameplay && input.down(GameAction.sprint) && forward;
    if (gameplay && input.down(GameAction.jump)) h.rideJump = true;
    position = saddlePosition(h);
    velocity = h.velocity.clone();
    motor.resetFall();
    model.animate(dt, 0.0, true, false, false);
    model.yaw = lerpAngle(model.yaw, h.modelYaw(), dt * 8.0);
    model.setHeld(heldItem());
    // A rider works the world from the saddle exactly as on foot: the same
    // aim, the same swing, the same mining, the same placing.
    _finishTick(dt, input, gameplay, flatForward, wish, h.rideSprint);
  }

  /// Holding the use button repeats a placement; the rod and the buckets act
  /// once per press.
  bool _useRepeats() {
    final item = heldItem();
    return item != 'fishing_rod' && item != 'bucket' && (item == '' || Items.liquidOf(item) == '');
  }

  /// The first liquid cell along a ray, stopping at the first solid; null when
  /// there is none.
  IVec3? liquidRaycast(Vector3 origin, Vector3 direction, double reachDist) =>
      VoxelRaycast.liquid(world, origin, direction, reachDist);

  /// Cast the line at a water cell: the bobber flies there and waits for a bite.
  void castFishing(IVec3 cell) {
    if (!world.isLiquid(cell)) throw ArgumentError('a line is cast at water');
    if (bobber != null) reelIn(false);
    final b = Bobber(world, this, model.handWorldPosition(), cell);
    bobber = b;
    main.entities.add(b.node);
    main.entities.add(b.lineNode);
    swingArm();
    Sfx.play('swing', -12.0, 1.3);
  }

  void reelIn(bool say) {
    final b = bobber;
    if (b == null) return;
    main.entities.remove(b.node);
    main.entities.remove(b.lineNode);
    bobber = null;
    if (say) notify('Reeled in');
  }

  /// The line is dropped when the rod leaves the hand or the bobber is left
  /// too far behind.
  void _tendBobber() {
    final b = bobber;
    if (b == null) return;
    if (heldItem() != 'fishing_rod' || (b.position - position).length > fishingReach * 2.0) {
      reelIn(false);
    }
  }

  /// A bite answered in time: 70% fish, 10% salmon, 15% junk, 5% treasure.
  /// Returns the item id.
  String catchFish() {
    final b = bobber;
    if (b == null || !b.isBiting) throw StateError('catchFish needs a biting bobber');
    final rng = main.random;
    final roll = rng.nextDouble();
    String got;
    Loot? loot;
    if (roll < 0.70) {
      got = 'raw_fish';
    } else if (roll < 0.80) {
      got = 'raw_salmon';
    } else if (roll < 0.95) {
      got = const ['stick', 'bone', 'leather'][rng.nextInt(3)];
    } else {
      final treasure = rng.nextDouble();
      if (treasure < 0.4) {
        got = 'magic_dust';
      } else if (treasure < 0.8) {
        got = 'gem_shard';
      } else {
        loot = main.randomLootWeapon(rng, 2);
        got = loot.id;
      }
      notify('Treasure!');
    }
    if (loot == null) {
      if (pickUp(got, 1) > 0) main.spawnDrop(centre(), got, 1);
    } else if (!inventory.addStack(ItemStack(loot.id, 1, bonus: loot.bonus))) {
      main.spawnDrop(centre(), got, 1);
    }
    main.spawnEffect(b.position, Vector3(0.5, 0.75, 1.0), 1.0);
    Sfx.play('splash', -6.0, 1.2);
    swingArm();
    gainXp(2);
    Achievements.instance.unlock('fisher');
    reelIn(false);
    return got;
  }

  /// Shears on a sheep: 1..3 wool drops beside it. Returns the number dropped.
  int shearMob(Mob m) {
    final n = m.shear();
    main.spawnDrop(m.centre(), 'wool', n, Vector3.zero(), 0.0);
    Sfx.play('dig', -6.0);
    swingArm();
    return n;
  }

  /// An empty bucket over a liquid SOURCE: the cell empties and the bucket
  /// fills with it. A flowing cell gives nothing; the puddle it belonged to
  /// drains once its source is gone.
  bool scoopLiquid(IVec3 cell) {
    final id = world.getBlock(cell);
    if (!Blocks.isLiquidSource(id) || heldItem() != 'bucket') return false;
    if (!world.setBlock(cell, Blocks.air)) return false;
    inventory.setSlot(selectedSlot, ItemStack('${Blocks.liquidKind(id)}_bucket', 1));
    Sfx.play('splash', -10.0);
    swingArm();
    return true;
  }

  /// A filled bucket at a replaceable cell: a source goes there (the world's
  /// flow spreads it) and the empty bucket comes back.
  bool pourLiquid(IVec3 target) {
    final liquid = Items.liquidOf(heldItem());
    if (liquid == '' || !Blocks.isReplaceable(world.getBlock(target))) return false;
    if (liquid == 'water' && world.dimension == VoxelWorld.dimUnderworld) {
      // Stage 29: there is no water in the underworld; the bucket empties into steam.
      inventory.setSlot(selectedSlot, ItemStack('bucket', 1));
      main.spawnEffect(target.toVector3() + Vector3(0.5, 0.5, 0.5), Vector3(0.8, 0.8, 0.85), 1.2);
      Sfx.play('splash', -10.0, 1.6);
      notify('The water hisses away');
      swingArm();
      return true;
    }
    if (!world.setBlock(target, Blocks.indexOf(liquid))) return false;
    inventory.setSlot(selectedSlot, ItemStack('bucket', 1));
    Sfx.play('splash', -10.0, 0.8);
    swingArm();
    return true;
  }

  // --- stage 18: effects, talents, dodge -------------------------------------------

  static const double dodgeTime = 0.4;

  /// The dash leaves the ground a little: at 4 m/s up it clears about 0.3 m.
  static const double dashHop = 4.0;

  int talentRank(String id) => talents[id] ?? 0;

  bool learnTalent(String id) {
    if (talentPoints <= 0 || talentRank(id) >= Talents.maxRank) return false;
    talentPoints -= 1;
    talents[id] = talentRank(id) + 1;
    if (id == 'vitality') {
      maxHp += 4.0;
      hp += 4.0;
    }
    notify('Learned ${id[0].toUpperCase()}${id.substring(1)} ${talents[id]}');
    Achievements.instance.unlock('talent');
    return true;
  }

  double damageMultiplier() => effects.damageMultiplier() * (1.0 + 0.08 * talentRank('might'));

  double manaCost(double base) => base * (1.0 - 0.15 * talentRank('focus'));

  /// Drink a potion effect: "cure" clears every bad effect, anything else
  /// applies for [seconds].
  void drink(String effect, double seconds) {
    if (effect == 'cure') {
      final n = effects.clearBad();
      notify('Cured $n ailment${n == 1 ? '' : 's'}');
      return;
    }
    effects.apply(effect, seconds);
    main.spawnEffect(centre(), StatusEffects.def(effect).color, 1.2);
  }

  void applyEffect(String id, double seconds, [double power = 1.0]) {
    if (isDead) return;
    final fresh = !effects.has(id);
    effects.apply(id, seconds, power);
    if (fresh) notify('${StatusEffects.def(id).name}!');
  }

  void _dodgePressed() {
    final cost = math.max(15.0 - 5.0 * talentRank('shadowstep'), 0.0);
    if (_dodge > 0.0 || _dodgeCd > 0.0 || !hasStamina(cost) || riding != null || mount != null || cart != null || sleeping > 0.0 || inLiquid) {
      return;
    }
    spendStamina(cost);
    _dodge = dodgeTime;
    _dodgeCd = 0.9;
    _invulnerable = dodgeTime;
    // Where the player is walking, backward included; standing, where the body faces.
    final dir = _moveWish.length > 0.1 ? _moveWish : _lastMoveDir;
    _dodgeDir = dir.length > 0.1 ? dir.normalized() : flatForward;
    if (onFloor) velocity.y = dashHop;
    Sfx.play('swing', -8.0, 0.7);
  }

  void probeDodge() => _dodgePressed();

  /// Stage 28: the F key's action, for a probe.
  void probeInteract() => _interactPressed();

  Vector3 _probeWalk = Vector3.zero();

  /// A probe's walk input: a world-space direction held until zero is handed back.
  void probeWalk(Vector3 dir) => _probeWalk = dir.clone();

  /// Stage 30 probe: the jump the Space key would give.
  void probeJump() => _jump();

  void _jump() {
    motor.jump();
    Tutorial.instance.event('jump');
  }

  /// Stage 30: what a placed block costs — nothing in creative.
  void _consumeHeld() {
    if (!GameState.instance.creative) inventory.takeFromSlot(selectedSlot, 1);
  }

  /// One crafting click (the inventory screen's, or the probe's): the recipe
  /// applied to the bag, the quest, the achievement counter and the tutorial told.
  bool craft(Recipe r) {
    if (!Recipes.craft(r, inventory)) return false;
    notify('Crafted ${Items.displayName(r.result)}');
    main.quests.onCraft(r.result, r.count);
    Achievements.instance.onCrafted();
    if (Items.kind(r.result) == ItemKind.tool) Tutorial.instance.event('craft');
    return true;
  }

  bool isDodging() => _dodge > 0.0;

  bool get invulnerable => _invulnerable > 0.0;
}
