import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/src/merged_surface.dart';
import 'package:voxel_scene/src/view_region.dart';
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

/// A focus far from every chunk a test applies: no clear zone reaches them.
const ChunkPos _far = (x: 1000, z: 1000);

/// A view whose quiet regions settle at once, with no clear zone unless asked.
VoxelChunkView _settling({int settleClear = 0}) => VoxelChunkView(settleAfter: Duration.zero, settleClear: settleClear);

/// Applies a chunk to each of the 16 of the 4 × 4 at [at], but [skip].
void _fill(VoxelChunkView view, ChunkPos at, {ChunkVisibility? visibility, ChunkPos? skip}) {
  for (var dx = 0; dx < 4; dx++) {
    for (var dz = 0; dz < 4; dz++) {
      final pos = (x: at.x * 4 + dx, z: at.z * 4 + dz);
      if (pos != skip) view.apply(pos, _empty(visibility));
    }
  }
}

/// The names of the nodes under the view's root.
Set<String> _drawn(VoxelChunkView view) => {for (final n in view.root.children) n.name};

/// The four 2 × 2s of the 4 × 4 at (0, 0).
const Set<String> _quadrants = {'region_0_0', 'region_0_1', 'region_1_0', 'region_1_1'};

/// Whether the 4 × 4 at (0, 0) draws as itself or as its four quadrants, never
/// both and never neither.
void _expectOneOrTheOther(VoxelChunkView view) {
  final drawn = _drawn(view);
  final whole = drawn.contains('settled_0_0');
  expect(whole ? drawn.intersection(_quadrants) : drawn.containsAll(_quadrants), whole ? isEmpty : isTrue);
}

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

  test('a region carries its size: its key, corner, chunks and bounds', () {
    final settled = ViewRegion((x: -1, z: 1), 4, Node());
    expect(settled.key, (chunks: 4, at: (x: -1, z: 1)));
    expect(settled.key, isNot(ViewRegion((x: -1, z: 1), 2, Node()).key), reason: 'a 2 x 2 at one corner is another');
    expect(settled.origin, (x: -4, z: 4));
    expect(settled.members, hasLength(16));
    expect(settled.members, containsAll([(x: -4, z: 4), (x: -1, z: 7)]));
    expect(settled.members, isNot(contains((x: 0, z: 4))));
    expect((settled.position.x, settled.position.z), (-64.0, 64.0));
    final box = settled.bounds(-3, 70);
    expect((box.min.x, box.min.y, box.min.z), (0.0, -3.0, 0.0));
    expect((box.max.x, box.max.y, box.max.z), (64.0, 70.0, 64.0));
    final small = ViewRegion((x: -1, z: 1), 2, Node()).bounds(-3, 70);
    expect((small.max.x, small.max.z), (32.0, 32.0));
  });

  test('a settled region is whole regions, under 256 m', () {
    expect(VoxelChunkView(regionChunks: 4, settledRegionChunks: 8).settledRegionChunks, 8);
    expect(VoxelChunkView(settledRegionChunks: 2).settledRegionChunks, 2);
    expect(() => VoxelChunkView(settledRegionChunks: 3), throwsA(isA<AssertionError>()));
    expect(() => VoxelChunkView(settledRegionChunks: 16), throwsA(isA<AssertionError>()));
  });

  test('sky intensity reaches the three lit materials, not the unlit glow', () {
    final view = VoxelChunkView()..setSkyIntensity(0.35);
    expect([view.matSolid.skyIntensity, view.matCutout.skyIntensity, view.matLiquid.skyIntensity], [0.35, 0.35, 0.35]);
    expect(TerrainMaterial.loaded, isFalse, reason: 'tests never load the shader bundle');
  });

  group('settle', () {
    test('a whole, quiet 4 x 4 settles: one node at its corner in place of its four 2 x 2s', () {
      final view = _settling();
      _fill(view, (x: -1, z: 1));
      view.rebuild(_far, budgetUsec: _everything);
      expect(_drawn(view), {'settled_-1_1'});
      expect((view.regionCount, view.pendingRegions), (1, 0));
      final node = view.root.children.single;
      expect((node.position.x, node.position.z), (-64.0, 64.0));
    });

    test('these never settle: a 4 x 4 short of a chunk, one not quiet yet, one in the clear zone', () {
      final short = _settling();
      _fill(short, (x: 0, z: 0), skip: (x: 3, z: 3));
      for (var i = 0; i < 3; i++) {
        short.rebuild(_far, budgetUsec: _everything);
      }
      expect(_drawn(short), _quadrants);
      final restless = VoxelChunkView(settleAfter: const Duration(hours: 1), settleClear: 0);
      _fill(restless, (x: 0, z: 0));
      restless.rebuild(_far, budgetUsec: _everything);
      expect(_drawn(restless), _quadrants);
      final near = _settling(settleClear: 2);
      _fill(near, (x: 0, z: 0));
      _fill(near, (x: 2, z: 0));
      near.rebuild((x: 5, z: 1), budgetUsec: _everything);
      expect(_drawn(near), {..._quadrants, 'settled_2_0'}, reason: '(5, 1) is 2 from (3, 1), 3 from (8, 1)');
      expect(VoxelChunkView(settledRegionChunks: 2, settleAfter: Duration.zero).settledRegionChunks, 2);
    });

    test('a settled 4 x 4 the clear zone reaches splits, and settles again once left behind', () {
      final view = _settling(settleClear: 1);
      _fill(view, (x: 0, z: 0));
      view.rebuild(_far, budgetUsec: _everything);
      expect(_drawn(view), {'settled_0_0'});
      view.rebuild((x: 4, z: 2), budgetUsec: 0);
      expect(_drawn(view), {'settled_0_0'}, reason: 'drawn until its quadrants are built');
      expect(view.pendingRegions, 3, reason: 'one built and waiting, three to go, the frame\'s first forced');
      for (var i = 0; i < 3; i++) {
        _expectOneOrTheOther(view);
        view.rebuild((x: 4, z: 2), budgetUsec: 0);
      }
      expect(_drawn(view), _quadrants);
      expect(view.pendingRegions, 0);
      view.rebuild((x: 4, z: 2), budgetUsec: _everything);
      expect(_drawn(view), _quadrants, reason: 'inside the zone it stays split');
      view.rebuild((x: 5, z: 2), budgetUsec: _everything);
      expect(_drawn(view), {'settled_0_0'}, reason: 'two chunks off, it settles again');
    });

    group('a change in a settled 4 x 4', () {
      /// The 4 x 4 at (0, 0) settled, with no settle after: what a split
      /// leaves is then what the tests see.
      VoxelChunkView settled() {
        final view = _settling();
        _fill(view, (x: 0, z: 0));
        view.rebuild(_far, budgetUsec: _everything);
        expect(_drawn(view), {'settled_0_0'});
        return view..settleStepLimit = 0;
      }

      test('an apply: it stays drawn until its four quadrants are built, then they swap in one rebuild', () {
        final view = settled();
        view.apply((x: 1, z: 2), _empty());
        expect(view.pendingRegions, 4, reason: 'a split waits for its four quadrants');
        for (var i = 0; i < 3; i++) {
          view.rebuild(_far, budgetUsec: 0);
          _expectOneOrTheOther(view);
          expect(_drawn(view), {'settled_0_0'});
        }
        view.rebuild(_far, budgetUsec: 0);
        expect(_drawn(view), _quadrants);
        expect((view.regionCount, view.pendingRegions), (4, 0));
      });

      test('a quadrant changed again after its build does not hold the swap back', () {
        final view = settled();
        const away = (x: -1000, z: -1000);
        view.apply((x: 0, z: 0), _empty());
        for (var i = 0; i < 3; i++) {
          view.rebuild(away, budgetUsec: 0);
        }
        expect(_drawn(view), {'settled_0_0'}, reason: '(1, 1), the farthest, is not built yet');
        view.apply((x: 0, z: 0), _empty());
        view.rebuild(_far, budgetUsec: 0);
        expect(_drawn(view), _quadrants, reason: 'the last built, the swap waits for no rebuild of (0, 0)');
        expect(view.pendingRegions, 1, reason: '(0, 0) rebuilds as any 2 x 2 does');
        final swapped = view.root.children.singleWhere((n) => n.name == 'region_0_0');
        view.rebuild(_far, budgetUsec: 0);
        expect(view.root.children.singleWhere((n) => n.name == 'region_0_0'), isNot(same(swapped)));
        expect(view.pendingRegions, 0);
      });

      test('a remove: the same, and a quadrant left with no chunk is ready with no build', () {
        final view = settled();
        for (final pos in [(x: 2, z: 2), (x: 2, z: 3), (x: 3, z: 2), (x: 3, z: 3)]) {
          view.remove(pos);
        }
        view.rebuild(_far, budgetUsec: 0);
        expect(_drawn(view), {'settled_0_0'});
        expect(view.pendingRegions, 2, reason: '(1, 1) was ready at once, one more was built');
        view.rebuild(_far, budgetUsec: 0);
        expect(_drawn(view), {'settled_0_0'});
        view.rebuild(_far, budgetUsec: 0);
        expect(_drawn(view), {'region_0_0', 'region_0_1', 'region_1_0'});
        expect((view.chunkCount, view.pendingRegions), (12, 0));
      });

      test('removing every chunk drops every 4 x 4 in one rebuild', () {
        final view = _settling();
        _fill(view, (x: 0, z: 0));
        _fill(view, (x: -1, z: 0));
        _fill(view, (x: 5, z: 5), skip: (x: 20, z: 20));
        view.rebuild(_far, budgetUsec: _everything);
        expect(view.regionCount, 2 + 4);
        for (final pos in [
          for (var x = -4; x < 24; x++)
            for (var z = 0; z < 24; z++) (x: x, z: z),
        ]) {
          view.remove(pos);
        }
        view.rebuild(_far, budgetUsec: 0);
        expect(view.root.children, isEmpty);
        expect((view.chunkCount, view.regionCount, view.pendingRegions), (0, 0, 0));
      });
    });

    test('a settle is never forced: never a frame\'s first build, never past what the builds left', () {
      final view = _settling();
      _fill(view, (x: 0, z: 0));
      for (var i = 0; i < 4; i++) {
        view.rebuild(_far, budgetUsec: 0);
      }
      expect(_drawn(view), _quadrants, reason: 'one quadrant forced a call, the settle never');
      view.apply((x: 40, z: 40), _empty());
      view.rebuild(_far, budgetUsec: 0);
      expect(_drawn(view), {..._quadrants, 'region_20_20'}, reason: 'the forced build left nothing of a zero budget');
      for (var i = 0; i < 3; i++) {
        view.rebuild(_far, budgetUsec: 0);
      }
      expect(_drawn(view), contains('region_0_0'), reason: 'a step predicted at or over the whole budget never runs');
      expect(view.pendingRegions, 0, reason: 'a settle waiting is not a region waiting');
      view.rebuild(_far, budgetUsec: _everything);
      expect(_drawn(view), {'settled_0_0', 'region_20_20'});
    });

    test('a settle runs a step at a time, and a change in its 4 x 4 or the clear zone starts it over', () {
      // An empty 4 x 4 settles in 17 steps: 16 copies and the swap.
      int stepsToSettle(VoxelChunkView view, {ChunkPos near = _far}) {
        for (var calls = 1; calls <= 40; calls++) {
          view.rebuild(near, budgetUsec: _everything);
          if (_drawn(view).contains('settled_0_0')) return calls;
          _expectOneOrTheOther(view);
        }
        fail('it never settled');
      }

      final view = _settling(settleClear: 1)..settleStepLimit = 1;
      _fill(view, (x: 0, z: 0));
      expect(stepsToSettle(view), 17);
      view.settleStepLimit = 0;
      view.apply((x: 0, z: 0), _empty());
      view.rebuild(_far, budgetUsec: _everything);
      view.settleStepLimit = 1;
      for (var i = 0; i < 6; i++) {
        view.rebuild(_far, budgetUsec: _everything);
      }
      view.apply((x: 9, z: 9), _empty());
      expect(stepsToSettle(view), 17 - 6, reason: 'a change outside its 4 x 4 leaves it alone');
      view.settleStepLimit = 0;
      view.apply((x: 0, z: 0), _empty());
      view.rebuild(_far, budgetUsec: _everything);
      view.settleStepLimit = 1;
      for (var i = 0; i < 6; i++) {
        view.rebuild(_far, budgetUsec: _everything);
      }
      view.apply((x: 2, z: 1), _empty());
      expect(stepsToSettle(view), 17, reason: 'a chunk of it changed: its copies start over');
      view.settleStepLimit = 0;
      view.apply((x: 0, z: 0), _empty());
      view.rebuild(_far, budgetUsec: _everything);
      view.settleStepLimit = 1;
      for (var i = 0; i < 6; i++) {
        view.rebuild(_far, budgetUsec: _everything);
      }
      view.rebuild((x: 4, z: 4), budgetUsec: _everything);
      expect(stepsToSettle(view), 17, reason: 'the clear zone reached it: it starts over once left');
    });
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

    // Chunks from (-4, -4) to (7, 7), all stone: the nine 4 x 4s (-1, -1) to
    // (1, 1), whole, settled before the first cull.
    VoxelChunkView settledWorld() {
      final view = _settling();
      for (var x = -1; x <= 1; x++) {
        for (var z = -1; z <= 1; z++) {
          _fill(view, (x: x, z: z), visibility: _sealed);
        }
      }
      view.rebuild(_far, budgetUsec: _everything);
      expect(view.regionCount, 9, reason: 'every 4 x 4 settled');
      return view;
    }

    test('a settled region shows when any of its 16 chunks is reached', () {
      final view = settledWorld();
      final surface = _surface(region(view, 'settled_0_-1'));
      expect(view.root.children.map((n) => n.layers), everyElement(kRenderLayerDefault), reason: 'no cull yet');
      view.cull(eye);
      expect(
        {
          for (final n in view.root.children)
            if (n.layers == kRenderLayerDefault) n.name,
        },
        {'settled_0_0', 'settled_-1_0', 'settled_0_-1'},
        reason: 'the 4 x 4s of (0, 0), (-1, 0) and (0, -1); (0, -1) alone of its 16 is reached',
      );
      expect(surface.layers, kRenderLayerDefault);
    });

    test('a settled region and a quadrant swapped in take the last cull\'s state', () {
      final view = _settling()..settleStepLimit = 0;
      for (var x = -1; x <= 1; x++) {
        for (var z = -1; z <= 1; z++) {
          _fill(view, (x: x, z: z), visibility: _sealed);
        }
      }
      view.rebuild(_far, budgetUsec: _everything);
      expect(view.regionCount, 36, reason: 'no settle step allowed yet');
      view.cull(eye);
      view.settleStepLimit = null;
      view.rebuild(_far, budgetUsec: _everything);
      expect(view.regionCount, 9);
      expect(region(view, 'settled_0_0').layers, kRenderLayerDefault);
      expect(region(view, 'settled_1_1').layers, 0, reason: 'settled after the cull, it takes its state');
      view.settleStepLimit = 0; // or the split would settle again in its own rebuild
      view.apply((x: 6, z: 6), _empty(_sealed));
      view.rebuild(_far, budgetUsec: _everything);
      expect(_drawn(view), containsAll(['region_2_2', 'region_3_3']), reason: 'the split swapped its quadrants in');
      expect(region(view, 'region_3_3').layers, 0, reason: 'swapped in before the next cull, it takes the last');
      expect(region(view, 'settled_0_0').layers, kRenderLayerDefault);
    });

    test('the cull touches layers only: never visible, the shadow casting mode or shadowStatic', () {
      final view = settledWorld()..settleStepLimit = 0;
      view.apply((x: 0, z: 0), _empty(_sealed));
      view.rebuild(_far, budgetUsec: _everything);
      expect(view.root.children.map((n) => n.name), containsAll(['region_0_0', 'settled_1_1']), reason: 'both sizes');
      final surfaces = [for (final n in view.root.children) _surface(n)..shadowStatic = true];
      List<Object> state() => [
        for (final n in [view.root, ...view.root.children, ...surfaces])
          (n.visible, n.shadowCastingMode, n.shadowStatic),
      ];
      final before = state();
      view.cull(eye);
      expect(surfaces.map((s) => s.layers), containsAll([0, kRenderLayerDefault]), reason: 'the cull hid something');
      expect([region(view, 'settled_1_1').layers, region(view, 'settled_-1_0').layers], [0, kRenderLayerDefault]);
      expect(state(), before);
    });
  });
}
