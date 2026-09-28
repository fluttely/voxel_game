// Geometry's stream binding is marked internal to flutter_scene, but a geometry with
// its own vertex layout has to set and bind its streams: LineSegmentsGeometry, the
// engine's own custom geometry, calls the same two members.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
// The engine's own gpu shim, as in terrain_material.dart: Geometry.bind is typed
// against it.
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
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
/// Needs [TerrainMaterial.loadLibrary] to have finished and Flutter GPU: the
/// streams are uploaded at construction.
class TerrainGeometry extends Geometry {
  /// [surface] uploaded to one device buffer, bounded by [bounds] in the
  /// region's frame.
  TerrainGeometry(PackedSurface surface, Aabb3 bounds) {
    setVertexShader(_vertexShader ??= TerrainMaterial.shader('TerrainVertex'));
    final positions = ByteData.sublistView(surface.positions);
    final attributes = ByteData.sublistView(surface.attributes);
    final indices = switch (surface.indices) {
      final Uint16List i => (ByteData.sublistView(i), gpu.IndexType.int16),
      final Uint32List i => (ByteData.sublistView(i), gpu.IndexType.int32),
      final other => throw ArgumentError('indices are a Uint16List or a Uint32List, not ${other.runtimeType}'),
    };
    final total = positions.lengthInBytes + attributes.lengthInBytes + indices.$1.lengthInBytes;
    final buffer = gpu.gpuContext.createDeviceBuffer(gpu.StorageMode.hostVisible, total);
    var offset = 0;
    gpu.BufferView upload(ByteData bytes) {
      buffer.overwrite(bytes, destinationOffsetInBytes: offset);
      final view = gpu.BufferView(buffer, offsetInBytes: offset, lengthInBytes: bytes.lengthInBytes);
      offset += bytes.lengthInBytes;
      return view;
    }

    setVertexStreams([upload(positions), upload(attributes)], surface.vertexCount);
    setIndices(upload(indices.$1), indices.$2);
    buffer.flush(offsetInBytes: 0, lengthInBytes: total);
    setLocalBounds(bounds, Sphere.centerRadius(bounds.center, (bounds.max - bounds.min).length * 0.5));
  }

  static gpu.Shader? _vertexShader;
  static gpu.Shader? _depthVertexShader;

  /// Slot 0: the packed position, 8 bytes a vertex.
  static const VertexBufferDescriptor _positionBuffer = VertexBufferDescriptor(
    strideInBytes: 8,
    attributes: [VertexAttributeDescriptor(name: 'packed_position', format: gpu.VertexFormat.uint32x2)],
  );

  /// Slot 1 of the colour layout: the packed colour, normal and light.
  static const VertexBufferDescriptor _attributeBuffer = VertexBufferDescriptor(
    strideInBytes: 8,
    attributes: [VertexAttributeDescriptor(name: 'packed_attributes', format: gpu.VertexFormat.uint32x2)],
  );

  /// The engine's instance record: the model matrix's columns, then a colour
  /// multiplier. [instanceColor] false is the depth passes' 64-byte record.
  static VertexBufferDescriptor _instanceBuffer({required bool instanceColor}) => VertexBufferDescriptor(
    strideInBytes: instanceColor ? 80 : 64,
    stepMode: gpu.VertexStepMode.instance,
    attributes: [
      for (var column = 0; column < 4; column++)
        VertexAttributeDescriptor(
          name: 'model_transform_$column',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: column * 16,
        ),
      if (instanceColor)
        const VertexAttributeDescriptor(name: 'instance_color', format: gpu.VertexFormat.float32x4, offsetInBytes: 64),
    ],
  );

  static final VertexLayoutDescriptor _colorLayout = VertexLayoutDescriptor(
    buffers: [_positionBuffer, _attributeBuffer, _instanceBuffer(instanceColor: true)],
  );

  static final VertexLayoutDescriptor _depthLayout = VertexLayoutDescriptor(
    buffers: [_positionBuffer, _instanceBuffer(instanceColor: false)],
  );

  @override
  VertexLayoutDescriptor? get defaultVertexLayout => _colorLayout;

  @override
  ({gpu.Shader shader, VertexLayoutDescriptor layout})? get depthOnlyVertex =>
      (shader: _depthVertexShader ??= TerrainMaterial.shader('TerrainDepthVertex'), layout: _depthLayout);

  // A `.fmat` material's generated vertex variants read the engine's 72-byte
  // vertex; none applies to this one.
  @override
  String get materialVertexVariant => 'terrain';

  final Float32List _frameInfo = Float32List(20);

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    assert(shaderOverride == null, 'no material vertex variant reads the packed terrain vertex');
    // Slots 0 and 1; the encoder binds the instance record in slot 2.
    bindGeometryBuffers(pass);
    _frameInfo
      ..setAll(0, cameraTransform.storage)
      ..[16] = cameraPosition.x
      ..[17] = cameraPosition.y
      ..[18] = cameraPosition.z
      ..[19] = depthBias;
    pass.bindUniform(
      vertexShader.getUniformSlot('FrameInfo'),
      transientsBuffer.emplace(ByteData.sublistView(_frameInfo)),
    );
  }
}
