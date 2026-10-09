import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/src/merged_surface.dart';
import 'package:voxel_scene/voxel_scene.dart';

/// A mesh result with every surface empty: applying it builds nodes but no
/// GPU geometry, so the view's bookkeeping is testable without Flutter GPU.
/// Open to sight unless [visibility] says otherwise.
ChunkMeshResult _empty([ChunkVisibility? visibility]) {
  MeshSurface surface() => MeshSurface(Float32List(0), Float32List(0), Float32List(0), Float32List(0), Int32List(0));
  return ChunkMeshResult(
    surface(),
    surface(),
    surface(),
    surface(),
    sky: Uint8List(ChunkSize.volume),
    block: Uint8List(ChunkSize.volume),
    visibility: visibility ?? ChunkVisibility.open,
  );
}

/// A chunk of solid stone: no section joins any two faces.
final ChunkVisibility _sealed = ChunkVisibility(Uint16List(ChunkVisibility.sections));

/// A region's surface as a test can make one: a node with no mesh, since an
/// empty surface gets none and a real one needs Flutter GPU. [VoxelChunkView.cull]
/// sets the layers of every child of a region node.
Node _surface(Node region) {
  final surface = Node(name: 'surface');
  region.add(surface);
  return surface;
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

  group('cull', () {
    // Camera in chunk (0, 0), section 2: through a sealed world the search
    // reaches its own chunk and its four side neighbours, nothing further.
    final eye = Vector3(8, 40, 8);

    Node region(VoxelChunkView view, String name) => view.root.children.singleWhere((n) => n.name == name);

    // Chunks from (-2, -2) to (5, 5), all stone: regions (-1, -1) to (2, 2). A
    // chunk with no mesh would be crossed as open, so the window has no gaps.
    VoxelChunkView sealedWorld() {
      final view = VoxelChunkView();
      for (var x = -2; x <= 5; x++) {
        for (var z = -2; z <= 5; z++) {
          view.apply((x: x, z: z), _empty(_sealed));
        }
      }
      view.rebuild((x: 0, z: 0), budgetUsec: _everything);
      return view;
    }

    test('a sealed camera hides the regions it reaches no chunk of, and shows the rest', () {
      final view = sealedWorld();
      final surfaces = {for (final n in view.root.children) n.name: _surface(n)};
      expect(view.cull(eye), isTrue);
      final shown = {for (final n in view.root.children) n.name: n.layers == kRenderLayerDefault};
      expect(
        {
          for (final MapEntry(:key, :value) in shown.entries)
            if (value) key,
        },
        {'region_0_0', 'region_-1_0', 'region_0_-1'},
        reason: 'the regions of (0, 0), (-1, 0) and (0, -1); (1, 0) and (0, 1) are in region (0, 0)',
      );
      expect(shown.values.where((s) => !s), hasLength(16 - 3));
      expect({for (final MapEntry(:key, :value) in surfaces.entries) key: value.layers == kRenderLayerDefault}, shown);
      expect(view.cull(eye), isFalse, reason: 'nothing changed, the search does not rerun');
    });

    test('an open world shows every region', () {
      final view = VoxelChunkView();
      for (var x = -4; x <= 4; x++) {
        for (var z = -4; z <= 4; z++) {
          view.apply((x: x, z: z), _empty());
        }
      }
      view.rebuild((x: 0, z: 0), budgetUsec: _everything);
      view.cull(eye);
      expect(view.root.children.map((n) => n.layers), everyElement(kRenderLayerDefault));
    });

    test('a region built before any cull draws; one rebuilt after takes the last cull', () {
      final view = sealedWorld();
      expect(view.root.children.map((n) => n.layers), everyElement(kRenderLayerDefault));
      view.cull(eye);
      expect(region(view, 'region_2_2').layers, 0);
      view.apply((x: 4, z: 4), _empty(_sealed));
      view.rebuild((x: 0, z: 0), budgetUsec: _everything);
      final rebuilt = region(view, 'region_2_2');
      expect(rebuilt.layers, 0, reason: 'a rebuilt region keeps its state before the next cull');
      expect(view.cull(eye), isTrue, reason: 'a remeshed chunk reruns the search');
      expect(rebuilt.layers, 0);
    });

    test('a chunk opened or removed reruns the search and lets sight through', () {
      final view = sealedWorld();
      view.cull(eye);
      expect(region(view, 'region_1_0').layers, 0, reason: '(2, 0) lies past the sealed (1, 0)');
      view.apply((x: 1, z: 0), _empty());
      view.rebuild((x: 0, z: 0), budgetUsec: _everything);
      expect(view.cull(eye), isTrue);
      expect(region(view, 'region_1_0').layers, kRenderLayerDefault, reason: 'an open (1, 0) lets sight into (2, 0)');
      view.apply((x: 1, z: 0), _empty(_sealed));
      view.rebuild((x: 0, z: 0), budgetUsec: _everything);
      view.cull(eye);
      expect(region(view, 'region_1_0').layers, 0);
      view.remove((x: 0, z: 1));
      view.rebuild((x: 0, z: 0), budgetUsec: _everything);
      expect(view.cull(eye), isTrue);
      expect(region(view, 'region_0_1').layers, kRenderLayerDefault, reason: 'a chunk with no mesh is crossed as open');
      expect(view.cull(Vector3(8, 40 + 16, 8)), isTrue, reason: 'another section reruns it');
      expect(view.cull(Vector3(15, 40 + 16, 15)), isFalse, reason: 'the same section, elsewhere in it, does not');
    });

    test('the cull touches layers only: never visible, the shadow casting mode or shadowStatic', () {
      final view = sealedWorld();
      final surfaces = [for (final n in view.root.children) _surface(n)..shadowStatic = true];
      List<Object> state() => [
        for (final n in [view.root, ...view.root.children, ...surfaces])
          (n.visible, n.shadowCastingMode, n.shadowStatic),
      ];
      final before = state();
      view.cull(eye);
      expect(surfaces.map((s) => s.layers), containsAll([0, kRenderLayerDefault]), reason: 'the cull hid something');
      expect(state(), before);
    });
  });
}
