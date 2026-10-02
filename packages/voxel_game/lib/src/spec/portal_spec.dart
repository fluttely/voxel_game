import 'voxel_game_spec.dart';

/// A gateway between two dimensions of a game: a [frame] of blocks around a
/// hollow [width] wide and [height] tall, standing in either vertical plane,
/// which the [lighter] item (used on the hollow) fills with [portal] blocks.
/// A player standing in them for [seconds] goes to the other dimension: from
/// [from] to [to], and back.
///
/// The trip keeps the player's column: it arrives at the same x and z, on the
/// nearest spot there with two clear cells over firm ground, a pocket carved
/// when there is none. Unless a lit portal of this kind lies within [search]
/// blocks of that spot, a return portal is built in front of it, so there is
/// always a way back.
class PortalSpec {
  /// A portal between [from] (the world a game starts in when left out) and
  /// [to], dimensions the game declares (`VoxelGameSpec.dimensions`).
  const PortalSpec({
    required this.frame,
    required this.portal,
    required this.lighter,
    required this.to,
    this.from = VoxelGameSpec.mainDimension,
    this.width = 2,
    this.height = 3,
    this.seconds = 2.0,
    this.search = 16,
  }) : assert(width >= 1 && height >= 2, 'a portal is at least one wide and two tall'),
       assert(seconds >= 0.0 && search >= 0);

  /// The block of the frame.
  final String frame;

  /// The block the lit hollow fills with: not solid, so a body stands in it.
  final String portal;

  /// The item whose use on the hollow of a closed frame lights it.
  final String lighter;

  /// One end: the dimension a portal of this kind leads from.
  final String from;

  /// The other end: the dimension it leads to.
  final String to;

  /// The hollow's width, in blocks.
  final int width;

  /// The hollow's height, in blocks.
  final int height;

  /// Seconds a player stands in it before it takes them.
  final double seconds;

  /// How far from an arrival a lit portal of this kind is looked for before
  /// a return portal is built, in blocks.
  final int search;

  /// The end the portal leads to from [dimension]; null when [dimension] is
  /// neither of its ends.
  String? otherEnd(String dimension) => dimension == from ? to : (dimension == to ? from : null);
}
