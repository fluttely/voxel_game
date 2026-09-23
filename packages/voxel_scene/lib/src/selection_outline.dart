import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import 'mirrored_camera.dart';

/// The skeleton drawn around whatever the crosshair rests on: the twelve edges
/// of a box, as cuboid sticks. The box is the thing's own (a torch's post, a
/// slab's half, a mob's collider), never the whole cell.
///
/// Why cuboids and not a line geometry: a `LineSegmentsGeometry` node does not
/// reach the screen in flutter_scene 0.23.
///
/// Why a depth bias: a stick on the edge of a block that sits flush with its
/// neighbours lies half inside them, and the depth test eats those halves (a
/// block in a floor loses eleven of its twelve edges). The sticks are drawn
/// [depthBias] metres toward the eye instead, so an edge shared with a
/// neighbour still shows, while the far edges stay hidden behind the thing
/// they outline.
class SelectionOutline {
  /// Twelve sticks of [color], hidden until [show]. Add [node] to the scene.
  SelectionOutline({Vector4? color}) {
    final stick = UnlitMaterial()
      ..baseColorFactor = color ?? Vector4(0.75, 0.75, 0.75, 1)
      ..vertexColorWeight = 0.0
      ..depthBias = depthBias;
    for (var axis = 0; axis < 3; axis++) {
      for (var corner = 0; corner < 4; corner++) {
        // A unit-long stick along its axis; [show] stretches it to the edge.
        final size = Vector3.all(thickness);
        size[axis] = 1.0;
        final n = MirroredCamera.primitiveNode(Mesh(CuboidGeometry(size), stick), castsShadows: false);
        _sticks.add(n);
        node.add(n);
      }
    }
  }

  /// How far the skeleton stands off the box.
  static const double gap = 0.005;

  /// A stick's thickness.
  static const double thickness = 0.03;

  /// How far toward the eye the sticks are drawn. Enough to clear the half of
  /// a stick buried in a neighbour (a hundredth of a metre) seen at a grazing
  /// angle; small enough that the back edges of a cube stay behind its front.
  static const double depthBias = 0.06;

  /// The skeleton's root; it sits at the box's minimum corner while shown.
  final Node node = Node()
    ..visible = false
    ..castsShadows = false;
  final List<Node> _sticks = [];

  /// The box the skeleton was last fitted to, or null while hidden.
  CollisionBox? box;

  /// Whether the skeleton is shown.
  bool get visible => node.visible;

  /// Fits the skeleton to [b] (world space) and shows it.
  void show(CollisionBox b) {
    box = b;
    node.visible = true;
    node.position = Vector3(b.x0, b.y0, b.z0);
    final sticks = stickTransforms(b);
    for (var i = 0; i < 12; i++) {
      _sticks[i]
        ..position = sticks[i].position
        ..scale = sticks[i].scale;
    }
  }

  /// Hides the skeleton.
  void hide() {
    box = null;
    node.visible = false;
  }

  /// The twelve sticks around [b], relative to its minimum corner: stick
  /// `axis * 4 + corner` runs along `axis`, and `corner`'s two bits pick the
  /// low or high side of the other two axes. Each spans the edge corner to
  /// corner, [gap] off the box, so the joints close.
  static List<({Vector3 position, Vector3 scale})> stickTransforms(CollisionBox b) {
    final span = Vector3(b.x1 - b.x0, b.y1 - b.y0, b.z1 - b.z0);
    final out = <({Vector3 position, Vector3 scale})>[];
    for (var axis = 0; axis < 3; axis++) {
      for (var corner = 0; corner < 4; corner++) {
        final a1 = (axis + 1) % 3, a2 = (axis + 2) % 3;
        final centre = Vector3.zero();
        centre[axis] = span[axis] * 0.5;
        centre[a1] = corner & 1 == 0 ? -gap : span[a1] + gap;
        centre[a2] = corner & 2 == 0 ? -gap : span[a2] + gap;
        final scale = Vector3.all(1.0);
        scale[axis] = span[axis] + 2 * gap + thickness;
        out.add((position: centre, scale: scale));
      }
    }
    return out;
  }
}
