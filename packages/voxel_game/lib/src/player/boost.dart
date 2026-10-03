/// A lasting change to the player's numbers from a game's own code: a class,
/// a talent, a blessing. Kept in `PlayerEntity.boosts` under its source until
/// the game removes it; unlike a status effect it has no clock, and a
/// respawn or a cure leaves it on.
///
/// ```dart
/// game.player.boosts['warrior'] = const Boost(maxHp: 6, damage: 1.2);
/// game.player.boosts.remove('warrior');
/// ```
///
/// The kit does not save boosts: the system that gives one gives it again
/// when its world loads (`SavedSystem.restore`).
class Boost {
  /// A boost; the defaults change nothing.
  const Boost({this.speed = 1.0, this.damage = 1.0, this.mining = 1.0, this.armor = 0.0, this.maxHp = 0.0})
    : assert(speed >= 0.0 && damage >= 0.0 && mining > 0.0);

  /// What the speed on foot, swimming and flying is multiplied by.
  final double speed;

  /// What the damage of the player's blows is multiplied by.
  final double damage;

  /// What how fast blocks are mined is multiplied by.
  final double mining;

  /// Armour points added.
  final double armor;

  /// Health added to the most the player has (`PlayerEntity.maxHp`).
  final double maxHp;
}
