import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:voxel_engine/content.dart';
import 'package:voxel_engine/core.dart';

/// One visible face of an icon: a quad in the icon's unit square (0..1, y
/// down), its shaded colour and how near the eye its voxel is.
typedef IconFace = ({List<Offset> corners, Color color, double depth});

/// An item's icon in a slot, drawn from its voxel [model] — the pickaxe in the
/// bag is the pickaxe in the hand.
///
/// A slot runs no 3D render: each model is projected once, on first sight,
/// into a recorded picture ([picture]), and every paint after that replays it.
/// The projection is orthographic, so painting whole voxels from the back to
/// the front is exact and needs no depth buffer.
class ItemIcon extends StatelessWidget {
  /// [model]'s icon, [size] logical pixels a side.
  const ItemIcon(this.model, {super.key, required this.size});

  /// What is drawn.
  final ItemModel model;

  /// The side of the square it fills.
  final double size;

  /// How much of the square the model fills.
  static const double fill = 0.84;

  /// The side the pictures are recorded at; they are scaled to [size].
  static const double _recorded = 64.0;

  static final Map<ItemModel, ui.Picture> _pictures = {};

  /// Where the light comes from, in view space: above, left and in front.
  static final vm.Vector3 _light = vm.Vector3(-0.35, 0.65, 0.68).normalized();

  static const List<IVec3> _normals = [
    IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), //
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

  /// How a model is turned to face the slot. A flat piece faces the eye with
  /// its shaft on the diagonal, tip to the top right, turned a little so its
  /// thickness shows; anything else is seen from a top corner, the classic
  /// isometric cube.
  static vm.Matrix3 view(ItemModel model) => model.grip == ItemGrip.flat
      ? vm.Matrix3.rotationX(0.25)
            .multiplied(vm.Matrix3.rotationY(-0.35))
            .multiplied(vm.Matrix3.rotationZ(-math.pi / 4))
      : vm.Matrix3.rotationX(math.pi / 6).multiplied(vm.Matrix3.rotationY(-math.pi / 4));

  /// The faces the eye sees, back to front, fitted to the unit square.
  static List<IconFace> faces(ItemModel model) {
    final r = view(model);
    final normals = [
      for (final n in _normals) r.transformed(vm.Vector3(n.x.toDouble(), n.y.toDouble(), n.z.toDouble())),
    ];
    double depth(IVec3 p) => r.transformed(vm.Vector3(p.x + 0.5, p.y + 0.5, p.z + 0.5)).z;
    final order = model.voxels.keys.toList()..sort((a, b) => depth(a).compareTo(depth(b)));
    final raw = <(List<vm.Vector3>, vm.Vector3, double)>[];
    var lo = vm.Vector2.all(double.infinity), hi = vm.Vector2.all(double.negativeInfinity);
    for (final p in order) {
      final colour = model.voxels[p]!;
      for (var f = 0; f < 6; f++) {
        // The eye looks down -Z: a face is seen when it turns toward +Z, and
        // only an outer face is ever seen.
        if (normals[f].z <= 1e-6 || model.voxels.containsKey(p + _normals[f])) continue;
        final pts = [
          for (final c in _corners[f])
            r.transformed(vm.Vector3((p.x + c.x).toDouble(), (p.y + c.y).toDouble(), (p.z + c.z).toDouble())),
        ];
        for (final q in pts) {
          lo = vm.Vector2(math.min(lo.x, q.x), math.min(lo.y, q.y));
          hi = vm.Vector2(math.max(hi.x, q.x), math.max(hi.y, q.y));
        }
        final shade = 0.55 + 0.45 * math.max(0.0, normals[f].dot(_light));
        raw.add((pts, colour * shade, depth(p)));
      }
    }
    final k = fill / math.max(hi.x - lo.x, hi.y - lo.y);
    final mid = (lo + hi) * 0.5;
    return [
      for (final (pts, c, d) in raw)
        (
          // Screen y runs down.
          corners: [for (final q in pts) Offset(0.5 + (q.x - mid.x) * k, 0.5 - (q.y - mid.y) * k)],
          color: Color.from(alpha: 1, red: c.x.clamp(0.0, 1.0), green: c.y.clamp(0.0, 1.0), blue: c.z.clamp(0.0, 1.0)),
          depth: d,
        ),
    ];
  }

  /// [model]'s faces recorded once, [_recorded] units a side.
  static ui.Picture picture(ItemModel model) => _pictures[model] ??= _record(model);

  static ui.Picture _record(ItemModel model) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final f in faces(model)) {
      final path = Path()..addPolygon([for (final c in f.corners) c * _recorded], true);
      canvas.drawPath(path, Paint()..color = f.color);
      // A hairline of the same colour closes the seams antialiasing leaves
      // between two quads that share an edge.
      canvas.drawPath(
        path,
        Paint()
          ..color = f.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
    }
    return recorder.endRecording();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _IconPainter(picture(model)));
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.picture);

  final ui.Picture picture;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / ItemIcon._recorded, size.height / ItemIcon._recorded)
      ..drawPicture(picture)
      ..restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) => !identical(old.picture, picture);
}
