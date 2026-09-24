import 'sfx.dart';

class AchievementDef {
  const AchievementDef(this.id, this.name, this.description);
  final String id;
  final String name;
  final String description;
}

/// Achievements: a fixed list, unlocked once, toasted through the player's
/// notification line. Persisted inside the stats block of the save.
class Achievements {
  Achievements._();
  static final Achievements instance = Achievements._();

  static const List<AchievementDef> defs = [
    AchievementDef('first_block', 'Getting Wood', 'Break your first block'),
    AchievementDef('builder', 'Builder', 'Place 100 blocks'),
    AchievementDef('first_kill', 'Monster Hunter', 'Defeat your first monster'),
    AchievementDef('slayer', 'Slayer', 'Defeat 50 monsters'),
    AchievementDef('level_5', 'Adventurer', 'Reach level 5'),
    AchievementDef('level_10', 'Hero', 'Reach level 10'),
    AchievementDef('diamonds', 'Diamonds!', 'Pick up a diamond'),
    AchievementDef('boss', 'Boss Slayer', 'Defeat a boss'),
    AchievementDef('elite', 'Elite Hunter', 'Defeat an elite monster'),
    AchievementDef('crafter', 'Crafter', 'Craft 25 items'),
    AchievementDef('sleeper', 'Good Night', 'Sleep in a bed'),
    AchievementDef('sailor', 'Sailor', 'Board a boat'),
    AchievementDef('deep', 'Deep Down', 'Go below height 20'),
    AchievementDef('brewer', 'Brewer', 'Drink a potion'),
    AchievementDef('talent', 'Gifted', 'Spend a talent point'),
    AchievementDef('traveler', 'Traveler', 'Teleport through a waypoint'),
    AchievementDef('tamer', 'Best Friend', 'Tame a wolf'),
    AchievementDef('glider', 'Wingsuit', 'Glide for the first time'),
    AchievementDef('fisher', 'Gone Fishing', 'Catch your first fish'),
    AchievementDef('rider', 'Saddle Up', 'Ride a horse'),
    AchievementDef('underworld', 'Into the Fire', 'Find a fortress in the underworld'), // stage 29
    AchievementDef('heart', 'Heart of the Underworld', 'Take the underworld heart'),
  ];

  final Set<String> unlocked = {};
  int crafted = 0;

  /// Where a toast goes; the game sets it once the player exists.
  void Function(String text)? notify;

  static AchievementDef def(String id) {
    for (final d in defs) {
      if (d.id == id) return d;
    }
    throw ArgumentError('unknown achievement $id');
  }

  void unlock(String id) {
    final d = def(id);
    if (!unlocked.add(id)) return;
    notify?.call('Achievement: ${d.name}');
    Sfx.play('quest', -4.0);
  }

  int get count => unlocked.length;

  void onCrafted() {
    crafted += 1;
    if (crafted >= 25) unlock('crafter');
  }

  void reset() {
    unlocked.clear();
    crafted = 0;
  }

  Map<String, Object> toJson() => {'unlocked': unlocked.toList(), 'crafted': crafted};

  void fromJson(Map<String, dynamic> d) {
    unlocked.clear();
    for (final k in (d['unlocked'] as List<dynamic>? ?? const [])) {
      unlocked.add(k.toString());
    }
    crafted = (d['crafted'] as num?)?.toInt() ?? 0;
  }
}
