import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import 'mob_spec.dart';
import 'spawn_place.dart';

/// Natural spawning: every [period] seconds a spot on a ring [minDistance]..
/// [maxDistance] around the player is tried, the specs whose [SpawnRule]
/// accepts its place, biome and light are weighed (`SpawnRule.weightIn`),
/// and a group appears, each at its level when its spec grows
/// (`MobSpec.levels`). Wild creatures farther than [despawnDistance] from
/// the player vanish; at most [cap] wild ones live at once.
///
/// The spot is on the surface, or, while the player is [caveDepth] or more
/// under the ground of their column, [caveShare] of the time a pocket of air
/// near the player's height: a cave. In a dimension that is all cavern
/// (`WorldGenSpec.cavern`) every spot is a pocket, and counts as its ground.
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

  /// How far under the ground of their column the player is underground.
  int caveDepth = 6;

  /// The share of the tries made underground, while the player is.
  double caveShare = 0.7;

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
      if (m.spec.spawn == null || m.tamed) continue;
      if (m.position.distanceTo(p) > despawnDistance) {
        m.removed = true;
      } else {
        alive++;
      }
    }
    if (alive >= cap) return;
    final r = game.random;
    final world = game.world;
    final a = r.nextDouble() * math.pi * 2, d = minDistance + r.nextDouble() * (maxDistance - minDistance);
    final x = (p.x + math.cos(a) * d).floor(), z = (p.z + math.sin(a) * d).floor();
    if (!world.isLoaded(IVec3(x, 0, z))) return;
    final cavern = world.generator.spec.cavern != null;
    final underground = p.y < world.groundHeight(p.x.floor(), p.z.floor()) - caveDepth;
    final int y;
    var cave = false;
    if (cavern || underground && r.nextDouble() < caveShare) {
      final pocket = _pocket(game, x, p.y.floor(), z, r);
      if (pocket == null) return;
      y = pocket;
      cave = !cavern;
    } else {
      y = world.groundHeight(x, z);
    }
    final feet = IVec3(x, y, z);
    if (game.blocks.table.isLiquid(world.getBlock(feet)) ||
        game.blocks.table.isLiquid(world.getBlock(feet + IVec3.down))) {
      return;
    }
    final light = world.lightAt(feet);
    final level = math.max(light.block, (light.sky * game.daylight).round());
    final biome = world.generator.biomeAt(x, z).name;
    final candidates = [
      for (final s in game.spec.mobs)
        if (_accepts(s, biome, level, cave: cave) &&
            game.mobs.where((m) => m.spec.id == s.id && !m.isDead).length < s.spawn!.maxAlive)
          s,
    ];
    if (candidates.isEmpty) return;
    final total = candidates.fold<double>(0.0, (n, s) => n + s.spawn!.weightIn(biome));
    var pick = r.nextDouble() * total;
    var chosen = candidates.last;
    for (final s in candidates) {
      pick -= s.spawn!.weightIn(biome);
      if (pick < 0.0) {
        chosen = s;
        break;
      }
    }
    final (lo, hi) = chosen.spawn!.group;
    final n = lo + r.nextInt(hi - lo + 1);
    final levels = chosen.levels;
    for (var i = 0; i < n; i++) {
      final ox = x + r.nextInt(5) - 2, oz = z + r.nextInt(5) - 2;
      final oy = cavern || cave ? _standNear(game, ox, y, oz) : world.groundHeight(ox, oz);
      if (oy == null || (oy - y).abs() > 2) continue;
      final mob = game.spawnMob(chosen.id, Vector3(ox + 0.5, oy.toDouble(), oz + 0.5));
      if (levels != null) {
        mob.growTo(levels.levelFor(game.player.level, r.nextInt(levels.spread * 2 + 1) - levels.spread, cave: cave));
      }
    }
  }

  /// A pocket in column ([x], [z]) within six of [y]: an air cell and the one
  /// over it, on a solid one. Twelve tries; null when none is found.
  static int? _pocket(VoxelGame game, int x, int y, int z, math.Random r) {
    for (var i = 0; i < 12; i++) {
      final ty = y + r.nextInt(13) - 6;
      if (_stands(game, IVec3(x, ty, z))) return ty;
    }
    return null;
  }

  /// The height of a pocket in column ([x], [z]) at [y] or one off it, or null.
  static int? _standNear(VoxelGame game, int x, int y, int z) {
    for (final ty in [y, y + 1, y - 1]) {
      if (_stands(game, IVec3(x, ty, z))) return ty;
    }
    return null;
  }

  static bool _stands(VoxelGame game, IVec3 feet) {
    final w = game.world;
    return feet.y >= 2 &&
        feet.y < ChunkSize.sizeY - 3 &&
        !w.isSolid(feet) &&
        !w.isSolid(feet + IVec3.up) &&
        w.isSolid(feet + IVec3.down);
  }

  static bool _accepts(MobSpec s, String biome, int light, {required bool cave}) {
    final rule = s.spawn;
    if (rule == null || rule.weightIn(biome) <= 0.0) return false;
    if (rule.biomes != null && !rule.biomes!.contains(biome)) return false;
    final placed = switch (rule.place) {
      SpawnPlace.anywhere => true,
      SpawnPlace.cave => cave,
      SpawnPlace.surface => !cave,
    };
    return placed && light >= rule.minLight && light <= rule.maxLight;
  }
}
