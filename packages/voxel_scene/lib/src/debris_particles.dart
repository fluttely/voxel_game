import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Chips off a broken block, embers off a fire: small squares of a colour
/// thrown out of a point, falling, spinning and gone in [lifetime] seconds.
/// They are all one of flutter_scene's particle systems, so every chip in the
/// world is one draw however many fly.
///
/// Add [node] to the scene: its emitter steps them every frame. [burst]
/// throws new ones from anywhere (a step, a frame). The squares are unlit,
/// so a colour is given as it should look where it flies.
class DebrisParticles {
  /// At most [capacity] chips in the air at once; [seed] makes the throws
  /// repeat.
  DebrisParticles({int capacity = 512, int seed = 11})
    : assert(capacity > 0, 'a pool of no chips'),
      _random = math.Random(seed),
      system = ParticleSystem(
        maxParticles: capacity,
        shape: PointEmitterShape(),
        spawner: Spawner(),
        modules: [RotationModule()],
        gravity: Vector3(0, -gravity, 0),
      );

  /// Seconds a chip flies.
  static const double lifetime = 0.6;

  /// What pulls the chips down, metres a second squared.
  static const double gravity = 9.8;

  /// The chips' simulation.
  final ParticleSystem system;

  final math.Random _random;

  /// What goes in the scene; built the first time it is asked for.
  late final Node node = Node(name: 'Debris')
    ..addComponent(ParticleEmitterComponent(system: system, material: SpriteMaterial()));

  /// Throws [count] chips of [color] (linear RGB, 0..1) out of [at]: each
  /// 0.08 to 0.16 m, a shade of 0.8 to 1.1 of the colour, starting within
  /// 0.3 m of the point and flying up at 2 to 4 m/s and up to 2 aside,
  /// [speed] times that. Returns how many were thrown: fewer when the pool is
  /// full, since a chip already flying is never cut short for a new one.
  int burst(Vector3 at, Vector3 color, {int count = 12, double speed = 1.0}) {
    if (count <= 0) throw ArgumentError.value(count, 'count', 'not positive');
    final s = system.storage;
    final r = _random;
    for (var n = 0; n < count; n++) {
      final i = s.spawn();
      if (i < 0) return n;
      final size = 0.08 + r.nextDouble() * 0.08;
      final shade = 0.8 + r.nextDouble() * 0.3;
      s
        ..random01[i] = r.nextDouble()
        ..age[i] = 0.0
        ..lifetime[i] = lifetime
        ..posX[i] = at.x + r.nextDouble() * 0.6 - 0.3
        ..posY[i] = at.y + r.nextDouble() * 0.6 - 0.2
        ..posZ[i] = at.z + r.nextDouble() * 0.6 - 0.3
        ..velX[i] = (r.nextDouble() * 4.0 - 2.0) * speed
        ..velY[i] = (2.0 + r.nextDouble() * 2.0) * speed
        ..velZ[i] = (r.nextDouble() * 4.0 - 2.0) * speed
        ..size[i] = size
        ..baseSize[i] = size
        ..rotation[i] = r.nextDouble() * math.pi
        ..angularVelocity[i] = (r.nextDouble() * 2.0 - 1.0) * 8.0
        ..colorR[i] = math.min(color.x * shade, 1.0)
        ..colorG[i] = math.min(color.y * shade, 1.0)
        ..colorB[i] = math.min(color.z * shade, 1.0)
        ..colorA[i] = 1.0
        ..frame[i] = 0.0
        ..axisX[i] = 0.0
        ..axisY[i] = 1.0
        ..axisZ[i] = 0.0;
    }
    return count;
  }
}
