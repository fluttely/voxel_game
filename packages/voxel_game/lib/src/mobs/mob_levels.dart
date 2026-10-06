/// How a creature grows with the player: a natural spawn of a spec with
/// these comes at the player's level plus one, give or take [spread], plus
/// [caveBonus] in a cave; each level above the first adds [hp], [damage] and
/// [xp] as a share of the spec's own.
class MobLevels {
  /// Levels that add [hp] of the health, [damage] of the strike's damage and
  /// [xp] of the experience per level.
  const MobLevels({this.hp = 0.18, this.damage = 0.1, this.xp = 0.15, this.spread = 1, this.caveBonus = 2})
    : assert(hp >= 0.0 && damage >= 0.0 && xp >= 0.0 && spread >= 0 && caveBonus >= 0);

  /// The share of the spec's health each level adds.
  final double hp;

  /// The share of a strike's damage each level adds.
  final double damage;

  /// The share of the spec's experience each level adds.
  final double xp;

  /// How many levels either side of the player's a spawn may fall.
  final int spread;

  /// The levels a spawn in a cave adds.
  final int caveBonus;

  /// The level of a natural spawn when the player is at [playerLevel] (from
  /// 0), [roll] in `-spread..spread`, [cave] when it spawned in a cave: at
  /// least 1.
  int levelFor(int playerLevel, int roll, {required bool cave}) {
    assert(roll.abs() <= spread);
    final level = playerLevel + 1 + roll + (cave ? caveBonus : 0);
    return level < 1 ? 1 : level;
  }

  /// What [share] per level makes of a base at [level].
  static double scale(double share, int level) => 1.0 + (level - 1) * share;
}
