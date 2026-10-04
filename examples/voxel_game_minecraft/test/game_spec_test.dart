import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart' show ChunkSize;
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/spec/affix.dart';
import 'package:voxel_game_minecraft/src/spec/game_sounds.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';
import 'package:voxel_game_minecraft/src/spec/item_table.dart';
import 'package:voxel_game_minecraft/src/spec/mob_table.dart';
import 'package:voxel_game_minecraft/src/spec/world_table.dart';

Future<VoxelGame> _start() async {
  final game = await VoxelGame.startHeadless(gameSpec, options: const {'class': 'warrior', 'tutorial': 'off'});
  game.spawner.enabled = false;
  for (var i = 0; i < 600 && !game.ready; i++) {
    game.frame(1 / 60);
    await Future<void>.delayed(Duration.zero);
  }
  expect(game.ready, isTrue);
  return game;
}

/// A chunk's cells at one height: a chunk counts up by these.
const int _layer = ChunkSize.sizeX * ChunkSize.sizeZ;

void main() {
  test('the game starts on its spec, the player with the four things to start with', () async {
    final game = await _start();
    final bag = game.player.inventory;
    expect(bag.countOf('wooden_pickaxe'), 1);
    expect(bag.countOf('wooden_axe'), 1);
    expect(bag.countOf('apple'), 5);
    expect(bag.countOf('torch'), 8);
    expect(game.graphics.paced, isTrue, reason: 'the app holds a frame back on a busy GPU');
    expect(game.stations, {'crafting_table', 'furnace', 'brewing_stand'});
    game.dispose();
  });

  test('every block a body walks on sounds one of the recorded footsteps', () async {
    final game = await _start();
    final recorded = {for (final k in stepKinds) 'step_$k'};
    expect(gameSounds.assets.keys.toSet(), recorded);
    for (var id = 1; id < game.blocks.count; id++) {
      final b = game.blocks[id];
      if (b.isLiquid || b.id == 'portal') continue;
      expect(recorded, contains(game.stepSound(id)), reason: b.id);
    }
    expect(game.stepSound(game.blocks.indexOf('grass')), 'step_forest');
    expect(game.stepSound(game.blocks.indexOf('soul_sand')), 'step_desert');
    expect(game.stepSound(game.blocks.indexOf('ice')), 'step_snow');
    expect(game.stepSound(game.blocks.indexOf('mud')), 'step_swamp');
    expect(game.stepSound(game.blocks.indexOf('stone')), 'step_lava');
    game.dispose();
  });

  test('a metal block, a lamp and leaves sound like what they are made of', () async {
    final game = await _start();
    String family(String block) => game.soundFamily(game.blocks.indexOf(block));
    expect(family('iron_block'), 'metal');
    expect(family('rail_ns'), 'metal');
    expect(family('glowstone'), 'glass');
    expect(family('oak_leaves'), 'plant');
    expect(family('bed'), 'wood');
    expect(family('oak_planks'), 'wood');
    expect(family('dirt'), 'earth');
    expect(family('stone'), 'stone');
    game.dispose();
  });

  test('the six tracks play where the app played them', () {
    final music = gameSounds.music!;
    expect(music.tracks, hasLength(6));
    String? at(String biome, {String dimension = VoxelGameSpec.mainDimension, bool cave = false, bool night = false}) =>
        music.trackAt(dimension: dimension, biome: biome, underground: cave, night: night);
    expect(at('plains'), 'meadow');
    expect(at('jungle', night: true), 'meadow');
    expect(at('desert'), 'dunes');
    expect(at('mountain'), 'frost');
    expect(at('frozen_shore'), 'frost');
    expect(at('swamp'), 'marsh');
    expect(at('forest', cave: true), 'deep');
    expect(at('underworld', dimension: 'underworld', cave: true), 'underworld');
  });

  test('one creature in twelve and a half the world spawns is an elite, of six even affixes', () {
    final byId = {for (final m in mobTable) m.id: m};
    final plain = speciesTable.where((s) => s.spawn != null && !s.boss).toList();
    expect(speciesTable, hasLength(29));
    expect(mobTable, hasLength(29 + plain.length * Affix.all.length));
    for (final s in plain) {
      final base = byId[s.id]!.spawn!.weight;
      final elites = [for (final a in Affix.all) byId[a.idOf(s.id)]!.spawn!.weight];
      expect(elites.toSet(), {s.spawn!.weight}, reason: s.id);
      expect(elites.fold(0, (n, w) => n + w) / (base + elites.fold(0, (n, w) => n + w)), closeTo(Affix.share, 1e-9));
    }
    for (final s in speciesTable.where((s) => s.boss)) {
      for (final a in Affix.all) {
        expect(byId.containsKey(a.idOf(s.id)), isFalse, reason: 'a boss has no elites: ${s.id}');
      }
    }
  });

  test('an elite is its kind scaled, named, harder hitting and worth more', () {
    final byId = {for (final m in mobTable) m.id: m};
    final zombie = byId['zombie']!;
    final giant = byId['giant_zombie']!;
    expect(giant.name, 'Giant Zombie');
    expect(giant.hp, closeTo(zombie.hp * 1.6, 1e-9));
    expect(giant.height, closeTo(zombie.height * 1.4, 1e-9));
    expect(giant.halfWidth, closeTo(zombie.halfWidth * 1.4, 1e-9));
    expect((giant.brain.first as MeleeAttack).damage, closeTo((zombie.brain.first as MeleeAttack).damage * 1.3, 1e-9));
    expect(giant.xp, (zombie.xp * Affix.xp).round());
    expect(giant.loot.entries.map((e) => e.item), containsAll(['rotten_flesh', 'gem_shard', 'magic_dust']));
    expect(giant.spawn!.group, (1, 1));
    expect(byId['swift_wolf']!.speed, closeTo(byId['wolf']!.speed * 1.5, 1e-9));
    expect(byId['swift_wolf']!.tameWith, ['bone']);
    // A venomous creature poisons in place of its own effect; one with no twist of the kind keeps its kind's.
    expect(byId['venomous_dark_skeleton']!.onHit!.effect, 'poison');
    expect(byId['sturdy_dark_skeleton']!.onHit!.effect, 'wither');
    // A shot hits as hard as the giant would.
    final shot = (byId['giant_skeleton']!.brain.first as RangedAttack).projectile;
    expect(shot.damage, closeTo(3.0 * 1.3, 1e-9));
  });

  test('an elite spawns in the world with its kind\'s body grown', () async {
    final game = await _start();
    final at = Vector3(0, game.world.groundHeight(0, 0) + 1.0, 0);
    final giant = game.spawnMob('giant_spider', at);
    expect(giant.hp, closeTo(12 * 1.6, 1e-9));
    expect(giant.spec.halfWidth, closeTo(0.6 * 1.4, 1e-9));
    game.dispose();
  });

  test('the staff and the daggers are drawn as the app drew them; the bows shoot, the staves cost no ammo', () async {
    final game = await _start();
    for (final id in ['staff', 'crystal_staff', 'dagger', 'iron_dagger']) {
      final m = ItemModel.of(game.items[id], game.blocks, game.items);
      expect(m.voxels, isNotEmpty, reason: id);
    }
    expect(ItemModel.of(game.items['staff'], game.blocks, game.items).voxels, hasLength(13 + 27 - 1));
    expect(game.items['bow'].launcher!.ammo, 'arrow');
    expect(game.items['longbow'].launcher!.shot, 'long_arrow');
    expect(game.items['staff'].launcher!.ammo, isNull);
    expect(shots['long_arrow']!.damage, game.items['longbow'].damage);
    game.dispose();
  });

  test('the underworld is a cave between bedrock, over a lava sea, of hellstone, soul sand and glowstone', () async {
    final game = await _start();
    final ids = {for (var i = 0; i < game.blocks.count; i++) game.blocks[i].id: i};
    final gen = underworld.compile(ids, gameSpec.seed);
    final counts = <String, int>{};
    for (var cz = 0; cz < 3; cz++) {
      for (var cx = 0; cx < 3; cx++) {
        final c = gen.generateIn(cx, cz, 0);
        for (var x = 0; x < 16; x++) {
          for (var z = 0; z < 16; z++) {
            expect(c[ChunkSize.index(x, 0, z)], ids['bedrock'], reason: 'the floor');
            for (var y = 101; y < ChunkSize.sizeY; y++) {
              expect(c[ChunkSize.index(x, y, z)], 0, reason: 'nothing over the roof');
            }
            for (var y = 0; y < ChunkSize.sizeY; y++) {
              final name = game.blocks[c[ChunkSize.index(x, y, z)]].id;
              counts[name] = (counts[name] ?? 0) + 1;
              if (name == 'lava') expect(y, lessThanOrEqualTo(28));
            }
          }
        }
      }
    }
    for (final b in ['hellstone', 'lava', 'soul_sand', 'glowstone', 'nether_quartz_ore']) {
      expect(counts[b] ?? 0, greaterThan(0), reason: b);
    }
    game.dispose();
  });

  test('every biome and every structure turns up within a few minutes\' walk of the spawn', () {
    final blocks = gameSpec.buildBlocks();
    final gen = overworld.compile({for (var i = 0; i < blocks.count; i++) blocks[i].id: i}, gameSpec.seed);
    final biomes = <String>{};
    for (var z = -1500; z <= 1500; z += 24) {
      for (var x = -1500; x <= 1500; x += 24) {
        biomes.add(gen.biomeAt(x, z).name);
      }
    }
    expect(biomes, {for (final b in overworld.allBiomes) b.name});
    final structures = <String>{};
    for (var cz = -96; cz <= 96; cz += 4) {
      for (var cx = -96; cx <= 96; cx += 4) {
        structures.addAll(gen.structuresNear(cx, cz).map((s) => s.name));
      }
    }
    expect(structures, {for (final s in overworld.structures) s.name});
  });

  test('every structure the world builds has its chests\' loot, and no loot names a structure it lacks', () {
    expect(structureLootTable.keys.toSet(), {
      for (final w in [overworld, underworld])
        for (final s in w.structures) s.name,
    });
    for (final name in ['dungeon', 'tower', 'temple']) {
      expect(structureLootTable[name]!.bonus, isNotNull, reason: name);
    }
  });

  test('a tool wears 60 × tier², a weapon 40 + 50 × tier', () {
    var tools = 0, weapons = 0;
    for (final t in itemTable) {
      if (t.tool == 'sword' || t.launcher != null) {
        expect(t.durability, 40 + 50 * t.tier, reason: t.id);
        weapons++;
      } else if (t.tool != null) {
        expect(t.durability, 60 * t.tier * t.tier, reason: t.id);
        tools++;
      }
    }
    expect(tools, greaterThan(10));
    expect(weapons, greaterThan(8));
  });

  test('a creature spawns where the app spawned it, the undead burn by day, and one blow in ten is a crit', () {
    final byId = {for (final m in speciesTable) m.id: m};
    expect(byId['bat']!.spawn!.place, SpawnPlace.cave, reason: 'bats only in caves');
    for (final id in ['spider', 'slime']) {
      expect(byId[id]!.spawn!.biomeWeights, {'swamp': 2.5}, reason: '$id: a swamp night crawls with them');
    }
    for (final id in ['parrot', 'ocelot']) {
      expect(byId[id]!.spawn!.biomes, ['jungle'], reason: id);
    }
    expect(
      {
        for (final m in speciesTable)
          if (m.burnsInDaylight) m.id,
      },
      {'zombie', 'skeleton', 'dark_skeleton'},
    );
    expect(gameSpec.player.critChance, 0.1);
    expect(gameSpec.player.critMultiplier, 1.5);
  });

  test('every elite that grows or shrinks keeps its width and height in step', () {
    final byId = {for (final m in mobTable) m.id: m};
    for (final m in mobTable) {
      final kind = byId[plainKinds[m.id]!]!;
      expect(m.height / kind.height, closeTo(m.halfWidth / kind.halfWidth, 1e-9), reason: m.id);
    }
  });

  test("a swamp pools water over mud with reeds by it, a jungle grows logs, vines and ferns, a desert palms", () {
    final blocks = gameSpec.buildBlocks();
    final gen = overworld.compile({for (var i = 0; i < blocks.count; i++) blocks[i].id: i}, gameSpec.seed);
    int id(String name) => blocks.indexOf(name);
    // Chunks wholly of [biome] (its corners and centre), nearest the spawn first.
    Map<String, int> census(String biome, {int chunks = 6}) {
      final found = <(int, int)>[];
      for (var r = 0; r < 96 && found.length < chunks; r++) {
        for (var cz = -r; cz <= r && found.length < chunks; cz++) {
          for (var cx = -r; cx <= r && found.length < chunks; cx++) {
            if (cx.abs() != r && cz.abs() != r) continue;
            final x = cx * 16, z = cz * 16;
            const probes = [(0, 0), (15, 0), (0, 15), (15, 15), (8, 8)];
            if (probes.every((p) => gen.biomeAt(x + p.$1, z + p.$2).name == biome)) found.add((cx, cz));
          }
        }
      }
      expect(found, hasLength(chunks), reason: biome);
      final counts = <String, int>{};
      void count(String what) => counts[what] = (counts[what] ?? 0) + 1;
      for (final (cx, cz) in found) {
        final c = gen.generateIn(cx, cz, 0);
        for (var i = _layer; i < c.length; i++) {
          final below = c[i - _layer];
          if (c[i] == id('water') && below == id('mud')) count('water over mud');
          if (c[i] == id('jungle_log') && below == id('sand')) count('palm over sand');
          for (final name in ['reeds', 'jungle_log', 'vines', 'fern']) {
            if (c[i] == id(name)) count(name);
          }
        }
      }
      return counts;
    }

    final swamp = census('swamp');
    expect(swamp['water over mud'], greaterThan(0));
    expect(swamp['reeds'], greaterThan(0));
    final jungle = census('jungle');
    for (final name in ['jungle_log', 'vines', 'fern']) {
      expect(jungle[name], greaterThan(0), reason: name);
    }
    expect(census('desert', chunks: 24)['palm over sand'], greaterThan(0));
  });

  test('villages stand on plains and forest only, and redstone lies under 30', () {
    final blocks = gameSpec.buildBlocks();
    final gen = overworld.compile({for (var i = 0; i < blocks.count; i++) blocks[i].id: i}, gameSpec.seed);
    final villages = <PlacedStructure>{};
    for (var cz = -96; cz <= 96; cz += 4) {
      for (var cx = -96; cx <= 96; cx += 4) {
        villages.addAll(gen.structuresNear(cx, cz).where((s) => s.name == 'village'));
      }
    }
    expect(villages, isNotEmpty);
    for (final v in villages) {
      expect(['plains', 'forest'], contains(gen.biomeAt(v.x, v.z).name), reason: '$v');
    }
    final redstone = blocks.indexOf('redstone_ore');
    var ores = 0;
    for (var cz = 0; cz < 4; cz++) {
      for (var cx = 0; cx < 4; cx++) {
        final c = gen.generateIn(cx, cz, 0);
        for (var i = 0; i < c.length; i++) {
          if (c[i] != redstone) continue;
          ores++;
          expect(i ~/ _layer, lessThan(30));
        }
      }
    }
    expect(ores, greaterThan(0));
  });
}
