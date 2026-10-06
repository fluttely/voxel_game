import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

import '../playground/playground.dart';
import 'ability.dart';
import 'class_table.dart';
import 'player_class.dart';
import 'talent.dart';

/// The player's class at play (`VoxelGame.options['class']`, its player
/// made by `classPlayer`): stamina and mana, the abilities and their
/// cooldowns, the dodge, and the talents a level buys.
///
/// - Stamina pays for a sprint ([sprintCost] a second; none left, a sprint
///   veto), a bow's draw, the dodge and some abilities; it comes back at
///   [staminaBack] a second while the sprint is let go. Mana pays for a staff's
///   bolt and the other abilities, back at [manaBack]. Each level adds
///   [PlayerClass.perLevel] to both; a respawn fills them.
/// - The class's abilities are cast by their actions (R, F): on cooldown, or
///   short of what they cost, the player is told so and nothing is spent.
/// - The dodge (Alt) dashes [dodgeSpeed] toward the walk (the look, standing)
///   for [dodgeSeconds], untouchable, once every [dodgeEvery].
/// - A level is worth a talent point ([points]), spent in the journal
///   ([learn]); every blow is the class's `PlayerClass.damage` times
///   [levelDamage] more a level, through a `Boost` with the talents'.
///
/// In a playground nothing runs out ([endless]): every cost is covered and
/// none is paid.
///
/// Its numbers are saved with the world (under `class`); the class itself is
/// the world's option, and the cooldowns start over.
class ClassSystem extends SavedSystem {
  /// Stamina a second of sprinting costs.
  static const double sprintCost = 6.0;

  /// Stamina back a second while not sprinting, before the talents.
  static const double staminaBack = 14.0;

  /// Mana back a second, before the talents.
  static const double manaBack = 2.5;

  /// What a sprint needs left to go on.
  static const double sprintFloor = 1.0;

  /// Stamina a dodge costs, before the talents.
  static const double dodgeCost = 15.0;

  /// Seconds a dodge dashes, untouchable.
  static const double dodgeSeconds = 0.4;

  /// Seconds from one dodge to the next.
  static const double dodgeEvery = 0.9;

  /// Metres a second a dodge dashes.
  static const double dodgeSpeed = 13.0;

  /// How fast a dodge off the floor leaves it: it clears about 0.3 m.
  static const double dodgeHop = 4.0;

  /// The share each level adds to the damage of a blow.
  static const double levelDamage = 0.08;

  /// The key of its numbers in the save.
  static const String key = 'class';

  /// The class system of [game], its class taken from the game's options
  /// the first time it is asked: what the HUD and the journal read, which
  /// may draw before the game's first step.
  static ClassSystem of(VoxelGame game) => game.system<ClassSystem>().._begin(game);

  VoxelGame? _game;
  PlayerClass? _class;

  /// Stamina now.
  double stamina = 0.0;

  /// Mana now.
  double mana = 0.0;

  /// Talent points not spent.
  int points = 0;

  /// The talents learned, by id, to their rank.
  final Map<String, int> ranks = {};

  final Map<String, double> _cooldowns = {};
  double _dodgeLeft = 0.0;
  double _dodgeAgain = 0.0;
  bool _dead = false;

  /// The class played; throws before the game has started it ([of], or its
  /// first step).
  PlayerClass get playerClass => _class ?? (throw StateError('the class is taken from the game, by of()'));

  VoxelGame get _played => _game ?? (throw StateError('no game yet'));

  /// The most stamina at the player's level.
  double get maxStamina => playerClass.stamina + PlayerClass.perLevel * _played.player.level;

  /// The most mana at the player's level.
  double get maxMana => playerClass.mana + PlayerClass.perLevel * _played.player.level;

  /// How full the stamina is, 0..1.
  double get staminaShare => stamina / maxStamina;

  /// How full the mana is, 0..1.
  double get manaShare => mana / maxMana;

  /// Seconds before the ability of [action] can be cast again; 0 when ready.
  double cooldownOf(String action) => _cooldowns[action] ?? 0.0;

  /// Whether a dodge dashes now.
  bool get dodging => _dodgeLeft > 0.0;

  /// The talents the class may learn: the six of every class, then its own.
  List<Talent> get talents => talentsOf(playerClass);

  /// The rank of the talent [id], 0 when not learned.
  int rank(String id) => ranks[id] ?? 0;

  /// Whether nothing runs out: in a playground (`Playground.isOn`).
  bool get endless => _endless;
  bool _endless = false;

  /// Starts the player of [game] at [level] with [points] to spend, full:
  /// a fresh playground's showcase.
  void startAt(VoxelGame game, {required int level, required int points}) {
    _begin(game);
    game.player.level = level;
    this.points = points;
    _boost();
    stamina = maxStamina;
    mana = maxMana;
  }

  /// What [base] mana comes to with the talents.
  double manaCost(double base) => base * math.max(1.0 - _sum((t) => t.manaCost), 0.0);

  /// Learns a rank of the talent [id] for a point: false, and nothing
  /// spent, with no point or the talent at its most.
  bool learn(String id) {
    final talent = talents.firstWhere((t) => t.id == id);
    if (points <= 0 || rank(id) >= Talent.maxRank) return false;
    points -= 1;
    ranks[id] = rank(id) + 1;
    _boost();
    final p = _played.player;
    p.hp = math.min(p.hp + talent.maxHp, p.maxHp);
    _played.notify('Learned ${talent.name} ${ranks[id]}');
    _played.playSound('levelup', volumeDb: -6.0);
    return true;
  }

  /// The damage of a swing of what the player holds, before a critical roll
  /// and the filters: its weapon's or the hand's, its bonus, times the
  /// player's multiplier (the class's, the level's, the talents').
  double meleeDamage(VoxelGame game) {
    final p = game.player;
    final held = p.heldItem.isEmpty ? null : game.items[p.heldItem];
    final base =
        (held == null || held.tool == null ? p.spec.handDamage : held.damage.toDouble()) +
        p.inventory.bonusAt(p.selectedSlot);
    return base * p.damageMultiplier;
  }

  /// The creatures alive within [radius] metres of the player.
  Iterable<Mob> mobsNear(VoxelGame game, double radius) =>
      game.mobs.where((m) => !m.removed && !m.isDead && m.position.distanceTo(game.player.position) < radius);

  /// Hits [mob] with a blow of the player's of [amount], through their
  /// damage filters, pushing it [knockback] away.
  void strike(VoxelGame game, Mob mob, double amount, {required double knockback}) {
    final p = game.player;
    mob.takeDamage(Damage(p.dealtTo(mob, amount), from: p.position, knockback: knockback, attacker: p));
  }

  @override
  void tick(VoxelGame game, double dt) {
    _begin(game);
    final p = game.player;
    for (final action in _cooldowns.keys.toList()) {
      _cooldowns[action] = math.max(_cooldowns[action]! - dt, 0.0);
    }
    _dodgeLeft = math.max(_dodgeLeft - dt, 0.0);
    _dodgeAgain = math.max(_dodgeAgain - dt, 0.0);
    if (p.isDead) {
      _dead = true;
      return;
    }
    if (_dead) {
      _dead = false;
      stamina = maxStamina;
      mana = maxMana;
    }
    if (p.sprinting && !_endless) stamina = math.max(stamina - sprintCost * dt, 0.0);
    if (!(game.gameplay && game.input.down(VoxelAction.sprint))) {
      stamina = math.min(stamina + staminaBack * (1.0 + _sum((t) => t.staminaRegen)) * dt, maxStamina);
    }
    mana = math.min(mana + manaBack * (1.0 + _sum((t) => t.manaRegen)) * dt, maxMana);
    if (!game.gameplay || game.screen.value != null) return;
    for (final MapEntry(key: action, value: ability) in playerClass.abilities.entries) {
      if (game.actions.justPressed(action)) _cast(game, action, ability);
    }
    if (game.actions.justPressed('dodge')) _dodge(game);
  }

  @override
  void onEvent(VoxelGame game, GameEvent event) {
    _begin(game);
    switch (event) {
      case LevelGained(:final level):
        points += 1;
        _boost();
        game.notify('Level $level! Talent point earned (J)');
      case ShotFired(:final launcher):
        final cost = shotCosts[launcher.id];
        if (cost == null || _endless) return;
        stamina = math.max(stamina - cost.stamina, 0.0);
        mana = math.max(mana - manaCost(cost.mana), 0.0);
      default:
    }
  }

  @override
  String get saveKey => key;

  @override
  Object? save(VoxelGame game) => {'stamina': stamina, 'mana': mana, 'points': points, 'talents': ranks};

  @override
  void restore(VoxelGame game, Object? saved) {
    _begin(game);
    final row = saved! as Map<String, Object?>;
    stamina = (row['stamina']! as num).toDouble();
    mana = (row['mana']! as num).toDouble();
    points = row['points']! as int;
    ranks
      ..clear()
      ..addAll((row['talents']! as Map<String, Object?>).map((id, r) => MapEntry(id, r! as int)));
    for (final id in ranks.keys) {
      if (!talents.any((t) => t.id == id)) throw FormatException('the ${playerClass.name} has no talent $id');
    }
    _boost();
  }

  // The class taken from the game's options, full, and its say on the
  // player's sprint, shots and blows; once.
  void _begin(VoxelGame game) {
    if (_game != null) return;
    _game = game;
    _class = classOf(game.options);
    _endless = Playground.isOn(game);
    stamina = maxStamina;
    mana = maxMana;
    final p = game.player;
    p.sprintVetoes[key] = () => stamina <= sprintFloor;
    p.shotVetoes[key] = _refuseShot;
    p.damageOut[key] = (mob, amount) => _shooting ? amount * (1.0 + _sum((t) => t.ranged)) : amount;
    _boost();
  }

  // What a shot of [launcher] costs and the player lacks, said; null for a
  // shot paid for.
  String? _refuseShot(ItemType launcher) {
    final cost = shotCosts[launcher.id];
    if (cost == null || _endless) return null;
    if (stamina < cost.stamina) return 'Too tired to draw';
    if (mana < manaCost(cost.mana)) return 'Not enough mana';
    return null;
  }

  // Whether the player holds something that shoots: a blow landing then is a
  // shot's.
  bool get _shooting {
    final game = _played;
    final held = game.player.heldItem;
    return held.isNotEmpty && game.items[held].launcher != null;
  }

  // The class's, the level's and the talents' numbers, on the player.
  void _boost() {
    final game = _played;
    game.player.boosts[key] = Boost(
      maxHp: _sum((t) => t.maxHp),
      damage: playerClass.damage * (1.0 + _sum((t) => t.damage)) * (1.0 + levelDamage * game.player.level),
      speed: 1.0 + _sum((t) => t.speed),
      armor: _sum((t) => t.armor),
    );
  }

  // [of] a talent, times its rank, over every talent learned.
  double _sum(double Function(Talent t) of) {
    var total = 0.0;
    for (final t in talents) {
      total += of(t) * rank(t.id);
    }
    return total;
  }

  void _cast(VoxelGame game, String action, Ability ability) {
    final p = game.player;
    final left = cooldownOf(action);
    if (left > 0.0) return game.notify('${ability.name} ready in ${left.ceil()}s');
    final arrows = p.spec.creative ? 0 : ability.arrows;
    if (p.inventory.countOf('arrow') < arrows) return game.notify('Need $arrows arrows');
    final cost = manaCost(ability.mana);
    if (!_endless) {
      if (stamina < ability.stamina) return game.notify('Too tired');
      if (mana < cost) return game.notify('Not enough mana');
      stamina -= ability.stamina;
      mana -= cost;
    }
    if (arrows > 0) p.inventory.remove('arrow', arrows);
    ability.cast(game, this);
    final shorter = _sum((t) => t.cooldownOf == action ? t.cooldown : 0.0);
    _cooldowns[action] = ability.cooldown * math.max(1.0 - shorter, 0.0);
  }

  void _dodge(VoxelGame game) {
    final p = game.player;
    final cost = math.max(dodgeCost - _sum((t) => t.dodgeCost), 0.0);
    if (dodging || _dodgeAgain > 0.0 || (!_endless && stamina < cost)) return;
    if (p.riding != null || p.sleeping || p.inLiquid) return;
    if (!_endless) stamina -= cost;
    _dodgeLeft = dodgeSeconds;
    _dodgeAgain = dodgeEvery;
    p.grantGrace(dodgeSeconds);
    final walk = Vector3(p.velocity.x, 0.0, p.velocity.z);
    final dir = walk.length2 > 0.25 ? walk.normalized() : p.flatForward;
    p.motor.shove(Vector3(dir.x * dodgeSpeed, p.onFloor ? dodgeHop : p.velocity.y, dir.z * dodgeSpeed), dodgeSeconds);
    game.playSound('swing', volumeDb: -8.0, pitch: 0.7);
  }
}
