import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';

import 'box_mesh.dart';

/// The skeleton drawn around whatever the crosshair rests on: the twelve edges
/// of a box, as cuboid sticks. The box is the thing's own (a torch's post, a
/// slab's half, a mob's collider), never the whole cell.
///
/// Why cuboids and not a line geometry: a `LineSegmentsGeometry` node does not
/// reach the screen in flutter_scene 0.23.
///
/// Why one mesh: flutter_scene draws a geometry a draw, so twelve sticks of
/// their own were twelve draws, and visits every node every frame. The twelve
/// are one [BoxMesh] on one node, built the first time a box of that size is
/// shown and kept by size: the shapes a game aims at are few.
///
/// Why a depth bias: a stick on the edge of a block that sits flush with its
/// neighbours lies half inside them, and the depth test eats those halves (a
/// block in a floor loses eleven of its twelve edges). The sticks are drawn
/// [depthBias] metres toward the eye instead, so an edge shared with a
/// neighbour still shows, while the far edges stay hidden behind the thing
/// they outline.
class SelectionOutline {
  /// Twelve sticks of [color], hidden until [show]. Add [node] to the scene.
  SelectionOutline({Vector4? color})
    : _stick = UnlitMaterial()
        ..baseColorFactor = color ?? Vector4(0.75, 0.75, 0.75, 1)
        ..vertexColorWeight = 0.0
        ..depthBias = depthBias;

  /// How far the skeleton stands off the box.
  static const double gap = 0.005;

  /// A stick's thickness.
  static const double thickness = 0.03;

  /// How far toward the eye the sticks are drawn. Enough to clear the half of
  /// a stick buried in a neighbour (a hundredth of a metre) seen at a grazing
  /// angle; small enough that the back edges of a cube stay behind its front.
  static const double depthBias = 0.06;

  /// The skeleton; it sits at the box's minimum corner while shown.
  final Node node = Node()
    ..visible = false
    ..castsShadows = false;
  final UnlitMaterial _stick;

  /// The skeleton of each box size shown so far.
  final Map<(double, double, double), Mesh> _meshes = {};
  (double, double, double)? _size;

  /// The box the skeleton was last fitted to, or null while hidden.
  CollisionBox? box;

  /// Whether the skeleton is shown.
  bool get visible => node.visible;

  /// Fits the skeleton to [b] (world space) and shows it.
  void show(CollisionBox b) {
    box = b;
    node.visible = true;
    node.position = Vector3(b.x0, b.y0, b.z0);
    final size = (b.x1 - b.x0, b.y1 - b.y0, b.z1 - b.z0);
    if (size == _size) return;
    _size = size;
    node.mesh = _meshes[size] ??= Mesh(BoxMesh.geometry(stickBoxes(b)), _stick);
  }

  /// Hides the skeleton.
  void hide() {
    box = null;
    node.visible = false;
  }

  /// The twelve sticks around [b], relative to its minimum corner: stick
  /// `axis * 4 + corner` runs along `axis`, and `corner`'s two bits pick the
  /// low or high side of the other two axes. Each is [thickness] across and
  /// spans the edge corner to corner, [gap] off the box, so the joints close.
  static List<Aabb3> stickBoxes(CollisionBox b) {
    final span = Vector3(b.x1 - b.x0, b.y1 - b.y0, b.z1 - b.z0);
    final out = <Aabb3>[];
    for (var axis = 0; axis < 3; axis++) {
      for (var corner = 0; corner < 4; corner++) {
        final a1 = (axis + 1) % 3, a2 = (axis + 2) % 3;
        final centre = Vector3.zero();
        centre[axis] = span[axis] * 0.5;
        centre[a1] = corner & 1 == 0 ? -gap : span[a1] + gap;
        centre[a2] = corner & 2 == 0 ? -gap : span[a2] + gap;
        final half = Vector3.all(thickness / 2);
        half[axis] = (span[axis] + 2 * gap + thickness) / 2;
        out.add(Aabb3.centerAndHalfExtents(centre, half));
      }
    }
    return out;
  }
}
