/// What eating or drinking an item does: hunger it fills, health it gives
/// back, an effect it starts, and an item it leaves in the hand (a bowl, a
/// bottle).
class Food {
  /// A food. An [effect] needs its [seconds].
  const Food({
    this.hunger = 0,
    this.heal = 0.0,
    this.effect,
    this.seconds = 0.0,
    this.power = 1.0,
    this.leaves,
    this.cures = false,
  }) : assert(hunger >= 0 && heal >= 0.0, 'a food takes nothing away'),
       assert((effect == null) == (seconds == 0.0), 'an effect lasts some seconds, and only an effect does'),
       assert(power > 0.0);

  /// Hunger points it fills.
  final int hunger;

  /// Health it gives back at once.
  final double heal;

  /// The status effect it starts (an `EffectType` id), or null.
  final String? effect;

  /// How long [effect] lasts.
  final double seconds;

  /// [effect]'s power.
  final double power;

  /// The item left behind once it is eaten, or null.
  final String? leaves;

  /// Whether eating it ends every bad effect (`EffectType.bad`): milk, an
  /// antidote. What a game's code gives (a boost) stays.
  final bool cures;
}
