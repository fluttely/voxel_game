import 'dart:ui';

import 'package:voxel_game_minecraft/src/core/species.dart';
import 'package:voxel_game_minecraft/src/entities/mob.dart';
import 'package:voxel_game_minecraft/src/player/player.dart';
import 'package:voxel_game_minecraft/src/ui/hud.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 37's pure pieces: a list rolled by a wheel, a trackpad and a finger;
/// a bigger mob is a bigger collider (`--outline-probe` checks every model
/// against its collider; the fence arms are pinned in voxel_core's
/// `physics_test`).
void main() {
  group('a panel list rolls', () {
    const body = Rect.fromLTWH(0, 0, 100, 300);
    PanelScroll list() {
      final s = PanelScroll();
      // Paints the box once so the list knows its length: 1000 tall, 700 to roll.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      s.begin(canvas, body, 1000);
      s.end(canvas, body);
      recorder.endRecording();
      return s;
    }

    test('by the wheel, a notch at a time, within its ends', () {
      final s = list()..wheel(1);
      expect(s.offset, PanelScroll.step);
      for (var i = 0; i < 40; i++) {
        s.wheel(1);
      }
      expect(s.offset, 700);
      expect(s.hasMore, isFalse);
      s.wheel(-1);
      expect(s.offset, 700 - PanelScroll.step);
      expect(s.hasMore, isTrue);
    });

    test('by a trackpad swipe, which is a pan gesture and never a wheel signal', () {
      final s = list();
      var k = 2.0;
      final input = PanelScrollInput(() => s, () => k);
      // Fingers up 120 px pull the content up: 60 panel units at 2x.
      input.panZoom(const PointerPanZoomUpdateEvent(panDelta: Offset(0, -120), pan: Offset(0, -120)));
      expect(s.offset, 60);
      k = 1.0;
      input.panZoom(const PointerPanZoomUpdateEvent(panDelta: Offset(0, 5000), pan: Offset(0, 4880)));
      expect(s.offset, 0);
      input.signal(const PointerScrollEvent(scrollDelta: Offset(0, 3)));
      expect(s.offset, PanelScroll.step);
    });

    test('by a finger past the slop, and a short touch is still a tap', () {
      final s = list();
      final input = PanelScrollInput(() => s, () => 1.0);
      input.down(const PointerDownEvent(kind: PointerDeviceKind.touch));
      input.move(const PointerMoveEvent(kind: PointerDeviceKind.touch, delta: Offset(0, -5)));
      expect(input.dragged, isFalse);
      expect(s.offset, 0);
      input.move(const PointerMoveEvent(kind: PointerDeviceKind.touch, delta: Offset(0, -50)));
      expect(input.dragged, isTrue);
      expect(s.offset, 50);
      input.down(const PointerDownEvent(kind: PointerDeviceKind.touch));
      expect(input.dragged, isFalse);
    });

    test('never by a mouse drag, which carries a stack', () {
      final s = list();
      final input = PanelScrollInput(() => s, () => 1.0);
      input.down(const PointerDownEvent(kind: PointerDeviceKind.mouse));
      input.move(const PointerMoveEvent(kind: PointerDeviceKind.mouse, delta: Offset(0, -80)));
      expect(s.offset, 0);
    });

    test('a click lands on the row drawn under it', () {
      final s = list()..drag(-90);
      expect(s.toContent(const Offset(10, 15)), const Offset(10, 105));
    });
  });

  test('a giant is a giant collider, and the model follows the collider', () {
    final zombie = Species.def('zombie');
    final m = Mob()
      ..species = zombie
      ..position = Vector3(0, 64, 0)
      ..halfWidth = zombie.halfWidth
      ..height = zombie.height;
    expect(m.sizeScale, 1.0);
    m.setAffix('Giant');
    final giant = Mob.affixes['Giant']!.scale;
    expect(m.height, closeTo(zombie.height * giant, 1e-9));
    expect(m.halfWidth, closeTo(zombie.halfWidth * giant, 1e-9));
    expect(m.sizeScale, closeTo(giant, 1e-9));
    final box = Player.mobBox(m);
    expect(box.y1 - box.y0, closeTo(zombie.height * giant, 1e-9));
    // What the crosshair ray tests is the same box: a shot at the giant's
    // head, over the plain collider's top, hits.
    final head = zombie.height * giant - 0.1;
    expect(head, greaterThan(zombie.height));
    expect(m.rayDistance(Vector3(-5, 64 + head, 0), Vector3(1, 0, 0)), greaterThan(0));
  });

  test('every affix that resizes keeps width and height in step', () {
    for (final entry in Mob.affixes.entries) {
      final sp = Species.def('spider');
      final m = Mob()
        ..species = sp
        ..halfWidth = sp.halfWidth
        ..height = sp.height
        ..setAffix(entry.key);
      expect(m.halfWidth / sp.halfWidth, closeTo(m.sizeScale, 1e-9), reason: entry.key);
      expect(m.sizeScale, closeTo(entry.value.scale, 1e-9), reason: entry.key);
    }
  });
}
