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
    expect(structureLootTable.keys.toSet(), {for (final s in overworld.structures) s.name});
    for (final name in ['dungeon', 'tower', 'temple']) {
      expect(structureLootTable[name]!.bonus, isNotNull, reason: name);
    }
  });
}
