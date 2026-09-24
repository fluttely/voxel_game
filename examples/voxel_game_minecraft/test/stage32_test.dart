import 'dart:math' as math;
import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/entities/mob.dart';
import 'package:voxel_game_minecraft/src/game/game.dart';
import 'package:voxel_game_minecraft/src/player/player.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 32's headless proofs (the app's `--stage32` covers the rest): light
/// crossing a chunk border exactly as it spreads inside one, the seeded sky BFS
/// against the full seeding, the crit roll and multiplier, the knockback vector,
/// the crack stage from the mining progress, the daylight burning rule and the
/// material families.
void main() {
  int id(String s) => Blocks.indexOf(s);
  const floorY = 10;

  ChunkMesher mesher() =>
      ChunkMesher(palette: Blocks.palette(), shape: Blocks.shapes(), opaque: Blocks.opaqueTable(), emission: Blocks.emission());

  Uint8List floorChunk() {
    final c = Uint8List(VoxelWorld.volume);
    for (var i = 0; i < 16 * 16 * floorY; i++) {
      c[i] = id('stone');
    }
    return c;
  }

  int at(Uint8List v, int x, int y, int z) => v[ChunkSize.index(x, y, z)];

  /// Ring order: c, nx, px, nz, pz, nxnz, pxnz, nxpz, pxpz.
  ChunkMeshResult build(List<Uint8List?> ring) =>
      mesher().build(0, 0, ring);

  List<Uint8List?> floorRing() => [for (var i = 0; i < 9; i++) floorChunk()];

  test('a torch 1-15 cells from a border lights the neighbour chunk exactly as inside one chunk', () {
    final torch = id('torch');
    expect(Blocks.lightOf(torch), 13);
    for (var d = 1; d <= 15; d++) {
      // Across the west border: the torch in the west neighbour, d steps from cell x 0.
      final west = floorRing();
      west[1]![ChunkSize.index(16 - d, floorY, 8)] = torch;
      final across = build(west);
      // Inside: the same torch and the same d steps within the chunk itself.
      final inside = floorRing();
      inside[0]![ChunkSize.index(0, floorY, 8)] = torch;
      final within = build(inside);
      final expected = math.max(13 - d, 0);
      expect(at(across.block, 0, floorY, 8), expected, reason: 'west, $d cells');
      expect(at(within.block, d, floorY, 8), expected, reason: 'inside, $d steps');
      // Across the east border and through a diagonal neighbour too.
      final east = floorRing();
      east[2]![ChunkSize.index(d - 1, floorY, 8)] = torch;
      expect(at(build(east).block, 15, floorY, 8), expected, reason: 'east, $d cells');
      final diag = floorRing();
      diag[8]![ChunkSize.index(0, floorY, d - 1)] = torch; // pxpz: (16, z 16 + d - 1)
      // From chunk cell (15, 15): one step east + d steps south = d + 1 steps.
      expect(at(build(diag).block, 15, floorY, 15), math.max(13 - d - 1, 0), reason: 'diagonal, $d cells');
    }
  });

  test('a stage 31 pad (one cell) would have left the seam: a torch 5 cells past the border reaches the face', () {
    // The first cell of the chunk reads 8 from a torch 5 steps away in the west
    // neighbour (Godot's probe figure); the cell two further in reads 6.
    final ring = floorRing();
    ring[1]![ChunkSize.index(11, floorY, 3)] = id('torch');
    final r = build(ring);
    expect(at(r.block, 0, floorY, 3), 8);
    expect(at(r.block, 2, floorY, 3), 6);
  });

  test('the sky BFS seeded only from cells with a darker side neighbour gives the full seeding\'s light', () {
    final rng = math.Random(32);
    for (var trial = 0; trial < 4; trial++) {
      final ring = <Uint8List?>[];
      for (var n = 0; n < 9; n++) {
        final c = floorChunk();
        // Roofs, pillars, water and leaves at random: overhangs, shafts and liquid.
        for (var k = 0; k < 90; k++) {
          final x = rng.nextInt(16), z = rng.nextInt(16), y = floorY + rng.nextInt(20);
          final w = 1 + rng.nextInt(6), dz = 1 + rng.nextInt(6);
          final block = const ['stone', 'stone', 'water', 'oak_leaves', 'glass'][rng.nextInt(5)];
          for (var xx = x; xx < math.min(16, x + w); xx++) {
            for (var zz = z; zz < math.min(16, z + dz); zz++) {
              c[ChunkSize.index(xx, y, zz)] = id(block);
            }
          }
        }
        ring.add(n == 3 && trial == 0 ? null : c); // a missing neighbour too
      }
      ChunkMesher.fullSkySeed = true;
      final full = build(ring);
      ChunkMesher.fullSkySeed = false;
      final seeded = build(ring);
      expect(seeded.sky, full.sky, reason: 'trial $trial sky');
      expect(seeded.block, full.block, reason: 'trial $trial block');
    }
  });

  test('the crit roll lands about one hit in ten and multiplies by 1.5, rounded', () {
    expect(Game.critChance, 0.1);
    expect(Game.critMult, 1.5);
    final rng = math.Random(7);
    var crits = 0;
    for (var i = 0; i < 20000; i++) {
      if (Game.rollCritWith(rng)) crits++;
    }
    expect(crits / 20000, closeTo(0.1, 0.01));
    expect(Game.critDamage(5, true), 8); // 7.5 rounds up
    expect(Game.critDamage(4, true), 6);
    expect(Game.critDamage(4, false), 4);
  });

  test('knockback: 4 m/s away on the ground plane (a bigger push wins) and 3 m/s up', () {
    final v = Mob.knockbackVelocity(Vector3(3, 70, 4), Vector3(0, 71.5, 0), 0.0);
    expect(v.x, closeTo(4 * 0.6, 1e-5));
    expect(v.z, closeTo(4 * 0.8, 1e-5));
    expect(v.y, 3.0);
    final strong = Mob.knockbackVelocity(Vector3(0, 0, -2), Vector3.zero(), 8.0);
    expect(strong.z, closeTo(-8.0, 1e-5));
    expect(Mob.staggerSeconds, 0.3);
    expect(Mob.hitStop, 0.06);
    expect(Mob.hitFlash, 0.1);
  });

  test('crack stage from the mining progress: four stages, the box darkens 0.16 a stage', () {
    expect(Player.crackStage(0.0), 0);
    expect(Player.crackStage(0.24), 0);
    expect(Player.crackStage(0.25), 1);
    expect(Player.crackStage(0.5), 2);
    expect(Player.crackStage(0.99), 3);
    expect(Player.crackStage(1.0), 3);
    expect(Player.crackAlphaFor(0.5), closeTo(0.48, 1e-9)); // Godot's probe figure
    expect(Player.crackAlphaFor(0.0), closeTo(0.16, 1e-9));
  });

  test('daylight burning: the undead under full sky at day factor 0.9+, not in water, not tamed, not dim', () {
    bool burns(String s, {bool water = false, bool tamed = false, int sky = 15, double day = 1.0}) =>
        Mob.burnsInDaylight(s, inLiquid: water, tamed: tamed, headSky: sky, dayFactor: day);
    expect(burns('zombie'), isTrue);
    expect(burns('skeleton'), isTrue);
    expect(burns('dark_skeleton'), isTrue);
    expect(burns('spider'), isFalse);
    expect(burns('zombie', sky: 14), isFalse); // a roof beside the open sky reads 13-14
    expect(burns('zombie', water: true), isFalse);
    expect(burns('zombie', tamed: true), isFalse);
    expect(burns('zombie', day: 0.89), isFalse);
    expect(burns('zombie', day: 0.9), isTrue);
    expect(burns('zombie', day: 0.0), isFalse); // the underworld: sky intensity 0
  });

  test('material families pick the break / place / step voice', () {
    String f(String s) => Blocks.materialFamily(id(s));
    expect(f('stone'), 'stone');
    expect(f('iron_ore'), 'metal'); // metal is checked before stone ("iron_")
    expect(f('coal_ore'), 'stone');
    expect(f('oak_planks'), 'wood');
    expect(f('oak_leaves'), 'plant');
    expect(f('grass'), 'earth');
    expect(f('tall_grass'), 'plant'); // plant before earth
    expect(f('sand'), 'earth');
    expect(f('sandstone'), 'stone');
    expect(f('glass'), 'glass');
    expect(f('redstone_lamp_on'), 'metal');
    expect(f('lamp'), 'glass');
    expect(f('water'), 'liquid');
    expect(f('lava_flow'), 'liquid');
    expect(f('rail_ns'), 'metal');
    expect(f('torch'), 'plant');
    expect(f('soul_sand'), 'earth');
  });
}
