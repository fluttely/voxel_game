/// Armour: worn in one [slot], it turns aside [points] of every blow.
class Armor {
  /// A piece worn in [slot] (`'head'`, `'chest'`) worth [points].
  const Armor(this.slot, this.points) : assert(points > 0);

  /// Where it is worn; one piece per slot.
  final String slot;

  /// How much it protects.
  final int points;
}
