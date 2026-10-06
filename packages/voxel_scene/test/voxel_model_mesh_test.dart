import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test('one material a tint, shared; white and whole is the plain one', () {
    final ghost = VoxelModelMesh.tinted(Vector4(0.85, 0.92, 1.0, 0.45));
    expect(VoxelModelMesh.tinted(Vector4(0.85, 0.92, 1.0, 0.45)), same(ghost));
    expect(ghost.alphaMode, AlphaMode.blend);
    expect(ghost.isOpaque(), isFalse, reason: 'drawn in the translucent pass, casting no shadow');
    expect(ghost.baseColorFactor, Vector4(0.85, 0.92, 1.0, 0.45));

    final burn = VoxelModelMesh.tinted(Vector4(1.0, 0.55, 0.15, 1.0));
    expect(burn, isNot(same(ghost)));
    expect(burn.isOpaque(), isTrue, reason: 'a tint at alpha 1 stays in the opaque pass, batched and shadowed');

    expect(VoxelModelMesh.tinted(Vector4(1, 1, 1, 1)), same(VoxelModelMesh.material()));
    expect(() => VoxelModelMesh.tinted(Vector4(1, 1, 1, 1.5)), throwsArgumentError);
  });

  test("a hit's white is one unlit material that leaves the voxel colours out", () {
    final flash = VoxelModelMesh.flash();
    expect(VoxelModelMesh.flash(), same(flash));
    expect(flash.vertexColorWeight, 0.0);
    expect(flash.baseColorFactor, Vector4(1, 1, 1, 1));
  });
}
