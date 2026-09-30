/// The variants of a block that turns to face the way it was placed: stairs
/// that climb away from the player, a door across the way they walk. Each
/// variant is a block of its own, named here by id.
class Facing {
  /// Four variants, one per compass side the placer looks toward (north is
  /// -Z, east +X).
  const Facing.compass({
    required String this.north,
    required String this.east,
    required String this.south,
    required String this.west,
  }) : x = null,
       z = null;

  /// Two variants, one per axis the placer looks along.
  const Facing.axis({required String this.x, required String this.z})
    : north = null,
      east = null,
      south = null,
      west = null;

  /// The compass variants; null on an axis facing.
  final String? north, east, south, west;

  /// The axis variants; null on a compass facing.
  final String? x, z;

  /// Every variant.
  List<String> get variants => [?north, ?east, ?south, ?west, ?x, ?z];

  /// The variant for a placer looking along ([forwardX], [forwardZ]).
  String toward(double forwardX, double forwardZ) {
    final alongX = forwardX.abs() > forwardZ.abs();
    if (x != null) return alongX ? x! : z!;
    if (alongX) return forwardX > 0 ? east! : west!;
    return forwardZ > 0 ? south! : north!;
  }
}
