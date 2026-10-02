import 'package:sound_recipes/sound_recipes.dart' show SoundFamily;
import 'package:voxel_engine/core.dart' show IVec3;

/// A vehicle a game declares (`VoxelGameSpec.vehicles`): the [item] that puts
/// one in the world and that it breaks back into, its body, where its rider
/// sits, and its look. One kind a subclass, each moving its own way: a
/// [BoatSpec] floats and is rowed, a [CartSpec] rides the rails.
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

/// A minecart: it rides the rails (`Rails`), never the ground, from the end
/// of each rail it came in by to the one it leaves by, and stays where it is
/// where no rail is under it. Along the line its speed (never over
/// [maxSpeed]) takes [slope] downhill and loses as much uphill, loses
/// [friction], gains [powered] on a powered rail on and loses [brake] on one
/// off, all in metres a second a second; a rider pushes it by [push] as they
/// move along its heading, or against it, and a cart with no rider rolls by
/// all the rest. Its look is a [cart] of iron on four wheels by default.
final class CartSpec extends VehicleSpec {
  /// A minecart put on a rail and broken back into [item].
  const CartSpec({
    required super.item,
    super.name,
    super.halfWidth = 0.5,
    super.height = 0.7,
    super.seat = 0.3,
    super.model = cart,
    super.voxel,
    super.sound = SoundFamily.metal,
    this.maxSpeed = 8.0,
    this.slope = 4.0,
    this.friction = 0.4,
    this.powered = 6.0,
    this.brake = 12.0,
    this.push = 2.0,
  }) : assert(maxSpeed > 0.0 && slope >= 0.0 && friction >= 0.0),
       assert(powered >= 0.0 && brake >= 0.0 && push >= 0.0);

  /// Its top speed, metres a second.
  final double maxSpeed;

  /// What a slope adds downhill and takes uphill.
  final double slope;

  /// What it loses on every rail.
  final double friction;

  /// What a powered rail on adds.
  final double powered;

  /// What a powered rail off takes from a moving cart.
  final double brake;

  /// What its rider's push adds, at a full push along its heading.
  final double push;

  /// A minecart of iron, 1.1 m by 0.9 m: a dark floor, four sides 0.4 m
  /// high and four dark wheels under it, resting on the rail's bars.
  static const List<(IVec3, IVec3, int)> cart = [
    (IVec3(-4, 1, -3), IVec3(4, 1, 3), _dark),
    (IVec3(-5, 2, -4), IVec3(-4, 5, 4), _iron),
    (IVec3(4, 2, -4), IVec3(5, 5, 4), _iron),
    (IVec3(-4, 2, -4), IVec3(4, 5, -3), _iron),
    (IVec3(-4, 2, 3), IVec3(4, 5, 4), _iron),
    (IVec3(-4, 0, -3), IVec3(-2, 1, -2), _dark),
    (IVec3(-4, 0, 2), IVec3(-2, 1, 3), _dark),
    (IVec3(2, 0, -3), IVec3(4, 1, -2), _dark),
    (IVec3(2, 0, 2), IVec3(4, 1, 3), _dark),
  ];

  static const int _iron = 0x8C8C94, _dark = 0x525259;
}
