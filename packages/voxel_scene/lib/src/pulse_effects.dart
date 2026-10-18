import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'mirrored_camera.dart';

/// A flash of colour over the world, where a blow lands or a spell goes off:
/// a see-through sphere that grows to a radius and fades in [seconds].
///
/// Add [node] to the scene and call [advance] every frame. [add] raises one
/// from anywhere. Every sphere shares one geometry and has its own unlit,
/// blended material, built once with the pool: a frame allocates nothing.
/// Without [node] (headless), the pulses keep their state and nothing draws.
class PulseEffects {
  /// At most [capacity] pulses at once; a new one past that drops the
  /// oldest.
  PulseEffects({this.capacity = 16}) : assert(capacity > 0, 'a pool of no pulses');

  /// Seconds a pulse lasts.
  static const double seconds = 0.35;

  /// A pulse's alpha when it is raised; it falls to 0 over [seconds].
  static const double alpha = 0.55;

  /// The most pulses shown at once.
  final int capacity;

  final List<_Pulse> _live = [];
  final List<_Sphere> _spheres = [];

  /// The scale of the unit-diameter sphere [age] seconds into a pulse that
  /// grows to [radius]: 1 at the start, `radius × 2` at [seconds], easing out
  /// as a cubic.
  static double scaleAt(double age, double radius) {
    final u = 1.0 - _t(age);
    return 1.0 + (radius * 2.0 - 1.0) * (1.0 - u * u * u);
  }

  /// A pulse's alpha [age] seconds in: [alpha], falling straight to 0 at
  /// [seconds].
  static double alphaAt(double age) => alpha * (1.0 - _t(age));

  static double _t(double age) => (age / seconds).clamp(0.0, 1.0);

  /// Each live pulse, oldest first: where it was raised, its `0xRRGGBB`, the
  /// radius it grows to and its seconds so far.
  Iterable<({Vector3 at, int color, double radius, double age})> get shown =>
      _live.map((p) => (at: p.at, color: p.color, radius: p.radius, age: p.age));

  /// Raises a pulse of [color] (`0xRRGGBB`, linear) at [at] that grows to
  /// [radius] metres. Throws for a radius not above 0 or a colour outside
  /// `0..0xFFFFFF`.
  void add(Vector3 at, int color, double radius) {
    if (!(radius > 0)) throw ArgumentError.value(radius, 'radius', 'not above 0');
    if (color < 0 || color > 0xFFFFFF) throw ArgumentError.value(color, 'color', 'not 0xRRGGBB');
    if (_live.length == capacity) _live.removeAt(0);
    _live.add(_Pulse(at.clone(), color, radius));
  }

  /// Ages every pulse by [dt] seconds, drops those past [seconds], and
  /// places, scales and fades a sphere for each live one, hiding the rest.
  void advance(double dt) {
    for (final p in _live) {
      p.age += dt;
    }
    _live.removeWhere((p) => p.age >= seconds);
    for (var i = 0; i < _spheres.length; i++) {
      final s = _spheres[i];
      if (i >= _live.length) {
        s.node.visible = false;
        continue;
      }
      final p = _live[i];
      final k = scaleAt(p.age, p.radius);
      s.node
        ..localTransform = (s.transform
          ..setZero()
          ..setEntry(0, 0, k)
          ..setEntry(1, 1, k)
          ..setEntry(2, 2, k)
          ..setEntry(3, 3, 1.0)
          ..setTranslationRaw(p.at.x, p.at.y, p.at.z))
        ..visible = true;
      s.material.baseColorFactor.setValues(
        ((p.color >> 16) & 0xFF) / 255.0,
        ((p.color >> 8) & 0xFF) / 255.0,
        (p.color & 0xFF) / 255.0,
        alphaAt(p.age),
      );
    }
  }

  /// What goes in the scene: [capacity] spheres, hidden until a pulse shows
  /// one. Built the first time it is asked for.
  late final Node node = () {
    final root = Node(name: 'Pulses');
    final geometry = SphereGeometry(radius: 0.5);
    for (var i = 0; i < capacity; i++) {
      final material = UnlitMaterial()
        ..alphaMode = AlphaMode.blend
        ..vertexColorWeight = 0.0;
      final node = MirroredCamera.primitiveNode(Mesh(geometry, material), shadowCastingMode: ShadowCastingMode.off)
        ..visible = false;
      root.add(node);
      _spheres.add(_Sphere(node, material));
    }
    return root;
  }();
}

class _Pulse {
  _Pulse(this.at, this.color, this.radius);

  final Vector3 at;
  final int color;
  final double radius;
  double age = 0.0;
}

class _Sphere {
  _Sphere(this.node, this.material);

  final Node node;
  final UnlitMaterial material;
  final Matrix4 transform = Matrix4.identity();
}
