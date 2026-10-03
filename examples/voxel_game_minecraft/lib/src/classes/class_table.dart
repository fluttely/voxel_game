import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

import '../spec/item_table.dart';
import 'ability.dart';
import 'class_system.dart';
import 'player_class.dart';
import 'talent.dart';

/// The four classes, by the id the title's class option keeps
/// (`classOption`), in its order.
const Map<String, PlayerClass> playerClasses = {
  'warrior': PlayerClass(
    'Warrior',
    hp: 30.0,
    stamina: 100.0,
    mana: 20.0,
    rig: Rig.humanoid(shirt: 0xB83833),
    weapon: 'stone_sword',
    damage: 1.25,
    abilities: {
      'ability': Ability('Whirlwind', cooldown: 8.0, stamina: 25.0, cast: _whirlwind),
      'ability2': Ability('Shield Bash', cooldown: 6.0, mana: 10.0, cast: _shieldBash),
    },
    signature: Talent(
      'rage',
      'Rage',
      'Whirlwind recharges 20% faster per rank',
      0xD93333,
      cooldown: 0.2,
      cooldownOf: 'ability',
    ),
  ),
  'ranger': PlayerClass(
    'Ranger',
    hp: 22.0,
    stamina: 120.0,
    mana: 30.0,
    rig: Rig.humanoid(shirt: 0x338C47),
    weapon: 'bow',
    kit: {'arrow': 48},
    damage: 1.0,
    abilities: {
      'ability': Ability('Arrow Volley', cooldown: 7.0, stamina: 25.0, arrows: 8, cast: _arrowVolley),
      'ability2': Ability('Volley', cooldown: 5.0, mana: 10.0, arrows: 5, cast: _volley),
    },
    signature: Talent('eagle_eye', 'Eagle Eye', '+12% ranged damage per rank', 0x4DA659, ranged: 0.12),
  ),
  'mage': PlayerClass(
    'Mage',
    hp: 18.0,
    stamina: 80.0,
    mana: 100.0,
    rig: Rig.humanoid(shirt: 0x5947BF),
    weapon: 'staff',
    kit: {'health_potion': 2},
    damage: 1.0,
    abilities: {
      'ability': Ability('Fire Nova', cooldown: 10.0, mana: 30.0, cast: _fireNova),
      'ability2': Ability('Frost Nova', cooldown: 9.0, mana: 25.0, cast: _frostNova),
    },
    signature: Talent('focus', 'Focus', 'Spells cost 15% less mana per rank', 0x8C66E6, manaCost: 0.15),
  ),
  'rogue': PlayerClass(
    'Rogue',
    hp: 24.0,
    stamina: 140.0,
    mana: 30.0,
    rig: Rig.humanoid(shirt: 0x40404D),
    weapon: 'dagger',
    damage: 1.1,
    abilities: {
      'ability': Ability('Shadow Dash', cooldown: 3.0, stamina: 20.0, cast: _shadowDash),
      'ability2': Ability('Smoke Bomb', cooldown: 12.0, mana: 15.0, cast: _smokeBomb),
    },
    signature: Talent('shadowstep', 'Shadowstep', 'Dodge costs 5 less stamina per rank', 0x595973, dodgeCost: 5.0),
  ),
};

/// The six talents every class has, before its own (`PlayerClass.signature`).
const List<Talent> sharedTalents = [
  Talent('vitality', 'Vitality', '+4 max HP per rank', 0xE64D59, maxHp: 4.0),
  Talent('might', 'Might', '+8% damage per rank', 0xF28C40, damage: 0.08),
  Talent('swiftness', 'Swiftness', '+5% move speed per rank', 0x73D9F2, speed: 0.05),
  Talent('endurance', 'Endurance', '+25% stamina regen per rank', 0x59CC59, staminaRegen: 0.25),
  Talent('arcana', 'Arcana', '+25% mana regen per rank', 0x7380F2, manaRegen: 0.25),
  Talent('toughness', 'Toughness', '+1 armor per rank', 0xB3B3BF, armor: 1.0),
];

/// What a shot of a launcher costs: stamina to draw a bow, mana for a
/// staff's bolt (less the class's `Talent.manaCost`).
typedef ShotCost = ({double stamina, double mana});

/// The launchers a shot of costs something, by item id (`ClassSystem`
/// refuses it short, and pays for it).
const Map<String, ShotCost> shotCosts = {
  'bow': (stamina: 3.0, mana: 0.0),
  'longbow': (stamina: 3.0, mana: 0.0),
  'staff': (stamina: 0.0, mana: 4.0),
  'crystal_staff': (stamina: 0.0, mana: 4.0),
};

/// The class a game's [options] play, by `classOption`'s id.
PlayerClass classOf(Map<String, String> options) =>
    playerClasses[options['class']] ?? (throw ArgumentError.value(options, 'options', 'no class among them'));

/// The talents [cls] may learn: the six of every class, then its own.
List<Talent> talentsOf(PlayerClass cls) => [...sharedTalents, cls.signature];

/// [player] as the class its [options] pick plays it (`VoxelGameSpec.playerFor`):
/// the class's health and look, its weapon and kit beside the game's start.
PlayerSpec classPlayer(PlayerSpec player, Map<String, String> options) {
  final cls = classOf(options);
  return player.copyWith(hp: cls.hp, rig: cls.rig, startingItems: {...player.startingItems, cls.weapon: 1, ...cls.kit});
}

// Whirlwind: every creature within 4 m takes a swing and a half, thrown back hard.
void _whirlwind(VoxelGame game, ClassSystem classes) {
  final damage = classes.meleeDamage(game) * 1.5;
  for (final m in classes.mobsNear(game, 4.0).toList()) {
    classes.strike(game, m, damage, knockback: 9.0);
  }
  game.playSound('swing', volumeDb: -2.0, pitch: 0.8);
}

// Shield Bash: a 3 m lunge; every creature within 3.5 m ahead is struck and stunned 2 s.
void _shieldBash(VoxelGame game, ClassSystem classes) {
  final p = game.player;
  final ahead = p.flatForward;
  p.motor.shove(Vector3(ahead.x * 12.0, math.max(p.velocity.y, 2.0), ahead.z * 12.0), 0.25);
  final damage = classes.meleeDamage(game) * 0.8;
  for (final m in classes.mobsNear(game, 3.5).toList()) {
    final to = m.position - p.position;
    if (!(to.length2 > 0.0 && to.normalized().dot(ahead) > 0.3)) continue;
    classes.strike(game, m, damage, knockback: 6.0);
    m.stun(2.0);
  }
  game.playSound('hit', volumeDb: -2.0, pitch: 0.8);
}

// Arrow Volley: eight arrows in a ring around the player, a fifth more than the bow's.
void _arrowVolley(VoxelGame game, ClassSystem classes) {
  final p = game.player;
  final from = p.position + Vector3(0.0, 0.9, 0.0);
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi * 2.0 / 8.0;
    final dir = Vector3(-math.sin(a), 0.0, -math.cos(a));
    final at = from + dir * 0.6;
    game.shoot(
      _arrowOf(game),
      from: at,
      at: at + dir * 30.0 + Vector3(0.0, 2.0, 0.0),
      owner: p,
      power: p.damageMultiplier * 1.2,
      overDrop: false,
    );
  }
}

// Volley: five arrows across a 40 degree fan where the player looks, 0.9 of the bow's.
void _volley(VoxelGame game, ClassSystem classes) {
  final p = game.player;
  final look = p.forward;
  final from = p.eyePosition + look * 0.8 - Vector3(0.0, 0.15, 0.0);
  for (var i = 0; i < 5; i++) {
    final dir = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), (i / 4 - 0.5) * 40.0 * math.pi / 180.0).rotated(look);
    game.shoot(_arrowOf(game), from: from, at: from + dir, owner: p, power: p.damageMultiplier * 0.9, overDrop: false);
  }
}

// The arrow a volley looses: the held bow's, or a plain bow's.
ProjectileSpec _arrowOf(VoxelGame game) {
  final held = game.player.heldItem;
  final launcher = held.isEmpty ? null : game.items[held].launcher;
  return shots[launcher != null && launcher.ammo == 'arrow' ? launcher.shot : 'arrow']!;
}

// Fire Nova: every creature within 6 m takes 8, and 2 more a level.
void _fireNova(VoxelGame game, ClassSystem classes) {
  final damage = 8.0 + 2.0 * (game.player.level + 1);
  for (final m in classes.mobsNear(game, 6.0).toList()) {
    classes.strike(game, m, damage, knockback: 7.0);
  }
  game.playSound('bolt', volumeDb: -2.0, pitch: 0.7);
}

// Frost Nova: every creature within 5 m takes 4 and goes at half its pace for 4 s.
void _frostNova(VoxelGame game, ClassSystem classes) {
  for (final m in classes.mobsNear(game, 5.0).toList()) {
    classes.strike(game, m, 4.0, knockback: 3.0);
    m.slow(0.5, 4.0);
  }
  game.playSound('bolt', volumeDb: -4.0, pitch: 1.4);
}

// Shadow Dash: a burst the way the player walks (or looks, standing), off the ground.
void _shadowDash(VoxelGame game, ClassSystem classes) {
  final p = game.player;
  final walk = Vector3(p.velocity.x, 0.0, p.velocity.z);
  final dir = walk.length2 > 0.25 ? walk.normalized() : p.flatForward;
  p.motor.shove(Vector3(dir.x * 22.0, 3.0, dir.z * 22.0), 0.17);
  game.playSound('swing', volumeDb: -4.0, pitch: 0.6);
}

// Smoke Bomb: 3 s untouchable and swift; every creature within 12 m forgets the player.
void _smokeBomb(VoxelGame game, ClassSystem classes) {
  final p = game.player;
  p.grantGrace(3.0);
  p.effects.apply('speed', 3.0, 1.0);
  for (final m in classes.mobsNear(game, 12.0).toList()) {
    m.forget();
  }
  game.playSound('splash', volumeDb: -6.0, pitch: 0.6);
}
