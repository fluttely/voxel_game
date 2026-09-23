import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:voxel_engine/core.dart';

import '../entities/voxel_mesh_builder.dart';

/// One visible face of an icon: a quad in the icon's unit square (0..1, y
/// down) and its shaded colour.
class IconFace {
  const IconFace(this.corners, this.color, this.depth);

  final List<Offset> corners;
  final Color color;

  /// How far toward the eye the face's voxel sits (the paint order).
  final double depth;
}

/// Inventory and hotbar icons, drawn from the item's own voxel model
/// ([VoxelMeshBuilder.itemShape]) — the pickaxe in the bag is the pickaxe in
/// the hand.
///
/// A slot does not run a 3D render: each item is projected once, on first
/// sight, into a small image, and every frame after that is one image copy.
/// The projection is orthographic, so painting whole voxels from the back to
/// the front is exact and needs no depth buffer.
class ItemIcon {
  ItemIcon._();

  /// The side of a cached icon, in pixels: sharp in a 54 px slot at 2x.
  static const int size = 128;

  /// How much of the square the model fills.
  static const double fill = 0.84;

  static final Map<String, ui.Image> _cache = {};

  /// Where the light comes from, in view space: above, left and in front.
  static final vm.Vector3 _light = vm.Vector3(-0.35, 0.65, 0.68).normalized();

  static const List<IVec3> _normals = [
    IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1),
  ];

  /// The four corners of each face, as offsets from the voxel's min corner,
  /// in order around the face.
  static const List<List<IVec3>> _corners = [
    [IVec3(0, 1, 0), IVec3(1, 1, 0), IVec3(1, 1, 1), IVec3(0, 1, 1)],
    [IVec3(0, 0, 0), IVec3(0, 0, 1), IVec3(1, 0, 1), IVec3(1, 0, 0)],
    [IVec3(1, 0, 0), IVec3(1, 0, 1), IVec3(1, 1, 1), IVec3(1, 1, 0)],
    [IVec3(0, 0, 0), IVec3(0, 1, 0), IVec3(0, 1, 1), IVec3(0, 0, 1)],
    [IVec3(0, 0, 1), IVec3(0, 1, 1), IVec3(1, 1, 1), IVec3(1, 0, 1)],
    [IVec3(0, 0, 0), IVec3(1, 0, 0), IVec3(1, 1, 0), IVec3(0, 1, 0)],
  ];

  /// How a model is turned to face the slot. A block is seen from a top
  /// corner, the classic isometric cube. A flat piece faces the eye with its
  /// shaft on the diagonal, tip to the top right, turned a little so its
  /// thickness shows.
  static vm.Matrix3 view(ItemShape shape) => shape.flat
      ? vm.Matrix3.rotationX(0.25).multiplied(vm.Matrix3.rotationY(-0.35)).multiplied(vm.Matrix3.rotationZ(-math.pi / 4))
      : vm.Matrix3.rotationX(math.pi / 6).multiplied(vm.Matrix3.rotationY(-math.pi / 4));

  /// The faces the eye sees, back to front, fitted to the unit square.
  static List<IconFace> faces(ItemShape shape) {
    final r = view(shape);
    final normals = [for (final n in _normals) r.transformed(vm.Vector3(n.x.toDouble(), n.y.toDouble(), n.z.toDouble()))];
    final order = shape.voxels.keys.toList()
      ..sort((a, b) => _depth(r, a).compareTo(_depth(r, b)));
    final raw = <(List<vm.Vector3>, vm.Vector3, double)>[];
    var lo = vm.Vector2.all(double.infinity), hi = vm.Vector2.all(double.negativeInfinity);
    for (final p in order) {
      final colour = shape.voxels[p]!;
      for (var f = 0; f < 6; f++) {
        // The eye looks down -Z: a face is seen when it turns toward +Z, and
        // only an outer face is ever seen.
        if (normals[f].z <= 1e-6 || shape.voxels.containsKey(p + _normals[f])) continue;
        final pts = [
          for (final c in _corners[f]) r.transformed(vm.Vector3((p.x + c.x).toDouble(), (p.y + c.y).toDouble(), (p.z + c.z).toDouble())),
        ];
        for (final q in pts) {
          lo = vm.Vector2(math.min(lo.x, q.x), math.min(lo.y, q.y));
          hi = vm.Vector2(math.max(hi.x, q.x), math.max(hi.y, q.y));
        }
        final shade = 0.55 + 0.45 * math.max(0.0, normals[f].dot(_light));
        raw.add((pts, colour * shade, _depth(r, p)));
      }
    }
    final span = math.max(hi.x - lo.x, hi.y - lo.y);
    final k = fill / span;
    final mid = (lo + hi) * 0.5;
    return [
      for (final (pts, c, d) in raw)
        IconFace(
          // Screen y runs down.
          [for (final q in pts) Offset(0.5 + (q.x - mid.x) * k, 0.5 - (q.y - mid.y) * k)],
          Color.from(alpha: 1, red: c.x.clamp(0.0, 1.0), green: c.y.clamp(0.0, 1.0), blue: c.z.clamp(0.0, 1.0)),
          d,
        ),
    ];
  }

  static double _depth(vm.Matrix3 r, IVec3 p) => r.transformed(vm.Vector3(p.x + 0.5, p.y + 0.5, p.z + 0.5)).z;

  /// [id]'s icon, projected on first use.
  static ui.Image image(String id) => _cache[id] ??= _render(id);

  static ui.Image _render(String id) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final s = size.toDouble();
    for (final f in faces(VoxelMeshBuilder.itemShape(id))) {
      final path = Path()..addPolygon([for (final c in f.corners) c * s], true);
      canvas.drawPath(path, Paint()..color = f.color);
      // A hairline of the same colour closes the seams antialiasing leaves
      // between two quads that share an edge.
      canvas.drawPath(
          path,
          Paint()
            ..color = f.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0);
    }
    return recorder.endRecording().toImageSync(size, size);
  }

  /// Draws [id]'s icon into [r].
  static void draw(Canvas canvas, Rect r, String id) {
    final img = image(id);
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), r,
        Paint()..filterQuality = FilterQuality.medium);
  }
}
