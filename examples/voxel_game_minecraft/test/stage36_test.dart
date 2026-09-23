import 'dart:math' as math;

import 'package:voxel_game_minecraft/src/core/items.dart';
import 'package:voxel_game_minecraft/src/entities/hand_view.dart';
import 'package:voxel_game_minecraft/src/entities/item_drop.dart';
import 'package:voxel_game_minecraft/src/entities/voxel_mesh_builder.dart';
import 'package:voxel_game_minecraft/src/ui/item_icon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 36's pure pieces (`--item-probe` draws the hotbar, the drops and the
/// first-person pickaxe on screen): one voxel model per item, the fist's
/// tool pose, the drop's size and the icon projected from the model.
void main() {
  test('every item has a model', () {
    for (final id in Items.defs.keys) {
      final shape = VoxelMeshBuilder.itemShape(id);
      expect(shape.voxels, isNotEmpty, reason: id);
      final b = shape.bounds();
      expect(b.max.x > b.min.x && b.max.y > b.min.y && b.max.z > b.min.z, isTrue, reason: id);
      expect(identical(VoxelMeshBuilder.itemShape(id), shape), isTrue, reason: '$id is built once');
    }
  });

  test('a first-person tool never points its head across the screen', () {
    // The head is built across the model's X; the camera's right is +X.
    final head = HandView.toolPose.rotated(Vector3(1, 0, 0));
    expect(head.x.abs(), lessThan(1e-6)); // float32 storage
    expect(head.z.abs(), greaterThan(0.7), reason: 'it runs into the screen');
  });

  test('a drop lies small if it is a lump and long if it is long', () {
    double longest(String id) {
      final b = VoxelMeshBuilder.itemShape(id).bounds();
      final e = b.max - b.min;
      return math.max(e.x, math.max(e.y, e.z)) * ItemDrop.dropScale(VoxelMeshBuilder.itemShape(id));
    }

    for (final id in ['stone', 'stone_slab', 'apple']) {
      expect(longest(id), closeTo(ItemDrop.blockSize, 1e-9), reason: id);
    }
    for (final id in ['iron_pickaxe', 'iron_sword', 'torch', 'flower_red', 'iron_armor']) {
      expect(longest(id), closeTo(ItemDrop.itemSize, 1e-9), reason: id);
    }
  });

  group('the icon is the model, projected', () {
    test('every face fits the square, painted back to front', () {
      for (final id in Items.defs.keys) {
        final faces = ItemIcon.faces(VoxelMeshBuilder.itemShape(id));
        expect(faces, isNotEmpty, reason: id);
        for (var i = 0; i < faces.length; i++) {
          for (final c in faces[i].corners) {
            expect(c.dx >= -1e-9 && c.dx <= 1 + 1e-9 && c.dy >= -1e-9 && c.dy <= 1 + 1e-9, isTrue, reason: '$id: $c');
          }
          if (i > 0) expect(faces[i].depth, greaterThanOrEqualTo(faces[i - 1].depth), reason: id);
        }
      }
    });

    test('a block shows its top and two sides, whole', () {
      // A 4-voxel cube: three 4x4 faces, nothing else.
      expect(ItemIcon.faces(VoxelMeshBuilder.itemShape('stone')).length, 48);
    });

    test('the model fills the square along its longer side', () {
      for (final id in ['iron_pickaxe', 'stone', 'torch']) {
        final faces = ItemIcon.faces(VoxelMeshBuilder.itemShape(id));
        var lo = const Offset(1, 1), hi = Offset.zero;
        for (final f in faces) {
          for (final c in f.corners) {
            lo = Offset(math.min(lo.dx, c.dx), math.min(lo.dy, c.dy));
            hi = Offset(math.max(hi.dx, c.dx), math.max(hi.dy, c.dy));
          }
        }
        expect(math.max(hi.dx - lo.dx, hi.dy - lo.dy), closeTo(ItemIcon.fill, 1e-6), reason: id);
      }
    });
  });
}
