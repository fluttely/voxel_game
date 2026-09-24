import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart' as content;

export 'package:voxel_engine/content.dart' show EffectEvent, EffectRow, EffectType, StatModifier;

/// This game's buffs and debuffs. VK3.3: voxel_content's [content.EffectType]
/// rows; the stat hooks the player reads (speed, damage, armour, mining) are
/// their modifiers, so a new effect bends a stat by data alone.
typedef EffectDef = content.EffectType;

/// An effect's colour, for damage numbers, bursts and HUD chips.
extension EffectColor on content.EffectType {
  Vector3 get color => Vector3(r, g, b);
}

/// Timed buffs and debuffs on a body. Each effect is one row: seconds left plus
/// power. Ticking damage and healing are applied by the owner through [tick],
/// which returns the events that happened this frame so the owner decides how
/// they show (damage numbers, sounds).
class StatusEffects extends content.StatusEffects {
  StatusEffects() : super(defs);

  static const Map<String, EffectDef> defs = {
    'poison': EffectDef('poison', 'Poisoned', 0.35, 0.80, 0.30, period: 2.0, damage: 1.0, bad: true),
    'burning': EffectDef('burning', 'Burning', 1.00, 0.55, 0.15, period: 1.0, damage: 1.0, bad: true),
    // Stage 29: the dark skeleton's touch.
    'wither': EffectDef('wither', 'Withering', 0.25, 0.22, 0.28, period: 1.5, damage: 1.0, bad: true),
    'slow': EffectDef('slow', 'Slowed', 0.50, 0.60, 0.85, bad: true, stats: {'speed': content.StatModifier.divide(0.40)}),
    'regen': EffectDef('regen', 'Regeneration', 0.95, 0.40, 0.60, period: 1.5, heal: 1.0),
    'speed': EffectDef('speed', 'Swiftness', 0.45, 0.85, 0.95, stats: {'speed': content.StatModifier.multiply(0.30)}),
    'strength': EffectDef('strength', 'Strength', 0.90, 0.30, 0.25, stats: {'damage': content.StatModifier.multiply(0.30)}),
    'resistance': EffectDef('resistance', 'Resistance', 0.70, 0.70, 0.75, stats: {'armor': content.StatModifier.add(4.0)}),
    'haste': EffectDef('haste', 'Haste', 0.95, 0.85, 0.35, stats: {'mining': content.StatModifier.multiply(0.6)}),
    'well_fed': EffectDef('well_fed', 'Well Fed', 0.85, 0.60, 0.30, period: 3.0, heal: 1.0),
  };

  static EffectDef def(String id) {
    final d = defs[id];
    if (d == null) throw ArgumentError('unknown effect $id');
    return d;
  }

  double speedMultiplier() => multiplier('speed');
  double damageMultiplier() => multiplier('damage');
  int armorBonus() => bonus('armor').toInt();
  double mineMultiplier() => multiplier('mining');
}
