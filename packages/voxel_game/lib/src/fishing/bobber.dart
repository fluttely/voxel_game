import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_scene/voxel_scene.dart';

import '../core/voxel_game.dart';
import '../entities/game_entity.dart';
import '../player/player_entity.dart';
import 'fishing_spec.dart';

/// A fishing line's float, cast by its [owner] (`PlayerEntity.bobber`): it
/// flies from the hand to [target] in an arc, floats there bobbing, and once
/// a wait of the [spec]'s is over something [bite]s: it dips for
/// `FishingSpec.bite` seconds ([biting]), and waits again if nobody answers.
/// A line runs from the owner's hand to it, drawn every frame.
class Bobber extends GameEntity {
  /// A float of [spec] cast by [owner] from [from] to land at [target].
  Bobber(this.spec, this.owner, Vector3 from, Vector3 target) : target = target.clone(), _start = from.clone() {
    position = from.clone();
  }

  /// How the game fishes.
  final FishingSpec spec;

  /// Who cast it.
  final PlayerEntity owner;

  /// Where it floats: the liquid's surface.
  final Vector3 target;

  final Vector3 _start;

  /// How much of the flight a second covers, and how high the arc rises,
  /// metres.
  static const double flightRate = 2.2, arc = 1.4;

  /// How far a bite pulls it under, metres.
  static const double dip = 0.22;

  /// Whether it has landed on the liquid.
  bool get landed => _flight >= 1.0;
  double _flight = 0.0;

  /// Whether something bites now: a use lands the catch.
  bool get biting => _biteLeft > 0.0;
  double _biteLeft = 0.0;

  late double _wait;
  double _phase = 0.0;
  late VoxelGame _game;

  /// The line, under [node] (which never turns), stretched to the hand every
  /// frame; null headless.
  Node? _line;

  @override
  void attached(VoxelGame game) {
    _game = game;
    setup(game.world, 0.1, 0.2);
    _wait = _nextWait();
    if (game.headless) return;
    node
      ..add(MirroredCamera.primitiveNode(Mesh(_float, _red)))
      ..add(MirroredCamera.primitiveNode(Mesh(_cap, _white))..position = Vector3(0, 0.12, 0));
    final line = MirroredCamera.primitiveNode(Mesh(_thread, _dark), castsShadows: false);
    node.add(line);
    _line = line;
  }

  double _nextWait() => spec.minWait + _game.random.nextDouble() * (spec.maxWait - spec.minWait);

  /// Something takes it, now: it dips for `FishingSpec.bite` seconds, a
  /// splash is heard and the owner told. Throws before it has landed.
  void bite() {
    if (!landed) throw StateError('nothing bites a float in the air');
    _biteLeft = spec.bite;
    _wait = _nextWait();
    _game.playSound('splash', at: position, volumeDb: -6.0);
    _game.notify('Something bites!');
  }

  @override
  void tick(VoxelGame game, double dt) {
    if (!landed) {
      _flight = math.min(_flight + dt * flightRate, 1.0);
      position = _start + (target - _start) * _flight
        ..y += math.sin(_flight * math.pi) * arc;
      if (landed) game.playSound('splash', at: target, volumeDb: -14.0);
      syncNode();
      return;
    }
    _phase += dt;
    var under = 0.0;
    if (_biteLeft > 0.0) {
      _biteLeft = math.max(_biteLeft - dt, 0.0);
      under = dip;
    } else {
      _wait -= dt;
      if (_wait <= 0.0) bite();
    }
    final wanted = target.y + math.sin(_phase * 3.0) * 0.04 - under;
    position = Vector3(target.x, position.y + (wanted - position.y) * math.min(1.0, dt * 12.0), target.z);
    syncNode();
  }

  @override
  void drawNode(double alpha) {
    super.drawNode(alpha);
    final line = _line;
    if (line == null) return;
    // Under the node, which stands where the float is drawn and never turns.
    final from = owner.drawnHand - drawnPosition;
    final to = Vector3(0, 0.12, 0);
    final delta = to - from;
    final length = delta.length;
    line.visible = length > 1e-4;
    if (!line.visible) return;
    final dir = delta / length;
    final axis = _down.cross(dir);
    final rotation = axis.length2 < 1e-8
        ? (_down.dot(dir) > 0 ? Quaternion.identity() : Quaternion.axisAngle(Vector3(0, 1, 0), math.pi))
        : Quaternion.axisAngle(axis.normalized(), math.acos(_down.dot(dir).clamp(-1.0, 1.0)));
    line.localTransform = Matrix4.compose(from + delta * 0.5, rotation, Vector3(1, 1, length));
  }

  /// The way the unit thread runs: its length is along -z.
  static final Vector3 _down = Vector3(0, 0, -1);

  static final Geometry _float = SphereGeometry(radius: 0.11);
  static final Geometry _cap = SphereGeometry(radius: 0.06);
  static final Geometry _thread = CuboidGeometry(Vector3(0.012, 0.012, 1.0));
  static final Material _red = UnlitMaterial()..baseColorFactor = Vector4(0.90, 0.20, 0.15, 1);
  static final Material _white = UnlitMaterial()..baseColorFactor = Vector4(0.95, 0.95, 0.92, 1);
  static final Material _dark = UnlitMaterial()..baseColorFactor = Vector4(0.12, 0.12, 0.12, 1);
}
