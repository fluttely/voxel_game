import '../spec/structure.dart';
import '../spec/structure_site.dart';

/// What is left of a 7 x 7 house: a cracked [floor] laid in the ground, the
/// [ground] showing through one cell in four, broken [walls] two to four high
/// with gaps (one brick in five [mossy]), one or two [plants] grown on the
/// wall tops, and a [chest] half the time.
class Ruins extends Structure {
  /// Ruins of these blocks; every one left null or empty is left out.
  const Ruins({
    required this.floor,
    required this.ground,
    required this.walls,
    this.mossy,
    this.plants = const [],
    this.chest,
  });

  /// The floor, level with the ground around it.
  final String floor;

  /// What shows through the floor's cracks (grass).
  final String ground;

  /// The bricks.
  final String walls;

  /// Two bricks in five, or null for [walls] all through.
  final String? mossy;

  /// What may grow on a wall top, one picked a plant.
  final List<String> plants;

  /// Half the time, in the middle.
  final String? chest;

  @override
  int get radius => 4;

  @override
  Set<String> get blockNames => {floor, ground, walls, ?mossy, ...plants, ?chest};

  @override
  void build(StructureSite site) {
    const half = 3;
    final h = site.roll(31);
    final plantA = h % 24, plantB = (h >> 5) % 24;
    var edge = 0;
    for (var z = -half; z <= half; z++) {
      for (var x = -half; x <= half; x++) {
        site.level(x, z, x, z, floor, floor: -1, clearTo: 5);
        site.put(x, -1, z, site.hashAt(x, 100, z) % 4 == 0 ? ground : floor);
        if (x.abs() != half && z.abs() != half) continue;
        final wh = site.hashAt(x, 101, z);
        final tall = wh % 10 < 3 ? 0 : 2 + (wh >> 4) % 3;
        for (var y = 0; y < tall; y++) {
          site.put(x, y, z, mossy != null && site.hashAt(x, y, z) % 5 < 2 ? mossy! : walls);
        }
        if (tall > 0 && plants.isNotEmpty && (edge == plantA || edge == plantB)) {
          site.put(x, tall, z, plants[(wh >> 12) % plants.length]);
        }
        edge++;
      }
    }
    if (chest != null && (h >> 10) % 2 == 0) site.put(0, 0, 0, chest!);
  }
}
