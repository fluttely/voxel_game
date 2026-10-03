import 'package:flutter_scene/scene.dart' show Node;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_scene/voxel_scene.dart' show RigPart;

void main() {
  test('one look at one size is one model, whoever declares it', () {
    const rig = Rig.humanoid(skin: 0x5E9A5A, armsForward: true);
    final model = RigModel.of(rig, 0.3, 1.8);
    expect(RigModel.of(rig, 0.3, 1.8), same(model));
    // Built at run time, not const: equal by its values, so the same model.
    var skin = 0x5E9A5A;
    expect(RigModel.of(Rig.humanoid(skin: skin, armsForward: true), 0.3, 1.8), same(model));
    skin = 0x5E9A5B;
    expect(RigModel.of(Rig.humanoid(skin: skin, armsForward: true), 0.3, 1.8), isNot(same(model)));
    expect(RigModel.of(rig, 0.3, 1.2), isNot(same(model)), reason: 'another size is fitted anew');
    expect(RigModel.of(const Rig.humanoid(skin: 0x5E9A5A), 0.3, 1.8), isNot(same(model)));
  });

  test('parts cut from the same voxels share one shape, so one mesh', () {
    RigShape shape(RigModel m, String name) => m.parts.firstWhere((p) => p.name == name).shape;

    final humanoid = RigModel.of(const Rig.humanoid(), 0.3, 1.8);
    expect(humanoid.parts.map((p) => p.name), ['leg0', 'leg1', 'body', 'arm0', 'arm1', 'head']);
    expect(shape(humanoid, 'leg1'), same(shape(humanoid, 'leg0')));
    expect(shape(humanoid, 'arm1'), same(shape(humanoid, 'arm0')));
    expect(shape(humanoid, 'arm0'), isNot(same(shape(humanoid, 'leg0'))), reason: 'skin, not pants');
    expect({for (final p in humanoid.parts) p.shape}, hasLength(4));

    final quadruped = RigModel.of(const Rig.quadruped(), 0.45, 1.3);
    expect({for (var i = 0; i < 4; i++) shape(quadruped, 'leg$i')}, hasLength(1));
    expect(quadruped.backHeight, greaterThan(0.0));

    final spider = RigModel.of(const Rig.spider(), 0.7, 0.9);
    expect(spider.legFan, hasLength(8));
    expect([for (final p in spider.parts.where((p) => p.name.startsWith('leg'))) p.sx], [1, -1, 1, -1, 1, -1, 1, -1]);
  });

  test("a humanoid's right fist is where its arm ends, sized with its body", () {
    final player = RigModel.of(const Rig.humanoid(), 0.3, 1.75);
    final hand = player.hand!;
    expect(hand.scale, 1.0);
    expect(hand.at.y, closeTo(-11.3 * 0.055, 1e-6), reason: 'at the bottom of the 12-voxel arm');
    final child = RigModel.of(const Rig.humanoid(), 0.2, 0.875).hand!;
    expect(child.scale, 0.5);
    expect(child.at.y, closeTo(hand.at.y / 2, 1e-6));
    expect(RigModel.of(const Rig.quadruped(), 0.45, 1.3).hand, isNull, reason: 'nothing to hold with');
  });

  test('a seated humanoid sits: its legs out in front, drawn as low as its thighs then rest at its feet', () {
    final player = RigModel.of(const Rig.humanoid(), 0.3, 1.75);
    expect(player.seatDrop, closeTo(0.66 - 2 * 0.055, 1e-9), reason: 'its hips, less half a thigh');
    expect(RigModel.of(const Rig.humanoid(), 0.2, 0.875).seatDrop, closeTo(player.seatDrop / 2, 1e-9));
    expect(RigModel.of(const Rig.quadruped(), 0.45, 1.3).seatDrop, 0.0, reason: 'only a humanoid sits');

    final parts = {
      for (final n in ['leg0', 'leg1', 'body', 'arm0', 'arm1', 'head']) n: RigPart(Node(), Vector3.zero()),
    };
    final animator = RigAnimator(RigKind.humanoid, parts);
    animator.pose(1 / 60, age: 0.0, speed: 0.0, seated: true);
    expect([parts['leg0']!.rx, parts['leg1']!.rx], [RigAnimator.seatedLegs, RigAnimator.seatedLegs]);
    animator.pose(1 / 60, age: 0.0, speed: 0.0);
    expect([parts['leg0']!.rx, parts['leg1']!.rx], [0.0, 0.0], reason: 'standing again');
  });

  test('a gliding humanoid spreads its arms, and folds them back after', () {
    final parts = {
      for (final n in ['leg0', 'leg1', 'body', 'arm0', 'arm1', 'head']) n: RigPart(Node(), Vector3.zero()),
    };
    final animator = RigAnimator(RigKind.humanoid, parts);
    for (var i = 0; i < 60; i++) {
      animator.pose(1 / 60, age: i / 60, speed: 10.0, gliding: true);
    }
    expect(parts['arm0']!.rz, closeTo(-RigAnimator.glideSpread, 1e-3), reason: 'the left arm out to the left');
    expect(parts['arm1']!.rz, closeTo(RigAnimator.glideSpread, 1e-3));
    expect(parts['arm1']!.rx, closeTo(0.0, 1e-3), reason: 'spread arms do not swing with the stride');
    for (var i = 0; i < 60; i++) {
      animator.pose(1 / 60, age: 1.0 + i / 60, speed: 0.0);
    }
    expect([parts['arm0']!.rz, parts['arm1']!.rz], [closeTo(0.0, 1e-3), closeTo(0.0, 1e-3)]);
  });
}
