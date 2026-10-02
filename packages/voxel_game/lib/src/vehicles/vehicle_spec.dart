import 'package:sound_recipes/sound_recipes.dart' show SoundFamily;
import 'package:voxel_engine/core.dart' show IVec3;

/// A vehicle a game declares (`VoxelGameSpec.vehicles`): the [item] that puts
/// one in the world and that it breaks back into, its body, where its rider
/// sits, and its look. One kind a subclass, each moving its own way: a
/// [BoatSpec] floats and is rowed.
///
/// Its look is [model]: boxes of voxels, each filled from its first corner to
/// its second (inclusive) in a `0xRRGGBB` colour, a later box painting over an
/// earlier one, as a `CustomItemShape`'s. Each voxel is [voxel] metres; the
/// middle of voxel (0, 0, 0)'s floor stands on the vehicle's feet, +y is up
/// and -z its front.
sealed class VehicleSpec {
  const VehicleSpec({
    required this.item,
    this._name,
    required this.halfWidth,
    required this.height,
    required this.seat,
    required this.model,
    this.voxel = 0.1,
    this.sound = SoundFamily.wood,
  }) : assert(halfWidth > 0.0 && height > 0.0 && seat >= 0.0 && voxel > 0.0);

  /// The item that places it and that it breaks back into: one that places no
  /// block (`VoxelGameSpec.checkVehicles`).
  final String item;

  final String? _name;

  /// The name a player reads; by default the [item] in title case.
  String get name => _name ?? item.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  /// Half its width, metres: its body is square.
  final double halfWidth;

  /// Its height, metres.
  final double height;

  /// Metres from its feet to its rider's.
  final double seat;

  /// Its look: (from, to, colour) boxes of voxels, painted in order.
  final List<(IVec3, IVec3, int)> model;

  /// Metres a voxel of [model].
  final double voxel;

  /// The material family it sounds like (`SoundFamily`): `place_<sound>` as
  /// it is put down, `break_<sound>` as it breaks.
  final String sound;
}

/// A boat: it floats on any liquid, rising while its bottom is under the
/// surface and settling there, and falls in air. Its rider rows it forward
/// and back at [liquidSpeed] (on land, dragged, [landSpeed]) and steers it
/// [turnSpeed] radians a second; its speed eases toward the rowed one by
/// [acceleration] a second, and without a rider it coasts to rest by [coast]
/// a second. Its look is a [hull] of wood by default.
final class BoatSpec extends VehicleSpec {
  /// A boat put down and broken back into [item].
  const BoatSpec({
    required super.item,
    super.name,
    super.halfWidth = 0.55,
    super.height = 0.5,
    super.seat = 0.35,
    super.model = hull,
    super.voxel,
    super.sound,
    this.liquidSpeed = 6.5,
    this.landSpeed = 1.5,
    this.turnSpeed = 1.7,
    this.rise = 1.6,
    this.acceleration = 2.5,
    this.coast = 1.5,
  }) : assert(liquidSpeed > 0.0 && landSpeed >= 0.0 && turnSpeed > 0.0 && rise > 0.0),
       assert(acceleration > 0.0 && coast > 0.0);

  /// Its rowed speed on liquid, metres a second.
  final double liquidSpeed;

  /// Its rowed speed out of liquid, metres a second.
  final double landSpeed;

  /// How fast it turns, radians a second.
  final double turnSpeed;

  /// The speed it rises toward, metres a second, while its bottom is under the
  /// surface.
  final double rise;

  /// How fast its speed eases toward the rowed one, a second.
  final double acceleration;

  /// How fast it comes to rest without a rider, a second.
  final double coast;

  /// A rowing boat of planks, 1.1 m wide and 1.9 m long: a dark floor, four
  /// sides and a bench across the middle.
  static const List<(IVec3, IVec3, int)> hull = [
    (IVec3(-4, 0, -7), IVec3(4, 0, 7), _dark),
    (IVec3(-5, 1, -8), IVec3(-4, 3, 8), _wood),
    (IVec3(4, 1, -8), IVec3(5, 3, 8), _wood),
    (IVec3(-4, 1, -9), IVec3(4, 3, -8), _wood),
    (IVec3(-4, 1, 8), IVec3(4, 3, 9), _wood),
    (IVec3(-4, 1, -1), IVec3(4, 1, 1), _dark),
  ];

  static const int _wood = 0x8C6133, _dark = 0x664524;
}
