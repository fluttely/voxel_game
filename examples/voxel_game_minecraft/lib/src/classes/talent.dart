/// A talent: what each of its ranks (up to [maxRank]) adds to a class's
/// numbers, bought with a talent point in the journal (`JournalScreen`). Six
/// every class shares and one of each class's own (`PlayerClass.signature`).
/// Each field is a rank's worth; the rest stay 0.
class Talent {
  /// The talent [id], shown as [name] with its [description], drawn in
  /// [color] (`0xRRGGBB`).
  const Talent(
    this.id,
    this.name,
    this.description,
    this.color, {
    this.maxHp = 0.0,
    this.damage = 0.0,
    this.speed = 0.0,
    this.armor = 0.0,
    this.staminaRegen = 0.0,
    this.manaRegen = 0.0,
    this.ranged = 0.0,
    this.manaCost = 0.0,
    this.dodgeCost = 0.0,
    this.cooldown = 0.0,
    this.cooldownOf,
  }) : assert(cooldown == 0.0 || cooldownOf != null, 'a shorter cooldown is some action\'s');

  /// The most ranks a talent takes.
  static const int maxRank = 3;

  /// Its key in the save.
  final String id;

  /// What the journal calls it.
  final String name;

  /// What a rank does, in a line.
  final String description;

  /// Its colour in the journal, `0xRRGGBB`.
  final int color;

  /// Most health added.
  final double maxHp;

  /// The share added to the damage of every blow.
  final double damage;

  /// The share added to the speed.
  final double speed;

  /// Armour points added.
  final double armor;

  /// The share added to how fast stamina comes back.
  final double staminaRegen;

  /// The share added to how fast mana comes back.
  final double manaRegen;

  /// The share added to a shot's damage.
  final double ranged;

  /// The share taken off every mana cost.
  final double manaCost;

  /// Stamina taken off the dodge's cost.
  final double dodgeCost;

  /// The share taken off the cooldown of the ability [cooldownOf] casts.
  final double cooldown;

  /// The action id (`'ability'`) of the ability whose [cooldown] is shorter.
  final String? cooldownOf;
}
