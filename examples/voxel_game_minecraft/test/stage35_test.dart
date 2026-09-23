import 'package:voxel_game_minecraft/src/entities/mob.dart';
import 'package:voxel_game_minecraft/src/player/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 35's pure pieces (`--outline-probe` builds every species and aims at
/// every shape on screen; `voxel_core`'s `selection_box_test` pins the block
/// boxes against the mesher): the face-plane check, the leg inset, the mob
/// outline box and the skeleton's standoff.
void main() {
  group('the face-plane check', () {
    Aabb3 box(double x0, double y0, double z0, double x1, double y1, double z1) =>
        Aabb3.minMax(Vector3(x0, y0, z0), Vector3(x1, y1, z1));

    test('a leg flush with the barrel side, over the voxel it sinks in, is a fight', () {
      final hits = Mob.coplanarFaces({
        'body': box(-0.24, 0.36, -0.42, 0.30, 0.84, 0.48),
        'leg0': box(0.12, 0.0, 0.24, 0.30, 0.42, 0.42),
      });
      expect(hits, ['body/leg0 +x=0.300']);
    });

    test('the same leg a centimetre in is not', () {
      final hits = Mob.coplanarFaces({
        'body': box(-0.24, 0.36, -0.42, 0.30, 0.84, 0.48),
        'leg0': box(0.13, 0.0, 0.25, 0.29, 0.42, 0.41),
      });
      expect(hits, isEmpty);
    });

    test('faces meeting head on hide each other and are not listed', () {
      // A leg's top against the belly; two legs side by side.
      final hits = Mob.coplanarFaces({
        'body': box(-0.2, 0.4, -0.2, 0.2, 0.8, 0.2),
        'leg0': box(-0.2, 0.0, -0.1, 0.0, 0.4, 0.1),
        'leg1': box(0.0, 0.0, -0.1, 0.2, 0.4, 0.1),
      });
      expect(hits, isEmpty);
    });

    test('planes that only touch along an edge are not a fight', () {
      final hits = Mob.coplanarFaces({
        'a': box(0, 0, 0, 1, 1, 1),
        'b': box(1, 0, 0, 2, 1, 1), // its y and z planes meet a's only along x = 1
      });
      expect(hits, isEmpty);
    });
  });

  test('the inset is enough for the depth buffer at play distance, and small against a leg', () {
    // A 24-bit buffer with the 0.05 m near plane resolves ~2 mm at 30 m.
    expect(Mob.partInset, greaterThanOrEqualTo(0.005));
    // A quadruped leg is three 0.06 m voxels wide; the inset keeps it over 85% of that.
    expect(1.0 - 2 * Mob.partInset / 0.18, greaterThan(0.85));
  });

  test('a mob is outlined by its collider, feet up', () {
    final m = Mob()
      ..position = Vector3(10.5, 64, -3.5)
      ..halfWidth = 0.45
      ..height = 1.1;
    final b = Player.mobBox(m);
    expect([b.x0, b.y0, b.z0, b.x1, b.y1, b.z1], [10.05, 64, -3.95, 10.95, 65.1, -3.05].map((v) => closeTo(v, 1e-9)).toList());
  });
}
