import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../mobs/hit_effect.dart';
import '../mobs/mob.dart';
import '../net/remote_player.dart';
import 'game_entity.dart';
import 'target.dart';

/// What is shot: how fast, how it falls, what it does on a hit, and how it
/// looks in flight (a [light] it carries, a [trail] behind it).
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
    this.light = 0.0,
    this.trail = 0.0,
    this.burns = 0.0,
    this.onHit,
  }) : assert(light >= 0.0 && trail >= 0.0 && burns >= 0.0);

  /// The shot [toJson] wrote: how a networked game sends one. Throws for a
  /// field missing, or for one no shot has (a size, a reach or a life of
  /// none, a light, trail or burn below none).
  factory ProjectileSpec.fromJson(Map<String, Object?> json) {
    double n(String key) => (json[key]! as num).toDouble();
    final radius = n('radius'), thickness = n('thickness'), length = n('length'), life = n('life');
    final light = n('light'), trail = n('trail'), burns = n('burns');
    if (radius <= 0.0 || thickness <= 0.0 || length <= 0.0 || life <= 0.0) {
      throw FormatException('a shot of no size or life: $json');
    }
    if (light < 0.0 || trail < 0.0 || burns < 0.0) throw FormatException('a shot below none: $json');
    final hit = json['onHit'] as Map<String, Object?>?;
    final seconds = hit == null ? 1.0 : (hit['seconds']! as num).toDouble();
    final power = hit == null ? 1.0 : (hit['power']! as num).toDouble();
    if (seconds <= 0.0 || power <= 0.0) throw FormatException('an effect on hit of none: $json');
    return ProjectileSpec(
      kind: json['kind']! as String,
      speed: n('speed'),
      gravity: n('gravity'),
      damage: n('damage'),
      knockback: n('knockback'),
      radius: radius,
      thickness: thickness,
      length: length,
      color: json['color']! as int,
      glow: json['glow']! as bool,
      life: life,
      light: light,
      trail: trail,
      burns: burns,
      onHit: hit == null ? null : HitEffect(hit['effect']! as String, seconds: seconds, power: power),
    );
  }

  /// Every field, for [ProjectileSpec.fromJson].
  Map<String, Object?> toJson() => {
    'kind': kind,
    'speed': speed,
    'gravity': gravity,
    'damage': damage,
    'knockback': knockback,
    'radius': radius,
    'thickness': thickness,
    'length': length,
    'color': color,
    'glow': glow,
    'life': life,
    'light': light,
    'trail': trail,
    'burns': burns,
    if (onHit case final h?) 'onHit': {'effect': h.effect, 'seconds': h.seconds, 'power': h.power},
  };

  /// This shot with the given fields replaced: the same arrow striking
  /// harder, say. [onHit], which may be null, is given as a getter of its new
  /// value, so `onHit: () => null` takes the effect away and leaving it out
  /// keeps it.
  ProjectileSpec copyWith({
    String? kind,
    double? speed,
    double? gravity,
    double? damage,
    double? knockback,
    double? radius,
    double? thickness,
    double? length,
    int? color,
    bool? glow,
    double? life,
    double? light,
    double? trail,
    double? burns,
    ValueGetter<HitEffect?>? onHit,
  }) => ProjectileSpec(
    kind: kind ?? this.kind,
    speed: speed ?? this.speed,
    gravity: gravity ?? this.gravity,
    damage: damage ?? this.damage,
    knockback: knockback ?? this.knockback,
    radius: radius ?? this.radius,
    thickness: thickness ?? this.thickness,
    length: length ?? this.length,
    color: color ?? this.color,
    glow: glow ?? this.glow,
    life: life ?? this.life,
    light: light ?? this.light,
    trail: trail ?? this.trail,
    burns: burns ?? this.burns,
    onHit: onHit == null ? this.onHit : onHit(),
  );

  /// An arrow: fast, falling, wooden.
  static const ProjectileSpec arrow = ProjectileSpec();

  /// A bolt of magic: straight, glowing, lighting its way and trailing.
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
    light: 4.0,
    trail: 1.6,
  );

  /// A fireball: a bolt of fire that sets the creature it hits burning for 4
  /// seconds. The player has no burning of the kit's: a game that wants its
  /// fire to burn the player declares its own shot like this one, with an
  /// [onHit] effect of its own.
  static const ProjectileSpec fireball = ProjectileSpec(
    kind: 'fire',
    speed: 16.0,
    gravity: 0.0,
    damage: 4.0,
    radius: 0.25,
    thickness: 0.4,
    length: 0.4,
    color: 0xFF5A0D,
    glow: true,
    light: 4.0,
    trail: 1.6,
    burns: 4.0,
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

  /// The reach, in metres, of the light in its [color] it carries (lighting
  /// the ground and the creatures it passes); 0 for none.
  final double light;

  /// The length, in metres, of the see-through streak of its [color] it
  /// leaves behind it; 0 for none.
  final double trail;

  /// Seconds a creature it hits burns for (`Mob.ignite`); 0 for none.
  final double burns;

  /// The status effect it leaves on the player when it hurts them, or null:
  /// what a fire shot does to the player, since the kit gives the player no
  /// burning of its own.
  final HitEffect? onHit;
}

/// The look of a shot, built once ([of]): its geometry and its material, and
/// its trail's, made the first time one is drawn. flutter_scene batches only
/// draws sharing both, so every shot of one size and colour hangs its own node
/// on these and is drawn once a pass, instanced, instead of once a shot.
class ProjectileModel {
  ProjectileModel._(this.size, this.color, this.glow, this.trail);

  /// The model of [spec]'s shots: the same object for every spec of the same
  /// size, colour, glow and trail.
  factory ProjectileModel.of(ProjectileSpec spec) {
    assert(spec.thickness > 0.0 && spec.length > 0.0, 'a shot of no size: ${spec.kind}');
    return _built[(spec.thickness, spec.length, spec.color, spec.glow, spec.trail)] ??= ProjectileModel._(
      Vector3(spec.thickness, spec.thickness, spec.length),
      spec.color,
      spec.glow,
      spec.trail,
    );
  }

  static final Map<(double, double, int, bool, double), ProjectileModel> _built = {};

  /// The box, in metres, its length along -z.
  final Vector3 size;

  /// Its colour, `0xRRGGBB`.
  final int color;

  /// Drawn unlit, bright.
  final bool glow;

  /// The length of the streak behind it, metres; 0 for none.
  final double trail;

  /// The colour, linear RGB 0..1.
  Vector3 get rgb => Vector3(((color >> 16) & 0xFF) / 255.0, ((color >> 8) & 0xFF) / 255.0, (color & 0xFF) / 255.0);

  /// The box, one for every shot of this model.
  late final Geometry geometry = CuboidGeometry(size);

  /// The material, one for every shot of this model.
  late final Material material = _material();

  /// The streak behind it, [trail] long and 0.8 of its width, one for every
  /// shot of this model; null for none.
  late final Geometry? trailGeometry = trail > 0.0 ? CuboidGeometry(Vector3(size.x * 0.8, size.y * 0.8, trail)) : null;

  /// The streak's material: its colour, unlit, see-through. Null for none.
  late final Material? trailMaterial = trail > 0.0
      ? (UnlitMaterial()
          ..baseColorFactor = Vector4(rgb.x, rgb.y, rgb.z, 0.45)
          ..alphaMode = AlphaMode.blend)
      : null;

  Material _material() {
    final c = Vector4(rgb.x, rgb.y, rgb.z, 1);
    return glow ? (UnlitMaterial()..baseColorFactor = c) : (PhysicallyBasedMaterial()..baseColorFactor = c);
  }
}

/// A shot in flight: swept each step against bodies (any [Target] but its
/// owner) and blocks, so a fast one cannot pass through a thin thing. A shot
/// of a player's, the local one or another's, may be critical
/// (`PlayerEntity.critical`), and one at a creature is filtered by its
/// shooter's `PlayerEntity.damageOut`: the host lands a peer's and hands the
/// blow back to the peer (`GameSession.landed`), which rolls and filters it
/// on its own side as it does its swing; one that hits a creature sets it
/// burning ([ProjectileSpec.burns]); one that hurts a player leaves its
/// [ProjectileSpec.onHit] (`Damage.effect`). A [replica] is only seen:
/// another side's shot, it flies and stops where it hits, and hurts nobody.
class Projectile extends GameEntity {
  /// A [spec] from [from] with [velocity0], shot by [owner], its damage
  /// multiplied by [power].
  Projectile(this.spec, Vector3 from, Vector3 velocity0, this.owner, {this.power = 1.0}) {
    position = from.clone();
    velocity = velocity0.clone();
    halfWidth = spec.radius;
    height = spec.radius * 2;
  }

  /// What it is.
  final ProjectileSpec spec;

  /// Who shot it; it never hits them.
  final Target? owner;

  /// What its spec's damage is multiplied by (a shooter's level).
  final double power;

  /// A shot whose hit is another side's (the host's, in a networked game):
  /// drawn here, it stops where it hits and deals nothing.
  bool replica = false;

  double _age = 0.0;

  /// How bright its [ProjectileSpec.light] is: the radiance a metre away.
  static const double lightIntensity = 6.0;

  @override
  void attached(VoxelGame game) {
    setup(game.world, spec.radius, spec.radius * 2);
    if (game.headless) return;
    final model = ProjectileModel.of(spec);
    node.add(MirroredCamera.primitiveNode(Mesh(model.geometry, model.material), castsShadows: false));
    final trail = model.trailGeometry;
    if (trail != null) {
      // Behind it: the box's length runs along -z, the way it flies.
      node.add(
        MirroredCamera.primitiveNode(Mesh(trail, model.trailMaterial!), castsShadows: false)
          ..position = Vector3(0, 0, spec.trail * 0.5),
      );
    }
    if (spec.light > 0.0) {
      node.addComponent(
        PointLightComponent(PointLight(color: model.rgb, intensity: lightIntensity, range: spec.light)),
      );
    }
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
    if (hit != null && replica) {
      removed = true;
      return;
    }
    if (hit != null) {
      removed = true;
      final shooter = owner;
      if (shooter is RemotePlayer && hit is Mob) {
        // A peer's shot at a creature is dealt on its side, by its own roll and filters.
        game.session!.landed(this, shooter, hit);
      } else {
        final player = game.player;
        final (:amount, :crit) = identical(shooter, player) || game.remotePlayers.contains(shooter)
            ? player.critical(spec.damage * power)
            : (amount: spec.damage * power, crit: false);
        // The local player's own shot is filtered as their swing is.
        final dealt = identical(shooter, player) && hit is Mob ? player.dealtTo(hit, amount) : amount;
        hit.takeDamage(
          Damage(
            dealt,
            source: spec.kind,
            from: position,
            knockback: spec.knockback,
            attacker: shooter,
            crit: crit,
            effect: spec.onHit,
          ),
        );
      }
      if (spec.burns > 0.0 && hit is Mob) hit.ignite(spec.burns);
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
