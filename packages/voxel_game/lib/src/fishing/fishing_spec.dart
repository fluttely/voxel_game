import 'package:voxel_engine/content.dart';

/// How a game fishes (`VoxelGameSpec.fishing`): a use with the [rod] in hand
/// casts a line at the first liquid of [liquids] along the aim within
/// [reach]; after [minWait] to [maxWait] seconds something bites, and a use
/// within [bite] seconds of it lands one roll of [catches] (in the bag, the
/// rest on the ground) and [xp] experience; a use before or after reels the
/// line in empty.
///
/// ```dart
/// fishing: FishingSpec(
///   rod: 'fishing_rod',
///   catches: LootTable.oneOf([
///     LootEntry('raw_fish', 1, 1, 0.7),
///     LootEntry('stick', 1, 2, 0.3),
///   ]),
/// ),
/// ```
class FishingSpec {
  /// Fishing with [rod] for [catches].
  const FishingSpec({
    required this.rod,
    required this.catches,
    this.liquids = const {'water'},
    this.reach = 8.0,
    this.minWait = 3.0,
    this.maxWait = 8.0,
    this.bite = 1.5,
    this.xp = 2,
  }) : assert(reach > 0.0 && minWait > 0.0 && maxWait >= minWait && bite > 0.0 && xp >= 0);

  /// The item that casts and reels in: one that places no block.
  final String rod;

  /// What a bite landed gives: one roll (a `LootTable.oneOf` gives one catch
  /// or none).
  final LootTable catches;

  /// The liquid kinds a line is cast at (`BlockType.liquid`).
  final Set<String> liquids;

  /// How far a line is cast, metres; it is reeled in on its own once the
  /// player is twice as far from it.
  final double reach;

  /// The fewest seconds before something bites, and the most.
  final double minWait, maxWait;

  /// Seconds a bite lasts: a use within them lands the catch.
  final double bite;

  /// Experience a catch gives (`PlayerSpec.xp` must be declared when it is
  /// over 0).
  final int xp;
}
