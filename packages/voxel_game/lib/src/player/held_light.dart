import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/content.dart';

/// The light a body's item in hand gives (`ItemType.light`): a point light
/// in the item's colour at the body's chest, reaching [metresPerLevel] a
/// level of the item's light, and hidden (lighting nothing) while the hand
/// holds none.
class HeldLight {
  /// A light hung on a body's [node], out.
  HeldLight(Node node) {
    _node
      ..position = Vector3(0, 1.4, 0)
      ..visible = false
      ..addComponent(PointLightComponent(_light));
    node.add(_node);
  }

  final Node _node = Node();
  final PointLight _light = PointLight(intensity: intensity);

  /// How bright it is: the radiance a metre away.
  static const double intensity = 10.0;

  /// Metres of reach a level of light: a torch's 14 lights 9 m around.
  static const double metresPerLevel = 0.65;

  /// Lights it for [item] in hand, or puts it out for an empty hand or an
  /// item that gives no light.
  void show(ItemType? item) {
    final level = item?.light ?? 0;
    _node.visible = level > 0;
    if (level == 0) return;
    _light
      ..range = level * metresPerLevel
      ..color = Vector3(item!.r, item.g, item.b);
  }
}
