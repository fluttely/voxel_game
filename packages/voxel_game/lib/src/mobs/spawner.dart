import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import 'mob_spec.dart';

/// Natural spawning: every [period] seconds a spot on a ring [minDistance]..
/// [maxDistance] around the player is tried, the specs whose [SpawnRule]
/// accepts its biome and light are weighed, and a group appears. Creatures
/// farther than [despawnDistance] from the player vanish; at most [cap] live
/// at once.
class MobSpawner implements GameSystem {
  /// The spawner of [game].
  MobSpawner(VoxelGame game);

  /// Seconds between tries.
  double period = 1.2;

  /// The nearest a creature appears.
  double minDistance = 18.0;

  /// The farthest.
  double maxDistance = 44.0;

  /// Beyond this a spawned creature vanishes.
  double despawnDistance = 96.0;

  /// The most natural creatures alive at once.
  int cap = 24;

  /// Whether it runs.
  bool enabled = true;

  double _clock = 0.0;

  @override
  void tick(VoxelGame game, double dt) {
    if (!enabled || game.player.isDead) return;
    _clock += dt;
    if (_clock < period) return;
    _clock = 0.0;
    final p = game.player.position;
    var alive = 0;
    for (final m in game.mobs) {
      if (m.spec.spawn == null) continue;
      if (m.position.distanceTo(p) > despawnDistance) {
        m.removed = true;
      } else {
        alive++;
      }
    }
    if (alive >= cap) return;
    final r = game.random;
    final a = r.nextDouble() * math.pi * 2, d = minDistance + r.nextDouble() * (maxDistance - minDistance);
    final x = (p.x + math.cos(a) * d).floor(), z = (p.z + math.sin(a) * d).floor();
    if (!game.world.isLoaded(IVec3(x, 0, z))) return;
    final y = game.world.groundHeight(x, z);
    final feet = IVec3(x, y, z);
    if (game.blocks.table.isLiquid(game.world.getBlock(feet)) || game.blocks.table.isLiquid(game.world.getBlock(feet + IVec3.down))) return;
    final light = game.world.lightAt(feet);
    final level = math.max(light.block, (light.sky * game.daylight).round());
    final biome = game.world.generator.biomeAt(x, z).name;
    final candidates = [
      for (final s in game.spec.mobs)
        if (_accepts(s, biome, level) && game.mobs.where((m) => m.spec.id == s.id && !m.isDead).length < s.spawn!.maxAlive) s,
    ];
    if (candidates.isEmpty) return;
    final total = candidates.fold<int>(0, (n, s) => n + s.spawn!.weight);
    var pick = r.nextInt(math.max(1, total));
    var chosen = candidates.first;
    for (final s in candidates) {
      pick -= s.spawn!.weight;
      if (pick < 0) {
        chosen = s;
        break;
      }
    }
    final (lo, hi) = chosen.spawn!.group;
    final n = lo + r.nextInt(hi - lo + 1);
    for (var i = 0; i < n; i++) {
      final ox = x + r.nextInt(5) - 2, oz = z + r.nextInt(5) - 2;
      final oy = game.world.groundHeight(ox, oz);
      if ((oy - y).abs() > 2) continue;
      game.spawnMob(chosen.id, Vector3(ox + 0.5, oy.toDouble(), oz + 0.5));
    }
  }

  static bool _accepts(MobSpec s, String biome, int light) {
    final rule = s.spawn;
    if (rule == null || rule.weight <= 0) return false;
    if (rule.biomes != null && !rule.biomes!.contains(biome)) return false;
    return light >= rule.minLight && light <= rule.maxLight;
  }
}
