import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import 'game_entity.dart';
import 'target.dart';

/// What is shot: how fast, how it falls, what it does on a hit.
class ProjectileSpec {
  /// A shot of [speed] metres a second dealing [damage].
  const ProjectileSpec({
    this.kind = 'arrow',
    this.speed = 24.0,
    this.gravity = 9.0,
    this.damage = 3.0,
    this.knockback = 4.0,
    this.radius = 0.15,
    this.thickness = 0.06,
    this.length = 0.6,
    this.color = 0xC8B090,
    this.glow = false,
    this.life = 6.0,
  });

  /// An arrow: fast, falling, wooden.
  static const ProjectileSpec arrow = ProjectileSpec();

  /// A bolt of magic: straight, glowing.
  static const ProjectileSpec bolt = ProjectileSpec(
    kind: 'bolt',
    speed: 18.0,
    gravity: 0.0,
    damage: 4.0,
    radius: 0.25,
    thickness: 0.5,
    length: 0.5,
    color: 0x70A0FF,
    glow: true,
  );

  /// What a hit reports as the damage source.
  final String kind;

  /// Launch speed.
  final double speed;

  /// Downward acceleration (0 flies straight).
  final double gravity;

  /// Damage on a hit.
  final double damage;

  /// The shove on a hit.
  final double knockback;

  /// How close it must pass to hit a body.
  final double radius;

  /// The width and height of its box, in metres. Only its look: [radius] hits.
  final double thickness;

  /// The length of its box along its flight, in metres. Only its look.
  final double length;

  /// Its colour, `0xRRGGBB`.
  final int color;

  /// Drawn unlit, bright.
  final bool glow;

  /// Seconds before it vanishes.
  final double life;
}

/// The look of a shot, built once ([of]): its geometry and its material, made
/// the first time one is drawn. flutter_scene batches only draws sharing both,
/// so every shot of one size and colour hangs its own node on these two and is
/// drawn once a pass, instanced, instead of once a shot.
class ProjectileModel {
  ProjectileModel._(this.size, this.color, this.glow);

  /// The model of [spec]'s shots: the same object for every spec of the same
  /// size, colour and glow.
  factory ProjectileModel.of(ProjectileSpec spec) {
    assert(spec.thickness > 0.0 && spec.length > 0.0, 'a shot of no size: ${spec.kind}');
    return _built[(spec.thickness, spec.length, spec.color, spec.glow)] ??= ProjectileModel._(
      Vector3(spec.thickness, spec.thickness, spec.length),
      spec.color,
      spec.glow,
    );
  }

  static final Map<(double, double, int, bool), ProjectileModel> _built = {};

  /// The box, in metres, its length along -z.
  final Vector3 size;

  /// Its colour, `0xRRGGBB`.
  final int color;

  /// Drawn unlit, bright.
  final bool glow;

  /// The box, one for every shot of this model.
  late final Geometry geometry = CuboidGeometry(size);

  /// The material, one for every shot of this model.
  late final Material material = _material();

  Material _material() {
    final c = Vector4(((color >> 16) & 0xFF) / 255.0, ((color >> 8) & 0xFF) / 255.0, (color & 0xFF) / 255.0, 1);
    return glow ? (UnlitMaterial()..baseColorFactor = c) : (PhysicallyBasedMaterial()..baseColorFactor = c);
  }
}

/// A shot in flight: swept each step against bodies (any [Target] but its
/// owner) and blocks, so a fast one cannot pass through a thin thing.
class Projectile extends GameEntity {
  /// A [spec] from [from] with [velocity0], shot by [owner].
  Projectile(this.spec, Vector3 from, Vector3 velocity0, this.owner) {
    position = from.clone();
    velocity = velocity0.clone();
    halfWidth = spec.radius;
    height = spec.radius * 2;
  }

  /// What it is.
  final ProjectileSpec spec;

  /// Who shot it; it never hits them.
  final Target? owner;

  double _age = 0.0;

  @override
  void attached(VoxelGame game) {
    setup(game.world, spec.radius, spec.radius * 2);
    if (game.headless) return;
    final model = ProjectileModel.of(spec);
    node.add(MirroredCamera.primitiveNode(Mesh(model.geometry, model.material), castsShadows: false));
    _face(velocity.normalized());
  }

  /// Turns the node along [dir], a unit vector.
  void _face(Vector3 dir) => syncNode(yaw: math.atan2(-dir.x, -dir.z), pitch: math.asin(dir.y.clamp(-1.0, 1.0)));

  @override
  void tick(VoxelGame game, double dt) {
    _age += dt;
    if (_age > spec.life) {
      removed = true;
      return;
    }
    velocity.y -= spec.gravity * dt;
    final step = velocity * dt;
    final len = step.length;
    if (len < 1e-6) return;
    final dir = step / len;
    // The nearest of: a body the segment passes within reach of, a block.
    final wall = VoxelRaycast.barrier(game.world, position, dir, len) ?? double.infinity;
    Target? hit;
    var hitD = math.min(wall, len);
    for (final t in game.allTargets) {
      if (identical(t, owner) || t.isDead || t is! VoxelBody) continue;
      final d = (t as VoxelBody).rayDistance(position, dir, spec.radius);
      if (d >= 0.0 && d < hitD) {
        hitD = d;
        hit = t;
      }
    }
    if (hit != null) {
      hit.takeDamage(
        Damage(spec.damage, source: spec.kind, from: position, knockback: spec.knockback, attacker: owner),
      );
      removed = true;
      return;
    }
    if (wall <= len) {
      removed = true;
      return;
    }
    position.add(step);
    _face(dir);
  }
}
