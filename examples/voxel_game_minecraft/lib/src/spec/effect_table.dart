import 'package:voxel_game/voxel_game.dart';

/// The ten status effects: what a creature's touch, a fireball, a potion or a
/// good meal leaves on the player. A stat an effect bends (speed, damage,
/// armour, mining) is a modifier on its row.
const List<EffectType> effectTable = [
  EffectType('poison', 'Poisoned', 0.35, 0.80, 0.30, period: 2.0, damage: 1.0, bad: true),
  EffectType('burning', 'Burning', 1.00, 0.55, 0.15, period: 1.0, damage: 1.0, bad: true),
  // The dark skeleton's touch.
  EffectType('wither', 'Withering', 0.25, 0.22, 0.28, period: 1.5, damage: 1.0, bad: true),
  EffectType('slow', 'Slowed', 0.50, 0.60, 0.85, bad: true, stats: {'speed': StatModifier.divide(0.40)}),
  EffectType('regen', 'Regeneration', 0.95, 0.40, 0.60, period: 1.5, heal: 1.0),
  EffectType('speed', 'Swiftness', 0.45, 0.85, 0.95, stats: {'speed': StatModifier.multiply(0.30)}),
  EffectType('strength', 'Strength', 0.90, 0.30, 0.25, stats: {'damage': StatModifier.multiply(0.30)}),
  EffectType('resistance', 'Resistance', 0.70, 0.70, 0.75, stats: {'armor': StatModifier.add(4.0)}),
  EffectType('haste', 'Haste', 0.95, 0.85, 0.35, stats: {'mining': StatModifier.multiply(0.6)}),
  EffectType('well_fed', 'Well Fed', 0.85, 0.60, 0.30, period: 3.0, heal: 1.0),
];
