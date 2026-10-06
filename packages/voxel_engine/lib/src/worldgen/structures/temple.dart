import '../spec/structure.dart';
import '../spec/structure_site.dart';

/// A desert temple: a step pyramid of [stone], 9 x 9 at its base and five
/// steps of two blocks, over a 3 x 3 x 3 chamber reached by a corridor from
/// the south (+z). In the chamber two [chest]s stand against the north wall
/// under a [light], and a [plate] in the middle of its floor sits on a
/// [trap] (TNT: the plate powers it). Every furnishing left null is left out.
class Temple extends Structure {
  /// A temple of these blocks.
  const Temple({required this.stone, this.chest, this.light, this.plate, this.trap});

  /// The pyramid and its foundation.
  final String stone;

  /// The two chests.
  final String? chest;

  /// The light over the chamber.
  final String? light;

  /// The plate in the middle of the chamber's floor.
  final String? plate;

  /// The block under the [plate]: what stepping on it sets off.
  final String? trap;

  @override
  int get radius => 5;

  @override
  Set<String> get blockNames => {stone, ?chest, ?light, ?plate, ?trap};

  @override
  void build(StructureSite site) {
    site.level(-4, -4, 4, 4, stone, floor: -1, clearTo: 12);
    for (var step = 0; step < 5; step++) {
      final half = 4 - step;
      site.fill(-half, step * 2, -half, half, step * 2 + 1, half, stone);
    }
    site.fill(-1, 1, -1, 1, 3, 1, 'air');
    site.fill(0, 1, 2, 0, 2, 4, 'air');
    final chest = this.chest, light = this.light, plate = this.plate, trap = this.trap;
    if (trap != null) site.put(0, -1, 0, trap);
    if (plate != null) site.put(0, 0, 0, plate);
    if (chest != null) {
      site.put(-1, 1, -1, chest);
      site.put(1, 1, -1, chest);
    }
    if (light != null) site.put(0, 4, 0, light);
  }
}
