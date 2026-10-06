import 'package:voxel_game/voxel_game.dart';

/// An elite's twist: a prefix on a creature's name and what it scales, or the
/// effect its blows leave. One creature in [Affix.share] that the world
/// spawns is an elite, one of [Affix.all] at even odds; each is a creature of
/// its own (`mobTable`), worth [xp] times the experience and dropping
/// [Affix.loot] on top of its own.
class Affix {
  const Affix(this.name, {this.speed = 1.0, this.hp = 1.0, this.damage = 1.0, this.scale = 1.0, this.effect});

  /// The prefix, and the id's (`swift_zombie`).
  final String name;

  /// What it multiplies.
  final double speed, hp, damage;

  /// How much bigger its body is, every side.
  final double scale;

  /// The effect its blows leave instead of its kind's, or null to keep it.
  final String? effect;

  /// How long [effect] lasts.
  static const double seconds = 6.0;

  /// The elites' share of what spawns.
  static const double share = 0.08;

  /// The experience an elite is worth, times its kind's.
  static const double xp = 2.5;

  /// What an elite drops beside its kind's loot.
  static const List<LootEntry> loot = [LootEntry('gem_shard', 1, 2, 1.0), LootEntry('magic_dust', 1, 1, 1.0)];

  static const List<Affix> all = [
    Affix('Swift', speed: 1.5),
    Affix('Sturdy', hp: 2.0),
    Affix('Venomous', effect: 'poison'),
    Affix('Burning', effect: 'burning'),
    Affix('Chilling', effect: 'slow'),
    Affix('Giant', scale: 1.4, hp: 1.6, damage: 1.3),
  ];

  /// The id of [mob]'s elite of this affix.
  String idOf(String mob) => '${name.toLowerCase()}_$mob';
}
