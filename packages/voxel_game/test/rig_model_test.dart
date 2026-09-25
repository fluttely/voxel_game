import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';

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
}
