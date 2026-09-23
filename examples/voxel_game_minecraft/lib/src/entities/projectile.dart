import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'package:voxel_engine/core.dart';
import '../game/game.dart';
import '../player/player.dart';
import 'package:voxel_scene/voxel_scene.dart';
import '../world/voxel_world.dart';
import 'mob.dart';

/// Arrows and magic bolts: a segment swept against blocks and body boxes on
/// the physics tick. The projectile owns its hit (dev's host-authoritative
/// shape): whoever runs the simulation resolves damage here, a replica would
/// only fly. `radius` inflates the target boxes so a bolt hits like a thick
/// beam; arrows stay thin and fall.
class Projectile {
  final Node node = Node(name: 'Projectile');
  Vector3 position = Vector3.zero();
  Vector3 velocity = Vector3.zero();
  double damage = 0;
  Object? ownerNode;
  String kind = 'arrow';
  double radius = 0.1;
  double knockback = 5.0;
  bool replica = false;
  late Game main;
  late VoxelWorld world;
  double _age = 0.0;
  bool removed = false;
  PointLight? _light;

  void setupProjectile(VoxelWorld w, Game m, Vector3 from, Vector3 vel, double dmg, Object? owner, String k,
      [double r = 0.1, double kb = 5.0]) {
    world = w;
    main = m;
    position = from.clone();
    velocity = vel.clone();
    damage = dmg;
    ownerNode = owner;
    kind = k;
    radius = r;
    knockback = kb;
    final v = <IVec3, Vector3>{};
    if (kind == 'arrow') {
      VoxelModel.box(v, const IVec3(0, 0, 0), const IVec3(0, 0, 7), Vector3(0.55, 0.42, 0.25));
      VoxelModel.box(v, const IVec3(0, 0, 8), const IVec3(0, 0, 9), Vector3(0.7, 0.7, 0.72));
      VoxelModel.box(v, const IVec3(0, -1, 0), const IVec3(0, 1, 1), Vector3(0.9, 0.9, 0.9));
      node.add(VoxelModelMesh.node(v, 0.06, Vector3(0.5, 0.5, 9)));
    } else {
      final col = colour();
      final size = radius < 0.3 ? 1 : 2;
      VoxelModel.box(v, IVec3(-size, -size, -size), IVec3(size, size, size), col, 0.15);
      node.add(VoxelModelMesh.node(v, 0.09, Vector3(0.5, 0.5, 0.5)));
      _light = PointLight(color: col, intensity: 6.0, range: 4.0);
      node.addComponent(PointLightComponent(_light!));
      final trail = MirroredCamera.primitiveNode(
        Mesh(
          CuboidGeometry(Vector3(radius * 0.8, radius * 0.8, 1.6)),
          UnlitMaterial()
            ..baseColorFactor = Vector4(col.x, col.y, col.z, 0.45)
            ..alphaMode = AlphaMode.blend,
        ),
      )..position = Vector3(0, 0, 0.9);
      node.add(trail);
    }
    node.position = position.clone();
  }

  Vector3 colour() {
    switch (kind) {
      case 'bolt':
        return Vector3(1.0, 0.45, 0.15);
      case 'frost':
        return Vector3(0.5, 0.8, 1.0);
      case 'fire':
        return Vector3(1.0, 0.35, 0.05); // stage 29: a blaze's fireball
    }
    return Vector3(0.5, 0.9, 0.4);
  }

  void update(double dt) {
    _age += dt;
    if (_age > 6.0) {
      removed = true;
      return;
    }
    if (kind == 'arrow') velocity.y -= 14.0 * dt;
    final from = position.clone();
    final to = from + velocity * dt;
    final dir = to - from;
    final dist = dir.length;
    if (dist > 0.0) {
      dir.scale(1.0 / dist);
      // Godot's `look_at` turns local -Z toward the target; flutter_scene's
      // `lookAtFrom` turns +Z, so aim it at the point behind.
      node.lookAtFrom(from, from - dir, up: dir.y.abs() < 0.99 ? Vector3(0, 1, 0) : Vector3(1, 0, 0));
    }
    // Bodies (mobs, and the player for hostile shots), nearest first along the
    // segment. A replica never resolves a hit: only the simulation that owns
    // the shot does.
    VoxelBody? best;
    var bestD = double.infinity;
    if (!replica) {
      for (final mob in main.mobs) {
        if (identical(mob, ownerNode)) continue;
        final d = mob.rayDistance(from, dir, radius);
        if (d >= 0.0 && d <= dist + radius && d < bestD) {
          best = mob;
          bestD = d;
        }
      }
      if (!identical(ownerNode, main.player)) {
        final p = main.player;
        final dp = p.rayDistance(from, dir, radius);
        if (dp >= 0.0 && dp <= dist + radius && dp < bestD) {
          best = p;
          bestD = dp;
        }
      }
    }
    if (best != null) {
      position = from + dir * bestD;
      if (best is Player) {
        best.takeDamage(damage, kind, from);
        if (kind == 'fire') best.applyEffect('burning', 4.0); // stage 29: a fireball sets its target alight
      } else if (best is Mob) {
        final owner = ownerNode;
        final ownerPos = owner is VoxelBody ? owner.position : (owner is Player ? owner.position : from);
        final crit = kind == 'arrow' && main.rollCrit(); // stage 32: arrows crit like swings
        if (crit) damage = (damage * Game.critMult).roundToDouble();
        best.takeDamage(damage, ownerPos, knockback, owner);
        main.spawnDamageNumber(best.centre(), damage, kind == 'arrow' ? Vector3(1, 0.9, 0.5) : colour(), crit);
      }
      _impact();
      return;
    }
    // Blocks.
    final steps = math.max(1, (dist / 0.25).ceil());
    for (var i = 0; i <= steps; i++) {
      final p = from + dir * (dist * i / steps);
      if (world.isSolidXYZ(p.x.floor(), p.y.floor(), p.z.floor())) {
        position = p;
        _impact();
        return;
      }
    }
    position = to;
    node.position = position.clone();
  }

  void _impact() {
    if (kind != 'arrow') main.spawnEffect(position, colour(), 0.6 + radius * 1.5);
    removed = true;
  }
}
