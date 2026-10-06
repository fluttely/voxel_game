import 'dart:math' as math;

import '../spec/structure.dart';
import '../spec/structure_site.dart';

/// A clearing with [minHuts] to [maxHuts] huts on a ring around a well, each
/// hut sat on its own ground with its door to the well and a [path] from the
/// door to it, and a fenced [farm] off to one side.
///
/// A hut is 5 x 5: a [floor] (and its foundation down to the ground), [walls]
/// with [corners], a [window] facing the door, a [roof] with a rim of
/// [roofRim]; inside a [chest] and a [bed] at the back, a [torch], and a
/// [workbench] or a [furnace] in two of them. The well is a 3 x 3 [wellRim]
/// around [water], four [corners] holding a [roof]; [light]s stand beside it.
class Village extends Structure {
  /// A village of these blocks; every one left null is left out.
  const Village({
    required this.floor,
    required this.walls,
    required this.corners,
    required this.roof,
    required this.path,
    required this.wellRim,
    required this.water,
    this.roofRim,
    this.window,
    this.chest,
    this.bed,
    this.torch,
    this.workbench,
    this.furnace,
    this.light,
    this.farm,
    this.minHuts = 4,
    this.maxHuts = 7,
  }) : assert(minHuts >= 1 && minHuts <= maxHuts);

  /// The huts' floors and foundations, and what levels the well.
  final String floor;

  /// The huts' walls.
  final String walls;

  /// The huts' corner posts and the well's.
  final String corners;

  /// The huts' ceilings and the well's roof.
  final String roof;

  /// The paths, laid in the ground.
  final String path;

  /// The well's ring.
  final String wellRim;

  /// The well's water, and the farm's channel.
  final String water;

  /// The rim and cap on a hut's roof, or null for a flat roof.
  final String? roofRim;

  /// A hut's window, or null for a wall there.
  final String? window;

  /// In every hut, at the back.
  final String? chest;

  /// In every hut, at the back.
  final String? bed;

  /// In every hut.
  final String? torch;

  /// In the third hut.
  final String? workbench;

  /// In the fourth hut.
  final String? furnace;

  /// Beside the well, two.
  final String? light;

  /// The fenced field, or null for none.
  final VillageFarm? farm;

  /// The fewest huts.
  final int minHuts;

  /// The most huts.
  final int maxHuts;

  /// How far the huts stand from the well, at the least.
  static const int ring = 11;

  @override
  int get radius => 24;

  @override
  Set<String> get blockNames => {
    floor,
    walls,
    corners,
    roof,
    path,
    wellRim,
    water,
    ?roofRim,
    ?window,
    ?chest,
    ?bed,
    ?torch,
    ?workbench,
    ?furnace,
    ?light,
    ...?farm?.blockNames,
  };

  /// How many huts the village at [site] has.
  int hutCount(StructureSite site) => minHuts + site.roll(51) % (maxHuts - minHuts + 1);

  /// Where hut [i] of the village at [site] stands, site-relative.
  ({int x, int z}) hutAt(StructureSite site, int i) {
    final n = hutCount(site);
    final a = i * math.pi * 2 / n + (site.roll(52) % 100) / 100.0;
    final r = ring + site.roll(53 + i) % 3;
    return (x: (math.cos(a) * r).round(), z: (math.sin(a) * r).round());
  }

  @override
  void build(StructureSite site) {
    for (var i = 0; i < hutCount(site); i++) {
      final hut = hutAt(site, i);
      final door = hut.z > 0 ? -1 : 1;
      _hut(site, hut.x, site.surfaceAt(hut.x, hut.z), hut.z, door, i);
      _path(site, hut.x, hut.z + 3 * door);
    }
    for (var z = -1; z <= 1; z++) {
      for (var x = -1; x <= 1; x++) {
        final rim = x.abs() == 1 || z.abs() == 1;
        site.level(x, z, x, z, floor, floor: -1, clearTo: 5);
        site.put(x, 0, z, rim ? wellRim : water);
        site.put(x, -1, z, rim ? wellRim : water);
        for (var y = 1; y < 4; y++) {
          if (x.abs() == 1 && z.abs() == 1) site.put(x, y, z, corners);
        }
        site.put(x, 4, z, roof);
      }
    }
    if (light != null) {
      site.put(3, 0, 0, light!);
      site.put(-3, 0, 0, light!);
    }
    if (farm != null) farm!.build(site, 5, -ring - 6, water);
  }

  /// A path from ([fromX], [fromZ]) to the well, along x then along z, one
  /// block wide, laid in each column's own ground.
  void _path(StructureSite site, int fromX, int fromZ) {
    final stepX = fromX > 0 ? -1 : 1, stepZ = fromZ > 0 ? -1 : 1;
    for (var x = fromX; x != 0; x += stepX) {
      if (x.abs() <= 2 && fromZ.abs() <= 2) break;
      final y = site.surfaceAt(x, fromZ);
      site.put(x, y - 1, fromZ, path);
      site.put(x, y, fromZ, 'air');
    }
    for (var z = fromZ; z != 0; z += stepZ) {
      if (z.abs() <= 2) break;
      final y = site.surfaceAt(0, z);
      site.put(0, y - 1, z, path);
      site.put(0, y, z, 'air');
    }
  }

  /// Hut [variant] at site-relative ([cx], [cy], [cz]), its door on the
  /// [door] (+1 or -1) side along z.
  void _hut(StructureSite site, int cx, int cy, int cz, int door, int variant) {
    const half = 2, h = 4;
    final doorZ = door * half;
    for (var z = -half; z <= half; z++) {
      for (var x = -half; x <= half; x++) {
        site.level(cx + x, cz + z, cx + x, cz + z, floor, floor: cy - 1, clearTo: cy + h + 2);
        final wall = x.abs() == half || z.abs() == half;
        final corner = x.abs() == half && z.abs() == half;
        for (var y = -2; y <= h + 1; y++) {
          var name = 'air';
          if (y <= 0) {
            name = floor;
          } else if (y == h) {
            name = roof;
          } else if (y == h + 1) {
            if (roofRim != null && (wall || (x == 0 && z == 0))) name = roofRim!;
          } else if (corner) {
            name = corners;
          } else if (wall) {
            final doorway = z == doorZ && x == 0 && y <= 2;
            final pane = window != null && y == 2 && x == 0 && z == -doorZ;
            if (!doorway) name = pane ? window! : walls;
          }
          site.put(cx + x, cy + y, cz + z, name);
        }
      }
    }
    final back = -door * (half - 1), front = door * (half - 1);
    if (chest != null) site.put(cx - 1, cy + 1, cz + back, chest!);
    if (bed != null) site.put(cx + 1, cy + 1, cz + back, bed!);
    if (torch != null) site.put(cx - 1, cy + 1, cz, torch!);
    if (variant == 2 && workbench != null) site.put(cx + 1, cy + 1, cz + front, workbench!);
    if (variant == 3 && furnace != null) site.put(cx - 1, cy + 1, cz + front, furnace!);
  }
}

/// A village's field: 9 x 7, fenced, [crop] on [tilled] soil in rows
/// either side of a channel of the village's water, its ground [soil], a gate
/// on the side towards the village and a [torch] on the post beside it.
class VillageFarm {
  /// A field of these blocks; [torch] left null is left out.
  const VillageFarm({required this.soil, required this.tilled, required this.crop, required this.fence, this.torch});

  /// What the field is raised on, and its edge.
  final String soil;

  /// What the crop grows on.
  final String tilled;

  /// The crop, grown.
  final String crop;

  /// The fence around it.
  final String fence;

  /// On the post beside the gate.
  final String? torch;

  /// Every block it uses.
  Set<String> get blockNames => {soil, tilled, crop, fence, ?torch};

  /// Draws the field centred on site-relative ([fx], [fz]), its channel of
  /// [water], the gate on its +z side.
  void build(StructureSite site, int fx, int fz, String water) {
    final fy = site.surfaceAt(fx, fz);
    for (var z = -3; z <= 3; z++) {
      for (var x = -4; x <= 4; x++) {
        final edge = x.abs() == 4 || z.abs() == 3;
        site.level(fx + x, fz + z, fx + x, fz + z, soil, floor: fy - 1, clearTo: fy + 3);
        if (edge) {
          site.put(fx + x, fy - 1, fz + z, soil);
          site.put(fx + x, fy, fz + z, fence);
        } else if (z == 0) {
          site.put(fx + x, fy - 1, fz + z, water);
        } else {
          site.put(fx + x, fy - 1, fz + z, tilled);
          site.put(fx + x, fy, fz + z, crop);
        }
      }
    }
    site.put(fx, fy, fz + 3, 'air'); // the gate
    if (torch != null) site.put(fx + 4, fy + 1, fz + 3, torch!);
  }
}
