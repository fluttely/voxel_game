import '../spec/structure.dart';
import '../spec/structure_site.dart';

/// A village well on its own: a 3 x 3 [rim] standing a block over the
/// ground around [water] [deep] blocks deep, two [posts] and a [roof].
class Well extends Structure {
  /// A well of these blocks.
  const Well({required this.rim, required this.water, required this.posts, required this.roof, this.deep = 4})
    : assert(deep >= 1);

  /// The ring around the water.
  final String rim;

  /// What fills it.
  final String water;

  /// The two posts that hold the roof.
  final String posts;

  /// The roof.
  final String roof;

  /// How far the water reaches under the ground.
  final int deep;

  @override
  int get radius => 2;

  @override
  Set<String> get blockNames => {rim, water, posts, roof};

  @override
  void build(StructureSite site) {
    for (var z = -1; z <= 1; z++) {
      for (var x = -1; x <= 1; x++) {
        final ring = x.abs() == 1 || z.abs() == 1;
        site.level(x, z, x, z, rim, floor: -deep - 1, clearTo: 2);
        for (var y = -deep; y <= 0; y++) {
          site.put(x, y, z, ring ? rim : water);
        }
        site.put(x, 3, z, roof);
      }
    }
    for (var y = 1; y <= 2; y++) {
      site.put(-1, y, 0, posts);
      site.put(1, y, 0, posts);
    }
  }
}
