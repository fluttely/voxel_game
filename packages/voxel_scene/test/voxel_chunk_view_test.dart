import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

/// A mesh result with every surface empty: applying it builds nodes but no
/// GPU geometry, so the view's bookkeeping is testable without Flutter GPU.
ChunkMeshResult _empty() {
  MeshSurface surface() => MeshSurface(Float32List(0), Float32List(0), Float32List(0), Float32List(0), Int32List(0));
  return ChunkMeshResult(
    surface(),
    surface(),
    surface(),
    surface(),
    sky: Uint8List(ChunkSize.volume),
    block: Uint8List(ChunkSize.volume),
  );
}

void main() {
  test('apply puts one node per chunk under root at the chunk origin', () {
    final view = VoxelChunkView();
    view.apply((x: 2, z: -1), _empty());
    view.apply((x: 0, z: 0), _empty());
    expect(view.nodeCount, 2);
    expect(view.root.children, hasLength(2));
    final node = view.root.children.firstWhere((n) => n.name == 'chunk_2_-1');
    expect(node.position.x, 32.0);
    expect(node.position.z, -16.0);
    expect(node.children, isEmpty, reason: 'an empty surface gets no child');
  });

  test('a remesh replaces the chunk node; remove drops it; removing twice is harmless', () {
    final view = VoxelChunkView(rootName: 'Vista');
    expect(view.root.name, 'Vista');
    view.apply((x: 0, z: 0), _empty());
    final first = view.root.children.single;
    view.apply((x: 0, z: 0), _empty());
    expect(view.root.children.single, isNot(same(first)));
    view.remove((x: 0, z: 0));
    view.remove((x: 0, z: 0));
    expect(view.nodeCount, 0);
    expect(view.root.children, isEmpty);
  });

  test('sky intensity reaches the three lit materials, not the unlit glow', () {
    final view = VoxelChunkView()..setSkyIntensity(0.35);
    expect([view.matSolid.skyIntensity, view.matCutout.skyIntensity, view.matLiquid.skyIntensity], [0.35, 0.35, 0.35]);
    expect(TerrainMaterial.loaded, isFalse, reason: 'tests never load the shader bundle');
  });
}
