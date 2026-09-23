/// The talent tree (skill points): one point per level from level
/// 2, spent in the journal. Six talents every class shares plus one signature
/// per class, three ranks each.
class TalentDef {
  const TalentDef(this.id, this.name, this.description, this.r, this.g, this.b);
  final String id;
  final String name;
  final String description;
  final double r, g, b;
}

class Talents {
  Talents._();

  static const int maxRank = 3;

  static const List<TalentDef> shared = [
    TalentDef('vitality', 'Vitality', '+4 max HP per rank', 0.90, 0.30, 0.35),
    TalentDef('might', 'Might', '+8% damage per rank', 0.95, 0.55, 0.25),
    TalentDef('swiftness', 'Swiftness', '+5% move speed per rank', 0.45, 0.85, 0.95),
    TalentDef('endurance', 'Endurance', '+25% stamina regen per rank', 0.35, 0.80, 0.35),
    TalentDef('arcana', 'Arcana', '+25% mana regen per rank', 0.45, 0.50, 0.95),
    TalentDef('toughness', 'Toughness', '+1 armor per rank', 0.70, 0.70, 0.75),
  ];

  static const Map<String, TalentDef> signature = {
    'warrior': TalentDef('rage', 'Rage', 'Whirlwind recharges 20% faster per rank', 0.85, 0.20, 0.20),
    'ranger': TalentDef('eagle_eye', 'Eagle Eye', '+12% ranged damage per rank', 0.30, 0.65, 0.35),
    'mage': TalentDef('focus', 'Focus', 'Spells cost 15% less mana per rank', 0.55, 0.40, 0.90),
    'rogue': TalentDef('shadowstep', 'Shadowstep', 'Dodge costs 5 less stamina per rank', 0.35, 0.35, 0.45),
  };

  static List<TalentDef> listFor(String playerClass) => [...shared, signature[playerClass]!];
}
