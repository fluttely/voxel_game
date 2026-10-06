import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Rain and snow around one point (the player, the camera): two of
/// flutter_scene's particle systems falling through a box [reach] metres
/// either side, from [height] metres above the point to as far below it.
///
/// Add [node] to the scene and call [update] once a frame with how hard each
/// falls. The particles fall in the node's space, so the box goes where the
/// point goes; they fall through roofs and into the ground, as the cheapest
/// weather does.
class WeatherParticles {
  /// At most [drops] rain drops and [flakes] snowflakes in the air at once.
  WeatherParticles({int drops = 900, int flakes = 500}) : rain = rainSystem(drops), snow = snowSystem(flakes) {
    _rainRate = rain.spawner.rate;
    _snowRate = snow.spawner.rate;
    node
      ..add(_rainNode..addComponent(_emitter(rain, BillboardFacing.velocityStretched, 0.04 / 0.55)))
      ..add(_snowNode..addComponent(_emitter(snow, BillboardFacing.spherical, 1.0)));
    _rainNode.visible = false;
    _snowNode.visible = false;
  }

  /// Metres the box reaches either side of the point.
  static const reach = 26.0;

  /// Metres above the point the particles start.
  static const height = 18.0;

  /// The falling rain: long thin drops at 16 m/s, slanted by a breeze.
  static ParticleSystem rainSystem(int drops) =>
      _falling(drops, size: 0.55, color: Vector4(0.65, 0.75, 0.95, 0.55), speed: 16.0);

  /// The falling snow: small flakes drifting down at 2 m/s.
  static ParticleSystem snowSystem(int flakes) =>
      _falling(flakes, size: 0.12, color: Vector4(0.95, 0.96, 1.0, 0.9), speed: 2.0);

  /// [amount] particles live at once at full rate: each lives as long as it
  /// takes to fall twice [height] (from the top of the box to as far under
  /// the point), and the rate replaces them as they die.
  static ParticleSystem _falling(int amount, {required double size, required Vector4 color, required double speed}) {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'not positive');
    final lifetime = 2.0 * height / speed;
    return ParticleSystem(
      maxParticles: amount,
      shape: BoxEmitterShape(halfExtents: Vector3(reach, 1.0, reach), direction: Vector3(0.15, -1.0, 0.0)),
      spawner: Spawner(rate: amount / lifetime),
      lifetime: ConstantFloat(lifetime),
      startSpeed: UniformFloat(speed * 0.8, speed * 1.2),
      startSize: ConstantFloat(size),
      startColor: ConstantColor(color),
    );
  }

  static ParticleEmitterComponent _emitter(ParticleSystem system, BillboardFacing facing, double aspect) =>
      ParticleEmitterComponent(system: system, material: SpriteMaterial()..blendMode = SpriteBlendMode.alpha)
        ..facing = facing
        ..aspectRatio = aspect;

  /// The rain's simulation.
  final ParticleSystem rain;

  /// The snow's simulation.
  final ParticleSystem snow;

  /// What goes in the scene.
  final Node node = Node(name: 'Weather');
  final Node _rainNode = Node(name: 'Rain');
  final Node _snowNode = Node(name: 'Snow');
  late final double _rainRate;
  late final double _snowRate;

  /// Puts the box over [around] and lets [rainShare] of the full rain and
  /// [snowShare] of the full snow fall (0 none .. 1 all). What already fell
  /// finishes its fall when a share drops to 0. Throws [ArgumentError] for a
  /// share out of 0..1.
  void update(Vector3 around, {required double rainShare, required double snowShare}) {
    if (!(rainShare >= 0.0 && rainShare <= 1.0)) throw ArgumentError.value(rainShare, 'rainShare', 'not in 0..1');
    if (!(snowShare >= 0.0 && snowShare <= 1.0)) throw ArgumentError.value(snowShare, 'snowShare', 'not in 0..1');
    node.position = around + Vector3(0.0, height, 0.0);
    rain.spawner.rate = _rainRate * rainShare;
    snow.spawner.rate = _snowRate * snowShare;
    _rainNode.visible = rainShare > 0.0 || rain.storage.aliveCount > 0;
    _snowNode.visible = snowShare > 0.0 || snow.storage.aliveCount > 0;
  }
}
