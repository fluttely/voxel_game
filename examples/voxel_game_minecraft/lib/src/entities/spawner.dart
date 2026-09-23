import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:voxel_engine/core.dart';
import '../core/species.dart';
import '../game/game.dart';
import '../player/player.dart';
import '../world/voxel_world.dart';
import 'mob.dart';

/// Keeps a population of creatures around the player: passive by day, hostile
/// at night and underground; despawns what wandered far.
class Spawner {
  Spawner(this.world, this.player, this.main);

  static const int cap = 26;
  static const double minDist = 18.0;
  static const double maxDist = 44.0;

  final VoxelWorld world;
  final Player player;
  final Game main;
  double _timer = 0.0;

  void update(double dt) {
    _timer -= dt;
    if (_timer > 0.0) return;
    _timer = 1.2;
    for (final m in main.mobs) {
      if (m.species.persistent || m.exhibit != '') continue; // stage 26: a villager never despawns; stage 33: nor an exhibit
      if ((m.position - player.position).length > 96.0) m.removed = true;
    }
    if (main.mobs.where((m) => m.exhibit == '').length >= cap) return;
    _trySpawn();
  }

  void _trySpawn() {
    final rng = main.random;
    final a = rng.nextDouble() * math.pi * 2;
    final d = minDist + rng.nextDouble() * (maxDist - minDist);
    final x = (player.position.x + math.cos(a) * d).toInt();
    final z = (player.position.z + math.sin(a) * d).toInt();
    if (!world.chunks.containsKey(VoxelWorld.chunkOfXZ(x, z))) return;
    final surface = world.groundHeight(x, z);
    var cave = false;
    var y = surface;
    // Underground spawn when the player is underground; the underworld (stage
    // 29) is all caverns, so it always searches a pocket of air over solid
    // around the player's height.
    final playerSurface = world.surfaceHeight(player.position.x.toInt(), player.position.z.toInt());
    final underworld = world.dimension == VoxelWorld.dimUnderworld;
    if (underworld || (player.position.y < playerSurface - 6 && rng.nextDouble() < 0.7)) {
      final py = player.position.y.toInt();
      for (var i = 0; i < 12; i++) {
        final ty = py + rng.nextInt(13) - 6;
        if (ty < 2) continue;
        final cell = IVec3(x, ty, z);
        if (!world.isSolid(cell) && !world.isSolid(cell + IVec3.up) && world.isSolid(cell + IVec3.down)) {
          y = ty;
          cave = true;
          break;
        }
      }
      if (!cave) return;
      cave = !underworld; // the underworld picks from its own biome table, not the cave one
    }
    if (y >= VoxelWorld.sizeY - 3 || y <= 1) return;
    if (world.isLiquid(IVec3(x, y, z)) || world.isLiquid(IVec3(x, y - 1, z))) return;
    final biome = world.biomeAt(x, z);
    final night = main.isNight;
    // Stage 31: a hostile needs the dark, read from the baked light of the cell (a
    // torch-lit cave stays quiet, a shaded pit spawns by day); the old y /
    // night-only cave rules are gone.
    final dark = hostileAllowedAt(IVec3(x, y, z));
    final candidates = Species.candidates(biome, night, cave, dark, rng);
    if (candidates.isEmpty) return;
    var total = 0.0;
    for (final c in candidates) {
      total += Species.weightIn(c, biome);
    }
    var pick = rng.nextDouble() * total;
    var chosen = candidates[0];
    for (final c in candidates) {
      pick -= Species.weightIn(c, biome);
      if (pick <= 0.0) {
        chosen = c;
        break;
      }
    }
    final group = chosen.hostile ? 1 : 1 + rng.nextInt(3);
    for (var i = 0; i < group; i++) {
      final mob = Mob();
      mob.setupMob(world, main, player, chosen);
      mob.position = Vector3(x + 0.5 + rng.nextDouble() * 3.0 - 1.5, y + 0.1, z + 0.5 + rng.nextDouble() * 3.0 - 1.5);
      if (chosen.hostile) {
        mob.scaleToLevel(player.level + rng.nextInt(3) - 1 + (cave ? 2 : 0));
        if (!chosen.boss && rng.nextDouble() < 0.08) {
          final names = Mob.affixes.keys.toList();
          mob.setAffix(names[rng.nextInt(names.length)]);
        }
      }
      main.addMob(mob);
      main.spawnPoof(mob.centre()); // stage 32
    }
  }

  /// Stage 31: the light gate every hostile spawn passes:
  /// `block + sky * dayFactor < 7` at the cell.
  bool hostileAllowedAt(IVec3 cell) => lightAllowsHostile(world.lightAt(cell), main.dayFactor);

  static bool lightAllowsHostile(({int sky, int block}) light, double dayFactor) =>
      light.block + light.sky * dayFactor < 7.0;

  /// Stage 23: one creature of [speciesId] at [at], levelled to the player when
  /// hostile. Used by the ruin ghosts (`Game._tickRuinGhosts`) and the probes.
  Mob forceSpawn(String speciesId, Vector3 at) {
    final d = Species.def(speciesId);
    final mob = Mob();
    mob.setupMob(world, main, player, d);
    mob.position = at.clone();
    if (d.hostile && !d.boss) mob.scaleToLevel(player.level);
    if (d.trader) mob.makeTrader(at);
    main.addMob(mob);
    main.spawnPoof(mob.centre()); // stage 32
    return mob;
  }
}
