/// What an item that shoots does: a press of attack with it in hand looses
/// one [shot], spending one [ammo] from the bag, at most once every
/// [cooldown] seconds. A bow shoots arrows; a game's staff, shooting bolts
/// that cost no item, has no [ammo].
class Launcher {
  /// A launcher of [shot], the name a game's shots are declared by.
  const Launcher({required this.shot, this.ammo, this.cooldown = 0.5})
    : assert(cooldown > 0.0, 'a launcher shoots once at a time');

  /// The shot it looses, by name (`VoxelGameSpec.shots` in `voxel_game`).
  final String shot;

  /// The item a shot spends, one each, or null for a shot that spends none.
  final String? ammo;

  /// Seconds between two shots.
  final double cooldown;
}
