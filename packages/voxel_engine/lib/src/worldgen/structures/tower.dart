import '../spec/structure.dart';
import '../spec/structure_site.dart';

/// A square watchtower, 5 x 5 and [height] tall, on a foundation down to its
/// ground: a door on its +z side, windows every third row, a ladder up the
/// inside to a [floor] under the top, a [chest] and a [light] up there, and
/// battlements. One brick in five is [mossy].
class Tower extends Structure {
  /// A tower of these blocks; every one left null is left out.
  const Tower({
    required this.walls,
    required this.floor,
    required this.ladder,
    this.mossy,
    this.chest,
    this.light,
    this.height = 9,
  }) : assert(height >= 6);

  /// The bricks, and the foundation.
  final String walls;

  /// The top floor.
  final String floor;

  /// The way up.
  final String ladder;

  /// One brick in five, or null for [walls] all through.
  final String? mossy;

  /// On the top floor.
  final String? chest;

  /// On the top floor.
  final String? light;

  /// From the ground floor to the top floor's ceiling, in blocks.
  final int height;

  @override
  int get radius => 3;

  @override
  Set<String> get blockNames => {walls, floor, ladder, ?mossy, ?chest, ?light};

  @override
  void build(StructureSite site) {
    final h = height;
    site.level(-2, -2, 2, 2, walls, clearTo: h + 1);
    for (var z = -2; z <= 2; z++) {
      for (var x = -2; x <= 2; x++) {
        final wall = x.abs() == 2 || z.abs() == 2;
        for (var y = 0; y <= h; y++) {
          var name = 'air';
          if (y == 0) {
            name = walls;
          } else if (wall) {
            final door = z == 2 && x == 0 && y <= 2;
            final window = y % 3 == 2 && (x == 0 || z == 0);
            if (!door && !window) name = mossy != null && site.hashAt(x, y, z) % 5 == 0 ? mossy! : walls;
          } else if (y == h - 1) {
            name = floor;
          }
          site.put(x, y, z, name);
        }
        if (wall && (x + z) % 2 == 0) site.put(x, h + 1, z, walls);
      }
    }
    if (chest != null) site.put(0, h, 0, chest!);
    if (light != null) site.put(-1, h, -1, light!);
    for (var y = 1; y < h - 1; y++) {
      site.put(-1, y, -1, ladder);
    }
    site.put(-1, h - 1, -1, 'air'); // the hatch in the top floor
  }
}
