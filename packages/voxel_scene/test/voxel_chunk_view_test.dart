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
    visibility: ChunkVisibility.open,
  );
}

/// A budget no test's regions reach, so a rebuild builds every one of them
/// whatever the machine's clock says.
const int _everything = 1000000;

void main() {
  test('chunks share one node per region under root, at the region origin', () {
    final view = VoxelChunkView();
    view.apply((x: 2, z: -1), _empty());
    view.apply((x: 3, z: -2), _empty());
    view.apply((x: 0, z: 0), _empty());
    view.rebuild((x: 0, z: 0), budgetUsec: _everything);
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
    view.rebuild((x: 0, z: 0), budgetUsec: _everything);
    final first = view.root.children.single;
    view.apply((x: 0, z: 0), _empty());
    view.rebuild((x: 0, z: 0), budgetUsec: _everything);
    expect(view.root.children.single, isNot(same(first)));
    view.remove((x: 0, z: 0));
    view.rebuild((x: 0, z: 0), budgetUsec: _everything);
    expect(view.regionCount, 1, reason: '(1, 1) still draws in it');
    view.remove((x: 1, z: 1));
    view.remove((x: 1, z: 1));
    view.rebuild((x: 0, z: 0), budgetUsec: _everything);
    expect(view.chunkCount, 0);
    expect(view.root.children, isEmpty);
  });

  test('apply and remove build nothing until rebuild, which builds a region once for all its chunks', () {
    final view = VoxelChunkView();
    for (final pos in [(x: 0, z: 0), (x: 1, z: 0), (x: 0, z: 1), (x: 1, z: 1)]) {
      view.apply(pos, _empty());
    }
    expect(view.root.children, isEmpty);
    expect((view.chunkCount, view.pendingRegions), (4, 1));
    view.rebuild((x: 0, z: 0), budgetUsec: _everything);
    expect(view.root.children.single.name, 'region_0_0');
    expect(view.pendingRegions, 0);
    final built = view.root.children.single;
    view.rebuild((x: 0, z: 0), budgetUsec: _everything);
    expect(view.root.children.single, same(built), reason: 'nothing changed, nothing is rebuilt');
    view.remove((x: 1, z: 1));
    expect(view.root.children.single, same(built));
    expect(view.pendingRegions, 1);
  });

  test('a zero budget builds one region a call, the nearest first', () {
    final view = VoxelChunkView();
    view.apply((x: 8, z: 0), _empty());
    view.apply((x: -4, z: 0), _empty());
    view.apply((x: 0, z: 2), _empty());
    view.rebuild((x: 0, z: 0), budgetUsec: 0);
    expect(view.root.children.map((n) => n.name), ['region_0_1']);
    view.rebuild((x: 0, z: 0), budgetUsec: 0);
    expect(view.root.children.map((n) => n.name), ['region_0_1', 'region_-2_0']);
    expect(view.pendingRegions, 1);
    view.rebuild((x: 0, z: 0), budgetUsec: 0);
    expect(view.pendingRegions, 0);
    expect(view.regionCount, 3);
  });

  test('a region whose chunks all left is dropped in the same call, whatever the budget', () {
    final view = VoxelChunkView();
    view.apply((x: 0, z: 0), _empty());
    view.apply((x: 6, z: 6), _empty());
    view.rebuild((x: 0, z: 0), budgetUsec: _everything);
    view.remove((x: 6, z: 6));
    view.apply((x: 2, z: 0), _empty());
    view.apply((x: 0, z: 2), _empty());
    view.rebuild((x: 0, z: 0), budgetUsec: 0);
    expect(view.root.children.map((n) => n.name), containsAll(['region_0_0']));
    expect(view.root.children.map((n) => n.name), isNot(contains('region_3_3')));
    expect(view.pendingRegions, 1, reason: 'one of the two new regions waits for the next call');
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
