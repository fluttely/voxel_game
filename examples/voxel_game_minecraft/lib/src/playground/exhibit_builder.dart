import 'dart:math' as math;

import 'package:voxel_game/voxel_game.dart';

import '../spec/world_table.dart';
import '../waypoints/waypoints.dart';
import 'playground.dart';
import 'playground_zone.dart';

/// Writes the playground's exhibits into a loaded world, block by block, over
/// whatever stands there ([build]), and clears one back to the bare plaza
/// ([clear]). The hub's chests are filled with every item, the circuits'
/// levers left on, the crops planted growing; what lives there is the
/// playground's to place (`Playground`).
class ExhibitBuilder {
  /// The builder of [game]'s exhibits.
  ExhibitBuilder(this.game);

  /// The game built in.
  final VoxelGame game;

  /// Blocks written so far.
  int edits = 0;

  static const int _floor = Playground.floor;

  /// The farm's four pens, what each holds.
  static const List<List<String>> pens = [
    ['sheep', 'sheep', 'sheep'],
    ['cow', 'cow', 'pig', 'pig'],
    ['chicken', 'chicken', 'chicken', 'chicken'],
    ['bear', 'ocelot'],
  ];

  /// The arena's creatures, an elite of three of them among them.
  static const List<String> arenaMobs = [
    'zombie',
    'skeleton',
    'spider',
    'cave_slime',
    'slime',
    'snow_golem',
    'scorpion',
    'bat',
    'dark_skeleton',
    'magma_cube',
    'blaze',
    'giant_zombie',
    'venomous_spider',
    'burning_skeleton',
  ];

  /// The arena's boss plates: the boss each calls, and the block under it.
  static const List<(String, String)> bossPlates = [
    ('boomer', 'mossy_stone_bricks'),
    ('troll', 'bone_block'),
    ('yeti', 'snow'),
    ('scorpion_king', 'sandstone'),
    ('mummy_king', 'gold_block'),
    ('underworld_lord', 'nether_brick'),
  ];

  /// Where the arena's spawner block stands.
  static IVec3 arenaSpawnerCell(PlaygroundZone z) => IVec3(z.cx - 12, _floor, z.cz - 12);

  /// Where the arena's gold button is, on its gold block.
  static IVec3 arenaRefillCell(PlaygroundZone z) => IVec3(z.cx + 4, _floor + 1, z.cz + 16);

  /// Where the arena's [i]th boss plate is.
  static IVec3 bossPlateCell(PlaygroundZone z, int i) => IVec3(z.cx - 12 + i * 3, _floor, z.cz + 19);

  /// The rail loop's north-west corner.
  static IVec3 railStart(PlaygroundZone z) => IVec3(z.cx - 14, _floor, z.cz - 8);

  /// The lights of the dark hall.
  static const List<String> lightSources = [
    'torch',
    'wall_torch',
    'lamp',
    'glowstone',
    'redstone_lamp_on',
    'lava',
    'mushroom',
    'enchanting_table',
    'waypoint',
    'fortress_core',
    'brewing_stand',
  ];

  /// Pedestals a row in the gallery.
  static const int galleryColumns = 13;

  /// Every block of [blocks] but air, the liquids, the portal (lit in the
  /// water exhibit) and the spawner (it is the arena's).
  static List<int> galleryBlocks(BlockRegistry<BlockType> blocks) => [
    for (var i = 1; i < blocks.count; i++)
      if (blocks.liquidOf(i) == null && blocks.idOf(i) != 'portal' && blocks.idOf(i) != 'spawner') i,
  ];

  /// Every item of [items]: the blocks', the tools, the weapons, the food,
  /// the armour, then the rest, by name in each.
  static List<String> libraryItems(ItemRegistry items) {
    int kind(ItemType t) => switch (t) {
      ItemType(block: _?) => 0,
      ItemType(tool: _?) => 1,
      ItemType(launcher: _?) => 2,
      ItemType(damage: > 1) => 2,
      ItemType(food: _?) => 3,
      ItemType(armor: _?) => 4,
      _ => 5,
    };
    final all = items.all.toList()
      ..sort((a, b) {
        final k = kind(a).compareTo(kind(b));
        return k != 0 ? k : a.name.compareTo(b.name);
      });
    return [for (final t in all) t.id];
  }

  /// Writes exhibit [z].
  void build(PlaygroundZone z) {
    switch (z.id) {
      case 'hub':
        _hub(z);
      case 'blocks':
        _gallery(z);
      case 'building':
        _shapes(z);
      case 'redstone':
        _redstone(z);
      case 'rails':
        _rails(z);
      case 'water':
        _water(z);
      case 'farm':
        _farm(z);
      case 'arena':
        _arena(z);
      case 'caves':
        _caves(z);
      default:
        throw ArgumentError.value(z.id, 'z', 'no such exhibit');
    }
  }

  /// [z] as the untouched plaza: air over the floor, grass and dirt under it.
  void clear(PlaygroundZone z) {
    final top = z.id == 'hub' ? _floor + 24 : _floor + 12;
    const h = PlaygroundZone.half;
    final x0 = z.cx - h, x1 = z.cx + h - 1, z0 = z.cz - h, z1 = z.cz + h - 1;
    _fill(x0, _floor, z0, x1, top, z1, 'air');
    _fill(x0, _floor - 4, z0, x1, _floor - 2, z1, 'dirt');
    _fill(x0, _floor - 1, z0, x1, _floor - 1, z1, 'grass');
  }

  void _set(int x, int y, int z, String block) => _setId(x, y, z, game.blocks.indexOf(block));

  void _setId(int x, int y, int z, int id) {
    if (game.world.setBlock(IVec3(x, y, z), id)) edits += 1;
  }

  // Every cell of the box between the two corners, both in.
  void _fill(int x0, int y0, int z0, int x1, int y1, int z1, String block) {
    final id = game.blocks.indexOf(block);
    for (var x = math.min(x0, x1); x <= math.max(x0, x1); x++) {
      for (var y = math.min(y0, y1); y <= math.max(y0, y1); y++) {
        for (var z = math.min(z0, z1); z <= math.max(z0, z1); z++) {
          _setId(x, y, z, id);
        }
      }
    }
  }

  // The four walls of the box, both corners in.
  void _ring(int x0, int y0, int z0, int x1, int y1, int z1, String block) {
    _fill(x0, y0, z0, x1, y1, z0, block);
    _fill(x0, y0, z1, x1, y1, z1, block);
    _fill(x0, y0, z0, x0, y1, z1, block);
    _fill(x1, y0, z0, x1, y1, z1, block);
  }

  // A chest at the cell, holding [items].
  void _chest(IVec3 at, Iterable<(String, int)> items) {
    _set(at.x, at.y, at.z, 'chest');
    final store = game.blockRules.storeAt(at);
    for (final (id, n) in items) {
      store.add(id, n);
    }
  }

  // The lever at the cell, put down and flipped on.
  void _leverOn(int x, int y, int z) {
    _set(x, y, z, 'lever_off');
    game.useSignal(IVec3(x, y, z));
  }

  // --- hub ---------------------------------------------------------------------------

  void _hub(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = _floor;
    _fill(cx - 10, f - 1, cz - 10, cx + 10, f - 1, cz + 14, 'stone_bricks');
    // The glider tower: a hollow 5 x 5 shaft with a ladder up its north wall, a
    // railed platform with a gap to the south to jump from, glowstone corners.
    const top = 18;
    _ring(cx - 2, f, cz - 2, cx + 2, f + top - 1, cz + 2, 'stone_bricks');
    _fill(cx, f, cz + 2, cx, f + 1, cz + 2, 'air');
    for (final y in [f + 4, f + 9, f + 14]) {
      _set(cx - 2, y, cz, 'glass');
      _set(cx + 2, y, cz, 'glass');
    }
    _fill(cx - 4, f + top, cz - 4, cx + 4, f + top, cz + 4, 'stone_bricks');
    _fill(cx, f, cz - 1, cx, f + top, cz - 1, 'ladder');
    _set(cx, f + 2, cz + 1, 'lamp');
    for (var dx = -4; dx <= 4; dx++) {
      for (var dz = -4; dz <= 4; dz++) {
        if (dx.abs() != 4 && dz.abs() != 4) continue;
        if (dz == 4 && dx.abs() <= 1) continue;
        _set(cx + dx, f + top + 1, cz + dz, dx.abs() == 4 && dz.abs() == 4 ? 'glowstone' : 'oak_fence');
      }
    }
    // Lamp posts on the plaza's corners.
    for (final (dx, dz) in const [(-9, -9), (9, -9), (-9, 13), (9, 13)]) {
      _fill(cx + dx, f, cz + dz, cx + dx, f + 2, cz + dz, 'oak_fence');
      _set(cx + dx, f + 3, cz + dz, 'lamp');
    }
    // The library: every item, in chests along the west side.
    final items = libraryItems(game.items);
    var chests = 0;
    for (var start = 0; start < items.length; chests++) {
      final at = IVec3(cx - 10, f, cz - 6 + chests * 2);
      _set(at.x, at.y, at.z, 'chest');
      final store = game.blockRules.storeAt(at);
      final end = math.min(start + store.capacity, items.length);
      for (final id in items.sublist(start, end)) {
        store.add(id, game.items[id].stack);
      }
      start = end;
    }
    // The stations along the east side.
    const stations = ['crafting_table', 'furnace', 'brewing_stand', 'enchanting_table', 'bed'];
    for (var i = 0; i < stations.length; i++) {
      _set(cx + 10, f, cz - 6 + i * 2, stations[i]);
    }
    final wp = IVec3(cx + 3, f, cz + 10);
    _set(wp.x, wp.y, wp.z, Waypoints.block);
    Waypoints.of(game).add(game, wp, 'Playground Hub');
  }

  /// The world's structures the tour visits, by name, and what it calls
  /// them; how far south of the site it lands.
  static const Map<String, (String, int)> tourStructures = {
    'dungeon': ('Dungeon', 0),
    'tower': ('Tower', 7),
    'camp': ('Camp', 7),
    'village': ('Village', 6),
    'ruins': ('Ruin', 8),
    'well': ('Well', 5),
    'mine': ('Abandoned Mine', 0),
    'temple': ('Desert Temple', 9),
  };

  /// The biomes the tour visits, by name, and what it calls them.
  static const Map<String, String> tourBiomes = {
    'forest': 'Forest',
    'desert': 'Desert',
    'snow': 'Snow',
    'mountain': 'Mountains',
    'swamp': 'Swamp',
    'jungle': 'Jungle',
    'ocean': 'Ocean',
  };

  /// The world tour, set as waypoints with no block of their own
  /// (`Waypoints.mark`): one at the nearest structure of each kind within 48
  /// chunks, and one at the nearest column of each biome within 1.5 km.
  /// Returns their labels, in that order.
  List<String> tour() {
    const ox = PlaygroundZone.originX, oz = PlaygroundZone.originZ;
    final generator = game.world.generator;
    final best = <String, PlacedStructure>{};
    double far(int x, int z) => math.sqrt(((x - ox) * (x - ox) + (z - oz) * (z - oz)).toDouble());
    for (var dz = -48; dz <= 48; dz += 4) {
      for (var dx = -48; dx <= 48; dx += 4) {
        for (final s in generator.structuresNear(dx, dz)) {
          if (!tourStructures.containsKey(s.name)) continue;
          final had = best[s.name];
          if (had == null || far(s.x, s.z) < far(had.x, had.z)) best[s.name] = s;
        }
      }
    }
    final labels = <String>[];
    for (final MapEntry(key: name, value: (label, south)) in tourStructures.entries) {
      final s = best[name];
      if (s != null) labels.add(_stop('Tour: $label', s.x, s.z + south));
    }
    final biomeAt = <String, (int, int)>{};
    final biomeFar = <String, int>{};
    for (var z = -1536; z <= 1536; z += 48) {
      for (var x = -1536; x <= 1536; x += 48) {
        if (Playground.plaza.contains(x, z, 64)) continue;
        final b = generator.biomeAt(x, z).name;
        if (!tourBiomes.containsKey(b)) continue;
        final d = (x - ox) * (x - ox) + (z - oz) * (z - oz);
        if (d < (biomeFar[b] ?? 1 << 62)) {
          biomeFar[b] = d;
          biomeAt[b] = (x, z);
        }
      }
    }
    for (final MapEntry(key: b, value: label) in tourBiomes.entries) {
      final at = biomeAt[b];
      if (at != null) labels.add(_stop('Biome: $label', at.$1, at.$2));
    }
    return labels;
  }

  // A tour stop on the ground block of column (x, z), the sea's top over an ocean.
  String _stop(String label, int x, int z) {
    final y = math.max(game.world.generator.surfaceHeight(x, z) - 1, overworld.seaLevel);
    Waypoints.of(game).mark(game, IVec3(x, y, z), label);
    return label;
  }

  // --- block gallery -----------------------------------------------------------------

  void _gallery(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = _floor;
    final ids = galleryBlocks(game.blocks);
    for (var k = 0; k < ids.length; k++) {
      final x = cx - 18 + (k % galleryColumns) * 3;
      final zz = cz - 18 + (k ~/ galleryColumns) * 3;
      _set(x, f - 1, zz, 'stone_bricks');
      _set(x, f, zz, 'stone_bricks');
      _setId(x, f + 1, zz, ids[k]);
    }
    // The two liquids in glass tanks.
    for (final (dx, liquid) in const [(-4, 'water'), (4, 'lava')]) {
      final x = cx + dx, zz = cz + 18;
      _fill(x - 1, f, zz - 1, x + 1, f + 3, zz + 1, 'glass');
      _fill(x, f + 1, zz, x, f + 2, zz, liquid);
    }
  }

  // --- shapes & building -------------------------------------------------------------

  void _shapes(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = _floor;
    // A cottage: log corners, plank walls, glass windows, a door, a gable roof
    // of stairs (the south slope's high step is north), a bed, a chest, a torch.
    final x0 = cx - 18, z0 = cz - 18, x1 = x0 + 8, z1 = z0 + 6;
    _fill(x0, f - 1, z0, x1, f - 1, z1, 'oak_planks');
    _ring(x0, f, z0, x1, f + 3, z1, 'oak_planks');
    for (final (x, zz) in [(x0, z0), (x1, z0), (x0, z1), (x1, z1)]) {
      _fill(x, f, zz, x, f + 3, zz, 'oak_log');
    }
    for (final x in [x0 + 2, x0 + 6]) {
      _fill(x, f + 1, z0, x, f + 2, z0, 'glass');
      _fill(x, f + 1, z1, x, f + 2, z1, 'glass');
    }
    _fill(x0, f + 1, z0 + 3, x0, f + 2, z0 + 3, 'glass');
    _fill(x1, f + 1, z0 + 3, x1, f + 2, z0 + 3, 'glass');
    _set(x0 + 4, f, z1, 'door_z');
    _set(x0 + 4, f + 1, z1, 'door_z');
    for (var k = 0; k < 4; k++) {
      _fill(x0 - 1, f + 4 + k, z1 + 1 - k, x1 + 1, f + 4 + k, z1 + 1 - k, 'oak_stairs_n');
      _fill(x0 - 1, f + 4 + k, z0 - 1 + k, x1 + 1, f + 4 + k, z0 - 1 + k, 'oak_stairs_s');
    }
    _fill(x0 - 1, f + 7, z0 + 3, x1 + 1, f + 7, z0 + 3, 'oak_planks');
    _fill(x0 - 1, f + 8, z0 + 3, x1 + 1, f + 8, z0 + 3, 'oak_slab');
    for (final x in [x0, x1]) {
      for (var k = 1; k < 4; k++) {
        _fill(x, f + 4, z0 + k, x, f + 3 + k, z0 + k, 'oak_planks');
        _fill(x, f + 4, z1 - k, x, f + 3 + k, z1 - k, 'oak_planks');
      }
    }
    _set(x0 + 1, f, z0 + 1, 'bed');
    _set(x0 + 2, f, z0 + 1, 'chest');
    _set(x0 + 7, f, z0 + 1, 'crafting_table');
    _set(x0 + 7, f, z0 + 5, 'torch');
    // Stone stairs up to a railed platform, walking north.
    for (var k = 0; k < 5; k++) {
      _fill(cx + 4, f, cz - 10 - k, cx + 6, f + k - 1, cz - 10 - k, 'cobblestone');
      _fill(cx + 4, f + k, cz - 10 - k, cx + 6, f + k, cz - 10 - k, 'stone_stairs_n');
    }
    _fill(cx + 3, f, cz - 17, cx + 7, f + 4, cz - 15, 'stone_bricks');
    _ring(cx + 3, f + 5, cz - 17, cx + 7, f + 5, cz - 15, 'oak_fence');
    _set(cx + 5, f + 5, cz - 15, 'air');
    // Half steps: slab, plank, slab... rising to the north.
    for (var k = 0; k < 6; k++) {
      final y = f + k ~/ 2;
      if (k.isOdd) _fill(cx + 10, f, cz - 10 - k, cx + 10, y, cz - 10 - k, 'oak_planks');
      if (k.isEven) {
        if (y > f) _fill(cx + 10, f, cz - 10 - k, cx + 10, y - 1, cz - 10 - k, 'oak_planks');
        _set(cx + 10, y, cz - 10 - k, 'oak_slab');
      }
    }
    // One-block steps (walk into them: the auto-jump), three wide.
    for (var k = 0; k < 5; k++) {
      _fill(cx + 13, f, cz - 10 - k, cx + 15, f + k, cz - 10 - k, 'cobblestone');
    }
    // The climbing wall (3 high) and a ladder wall (5 high) with its top walkable.
    _fill(cx + 2, f, cz + 4, cx + 8, f + 2, cz + 4, 'stone_bricks');
    _fill(cx + 12, f, cz + 4, cx + 14, f + 4, cz + 6, 'stone_bricks');
    _fill(cx + 13, f, cz + 7, cx + 13, f + 4, cz + 7, 'ladder');
    // A fence pen with a gap.
    _ring(cx - 18, f, cz + 4, cx - 12, f, cz + 10, 'oak_fence');
    _set(cx - 15, f, cz + 10, 'air');
    // A wall with a wooden door and an iron door opened by a button on either side.
    _fill(cx - 4, f, cz + 14, cx + 6, f + 2, cz + 14, 'stone_bricks');
    _set(cx - 2, f, cz + 14, 'door_z');
    _set(cx - 2, f + 1, cz + 14, 'door_z');
    _set(cx + 3, f, cz + 14, 'iron_door_z');
    _set(cx + 3, f + 1, cz + 14, 'iron_door_z');
    _set(cx + 3, f, cz + 15, 'button');
    _set(cx + 3, f, cz + 13, 'button');
    // Every stairs facing, oak and stone, and the three slabs.
    const shapes = [
      'oak_stairs_n',
      'oak_stairs_e',
      'oak_stairs_s',
      'oak_stairs_w',
      'stone_stairs_n',
      'stone_stairs_e',
      'stone_stairs_s',
      'stone_stairs_w',
      'oak_slab',
      'stone_slab',
      'cobblestone_slab',
    ];
    for (var i = 0; i < shapes.length; i++) {
      _set(cx - 18 + i * 2, f, cz + 18, shapes[i]);
    }
  }

  // --- redstone ----------------------------------------------------------------------

  void _redstone(PlaygroundZone z) {
    final x0 = z.cx - 10, z0 = z.cz - 14, y = _floor;
    _fill(x0 - 3, y - 1, z0 - 2, x0 + 20, y - 1, z0 + 19, 'stone');
    // 1. A lever, five wires, a lamp: left on.
    _fill(x0 + 1, y, z0, x0 + 5, y, z0, 'wire_off');
    _set(x0 + 6, y, z0, 'redstone_lamp_off');
    _leverOn(x0, y, z0);
    // 2. A button, three wires, a lamp.
    _set(x0, y, z0 + 2, 'button');
    _fill(x0 + 1, y, z0 + 2, x0 + 3, y, z0 + 2, 'wire_off');
    _set(x0 + 4, y, z0 + 2, 'redstone_lamp_off');
    // 3. A pressure plate, three wires, a lamp.
    _set(x0, y, z0 + 4, 'pressure_plate');
    _fill(x0 + 1, y, z0 + 4, x0 + 3, y, z0 + 4, 'wire_off');
    _set(x0 + 4, y, z0 + 4, 'redstone_lamp_off');
    // 4. A lever, two wires, an iron door.
    _set(x0, y, z0 + 6, 'lever_off');
    _fill(x0 + 1, y, z0 + 6, x0 + 2, y, z0 + 6, 'wire_off');
    _set(x0 + 3, y, z0 + 6, 'iron_door_x');
    _set(x0 + 3, y + 1, z0 + 6, 'iron_door_x');
    // 5. A wooden door, opened by hand.
    _set(x0 + 3, y, z0 + 8, 'door_x');
    _set(x0 + 3, y + 1, z0 + 8, 'door_x');
    // 6. A lever and sixteen wires, left on: the sixteenth stays dark.
    _fill(x0 + 1, y, z0 + 10, x0 + 16, y, z0 + 10, 'wire_off');
    _leverOn(x0, y, z0 + 10);
    // 7. TNT under the third wire of a lever's run.
    _set(x0, y, z0 + 12, 'lever_off');
    _fill(x0 + 1, y, z0 + 12, x0 + 3, y, z0 + 12, 'wire_off');
    _set(x0 + 3, y - 1, z0 + 12, 'tnt');
    // 8. A piston facing east with a cobblestone in front, its lever behind.
    _set(x0 - 1, y, z0 + 14, 'lever_off');
    _set(x0, y, z0 + 14, 'piston_e');
    _set(x0 + 1, y, z0 + 14, 'cobblestone');
    // 9. A row of lamps lit along a wire.
    _set(x0, y, z0 + 16, 'lever_off');
    _fill(x0 + 1, y, z0 + 16, x0 + 10, y, z0 + 16, 'wire_off');
    for (var x = x0 + 2; x <= x0 + 10; x += 2) {
      _set(x, y, z0 + 17, 'redstone_lamp_off');
    }
  }

  // --- rails -------------------------------------------------------------------------

  /// The loop from [start], in driving order: the north side west to east
  /// over a hill two high, the east side, the south side back west (four
  /// powered rails), the west side.
  static List<IVec3> railLoop(IVec3 start) {
    final x0 = start.x, y = start.y, z0 = start.z;
    int hill(int i) => switch (i) {
      9 || 14 => 1,
      >= 10 && <= 13 => 2,
      _ => 0,
    };
    return [
      for (var i = 0; i < 24; i++) IVec3(x0 + i, y + hill(i), z0),
      for (var j = 1; j < 14; j++) IVec3(x0 + 23, y, z0 + j),
      for (var i = 22; i >= 0; i--) IVec3(x0 + i, y, z0 + 13),
      for (var j = 12; j >= 1; j--) IVec3(x0, y, z0 + j),
    ];
  }

  void _rails(PlaygroundZone z) {
    final start = railStart(z);
    final x0 = start.x, z0 = start.z, y = start.y;
    _set(x0 + 9, y, z0, 'stone');
    _fill(x0 + 10, y, z0, x0 + 13, y + 1, z0, 'stone');
    _set(x0 + 14, y, z0, 'stone');
    bool powered(IVec3 c) => c.z == z0 + 13 && c.x >= x0 + 10 && c.x <= x0 + 13;
    for (final c in railLoop(start)) {
      _set(c.x, c.y, c.z, powered(c) ? 'powered_rail_ns' : 'rail_ns');
    }
    _leverOn(x0 + 11, y, z0 + 14);
    // A short spur inside the loop.
    for (var i = 6; i <= 12; i++) {
      _set(x0 + i, y, z0 + 6, 'rail_ns');
    }
  }

  // --- water, lava, portal -----------------------------------------------------------

  void _water(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = _floor;
    // The pool, 16 x 12 and 6 deep, with a sunken chest.
    final px0 = cx - 12, pz0 = cz - 6, px1 = px0 + 15, pz1 = pz0 + 11;
    _fill(px0 - 1, f - 8, pz0 - 1, px1 + 1, f - 1, pz1 + 1, 'sandstone');
    _fill(px0, f - 7, pz0, px1, f - 7, pz1, 'sand');
    _fill(px0, f - 6, pz0, px1, f - 1, pz1, 'water');
    _ring(px0 - 1, f - 1, pz0 - 1, px1 + 1, f - 1, pz1 + 1, 'sand');
    _chest(IVec3(px0 + 3, f - 6, pz0 + 8), const [('gold_ingot', 12), ('diamond', 3), ('raw_salmon', 8)]);
    // The dock over the south edge.
    _fill(px0 + 7, f - 1, pz1 - 2, px0 + 8, f - 1, pz1 + 1, 'oak_planks');
    _set(px0 + 7, f, pz1 - 2, 'oak_fence');
    _set(px0 + 8, f, pz1 - 2, 'oak_fence');
    // A stone pillar in the middle with a source on top: a waterfall.
    _fill(px0 + 7, f - 6, pz0 + 4, px0 + 7, f + 4, pz0 + 4, 'stone');
    _set(px0 + 7, f + 5, pz0 + 4, 'water');
    // The lava basin behind a cobblestone gate holding back a water source.
    final lx0 = cx + 8, lz0 = cz - 4;
    _fill(lx0 - 3, f - 2, lz0 - 1, lx0 + 3, f - 1, lz0 + 3, 'stone');
    _fill(lx0, f - 1, lz0, lx0 + 2, f - 1, lz0 + 2, 'lava');
    _ring(lx0 - 1, f, lz0 - 1, lx0 + 3, f, lz0 + 3, 'glass');
    _set(lx0 - 1, f, lz0 + 1, 'cobblestone');
    _set(lx0 - 2, f, lz0 + 1, 'water');
    for (final (x, zz) in [(lx0 - 3, lz0 + 1), (lx0 - 2, lz0), (lx0 - 2, lz0 + 2)]) {
      _set(x, f, zz, 'glass');
    }
    // A lit portal to the Underworld.
    game.portals.build(game.spec.portals.single, IVec3(cx + 12, f, cz + 10), 'stone_bricks');
  }

  // --- farm & animals ----------------------------------------------------------------

  void _farm(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = _floor;
    // The field: farmland about a water channel, wheat at all three stages.
    final fx0 = cx - 18, fz0 = cz - 20;
    _fill(fx0, f - 2, fz0, fx0 + 10, f - 2, fz0 + 8, 'dirt');
    _fill(fx0, f - 1, fz0, fx0 + 10, f - 1, fz0 + 8, 'farmland');
    _fill(fx0, f - 1, fz0 + 4, fx0 + 10, f - 1, fz0 + 4, 'water');
    const rows = ['wheat_2', 'wheat_2', 'wheat_1', 'wheat_1', '', 'wheat_0', 'wheat_0', 'wheat_2', 'wheat_2'];
    for (var r = 0; r < rows.length; r++) {
      if (rows[r] == '') continue;
      _fill(fx0, f, fz0 + r, fx0 + 10, f, fz0 + r, rows[r]);
    }
    _ring(fx0 - 1, f, fz0 - 1, fx0 + 11, f, fz0 + 9, 'oak_fence');
    _set(fx0 + 5, f, fz0 + 9, 'air');
    // Four pens.
    for (var p = 0; p < pens.length; p++) {
      final x = cx - 18 + p * 10;
      _ring(x, f, cz - 6, x + 8, f, cz + 2, 'oak_fence');
    }
    // A stable for the companions.
    _fill(cx + 2, f - 1, cz + 8, cx + 14, f - 1, cz + 12, 'oak_planks');
    // Two market stalls for the villagers.
    for (final sx in [cx + 8, cx + 14]) {
      for (final (dx, dz) in const [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
        _fill(sx + dx, f, cz - 13 + dz, sx + dx, f + 2, cz - 13 + dz, 'oak_log');
      }
      _fill(sx - 1, f + 3, cz - 14, sx + 1, f + 3, cz - 12, 'oak_slab');
      _set(sx, f, cz - 11, 'chest');
    }
  }

  // --- monster arena -----------------------------------------------------------------

  void _arena(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = _floor;
    final x0 = cx - 15, x1 = cx + 14, z0 = cz - 15, z1 = cz + 14;
    _fill(x0 + 1, f - 1, z0 + 1, x1 - 1, f - 1, z1 - 1, 'sand');
    _ring(x0, f, z0, x1, f + 4, z1, 'cobblestone');
    // Glass bands to watch through.
    _ring(x0, f + 2, z0, x1, f + 3, z1, 'glass');
    for (final (x, zz) in [(x0, z0), (x1, z0), (x0, z1), (x1, z1)]) {
      _fill(x, f, zz, x, f + 4, zz, 'cobblestone');
    }
    _fill(x0, f + 5, z0, x1, f + 5, z1, 'stone_bricks');
    for (var x = x0 + 3; x < x1; x += 6) {
      for (var zz = z0 + 3; zz < z1; zz += 6) {
        _set(x, f + 5, zz, 'glowstone');
      }
    }
    _set(cx, f, z1, 'iron_door_z');
    _set(cx, f + 1, z1, 'iron_door_z');
    _set(cx, f, z1 + 1, 'button');
    _set(cx, f, z1 - 1, 'button');
    final sp = arenaSpawnerCell(z);
    _set(sp.x, sp.y, sp.z, 'spawner');
    final refill = arenaRefillCell(z);
    _set(refill.x, refill.y - 1, refill.z, 'gold_block');
    _set(refill.x, refill.y, refill.z, 'button');
    for (var i = 0; i < bossPlates.length; i++) {
      final p = bossPlateCell(z, i);
      _set(p.x, p.y - 1, p.z, bossPlates[i].$2);
      _set(p.x, p.y, p.z, 'pressure_plate');
    }
  }

  // --- light & mining ----------------------------------------------------------------

  void _caves(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = _floor;
    // The dark hall: dark stone, a roof, one door to the south.
    final hx0 = cx - 16, hx1 = cx + 3, hz0 = cz - 16, hz1 = cz - 3;
    _fill(hx0, f - 1, hz0, hx1, f - 1, hz1, 'stone');
    _ring(hx0, f, hz0, hx1, f + 5, hz1, 'dark_stone');
    _fill(hx0, f + 6, hz0, hx1, f + 6, hz1, 'dark_stone');
    _fill(cx - 7, f, hz1, cx - 6, f + 1, hz1, 'air');
    // Every light: six along the north wall (the wall torch and the lava need
    // it), the rest in a row across the middle of the hall.
    for (var i = 0; i < lightSources.length; i++) {
      final x = i < 6 ? hx0 + 2 + i * 3 : hx0 + 3 + (i - 6) * 3;
      final zz = i < 6 ? hz0 + 1 : hz0 + 7;
      switch (lightSources[i]) {
        case 'wall_torch':
          _set(x, f + 2, zz, 'wall_torch');
        case 'redstone_lamp_on':
          _set(x, f, zz, 'redstone_lamp_off');
          _leverOn(x, f, zz + 1);
        case 'lava':
          _set(x, f, hz0, 'lava');
          _set(x, f, zz, 'glass');
        case final light:
          _set(x, f, zz, light);
      }
    }
    // The wall of ores on the west side.
    const ores = [
      'coal_ore',
      'iron_ore',
      'gold_ore',
      'diamond_ore',
      'redstone_ore',
      'nether_quartz_ore',
      'obsidian',
      'clay',
      'gravel',
    ];
    for (var i = 0; i < ores.length; i++) {
      _fill(hx0 + 1, f + i % 3, hz0 + 4 + (i ~/ 3) * 2, hx0 + 1, f + i % 3, hz0 + 5 + (i ~/ 3) * 2, ores[i]);
    }
    // Falling sand and gravel: break the dirt block under a column.
    for (final (dx, block) in const [(8, 'sand'), (11, 'gravel')]) {
      _set(cx + dx, f, cz - 12, 'dirt');
      _fill(cx + dx, f + 1, cz - 12, cx + dx, f + 4, cz - 12, block);
    }
    // The mining shaft: a 3 x 3 hole with a ladder down to a lit ore chamber.
    const bottom = 12;
    final sx = cx + 8, sz = cz + 8;
    _fill(sx - 3, bottom - 1, sz - 3, sx + 3, f - 2, sz + 3, 'stone');
    _fill(sx - 1, bottom, sz - 1, sx + 1, f - 1, sz + 1, 'air');
    _fill(sx - 2, bottom, sz - 2, sx + 2, bottom + 2, sz + 2, 'air');
    _fill(sx, bottom, sz - 1, sx, f, sz - 1, 'ladder');
    _ring(sx - 2, f - 1, sz - 2, sx + 2, f - 1, sz + 2, 'stone_bricks');
    _ring(sx - 2, f, sz - 2, sx + 2, f, sz + 2, 'oak_fence');
    _set(sx, f, sz - 2, 'air');
    _set(sx, bottom + 3, sz + 1, 'lamp');
    for (final (x, zz, ore) in [
      (sx - 3, sz, 'diamond_ore'),
      (sx + 3, sz, 'gold_ore'),
      (sx, sz + 3, 'iron_ore'),
      (sx - 3, sz + 1, 'diamond_ore'),
      (sx + 3, sz - 1, 'redstone_ore'),
    ]) {
      _set(x, bottom + 1, zz, ore);
    }
  }
}
