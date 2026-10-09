import 'dart:typed_data';

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'packed_surface.dart';
import 'terrain_material.dart';

/// A region's terrain surface in [PackedSurface]'s 16-byte vertex, drawn by the
/// terrain bundle's `TerrainVertex` (`shaders/terrain.vert`) where a
/// `MeshGeometry` spends 72 bytes a vertex. Its outputs are the engine's standard
/// varyings, so [TerrainMaterial] and any other material shade it; the depth
/// passes (shadow cascades, depth prepass, selection mask) run
/// `TerrainDepthVertex` over the position stream alone, 8 bytes a vertex.
///
/// An [UnskinnedGeometry] in a format of its own (flutter_scene's MATERIALS.md,
/// "A packed vertex format"): the engine binds the streams, the instance record
/// and its `FrameInfo`, which both shaders declare as its own unskinned ones do.
///
/// Needs [TerrainMaterial.loadLibrary] to have finished and Flutter GPU: the
/// streams are uploaded at construction.
class TerrainGeometry extends UnskinnedGeometry {
  /// [surface] uploaded to one device buffer, bounded by [bounds] in the
  /// region's frame.
  TerrainGeometry(PackedSurface surface, Aabb3 bounds) {
    final (indices, indexType) = switch (surface.indices) {
      final Uint16List i => (i, gpu.IndexType.int16),
      final Uint32List i => (i, gpu.IndexType.int32),
      final other => throw ArgumentError('indices are a Uint16List or a Uint32List, not ${other.runtimeType}'),
    };
    setVertexLayout(_colorLayout);
    setVertexShader(_vertexShader ??= TerrainMaterial.shader('TerrainVertex'));
    setDepthOnlyVertex(
      _depthVertexShader ??= TerrainMaterial.shader('TerrainDepthVertex'),
      positionStream: _positionBuffer,
    );
    uploadVertexStreams(
      [surface.positions, surface.attributes],
      surface.vertexCount,
      indices: indices,
      indexType: indexType,
    );
    setLocalBounds(bounds, Sphere.centerRadius(bounds.center, (bounds.max - bounds.min).length * 0.5));
  }

  static gpu.Shader? _vertexShader;
  static gpu.Shader? _depthVertexShader;

  /// Slot 0: the packed position, 8 bytes a vertex. The depth passes read it
  /// alone, with the engine's 64-byte model transform after it.
  static const VertexBufferDescriptor _positionBuffer = VertexBufferDescriptor(
    strideInBytes: 8,
    attributes: [VertexAttributeDescriptor(name: 'packed_position', format: gpu.VertexFormat.uint32x2)],
  );

  /// Slot 1: the packed colour, normal and light.
  static const VertexBufferDescriptor _attributeBuffer = VertexBufferDescriptor(
    strideInBytes: 8,
    attributes: [VertexAttributeDescriptor(name: 'packed_attributes', format: gpu.VertexFormat.uint32x2)],
  );

  /// Slot 2: the engine's 80-byte instance record, the model matrix's columns
  /// and then a colour multiplier.
  static const VertexBufferDescriptor _instanceBuffer = VertexBufferDescriptor(
    strideInBytes: 80,
    stepMode: gpu.VertexStepMode.instance,
    attributes: [
      VertexAttributeDescriptor(name: 'model_transform_0', format: gpu.VertexFormat.float32x4),
      VertexAttributeDescriptor(name: 'model_transform_1', format: gpu.VertexFormat.float32x4, offsetInBytes: 16),
      VertexAttributeDescriptor(name: 'model_transform_2', format: gpu.VertexFormat.float32x4, offsetInBytes: 32),
      VertexAttributeDescriptor(name: 'model_transform_3', format: gpu.VertexFormat.float32x4, offsetInBytes: 48),
      VertexAttributeDescriptor(name: 'instance_color', format: gpu.VertexFormat.float32x4, offsetInBytes: 64),
    ],
  );

  static const VertexLayoutDescriptor _colorLayout = VertexLayoutDescriptor(
    buffers: [_positionBuffer, _attributeBuffer, _instanceBuffer],
  );
}
