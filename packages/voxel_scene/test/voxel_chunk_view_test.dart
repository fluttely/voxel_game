import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/src/merged_surface.dart';
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
  test('chunks share one node per region under root, at the region origin', () {
    final view = VoxelChunkView();
    view.apply((x: 2, z: -1), _empty());
    view.apply((x: 3, z: -2), _empty());
    view.apply((x: 0, z: 0), _empty());
    expect(view.chunkCount, 3);
    expect(view.regionCount, 2);
    expect(view.root.children, hasLength(2));
    final node = view.root.children.firstWhere((n) => n.name == 'region_1_-1');
    expect(node.position.x, 32.0);
    expect(node.position.z, -32.0);
    expect(node.children, isEmpty, reason: 'an empty surface gets no child');
  });

  test('regionOf floors toward negative infinity', () {
    final view = VoxelChunkView(regionChunks: 4);
    expect(view.regionOf((x: 0, z: 3)), (x: 0, z: 0));
    expect(view.regionOf((x: -1, z: -4)), (x: -1, z: -1));
    expect(view.regionOf((x: -5, z: 4)), (x: -2, z: 1));
  });

  test('a remesh rebuilds the region; its last chunk removed drops it; removing twice is harmless', () {
    final view = VoxelChunkView(rootName: 'Vista');
    expect(view.root.name, 'Vista');
    view.apply((x: 0, z: 0), _empty());
    view.apply((x: 1, z: 1), _empty());
    final first = view.root.children.single;
    view.apply((x: 0, z: 0), _empty());
    expect(view.root.children.single, isNot(same(first)));
    view.remove((x: 0, z: 0));
    expect(view.regionCount, 1, reason: '(1, 1) still draws in it');
    view.remove((x: 1, z: 1));
    view.remove((x: 1, z: 1));
    expect(view.chunkCount, 0);
    expect(view.root.children, isEmpty);
  });

  test('a merged surface moves each chunk by its offset and its indices by the vertices before it', () {
    MeshSurface quad(double y) => MeshSurface(
      Float32List.fromList([0, y, 0, 1, y, 0, 1, y, 1, 0, y, 1]),
      Float32List.fromList(List.filled(12, 0.5)),
      Float32List.fromList(List.filled(16, 0.25)),
      Float32List.fromList(List.filled(8, 1.0)),
      Int32List.fromList([0, 1, 2, 0, 2, 3]),
    );
    final empty = MeshSurface(Float32List(0), Float32List(0), Float32List(0), Float32List(0), Int32List(0));
    final m = MergedSurface.of([((x: 0, z: 0), quad(3)), ((x: 0, z: 1), empty), ((x: 1, z: 1), quad(7))])!;
    expect(m.positions.sublist(12, 15), [16.0, 7.0, 16.0], reason: 'the second quad sits one chunk over on x and z');
    expect(m.indices, [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7]);
    expect(m.indices, isA<Uint16List>());
    expect((m.minY, m.maxY), (3.0, 7.0));
    expect(m.normals, hasLength(24));
    expect(m.colors, hasLength(32));
    expect(m.light, hasLength(16));
    expect(MergedSurface.of([((x: 0, z: 0), empty)]), isNull);
  });

  test('sky intensity reaches the three lit materials, not the unlit glow', () {
    final view = VoxelChunkView()..setSkyIntensity(0.35);
    expect([view.matSolid.skyIntensity, view.matCutout.skyIntensity, view.matLiquid.skyIntensity], [0.35, 0.35, 0.35]);
    expect(TerrainMaterial.loaded, isFalse, reason: 'tests never load the shader bundle');
  });
}
