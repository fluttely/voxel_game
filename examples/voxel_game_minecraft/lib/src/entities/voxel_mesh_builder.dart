import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../core/blocks.dart';
import '../core/items.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_scene/voxel_scene.dart';

/// VK1.4: this game's voxel models — block and item colours and the item
/// shape catalogue. Painting a model is voxel_core's [VoxelModel]; meshing it,
/// voxel_scene's [VoxelModelMesh].
class VoxelMeshBuilder {
  VoxelMeshBuilder._();

  static Vector3 blockColor(int id) {
    final d = Blocks.def(id);
    return Vector3(d.r, d.g, d.b);
  }

  static Vector3 itemColor(String id) {
    final d = Items.def(id);
    return Vector3(d.r, d.g, d.b);
  }

  static final Map<String, ItemShape> _shapes = {};

  /// A quarter turn about a held model's shaft: a flat tool is built with its
  /// head across X, and both hands turn it so the head runs along the swing.
  static final Quaternion headInSwingPlane = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2);

  /// What [itemId] looks like — one voxel model, built once, that the hand
  /// (both views), the drop on the ground and the inventory icon all draw.
  static ItemShape itemShape(String itemId) => _shapes[itemId] ??= _buildShape(itemId);

  /// [itemId]'s model as a scene node, standing up its own +Y from its grip.
  static Node heldItem(String itemId) {
    final shape = itemShape(itemId);
    final root = Node();
    root.add(VoxelModelMesh.node(shape.voxels, shape.scale, shape.origin));
    return root;
  }

  static ItemShape _buildShape(String itemId) {
    final v = <IVec3, Vector3>{};
    final color = itemColor(itemId);
    if (Items.isBlock(itemId)) {
      final block = Items.blockOf(itemId);
      final c = blockColor(block);
      final shape = Blocks.shapeOf(block);
      // The blocks that are not a box in the world are not one in the hand
      // either: the same post, sprout and flower the chunk mesher draws.
      if (shape == BlockShape.torch) {
        VoxelModel.box(v, const IVec3(3, 0, 3), const IVec3(4, 3, 4), Vector3(0.45, 0.32, 0.18), 0.03);
        VoxelModel.box(v, const IVec3(3, 4, 3), const IVec3(4, 4, 4), c, 0.0);
        return ItemShape(v, 0.045, Vector3(4, 0, 4), flat: false, block: false);
      }
      if (shape == BlockShape.cross) {
        for (var i = 0; i < 8; i++) {
          final top = 2 + (i * 5 + 3) % 3 + (i > 1 && i < 6 ? 1 : 0);
          VoxelModel.box(v, IVec3(i, 0, i), IVec3(i, 1, i), c * 0.7, 0.04);
          VoxelModel.box(v, IVec3(i, 2, i), IVec3(i, top, i), c, 0.04);
          VoxelModel.box(v, IVec3(i, 0, 7 - i), IVec3(i, 1, 7 - i), c * 0.7, 0.04);
          VoxelModel.box(v, IVec3(i, 2, 7 - i), IVec3(i, top - 1, 7 - i), c, 0.04);
        }
        return ItemShape(v, 0.045, Vector3(4, 0, 4), flat: false, block: false);
      }
      if (shape == BlockShape.flower) {
        VoxelModel.box(v, const IVec3(3, 0, 3), const IVec3(3, 3, 3), Vector3(0.30, 0.55, 0.22), 0.03);
        VoxelModel.box(v, const IVec3(2, 4, 2), const IVec3(4, 4, 4), c, 0.04);
        return ItemShape(v, 0.045, Vector3(3.5, 0, 3.5), flat: false, block: false);
      }
      final height = shape == BlockShape.slab ? 1 : 3;
      VoxelModel.box(v, IVec3.zero, IVec3(3, height, 3), c, 0.06);
      return ItemShape(v, 0.09, Vector3(2, 0, 2), flat: false, block: true);
    }
    final kind = Items.kind(itemId);
    final handle = Vector3(0.45, 0.32, 0.18);
    // Tools and weapons are drawn flat in XY, a shaft up +Y from the grip and
    // a head across X.
    if (kind == ItemKind.tool) {
      VoxelModel.box(v, const IVec3(0, 0, 0), const IVec3(0, 9, 0), handle);
      final tool = Items.toolOf(itemId);
      if (tool == ToolType.pickaxe) {
        VoxelModel.box(v, const IVec3(-3, 9, 0), const IVec3(3, 9, 0), color);
        VoxelModel.box(v, const IVec3(-4, 8, 0), const IVec3(-4, 8, 0), color);
        VoxelModel.box(v, const IVec3(4, 8, 0), const IVec3(4, 8, 0), color);
      } else if (tool == ToolType.axe) {
        VoxelModel.box(v, const IVec3(0, 8, 0), const IVec3(2, 10, 0), color);
        VoxelModel.box(v, const IVec3(3, 9, 0), const IVec3(3, 9, 0), color);
      } else {
        VoxelModel.box(v, const IVec3(-1, 9, 0), const IVec3(1, 11, 0), color);
      }
      return ItemShape(v, 0.045, Vector3(0.5, 0, 0.5), flat: true, block: false);
    }
    if (kind == ItemKind.weapon) {
      final style = Items.styleOf(itemId);
      if (style == 'bow') {
        VoxelModel.box(v, const IVec3(0, -4, 0), const IVec3(0, 4, 0), color);
        VoxelModel.box(v, const IVec3(1, -5, 0), const IVec3(1, -3, 0), color);
        VoxelModel.box(v, const IVec3(1, 3, 0), const IVec3(1, 5, 0), color);
        VoxelModel.box(v, const IVec3(-1, -5, 0), const IVec3(-1, 5, 0), Vector3(0.9, 0.9, 0.85), 0.0);
      } else if (style == 'staff') {
        VoxelModel.box(v, const IVec3(0, 0, 0), const IVec3(0, 12, 0), handle);
        VoxelModel.box(v, const IVec3(-1, 12, -1), const IVec3(1, 14, 1), color);
      } else {
        final length = style == 'melee_fast' ? 6 : 10;
        VoxelModel.box(v, const IVec3(0, 0, 0), const IVec3(0, 2, 0), handle);
        VoxelModel.box(v, const IVec3(-1, 3, 0), const IVec3(1, 3, 0), Vector3(0.5, 0.5, 0.5));
        VoxelModel.box(v, const IVec3(0, 4, 0), IVec3(0, 3 + length, 0), color, 0.02);
      }
      return ItemShape(v, 0.045, Vector3(0.5, 0, 0.5), flat: true, block: false);
    }
    if (kind == ItemKind.food) {
      // A round lump: a 5-wide cube with its edges filed off.
      VoxelModel.box(v, const IVec3(-2, 1, -1), const IVec3(2, 3, 1), color);
      VoxelModel.box(v, const IVec3(-1, 0, -1), const IVec3(1, 4, 1), color);
      VoxelModel.box(v, const IVec3(-1, 1, -2), const IVec3(1, 3, 2), color);
      return ItemShape(v, 0.045, Vector3(0.5, 0, 0.5), flat: false, block: false);
    }
    if (kind == ItemKind.equipment) {
      // A chest piece seen from the front: shoulders, a body and a neck gap.
      VoxelModel.box(v, const IVec3(-3, 4, 0), const IVec3(-1, 6, 0), color);
      VoxelModel.box(v, const IVec3(1, 4, 0), const IVec3(3, 6, 0), color);
      VoxelModel.box(v, const IVec3(-2, 0, 0), const IVec3(2, 5, 0), color);
      VoxelModel.box(v, const IVec3(-2, 0, 0), const IVec3(2, 0, 0), color * 0.75, 0.02);
      return ItemShape(v, 0.045, Vector3(0.5, 0, 0.5), flat: true, block: false);
    }
    // A material: a small cut gem, wider at its girdle.
    VoxelModel.box(v, const IVec3(-1, 0, 0), const IVec3(1, 0, 0), color * 0.8);
    VoxelModel.box(v, const IVec3(-2, 1, 0), const IVec3(2, 2, 0), color);
    VoxelModel.box(v, const IVec3(-1, 3, 0), const IVec3(1, 3, 0), color * 1.15);
    VoxelModel.box(v, const IVec3(0, 4, 0), const IVec3(0, 4, 0), color * 1.15);
    return ItemShape(v, 0.045, Vector3(0.5, 0, 0.5), flat: true, block: false);
  }
}

/// One item's voxel model. Every place an item is drawn reads this, so a
/// pickaxe is the same pickaxe in the hand, on the ground and in the bag.
class ItemShape {
  ItemShape(this.voxels, this.scale, this.origin, {required this.flat, required this.block});

  /// {voxel: colour}.
  final Map<IVec3, Vector3> voxels;

  /// Metres per voxel.
  final double scale;

  /// The voxel-space point the model's node sits on: its grip, on the floor
  /// of the model.
  final Vector3 origin;

  /// Drawn in the XY plane, one voxel deep: a tool, a weapon, a flat piece.
  /// An icon looks at its face; a block is looked at from a corner.
  final bool flat;

  /// Carried the way a block is (a box against the palm) rather than
  /// standing up out of the fist.
  final bool block;

  /// The model's bounds in metres, in its node's space.
  Aabb3 bounds() {
    final lo = Vector3.all(double.infinity), hi = Vector3.all(double.negativeInfinity);
    for (final p in voxels.keys) {
      final a = Vector3((p.x - origin.x) * scale, (p.y - origin.y) * scale, (p.z - origin.z) * scale);
      final b = a + Vector3.all(scale);
      Vector3.min(lo, a, lo);
      Vector3.max(hi, b, hi);
    }
    return Aabb3.minMax(lo, hi);
  }
}
