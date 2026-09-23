import 'dart:ui';

import 'package:voxel_game_minecraft/src/ui/hud.dart';
import 'package:voxel_game_minecraft/src/ui/hud_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage 39: one map in two frames. The dash pose is measured by
/// `--anim-probe`, which needs the scene.
void main() {
  test('M shows one map at a time: the corner, then the full map, then none', () {
    expect([MapView.off.next, MapView.corner.next, MapView.full.next], [MapView.corner, MapView.full, MapView.off]);
  });

  test('the corner frame centres the player on the same world-fixed bitmap', () {
    const view = Rect.fromLTWH(1000, 80, 240, 240);
    const f = MapFrame(view, 10.5, -3.25, 2.5);
    expect(f.toScreen(10.5, -3.25), view.center);
    // A bitmap built around another spot is drawn where its corner block is,
    // so the ground under the arrow is the ground under the player.
    final img = f.imageRect(-54, -70, 128, 128);
    expect(img.topLeft, Offset(view.center.dx + (-54 - 10.5) * 2.5, view.center.dy + (-70 + 3.25) * 2.5));
    expect(img.size, const Size(320, 320));
    final ground = Offset(img.left + (10.5 + 54) * 2.5, img.top + (-3.25 + 70) * 2.5);
    expect(ground, view.center);
    // 48 blocks each way are inside; 49 are clipped away.
    expect(f.inside(10.5 + 47.9, -3.25), isTrue);
    expect(f.inside(10.5 + 49, -3.25), isFalse);
  });

  test('the full frame is the same transform, fitted around the bitmap', () {
    const shown = Rect.fromLTWH(20, 64, 686, 686);
    const f = MapFrame(shown, -64 + 128 * 0.5, 16 + 128 * 0.5, 686 / 128);
    expect(f.imageRect(-64, 16, 128, 128), shown);
  });
}
