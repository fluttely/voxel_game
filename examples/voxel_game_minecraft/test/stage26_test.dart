import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/core/items.dart';
import 'package:voxel_game_minecraft/src/core/species.dart';
import 'package:voxel_game_minecraft/src/entities/mob.dart';
import 'package:voxel_game_minecraft/src/game/inventory.dart';
import 'package:voxel_game_minecraft/src/game/loot.dart';
import 'package:voxel_game_minecraft/src/game/music.dart';
import 'package:voxel_game_minecraft/src/game/sfx.dart';
import 'package:voxel_game_minecraft/src/world/terrain_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 26's pure pieces (`--stage26` covers the rest in the app): the six
/// appended blocks, the swamp and jungle in the generator, the village layout,
/// villager offers and their save, spawn weights, and the music moods.
void main() {
  const newBlocks = ['mud', 'reeds', 'jungle_log', 'vines', 'fern', 'melon'];

  test('six blocks appended after the pressure plate, in Godot order', () {
    final plate = Blocks.indexOf('pressure_plate');
    for (var i = 0; i < newBlocks.length; i++) {
      expect(Blocks.indexOf(newBlocks[i]), plate + 1 + i);
    }
    expect(Blocks.indexOf('redstone_ore'), plate + 7); // stage 27 appends after the melon
    expect(Blocks.shapeOf(Blocks.indexOf('reeds')), BlockShape.cross);
    expect(Blocks.dropOf(Blocks.indexOf('melon')), 'melon_slice');
    expect(Blocks.dropOf(Blocks.indexOf('vines')), '');
    final ids = Blocks.generatorIds();
    for (final id in [...newBlocks, 'bed', 'farmland', 'wheat_2', 'oak_slab']) {
      expect(ids[id], Blocks.indexOf(id), reason: id);
    }
    expect(Items.kind('melon_slice'), ItemKind.food);
  });

  // Seed 42: the chunk centres the Godot probe walked to (swamp and jungle
  // nearest to spawn) are found by scanning; the generator's noise is the
  // same FastNoiseLite family, so the biome map is Godot's.
  final gen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 42);

  ({int x, int z})? nearest(int biome) {
    for (var ring = 0; ring <= 80; ring++) {
      for (var dz = -ring; dz <= ring; dz++) {
        for (var dx = -ring; dx <= ring; dx++) {
          if (math.max(dx.abs(), dz.abs()) != ring) continue;
          if (gen.biomeAt(dx * 16 + 8, dz * 16 + 8) == biome) return (x: dx, z: dz);
        }
      }
    }
    return null;
  }

  test('seed 42 has a swamp with pools over mud and reeds, a jungle with logs, vines, ferns', () {
    final sw = nearest(TerrainGenerator.biomeSwamp)!;
    final jg = nearest(TerrainGenerator.biomeJungle)!;
    int count(({int x, int z}) c, String id, [bool onMud = false]) {
      final want = Blocks.indexOf(id), mud = Blocks.indexOf('mud');
      var n = 0;
      for (var dz = -1; dz <= 1; dz++) {
        for (var dx = -1; dx <= 1; dx++) {
          final b = gen.generate(c.x + dx, c.z + dz);
          for (var y = 43; y < 110; y++) {
            for (var z = 0; z < 16; z++) {
              for (var x = 0; x < 16; x++) {
                if (b[TerrainGenerator.index(x, y, z)] != want) continue;
                if (onMud && b[TerrainGenerator.index(x, y - 1, z)] != mud) continue;
                n++;
              }
            }
          }
        }
      }
      return n;
    }

    expect(count(sw, 'mud'), greaterThan(50));
    expect(count(sw, 'water', true), greaterThan(20));
    expect(count(sw, 'reeds'), greaterThan(5));
    expect(count(jg, 'jungle_log'), greaterThan(50));
    expect(count(jg, 'vines'), greaterThan(100));
    expect(count(jg, 'fern'), greaterThan(50));
    // A swamp is pressed flat to two blocks over the sea.
    final h = gen.surfaceHeight(sw.x * 16 + 8, sw.z * 16 + 8);
    expect(h, inInclusiveRange(TerrainGenerator.seaLevel + 1, TerrainGenerator.seaLevel + 5));
  });

  test('villages: plains / forest only, 4-7 huts on the ring, each with a chest and a bed', () {
    var villages = 0;
    for (var rz = -8; rz < 8; rz++) {
      for (var rx = -8; rx < 8; rx++) {
        for (final s in gen.structuresNear(rx * 6, rz * 6)) {
          if (s.type != TerrainGenerator.structVillage) continue;
          final biome = gen.biomeAt(s.x, s.z);
          expect(biome == TerrainGenerator.biomePlains || biome == TerrainGenerator.biomeForest, isTrue);
          final huts = gen.villageHuts(s.x, s.z);
          expect(huts.length, gen.villageHutCount(s.x, s.z));
          expect(huts.length, inInclusiveRange(4, 7));
          for (final h in huts) {
            final r = math.sqrt(math.pow(h.x - s.x, 2) + math.pow(h.z - s.z, 2));
            expect(r, inInclusiveRange(10.0, 14.0));
          }
          villages++;
        }
      }
    }
    expect(villages, greaterThan(0));
  });

  test('a village chunk set holds one chest and one bed per hut', () {
    ({int x, int y, int z, int type})? v;
    for (var r = 0; r < 20 && v == null; r++) {
      for (final s in gen.structuresNear(r * 6, 0)) {
        if (s.type == TerrainGenerator.structVillage) v = s;
      }
    }
    expect(v, isNotNull);
    final chest = Blocks.indexOf('chest'), bed = Blocks.indexOf('bed');
    var chests = 0, beds = 0;
    final cx0 = ((v!.x - 20) / 16).floor(), cx1 = ((v.x + 20) / 16).floor();
    final cz0 = ((v.z - 20) / 16).floor(), cz1 = ((v.z + 20) / 16).floor();
    for (var cz = cz0; cz <= cz1; cz++) {
      for (var cx = cx0; cx <= cx1; cx++) {
        final b = gen.generate(cx, cz);
        for (var i = 0; i < b.length; i++) {
          if (b[i] == chest) chests++;
          if (b[i] == bed) beds++;
        }
      }
    }
    final huts = gen.villageHutCount(v.x, v.z);
    expect(beds, huts);
    expect(chests, greaterThanOrEqualTo(huts));
    expect(LootTables.tableByKind[TerrainGenerator.structVillage], 'village');
  });

  test('three distinct offers from the pool; a trade moves the items and needs the price', () {
    final offers = Mob.rollTrades(math.Random(7));
    expect(offers.length, 3);
    expect(offers.toSet().length, 3);
    for (final o in Mob.tradePool) {
      expect(Items.has(o.take), isTrue, reason: o.take);
      expect(Items.has(o.give), isTrue, reason: o.give);
    }
    final m = Mob()
      ..species = Species.def('villager')
      ..trades = [const TradeOffer('gem_shard', 3, 'diamond', 1)];
    final bag = Inventory();
    bag.add('gem_shard', 2);
    expect(m.tradeWith(bag, 0), isFalse);
    bag.add('gem_shard', 1);
    expect(m.tradeWith(bag, 0), isTrue);
    expect(bag.countOf('gem_shard'), 0);
    expect(bag.countOf('diamond'), 1);
  });

  test('a villager keeps its offers and home across the save text', () {
    final m = Mob()
      ..species = Species.def('villager')
      ..position = Vector3(1, 60, 2)
      ..home = Vector3(-165, 58, 152)
      ..trades = [const TradeOffer('wheat', 3, 'gold_ingot', 1), const TradeOffer('gold_ingot', 5, 'iron_pickaxe', 1)];
    final saved = jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>;
    final back = Mob()..species = Species.def('villager');
    back.fromJson(saved);
    expect(back.home, Vector3(-165, 58, 152));
    expect(back.trades.map((t) => t.toString()).toList(), m.trades.map((t) => t.toString()).toList());
    expect(back.tamed, isFalse);
    expect(Species.def('villager').persistent, isTrue);
  });

  test('spawn weights: swamp x2.5 for spiders and slimes; jungle parrots and ocelots', () {
    expect(Species.weightIn(Species.def('spider'), 7), 45.0);
    expect(Species.weightIn(Species.def('spider'), 2), 18.0);
    expect(Species.weightIn(Species.def('slime'), 7), 35.0);
    expect(Species.def('slime').splits, 'slime_small');
    expect(Species.def('slime_small').weight, 0);
    final day = Species.candidates(8, false, false, false, math.Random(1)).map((d) => d.id).toSet();
    expect(day, containsAll(['parrot', 'ocelot']));
    expect(Species.def('ocelot').speed, greaterThan(4.6));
    expect(Species.def('parrot').tameWith, ['wheat_seeds']);
  });

  test('music moods per biome, night and depth; each mood plays a 2D game track that exists', () {
    expect(Music.moodFor(2, false, false), 'Meadow');
    expect(Music.moodFor(2, true, false), 'Meadow Night');
    expect(Music.moodFor(8, false, false), 'Jungle');
    expect(Music.moodFor(7, true, false), 'Marsh Night');
    expect(Music.moodFor(2, false, true), 'Deep');
    expect(Music.moodFor(5, true, true), 'Deep');
    expect(Music.trackFor('Meadow Night'), Music.trackFor('Meadow')); // night keeps the day's track
    expect(Music.trackFor('Dunes'), 'stardust_dreams.ogg');
    expect(Music.trackFor('Deep'), 'rites_of_passage.mp3');
    expect(Music.title('fishing_by_the_lake.ogg'), 'Fishing By The Lake');
    for (final t in Music.tracks.values) {
      expect(File('assets/audio/music/$t').existsSync(), isTrue, reason: t);
    }
    for (final k in Sfx.stepKinds) {
      for (var i = 1; i <= 4; i++) {
        expect(File('assets/audio/footstep/$k/${k}_$i.wav').existsSync(), isTrue, reason: '$k $i');
      }
    }
  });
}
