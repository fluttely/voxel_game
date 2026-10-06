import 'dart:math' as math;

import '../spec/structure.dart';
import '../spec/structure_site.dart';

/// A tent pitched on the ground: a ridge of [cloth] 7 long along x over a
/// floor 5 wide, its four corner [poles] down to their own ground, a [chest]
/// inside and a [light] six blocks off on a pole of its own.
class Camp extends Structure {
  /// A camp of these blocks; every one left null is left out.
  const Camp({required this.cloth, required this.poles, this.chest, this.light});

  /// The tent's roof.
  final String cloth;

  /// Its corner posts, and the light's.
  final String poles;

  /// Under the ridge.
  final String? chest;

  /// Beside the tent.
  final String? light;

  @override
  int get radius => 7;

  @override
  Set<String> get blockNames => {cloth, poles, ?chest, ?light};

  @override
  void build(StructureSite site) {
    for (var z = -2; z <= 2; z++) {
      for (var x = -3; x <= 3; x++) {
        // The slope climbs by faces: a block under each step of the roof.
        final roof = 4 - z.abs();
        site.put(x, roof, z, cloth);
        site.put(x, roof - 1, z, cloth);
        if (x.abs() != 3) continue;
        // A corner pole stands on its own ground, the ends open.
        final foot = z.abs() == 2 ? math.min(0, site.surfaceAt(x, z)) : 0;
        for (var y = foot; y < roof - 1; y++) {
          site.put(x, y, z, z.abs() == 2 ? poles : 'air');
        }
      }
    }
    if (chest != null) site.put(0, 0, 0, chest!);
    final light = this.light;
    if (light == null) return;
    site.put(6, 0, 0, light);
    for (var y = math.min(-1, site.surfaceAt(6, 0)); y <= -1; y++) {
      site.put(6, y, 0, poles);
    }
  }
}
