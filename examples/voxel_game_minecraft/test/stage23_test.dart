import 'dart:math' as math;
import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/core/items.dart';
import 'package:voxel_game_minecraft/src/core/species.dart';
import 'package:voxel_game_minecraft/src/game/inventory.dart';
import 'package:voxel_game_minecraft/src/game/loot.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 23's pure pieces (Godot `--stage23` covers the rest in the app): the
/// pressure plate id, weapon durability on the slot, loot tables, the spawn
/// candidate filter and the ghost's noclip.
void main() {
  test('the pressure plate is appended last, a solid slab the generator knows', () {
    final i = Blocks.indexOf('pressure_plate');
    expect(i, Blocks.indexOf('lava_flow') + 1); // stage 26 appended six more after it
    expect(Blocks.indexOf('lava_flow'), i - 1);
    expect(Blocks.shapeOf(i), BlockShape.slab);
    expect(Blocks.isSolid(i), isTrue);
    expect(Blocks.generatorIds()['pressure_plate'], i);
  });

  test('weapons wear 40 + 50 x tier, tools keep 60 x tier squared', () {
    expect(Items.durabilityOf('iron_sword'), 190);
    expect(Items.durabilityOf('bow'), 90);
    expect(Items.durabilityOf('ancient_blade'), 240);
    expect(Items.damageOf('ancient_blade'), 14);
    expect(Items.durabilityOf('iron_pickaxe'), 540);
    expect(Items.durabilityOf('apple'), 0);
  });

  test('a slot wears, saves its dur, and empties at zero', () {
    final inv = Inventory();
    inv.add('iron_sword', 1);
    inv.add('apple', 3);
    final s = inv.find('iron_sword');
    expect(inv.durAt(s), 190);
    expect(inv.toJson()[s], isNot(contains('dur')));
    for (var i = 0; i < 5; i++) {
      expect(inv.wear(s), isFalse);
    }
    expect(inv.durAt(s), 185);
    expect(inv.wear(inv.find('apple')), isFalse); // never wears
    final copy = Inventory()..fromJson(inv.toJson());
    expect(copy.durAt(s), 185);
    inv.slots[s]!.dur = 1;
    expect(inv.wear(s), isTrue);
    expect(inv.idAt(s), '');
  });

  test('loot rolls are seeded, in range, and name real items', () {
    for (final e in LootTables.tables.entries) {
      for (final row in e.value) {
        expect(Items.has(row.item), isTrue, reason: '${e.key}: ${row.item}');
      }
      for (var seed = 0; seed < 50; seed++) {
        final a = LootTables.roll(e.key, math.Random(seed));
        final b = LootTables.roll(e.key, math.Random(seed));
        expect(a, b);
        for (final st in a) {
          final row = e.value.firstWhere((r) => r.item == st.id);
          expect(st.count, inInclusiveRange(row.min, row.max));
        }
        for (final row in e.value.where((r) => r.chance >= 1.0)) {
          expect(a.any((st) => st.id == row.item), isTrue);
        }
      }
    }
    for (final t in LootTables.tableByKind.values) {
      expect(LootTables.tables.containsKey(t), isTrue);
    }
    expect(() => LootTables.roll('nope', math.Random(1)), throwsArgumentError);
  });

  test('weight 0 never spawns; bats only in dark caves (stage 31: the light gate replaced max y)', () {
    final rng = math.Random(7);
    final ids = <String>{};
    for (var biome = 0; biome < 8; biome++) {
      for (final night in [false, true]) {
        for (final d in Species.candidates(biome, night, false, true, rng)) {
          ids.add(d.id);
        }
      }
    }
    expect(ids, isNot(contains('mummy_king')));
    expect(ids, isNot(contains('ghost')));
    expect(ids, isNot(contains('villager')));
    expect(ids, isNot(contains('bat')));
    expect(ids, contains('bear'));
    expect(Species.candidates(2, false, true, true, rng).map((d) => d.id), contains('bat'));
    expect(Species.candidates(2, false, true, false, rng).map((d) => d.id), isNot(contains('bat')));
  });

  test('a noclip body flies through stone', () {
    final w = VoxelWorld(seedValue: 42, loadRadius: 1);
    final c = Uint8List(VoxelWorld.volume);
    c.fillRange(0, c.length, Blocks.indexOf('stone'));
    w.chunks[(x: 0, z: 0)] = c;
    final body = VoxelBody()..setup(w, 0.3, 1.8);
    body.position = Vector3(8.5, 20.2, 8.5);
    body.noclip = true;
    body.velocity = Vector3(2.4, 0, 0);
    for (var i = 0; i < 60; i++) {
      body.move(1 / 60);
    }
    expect(body.position.x, closeTo(10.9, 1e-4));
    expect(body.hitWall, isFalse);
  });
}
