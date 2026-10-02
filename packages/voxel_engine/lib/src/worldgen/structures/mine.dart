import 'dart:math' as math;

import '../spec/structure.dart';
import '../spec/structure_site.dart';

/// An abandoned mine: a head frame on the surface ([frame] floor, four
/// [posts], a [roof]) over a [ladder] shaft down to a corridor at [floorY],
/// three wide and three high, running [minLength] to [maxLength] blocks
/// along +x. Every fourth block a support of [beams] under the [roof]
/// block, a pair of [light]s on every second one; a [rail] down the middle
/// to the [chest] at the end, a [spawner] before it a third of the time.
/// Where the corridor's shell meets air or a liquid it is sealed with
/// [walls]; where it meets the world's rock, [veins] show through it, each
/// in its per cent of the cells.
class Mine extends Structure {
  /// A mine of these blocks; every one left null or empty is left out.
  const Mine({
    required this.frame,
    required this.posts,
    required this.roof,
    required this.ladder,
    required this.beams,
    required this.walls,
    this.rail,
    this.light,
    this.chest,
    this.spawner,
    this.veins = const {},
    this.floorY = 24,
    this.minLength = 20,
    this.maxLength = 30,
  }) : assert(minLength >= 8 && minLength <= maxLength);

  /// The head frame's floor.
  final String frame;

  /// The head frame's corner posts.
  final String posts;

  /// The head frame's roof and the supports' crossbeams.
  final String roof;

  /// The shaft's ladder.
  final String ladder;

  /// The supports' uprights.
  final String beams;

  /// What seals the corridor where it opens into a cave or the sea.
  final String walls;

  /// Down the middle of the corridor, or null for none.
  final String? rail;

  /// On every second support, in place of its crossbeam's ends.
  final String? light;

  /// At the corridor's end.
  final String? chest;

  /// Three blocks before the end, a third of the time.
  final String? spawner;

  /// Ores in the corridor's rock shell, with the per cent of the cells each
  /// takes.
  final Map<String, int> veins;

  /// The corridor's floor height, or eight under the site where the ground is
  /// lower.
  final int floorY;

  /// The shortest corridor.
  final int minLength;

  /// The longest corridor.
  final int maxLength;

  @override
  int get radius => maxLength + 2;

  /// Only the head frame keeps the trees off; the corridor runs under them.
  @override
  int get clearing => 2;

  @override
  Set<String> get blockNames => {
    frame,
    posts,
    roof,
    ladder,
    beams,
    walls,
    ?rail,
    ?light,
    ?chest,
    ?spawner,
    ...veins.keys,
  };

  @override
  void build(StructureSite site) {
    final h = site.roll(41);
    final length = minLength + h % (maxLength - minLength + 1);
    final fy = math.min(floorY, site.y - 8) - site.y;
    for (var z = -1; z <= 1; z++) {
      for (var x = -1; x <= 1; x++) {
        site.level(x, z, x, z, frame, floor: -1, clearTo: 3);
        site.put(x, -1, z, frame);
        site.put(x, 2, z, roof);
        if (x.abs() == 1 && z.abs() == 1) {
          site.put(x, 0, z, posts);
          site.put(x, 1, z, posts);
        }
      }
    }
    for (var y = fy + 1; y <= 0; y++) {
      site.put(0, y, 0, ladder);
    }
    for (var x = 1; x <= length; x++) {
      for (var z = -2; z <= 2; z++) {
        for (var y = 0; y <= 4; y++) {
          if (z.abs() <= 1 && y >= 1 && y <= 3) {
            site.put(x, fy + y, z, 'air');
          } else if (site.isOpen(x, fy + y, z)) {
            site.put(x, fy + y, z, walls);
          } else if (site.isRock(x, fy + y, z)) {
            final vein = _vein(site.hashAt(x, fy + y, z) % 100);
            if (vein != null) site.put(x, fy + y, z, vein);
          }
        }
      }
      if (x % 4 != 2) continue;
      final lit = light != null && x % 8 == 2;
      for (var y = 1; y <= 2; y++) {
        site.put(x, fy + y, -1, beams);
        site.put(x, fy + y, 1, beams);
      }
      site.put(x, fy + 3, 0, roof);
      site.put(x, fy + 3, -1, lit ? light! : roof);
      site.put(x, fy + 3, 1, lit ? light! : roof);
    }
    if (rail != null) {
      for (var x = 1; x < length; x++) {
        site.put(x, fy + 1, 0, rail!);
      }
    }
    if (chest != null) site.put(length, fy + 1, 0, chest!);
    if (spawner != null && (h >> 8) % 3 == 0) site.put(length - 3, fy + 1, 0, spawner!);
  }

  String? _vein(int roll) {
    var upTo = 0;
    for (final MapEntry(:key, :value) in veins.entries) {
      upTo += value;
      if (roll < upTo) return key;
    }
    return null;
  }
}
