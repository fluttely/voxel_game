import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../math/ivec3.dart';

/// A small voxel model: a map from voxel to linear rgb colour, the way
/// creatures, held items and drops are drawn (coloured cubes, no textures). These are
/// the tools that paint one; a renderer turns it into a mesh through
/// [VoxelModel.arrays].
abstract final class VoxelModel {
  static const List<int> _faceVerts = [
    0, 1, 0, 1, 1, 0, 1, 1, 1, 0, 1, 1, //
    0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 0, 0,
    1, 0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 0,
    0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1,
    0, 0, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1,
    0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0,
  ];
  static const List<IVec3> _faceNormals = [
    IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), //
  ];

  /// The shade baked into each face of a model, in face order +y, -y, +x, -x,
  /// +z, -z: a top lit fully, a bottom at 0.6, the sides between.
  static const List<double> faceTint = [1.0, 0.6, 0.84, 0.84, 0.74, 0.74];

  /// Fills the box [from]..[to] (inclusive) of [voxels] with [color], each
  /// voxel's brightness varied by up to ±[jitter] from a hash of its position.
  static void box(Map<IVec3, Vector3> voxels, IVec3 from, IVec3 to, Vector3 color, [double jitter = 0.05]) {
    for (var x = from.x; x <= to.x; x++) {
      for (var y = from.y; y <= to.y; y++) {
        for (var z = from.z; z <= to.z; z++) {
          final h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791);
          final n = 1.0 + ((h.abs() % 1000) / 1000.0 - 0.5) * 2.0 * jitter;
          voxels[IVec3(x, y, z)] = Vector3(color.x * n, color.y * n, color.z * n);
        }
      }
    }
  }

  /// The same voxels mirrored across the x = 0 plane. A voxel at x covers
  /// [x, x+1], so its mirror covers [-x-1, -x]. Rebuilding the map is how a
  /// left wing is made from a right one: scaling a node by -1 would mirror it
  /// too, but it also reverses the winding the renderer relies on.
  static Map<IVec3, Vector3> mirrorX(Map<IVec3, Vector3> voxels) => {
    for (final e in voxels.entries) IVec3(-e.key.x - 1, e.key.y, e.key.z): e.value,
  };

  /// The visible faces of [voxels] as mesh arrays, or null for a model with
  /// none. [scale] is metres per voxel; [origin] is the voxel-space point that
  /// maps to the mesh origin (a leg pivots at its hip). Faces between two
  /// voxels are culled; each face carries its [faceTint]. The winding is the
  /// chunk mesher's: clockwise seen from the normal side.
  static VoxelModelArrays? arrays(Map<IVec3, Vector3> voxels, double scale, [Vector3? origin]) {
    final o = origin ?? Vector3.zero();
    var faces = 0;
    for (final p in voxels.keys) {
      for (var f = 0; f < 6; f++) {
        if (!voxels.containsKey(p + _faceNormals[f])) faces++;
      }
    }
    if (faces == 0) return null;
    final positions = Float32List(faces * 12);
    final normals = Float32List(faces * 12);
    final colors = Float32List(faces * 16);
    final indices = Int32List(faces * 6);
    var v = 0, ii = 0;
    for (final e in voxels.entries) {
      final p = e.key;
      final color = e.value;
      for (var f = 0; f < 6; f++) {
        if (voxels.containsKey(p + _faceNormals[f])) continue;
        final tint = faceTint[f];
        final n = _faceNormals[f];
        final first = v;
        for (var i = 0; i < 4; i++) {
          final k = f * 12 + i * 3;
          positions[v * 3] = (p.x + _faceVerts[k] - o.x) * scale;
          positions[v * 3 + 1] = (p.y + _faceVerts[k + 1] - o.y) * scale;
          positions[v * 3 + 2] = (p.z + _faceVerts[k + 2] - o.z) * scale;
          normals[v * 3] = n.x.toDouble();
          normals[v * 3 + 1] = n.y.toDouble();
          normals[v * 3 + 2] = n.z.toDouble();
          colors[v * 4] = color.x * tint;
          colors[v * 4 + 1] = color.y * tint;
          colors[v * 4 + 2] = color.z * tint;
          colors[v * 4 + 3] = 1.0;
          v++;
        }
        indices[ii++] = first;
        indices[ii++] = first + 1;
        indices[ii++] = first + 2;
        indices[ii++] = first;
        indices[ii++] = first + 2;
        indices[ii++] = first + 3;
      }
    }
    return VoxelModelArrays(faces, positions, normals, colors, indices);
  }
}

/// A voxel model's faces as flat arrays, four vertices and six indices a face.
class VoxelModelArrays {
  /// The arrays of [faces] quads.
  const VoxelModelArrays(this.faces, this.positions, this.normals, this.colors, this.indices);

  /// How many quads.
  final int faces;

  /// xyz per vertex, in metres.
  final Float32List positions;

  /// xyz per vertex, one axis at ±1.
  final Float32List normals;

  /// rgba per vertex: the voxel colour times its face tint, alpha 1.
  final Float32List colors;

  /// Two triangles per quad.
  final Int32List indices;
}
