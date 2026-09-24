import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import '../core/blocks.dart';
import '../core/items.dart';
import '../core/species.dart';
import '../entities/mob.dart';
import '../player/player.dart';
import '../world/terrain_generator.dart';
import '../world/voxel_world.dart';
import 'game.dart';
import 'game_state.dart';
import 'inventory.dart';
import 'portals.dart';
import 'rails.dart';
import 'sfx.dart';
import 'weather.dart';

/// One exhibit of the playground: a [Playground.zoneSize] square of the plaza
/// at grid cell ([gx], [gz]) around the hub, with the card the player reads on
/// entering it.
class PlaygroundZone {
  const PlaygroundZone(this.id, this.gx, this.gz, this.title, this.hint);
  final String id;
  final int gx, gz;
  final String title;
  final String hint;

  int get cx => Playground.centreX + gx * Playground.zoneSize;
  int get cz => Playground.centreZ + gz * Playground.zoneSize;

  bool contains(double x, double z) =>
      x >= cx - Playground.half && x < cx + Playground.half && z >= cz - Playground.half && z < cz + Playground.half;
}

/// Stage 33: the playground, a creative world made to show every feature at
/// once. The generator flattens a 144 x 144 plaza around the spawn
/// (`TerrainGenerator.playground`); this class lays nine exhibits on it in a
/// 3 x 3 grid, each built the first time its chunks are loaded (a block write
/// into an unloaded chunk is dropped) and remembered in the save, so a reload
/// keeps the player's changes. Creatures that the save does not keep (the zoo,
/// the arena) come back on every boot. F7 cycles the weather, F8 the time of
/// day, F9 rebuilds the exhibit the player stands in; the waypoint in the hub
/// opens the world tour (the nearest real structure of each kind and the
/// nearest spot of each biome).
class Playground extends ChangeNotifier {
  Playground(this.game);

  final Game game;

  static const int version = 1;
  static const int centreX = 8, centreZ = 8, zoneSize = 48, half = 24;
  static const int floor = TerrainGenerator.plazaFloor;
  static const double cardSeconds = 12.0;

  static Vector3 get spawn => Vector3(centreX + 0.5, floor + 0.1, centreZ + 12.5);

  static const List<PlaygroundZone> zones = [
    PlaygroundZone('hub', 0, 0, 'Playground Hub',
        'Climb the tower and glide off with G. The chests hold every item. Right click the waypoint for the world tour.\nF5 fly · F7 weather · F8 time of day · F9 rebuild the exhibit you stand in'),
    PlaygroundZone('blocks', 0, -1, 'Block Gallery', 'Every block in the game, one on each pedestal. Aim at a block to read its name.'),
    PlaygroundZone('building', 1, -1, 'Shapes & Building',
        'Slabs, stairs, fences, doors, ladders and glass. Walk into a one-block step to hop up. The tall wall is for climbing (turn it on in Settings).'),
    PlaygroundZone('redstone', 1, 0, 'Redstone',
        'Flip the levers, press the buttons, stand on the plate. Wires carry power 15 blocks to lamps, iron doors, pistons and TNT.'),
    PlaygroundZone('rails', 1, 1, 'Rails & Minecarts',
        'A loop with a hill and a powered stretch. F beside a cart to ride, W and S to push. The chest cart carries cargo.'),
    PlaygroundZone('water', 0, 1, 'Water, Lava & Portal',
        'Dive into the pool, row the boat, fish from the dock. Break the cobblestone to pour water on lava. Stand in the portal to reach the Underworld.'),
    PlaygroundZone('farm', -1, 1, 'Farm & Animals',
        'Wheat at every stage, pens of animals, a tamed horse (F to ride), a wolf and a parrot, and villagers who trade (F).'),
    PlaygroundZone('arena', -1, 0, 'Monster Arena',
        'Every monster waits behind the iron door (press a button). Step on a plate to summon a boss inside. The gold button refills the arena.'),
    PlaygroundZone('caves', -1, -1, 'Light & Mining',
        'Every light source in the dark hall, a wall of ores, falling sand and gravel, and a ladder shaft down to the diamonds.'),
  ];

  static PlaygroundZone zone(String id) => zones.firstWhere((z) => z.id == id);

  /// Zones whose blocks are in the world (saved); zones whose creatures this
  /// session already placed.
  final Set<String> built = {};
  final Set<String> _populated = {};

  /// Blocks the builders wrote, for the probe.
  int edits = 0;

  /// The world tour's labels, in the order they were found (for the probe).
  final List<String> tour = [];

  PlaygroundZone? current;
  double _zoneTime = 0.0;
  bool cardVisible = false;
  double _pollTimer = 0.0;
  double _spawnerTimer = 0.0;
  IVec3? _onPlate;
  bool _refillWasOn = false;
  int _timeIndex = 0;
  final Map<String, Mob> _summoned = {};

  VoxelWorld get world => game.world;
  Player get player => game.player;

  Map<String, Object> toJson() => {'version': version, 'built': built.toList()};

  /// A save from another layout version rebuilds every zone over what is there.
  void fromJson(Map<String, dynamic> d) {
    built.clear();
    if ((d['version'] as num?)?.toInt() != version) return;
    for (final id in (d['built'] as List<dynamic>? ?? const [])) {
      built.add(id.toString());
    }
  }

  /// A fresh playground: the showcase kit, a few levels to spend in the
  /// journal, the spawn facing the tower.
  void startFresh() {
    final inv = player.inventory;
    for (var i = 0; i < Inventory.size; i++) {
      inv.setSlot(i, null);
    }
    final kit = kitItems(player.playerClass);
    for (var i = 0; i < kit.length && i < Inventory.size; i++) {
      inv.setSlot(i, ItemStack(kit[i], Items.stackSize(kit[i])));
    }
    player.level = 10;
    player.talentPoints = 10;
    player.setLook(0.0, -0.1);
    game.timeOfDay = 0.3;
  }

  /// The hotbar (class weapon first) then the bag.
  static List<String> kitItems(String cls) => [
        Player.classes[cls]!.weapon, 'diamond_pickaxe', 'torch', 'glider', 'fishing_rod', 'flint_and_steel',
        'water_bucket', 'rail', 'minecart',
        'diamond_axe', 'diamond_shovel', 'shears', 'wooden_hoe', 'bucket', 'lava_bucket', 'milk_bucket', 'boat',
        'chest_minecart', 'powered_rail', 'bow', 'arrow', 'crystal_staff', 'iron_dagger', 'ancient_blade', 'diamond_armor',
        'wheat_seeds', 'wheat', 'bone', 'cooked_beef', 'health_potion', 'speed_potion', 'strength_potion', 'tnt', 'lever',
        'wire', 'waypoint',
      ];

  // --- the frame ---------------------------------------------------------------------

  /// Once per simulation tick on the host / solo.
  void tick(double dt) {
    final overworld = world.dimension == VoxelWorld.dimOverworld;
    _pollTimer -= dt;
    if (overworld && _pollTimer <= 0.0) {
      _pollTimer = 0.25;
      // One zone a poll: a first boot with every chunk loaded spreads its nine
      // builds over two seconds instead of one long frame.
      for (final z in zones) {
        if (!_zoneLoaded(z)) continue;
        if (!built.contains(z.id)) {
          build(z);
          break;
        }
        if (!_populated.contains(z.id)) _populate(z, false);
      }
    }
    _trackZone(dt, overworld);
    if (overworld && built.contains('arena')) _tickArena(dt);
  }

  PlaygroundZone? zoneAt(Vector3 p) {
    for (final z in zones) {
      if (z.contains(p.x, p.z)) return z;
    }
    return null;
  }

  bool _zoneLoaded(PlaygroundZone z) {
    for (var x = z.cx - half; x <= z.cx + half; x += VoxelWorld.sizeX) {
      for (var zz = z.cz - half; zz <= z.cz + half; zz += VoxelWorld.sizeZ) {
        if (!world.chunks.containsKey(VoxelWorld.chunkOfXZ(x, zz))) return false;
      }
    }
    return true;
  }

  void _trackZone(double dt, bool overworld) {
    final z = overworld ? zoneAt(player.position) : null;
    if (!identical(z, current)) {
      current = z;
      _zoneTime = 0.0;
      cardVisible = z != null;
      notifyListeners();
      return;
    }
    if (z == null) return;
    _zoneTime += dt;
    if (cardVisible && _zoneTime > cardSeconds) {
      cardVisible = false;
      notifyListeners();
    }
  }

  // --- the showcase keys -------------------------------------------------------------

  void cycleWeather() {
    final next = (game.weather.kind.index + 1) % Weather.labels.length;
    game.weather.force(Weather.labels[next].toLowerCase());
    game.notify('Weather: ${Weather.labels[next]}');
  }

  static const List<(double, String)> timePresets = [(0.5, 'Noon'), (0.74, 'Sunset'), (0.0, 'Midnight'), (0.27, 'Sunrise')];

  void cycleTime() {
    final p = timePresets[_timeIndex];
    _timeIndex = (_timeIndex + 1) % timePresets.length;
    game.timeOfDay = p.$1;
    game.notify('Time: ${p.$2}');
  }

  /// F9: the exhibit under the player built again from scratch, its creatures,
  /// carts and boats replaced; the player steps to its south edge first.
  void rebuildHere() {
    final z = world.dimension == VoxelWorld.dimOverworld ? zoneAt(player.position) : null;
    if (z == null) {
      game.notify('Stand inside an exhibit to rebuild it');
      return;
    }
    if (player.cart != null) player.leaveCart();
    if (player.riding != null) player.leaveBoat();
    for (final m in game.mobs) {
      if (m.exhibit == z.id || (m.species.persistent && z.contains(m.position.x, m.position.z))) m.removed = true;
    }
    for (final c in game.carts) {
      if (z.contains(c.position.x, c.position.z)) c.removed = true;
    }
    for (final b in game.boats) {
      if (z.contains(b.position.x, b.position.z)) b.removed = true;
    }
    for (final d in game.drops) {
      if (z.contains(d.position.x, d.position.z)) d.removed = true;
    }
    if (z.id == 'arena') _summoned.clear();
    player.position = Vector3(z.cx + 0.5, floor + 0.1, z.cz + half - 1.5);
    player.velocity = Vector3.zero();
    player.syncNode();
    _clear(z);
    build(z);
    Sfx.play('quest', -6.0, 1.2);
    game.notify('${z.title} rebuilt');
  }

  // --- building ----------------------------------------------------------------------

  /// Writes zone [z]'s blocks (over whatever stands there) and places its
  /// creatures, carts and boats.
  void build(PlaygroundZone z) {
    switch (z.id) {
      case 'hub':
        _buildHub(z);
      case 'blocks':
        _buildGallery(z);
      case 'building':
        _buildShapes(z);
      case 'redstone':
        _buildRedstone(z);
      case 'rails':
        _buildRails(z);
      case 'water':
        _buildWater(z);
      case 'farm':
        _buildFarm(z);
      case 'arena':
        _buildArena(z);
      case 'caves':
        _buildCaves(z);
    }
    built.add(z.id);
    _populate(z, true);
  }

  static int _id(String block) => Blocks.indexOf(block);

  void _set(int x, int y, int z, String block) => _setId(x, y, z, _id(block));

  void _setId(int x, int y, int z, int id) {
    if (world.setBlock(IVec3(x, y, z), id)) edits += 1;
  }

  /// Every cell of the box between the two corners, both included.
  void _fill(int x0, int y0, int z0, int x1, int y1, int z1, String block) {
    final id = _id(block);
    for (var x = math.min(x0, x1); x <= math.max(x0, x1); x++) {
      for (var y = math.min(y0, y1); y <= math.max(y0, y1); y++) {
        for (var z = math.min(z0, z1); z <= math.max(z0, z1); z++) {
          _setId(x, y, z, id);
        }
      }
    }
  }

  /// The walls of the box (its four vertical faces), both corners included.
  void _ring(int x0, int y0, int z0, int x1, int y1, int z1, String block) {
    _fill(x0, y0, z0, x1, y1, z0, block);
    _fill(x0, y0, z1, x1, y1, z1, block);
    _fill(x0, y0, z0, x0, y1, z1, block);
    _fill(x1, y0, z0, x1, y1, z1, block);
  }

  /// A rebuild starts from the untouched plaza: air above the floor, grass and
  /// dirt below it.
  void _clear(PlaygroundZone z) {
    final top = z.id == 'hub' ? floor + 24 : floor + 12;
    final x0 = z.cx - half, x1 = z.cx + half - 1, z0 = z.cz - half, z1 = z.cz + half - 1;
    _fill(x0, floor, z0, x1, top, z1, 'air');
    _fill(x0, floor - 4, z0, x1, floor - 2, z1, 'dirt');
    _fill(x0, floor - 1, z0, x1, floor - 1, z1, 'grass');
  }

  Mob _mob(String species, Vector3 at, String exhibit, {Vector3? home, String affix = ''}) {
    final m = Mob();
    m.setupMob(world, game, player, Species.def(species));
    m.position = at.clone();
    final d = Species.def(species);
    if (d.hostile) m.scaleToLevel(player.level);
    if (affix != '') m.setAffix(affix);
    m.exhibit = exhibit;
    if (home != null) m.home = home.clone();
    game.addMob(m);
    return m;
  }

  /// A companion that rides the save like one the player tamed.
  Mob _pet(String species, Vector3 at) {
    final m = Mob();
    m.setupMob(world, game, player, Species.def(species));
    m.position = at.clone();
    m.restoreTamed();
    m.maxHp += 10.0;
    m.hp = m.maxHp;
    game.pets.add(m);
    game.entities.add(m.node);
    m.syncNode();
    return m;
  }

  Vector3 _at(int x, int y, int z) => Vector3(x + 0.5, y + 0.1, z + 0.5);

  /// Creatures for zone [z]. [fresh] (the build) also places what the save
  /// keeps afterwards: villagers, companions, carts and the boat.
  void _populate(PlaygroundZone z, bool fresh) {
    _populated.add(z.id);
    final cx = z.cx, cz = z.cz;
    switch (z.id) {
      case 'farm':
        const pens = [
          ['sheep', 'sheep', 'sheep'],
          ['cow', 'cow', 'pig', 'pig'],
          ['chicken', 'chicken', 'chicken', 'chicken'],
          ['bear', 'ocelot'],
        ];
        for (var p = 0; p < pens.length; p++) {
          final px = cx - 18 + p * 10 + 4, pz = cz - 2;
          for (var i = 0; i < pens[p].length; i++) {
            _mob(pens[p][i], _at(px - 2 + i * 2 % 5, floor, pz - 1 + i % 3), 'farm', home: _at(px, floor, pz));
          }
        }
        if (fresh) {
          for (final sx in [cx + 8, cx + 14]) {
            final v = _mob('villager', _at(sx, floor, cz - 13), '');
            v.makeTrader(_at(sx, floor, cz - 13));
          }
          _pet('horse', _at(cx + 4, floor, cz + 10));
          _pet('wolf', _at(cx + 8, floor, cz + 10));
          _pet('parrot', _at(cx + 12, floor + 1, cz + 10));
        }
      case 'arena':
        _refillArena();
      case 'rails':
        if (fresh) {
          final x0 = cx - 14, z0 = cz - 8;
          final cart = game.spawnMinecart(IVec3(x0 + 3, floor, z0), 'minecart');
          cart?.head(Rails.e);
          cart?.speed = 6.0;
          final chestCart = game.spawnMinecart(IVec3(x0 + 9, floor, z0 + 6), 'chest_minecart');
          for (final (id, n) in const [('iron_ingot', 16), ('gold_ingot', 8), ('diamond', 4), ('apple', 8)]) {
            chestCart?.cargo?.add(id, n);
          }
        }
      case 'water':
        if (fresh) game.spawnBoat(Vector3(cx - 8.0, floor - 0.1, cz + 0.5), 0.0);
    }
  }

  // --- hub -------------------------------------------------------------------------------

  void _buildHub(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = floor;
    _fill(cx - 10, f - 1, cz - 10, cx + 10, f - 1, cz + 14, 'stone_bricks');
    // The glider tower: a hollow 5 x 5 shaft with a ladder up its north wall, a
    // railed platform with a gap to the south to jump from, glowstone corners.
    const top = 18;
    _ring(cx - 2, f, cz - 2, cx + 2, f + top - 1, cz + 2, 'stone_bricks');
    _fill(cx, f, cz + 2, cx, f + 1, cz + 2, 'air'); // the door
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
    // Lamp posts on the plaza corners.
    for (final (dx, dz) in const [(-9, -9), (9, -9), (-9, 13), (9, 13)]) {
      _fill(cx + dx, f, cz + dz, cx + dx, f + 2, cz + dz, 'oak_fence');
      _set(cx + dx, f + 3, cz + dz, 'lamp');
    }
    // The item library: every item, in chests along the west side.
    final items = libraryItems();
    var chestIndex = 0;
    for (var start = 0; start < items.length; start += Inventory.size) {
      final at = IVec3(cx - 10, f, cz - 6 + chestIndex * 2);
      _set(at.x, at.y, at.z, 'chest');
      final inv = Inventory();
      for (final id in items.sublist(start, math.min(start + Inventory.size, items.length))) {
        inv.add(id, Items.stackSize(id));
      }
      game.chests[at] = inv;
      GameState.instance.placedChests.add(at.key);
      chestIndex += 1;
    }
    // The stations along the east side.
    const stations = ['crafting_table', 'furnace', 'brewing_stand', 'enchanting_table', 'bed'];
    for (var i = 0; i < stations.length; i++) {
      _set(cx + 10, f, cz - 6 + i * 2, stations[i]);
    }
    final wp = IVec3(cx + 3, f, cz + 10);
    _set(wp.x, wp.y, wp.z, 'waypoint');
    game.waypoints[wp] = 'Playground Hub';
    _registerTour();
  }

  /// Every item id, grouped by kind (blocks, tools, weapons, food, materials,
  /// equipment) and sorted by name inside a group.
  static List<String> libraryItems() {
    final ids = Items.defs.keys.toList();
    ids.sort((a, b) {
      final k = Items.kind(a).index.compareTo(Items.kind(b).index);
      return k != 0 ? k : Items.displayName(a).compareTo(Items.displayName(b));
    });
    return ids;
  }

  static const Map<int, String> tourStructures = {
    TerrainGenerator.structDungeon: 'Dungeon',
    TerrainGenerator.structTower: 'Tower',
    TerrainGenerator.structCamp: 'Camp',
    TerrainGenerator.structVillage: 'Village',
    TerrainGenerator.structRuin: 'Ruin',
    TerrainGenerator.structWell: 'Well',
    TerrainGenerator.structMine: 'Abandoned Mine',
    TerrainGenerator.structTemple: 'Desert Temple',
  };

  static const Map<int, String> tourBiomes = {
    TerrainGenerator.biomeForest: 'Forest',
    TerrainGenerator.biomeDesert: 'Desert',
    TerrainGenerator.biomeSnow: 'Snow',
    TerrainGenerator.biomeMountain: 'Mountains',
    TerrainGenerator.biomeSwamp: 'Swamp',
    TerrainGenerator.biomeJungle: 'Jungle',
    TerrainGenerator.biomeOcean: 'Ocean',
  };

  /// The world tour: a waypoint label (no block needed; the arrival reads the
  /// generator's height) at the nearest structure of each kind within 48
  /// chunks and the nearest column of each biome within 1.5 km.
  void _registerTour() {
    final best = <int, StructureAt>{};
    final bestD = <int, double>{};
    for (var dz = -48; dz <= 48; dz += 4) {
      for (var dx = -48; dx <= 48; dx += 4) {
        for (final s in world.structuresNear((x: dx, z: dz))) {
          if (!tourStructures.containsKey(s.type)) continue;
          final d = math.sqrt(math.pow(s.x - centreX, 2) + math.pow(s.z - centreZ, 2));
          if (d < (bestD[s.type] ?? double.infinity)) {
            bestD[s.type] = d;
            best[s.type] = s;
          }
        }
      }
    }
    for (final e in tourStructures.entries) {
      final s = best[e.key];
      if (s == null) continue;
      final off = switch (e.key) {
        TerrainGenerator.structVillage => 6,
        TerrainGenerator.structRuin => 8,
        TerrainGenerator.structWell => 5,
        TerrainGenerator.structTemple => 9,
        TerrainGenerator.structTower || TerrainGenerator.structCamp => 7,
        _ => 0,
      };
      _addTour('Tour: ${e.value}', s.x, s.z + off);
    }
    final biomeAt = <int, (int, int)>{};
    final biomeD = <int, int>{};
    for (var z = -1536; z <= 1536; z += 48) {
      for (var x = -1536; x <= 1536; x += 48) {
        if (TerrainGenerator.inPlaza(x, z, 64)) continue;
        final b = world.biomeAt(x, z);
        if (!tourBiomes.containsKey(b)) continue;
        final d = (x - centreX) * (x - centreX) + (z - centreZ) * (z - centreZ);
        if (d < (biomeD[b] ?? 1 << 62)) {
          biomeD[b] = d;
          biomeAt[b] = (x, z);
        }
      }
    }
    for (final e in tourBiomes.entries) {
      final at = biomeAt[e.key];
      if (at != null) _addTour('Biome: ${e.value}', at.$1, at.$2);
    }
  }

  void _addTour(String label, int x, int z) {
    // The waypoint cell is the ground block (travel lands 1.05 above it); the
    // ocean lands on the water.
    final y = math.max(world.surfaceHeight(x, z) - 1, TerrainGenerator.seaLevel);
    game.waypoints[IVec3(x, y, z)] = label;
    tour.add(label);
  }

  // --- block gallery ---------------------------------------------------------------------

  /// Every block but the liquids, the portal (lit in the water exhibit) and the
  /// spawner (it lives in the arena).
  static List<int> galleryBlocks() => [
        for (var i = 1; i < Blocks.count; i++)
          if (!Blocks.isLiquid(i) && Blocks.idOf(i) != 'portal' && Blocks.idOf(i) != 'spawner') i,
      ];

  static const int galleryColumns = 13;

  void _buildGallery(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = floor;
    final ids = galleryBlocks();
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

  // --- shapes & building -------------------------------------------------------------------

  void _buildShapes(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = floor;
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
      'oak_stairs_n', 'oak_stairs_e', 'oak_stairs_s', 'oak_stairs_w',
      'stone_stairs_n', 'stone_stairs_e', 'stone_stairs_s', 'stone_stairs_w',
      'oak_slab', 'stone_slab', 'cobblestone_slab',
    ];
    for (var i = 0; i < shapes.length; i++) {
      _set(cx - 18 + i * 2, f, cz + 18, shapes[i]);
    }
  }

  // --- redstone ------------------------------------------------------------------------------

  void _buildRedstone(PlaygroundZone z) {
    final x0 = z.cx - 10, z0 = z.cz - 14, y = floor;
    _fill(x0 - 3, y - 1, z0 - 2, x0 + 20, y - 1, z0 + 19, 'stone');
    final c = world.circuits;
    // 1. lever -> wire x5 -> lamp (left on)
    _set(x0, y, z0, 'lever_off');
    _fill(x0 + 1, y, z0, x0 + 5, y, z0, 'wire_off');
    _set(x0 + 6, y, z0, 'redstone_lamp_off');
    c.useBlock(IVec3(x0, y, z0));
    // 2. button -> wire x3 -> lamp
    _set(x0, y, z0 + 2, 'button');
    _fill(x0 + 1, y, z0 + 2, x0 + 3, y, z0 + 2, 'wire_off');
    _set(x0 + 4, y, z0 + 2, 'redstone_lamp_off');
    // 3. pressure plate -> wire x3 -> lamp
    _set(x0, y, z0 + 4, 'pressure_plate');
    _fill(x0 + 1, y, z0 + 4, x0 + 3, y, z0 + 4, 'wire_off');
    _set(x0 + 4, y, z0 + 4, 'redstone_lamp_off');
    // 4. lever -> wire x2 -> iron door
    _set(x0, y, z0 + 6, 'lever_off');
    _fill(x0 + 1, y, z0 + 6, x0 + 2, y, z0 + 6, 'wire_off');
    _set(x0 + 3, y, z0 + 6, 'iron_door_x');
    _set(x0 + 3, y + 1, z0 + 6, 'iron_door_x');
    // 5. a wooden door, opened by hand
    _set(x0 + 3, y, z0 + 8, 'door_x');
    _set(x0 + 3, y + 1, z0 + 8, 'door_x');
    // 6. a lever and sixteen wires: the 16th stays dark (left on)
    _set(x0, y, z0 + 10, 'lever_off');
    _fill(x0 + 1, y, z0 + 10, x0 + 16, y, z0 + 10, 'wire_off');
    c.useBlock(IVec3(x0, y, z0 + 10));
    // 7. TNT under the third wire of a lever's run
    _set(x0, y, z0 + 12, 'lever_off');
    _fill(x0 + 1, y, z0 + 12, x0 + 3, y, z0 + 12, 'wire_off');
    _set(x0 + 3, y - 1, z0 + 12, 'tnt');
    // 8. a piston facing east with a cobblestone in front, its lever behind
    _set(x0 - 1, y, z0 + 14, 'lever_off');
    _set(x0, y, z0 + 14, 'piston_e');
    _set(x0 + 1, y, z0 + 14, 'cobblestone');
    // 9. a lamp row lit along a wire
    _set(x0, y, z0 + 16, 'lever_off');
    _fill(x0 + 1, y, z0 + 16, x0 + 10, y, z0 + 16, 'wire_off');
    for (var x = x0 + 2; x <= x0 + 10; x += 2) {
      _set(x, y, z0 + 17, 'redstone_lamp_off');
    }
  }

  // --- rails ---------------------------------------------------------------------------------

  /// The loop, in driving order: north side west to east with a two-high hill,
  /// the east side, the south side back west (four powered rails), the west side.
  static List<IVec3> railLoop(int x0, int y, int z0) {
    int hill(int i) => switch (i) { 9 || 14 => 1, >= 10 && <= 13 => 2, _ => 0 };
    return [
      for (var i = 0; i < 24; i++) IVec3(x0 + i, y + hill(i), z0),
      for (var j = 1; j < 14; j++) IVec3(x0 + 23, y, z0 + j),
      for (var i = 22; i >= 0; i--) IVec3(x0 + i, y, z0 + 13),
      for (var j = 12; j >= 1; j--) IVec3(x0, y, z0 + j),
    ];
  }

  void _buildRails(PlaygroundZone z) {
    final x0 = z.cx - 14, z0 = z.cz - 8, y = floor;
    _set(x0 + 9, y, z0, 'stone');
    _fill(x0 + 10, y, z0, x0 + 13, y + 1, z0, 'stone');
    _set(x0 + 14, y, z0, 'stone');
    final rail = _id('rail_ns'), powered = _id('powered_rail_ns');
    final loop = railLoop(x0, y, z0);
    bool isPowered(IVec3 c) => c.z == z0 + 13 && c.x >= x0 + 10 && c.x <= x0 + 13;
    // Twice: the second pass turns every rail toward neighbours laid after it.
    for (var pass = 0; pass < 2; pass++) {
      for (final c in loop) {
        Rails.place(world, c, isPowered(c) ? powered : rail);
      }
    }
    edits += loop.length;
    final lever = IVec3(x0 + 11, y, z0 + 14);
    _set(lever.x, lever.y, lever.z, 'lever_off');
    world.circuits.useBlock(lever);
    // A short spur inside the loop for the chest cart.
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 6; i <= 12; i++) {
        Rails.place(world, IVec3(x0 + i, y, z0 + 6), rail);
      }
    }
  }

  // --- water, lava, portal -------------------------------------------------------------------

  void _buildWater(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = floor;
    // The pool, 16 x 12 and 6 deep, with a sunken chest.
    final px0 = cx - 12, pz0 = cz - 6, px1 = px0 + 15, pz1 = pz0 + 11;
    _fill(px0 - 1, f - 8, pz0 - 1, px1 + 1, f - 1, pz1 + 1, 'sandstone');
    _fill(px0, f - 7, pz0, px1, f - 7, pz1, 'sand');
    _fill(px0, f - 6, pz0, px1, f - 1, pz1, 'water');
    _ring(px0 - 1, f - 1, pz0 - 1, px1 + 1, f - 1, pz1 + 1, 'sand');
    final treasure = IVec3(px0 + 3, f - 6, pz0 + 8);
    _set(treasure.x, treasure.y, treasure.z, 'chest');
    game.chests[treasure] = Inventory()
      ..add('gold_ingot', 12)
      ..add('diamond', 3)
      ..add('raw_salmon', 8);
    GameState.instance.placedChests.add(treasure.key);
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
    Portals.buildAt(world, IVec3(cx + 12, f + 1, cz + 10));
    edits += 20;
  }

  // --- farm & animals ------------------------------------------------------------------------

  void _buildFarm(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = floor;
    // The field: farmland around a water channel, wheat at all three stages.
    final fx0 = cx - 18, fz0 = cz - 20;
    _fill(fx0, f - 2, fz0, fx0 + 10, f - 2, fz0 + 8, 'dirt');
    _fill(fx0, f - 1, fz0, fx0 + 10, f - 1, fz0 + 8, 'farmland');
    _fill(fx0, f - 1, fz0 + 4, fx0 + 10, f - 1, fz0 + 4, 'water');
    const rows = ['wheat_2', 'wheat_2', 'wheat_1', 'wheat_1', '', 'wheat_0', 'wheat_0', 'wheat_2', 'wheat_2'];
    for (var r = 0; r < rows.length; r++) {
      if (rows[r] == '') continue;
      for (var x = fx0; x <= fx0 + 10; x++) {
        _set(x, f, fz0 + r, rows[r]);
        if (rows[r] != 'wheat_2') game.plantCrop(IVec3(x, f, fz0 + r));
      }
    }
    _ring(fx0 - 1, f, fz0 - 1, fx0 + 11, f, fz0 + 9, 'oak_fence');
    _set(fx0 + 5, f, fz0 + 9, 'air');
    // Four pens.
    for (var p = 0; p < 4; p++) {
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

  // --- monster arena -------------------------------------------------------------------------

  static const List<(String, String)> arenaMobs = [
    ('zombie', ''), ('skeleton', ''), ('spider', ''), ('cave_slime', ''), ('slime', ''), ('snow_golem', ''),
    ('scorpion', ''), ('bat', ''), ('dark_skeleton', ''), ('magma_cube', ''), ('blaze', ''),
    ('zombie', 'Giant'), ('spider', 'Venomous'), ('skeleton', 'Burning'),
  ];

  static const List<(String, String)> bossPlates = [
    ('boomer', 'mossy_stone_bricks'), ('troll', 'bone_block'), ('yeti', 'snow'), ('scorpion_king', 'sandstone'),
    ('mummy_king', 'gold_block'), ('underworld_lord', 'nether_brick'),
  ];

  static IVec3 arenaSpawnerCell(PlaygroundZone z) => IVec3(z.cx - 12, floor, z.cz - 12);
  static IVec3 arenaRefillCell(PlaygroundZone z) => IVec3(z.cx + 4, floor + 1, z.cz + 16);
  static IVec3 bossPlateCell(PlaygroundZone z, int i) => IVec3(z.cx - 12 + i * 3, floor, z.cz + 19);

  void _buildArena(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = floor;
    final x0 = cx - 15, x1 = cx + 14, z0 = cz - 15, z1 = cz + 14;
    _fill(x0 + 1, f - 1, z0 + 1, x1 - 1, f - 1, z1 - 1, 'sand');
    _ring(x0, f, z0, x1, f + 4, z1, 'cobblestone');
    // Glass bands for watching (a side window lets in sky 14: nothing burns).
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

  /// Every arena creature that is not alive gets a new body.
  void _refillArena() {
    final z = zone('arena');
    final alive = <String>[
      for (final m in game.mobs)
        if (m.exhibit == 'arena' && !m.removed && !m.isDead) '${m.species.id}/${m.affix}',
    ];
    for (var i = 0; i < arenaMobs.length; i++) {
      final key = '${arenaMobs[i].$1}/${arenaMobs[i].$2}';
      if (alive.remove(key)) continue;
      final at = _at(z.cx - 10 + (i % 5) * 5, floor, z.cz - 10 + (i ~/ 5) * 6);
      _mob(arenaMobs[i].$1, at, 'arena', home: _at(z.cx, floor, z.cz), affix: arenaMobs[i].$2);
    }
  }

  void _tickArena(double dt) {
    final z = zone('arena');
    // The gold button (a rising edge of its lit state).
    final refillOn = Blocks.idOf(world.getBlock(arenaRefillCell(z))) == 'button_on';
    if (refillOn && !_refillWasOn) {
      _refillArena();
      game.notify('The arena is full again');
    }
    _refillWasOn = refillOn;
    // A boss plate summons on the step onto it.
    final feet = IVec3.floor(player.position);
    IVec3? on;
    for (var i = 0; i < bossPlates.length; i++) {
      final p = bossPlateCell(z, i);
      if (feet != p) continue;
      on = p;
      if (_onPlate != p) _summon(bossPlates[i].$1);
    }
    _onPlate = on;
    // The spawner block spawns the dungeon four near a watching player.
    _spawnerTimer -= dt;
    if (_spawnerTimer > 0.0) return;
    _spawnerTimer = 2.0;
    final sp = arenaSpawnerCell(z);
    if (sp.distanceTo(player.position) > 20.0 || Blocks.idOf(world.getBlock(sp)) != 'spawner') return;
    var near = 0;
    for (final m in game.mobs) {
      if (m.exhibit == 'arena_spawner' && !m.removed && !m.isDead) near += 1;
    }
    if (near >= 4) return;
    const pick = ['zombie', 'skeleton', 'spider', 'cave_slime'];
    final m = _mob(pick[game.random.nextInt(pick.length)], _at(sp.x + 2, floor, sp.z + 2), 'arena_spawner', home: _at(z.cx, floor, z.cz));
    game.spawnEffect(m.centre(), Vector3(0.6, 0.2, 0.9), 1.2);
  }

  void _summon(String species) {
    final z = zone('arena');
    final existing = _summoned[species];
    if (existing != null && !existing.removed && !existing.isDead) {
      game.notify('The ${existing.species.name} is already in the arena');
      return;
    }
    final m = _mob(species, _at(z.cx, floor, z.cz), 'arena', home: _at(z.cx, floor, z.cz));
    _summoned[species] = m;
    if (species != 'boomer') game.boss = m; // every summon but the boomer shows the boss bar
    game.spawnEffect(m.centre(), Vector3(0.9, 0.3, 0.2), 2.0);
    Sfx.play('quest', -4.0, 0.6);
    game.notify('${m.species.name} summoned into the arena!');
  }

  // --- light & mining ------------------------------------------------------------------------

  static const List<String> lightSources = [
    'torch', 'wall_torch', 'lamp', 'glowstone', 'redstone_lamp_on', 'lava', 'mushroom', 'enchanting_table',
    'waypoint', 'fortress_core', 'brewing_stand',
  ];

  void _buildCaves(PlaygroundZone z) {
    final cx = z.cx, cz = z.cz, f = floor;
    // The dark hall: dark stone, a roof, one door to the south.
    final hx0 = cx - 16, hx1 = cx + 3, hz0 = cz - 16, hz1 = cz - 3;
    _fill(hx0, f - 1, hz0, hx1, f - 1, hz1, 'stone');
    _ring(hx0, f, hz0, hx1, f + 5, hz1, 'dark_stone');
    _fill(hx0, f + 6, hz0, hx1, f + 6, hz1, 'dark_stone');
    _fill(cx - 7, f, hz1, cx - 6, f + 1, hz1, 'air');
    // Every light source: six along the north wall (the wall torch and the lava
    // need it), the rest in a row across the middle of the hall.
    for (var i = 0; i < lightSources.length; i++) {
      final x = i < 6 ? hx0 + 2 + i * 3 : hx0 + 3 + (i - 6) * 3;
      final zz = i < 6 ? hz0 + 1 : hz0 + 7;
      switch (lightSources[i]) {
        case 'wall_torch':
          _set(x, f + 2, zz, 'wall_torch');
        case 'redstone_lamp_on':
          _set(x, f, zz, 'redstone_lamp_off');
          _set(x, f, zz + 1, 'lever_off');
          world.circuits.useBlock(IVec3(x, f, zz + 1));
        case 'lava':
          _set(x, f, hz0, 'lava');
          _set(x, f, zz, 'glass');
        default:
          _set(x, f, zz, lightSources[i]);
      }
    }
    // The ore wall on the west side.
    const ores = ['coal_ore', 'iron_ore', 'gold_ore', 'diamond_ore', 'redstone_ore', 'nether_quartz_ore', 'obsidian', 'clay', 'gravel'];
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
    for (final (x, zz, ore) in [(sx - 3, sz, 'diamond_ore'), (sx + 3, sz, 'gold_ore'), (sx, sz + 3, 'iron_ore'), (sx - 3, sz + 1, 'diamond_ore'), (sx + 3, sz - 1, 'redstone_ore')]) {
      _set(x, bottom + 1, zz, ore);
    }
  }
}
