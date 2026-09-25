import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
// The engine's own gpu shim: Material.bind is typed against it, and only it
// resolves to the same RenderPass / Shader types for both the analyzer and the build
// (package:flutter_gpu directly analyzes as a different type; the public
// flutter_scene/gpu.dart has no RenderPass).
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// The lit voxel terrain surfaces. A [PhysicallyBasedMaterial] whose fragment
/// shader is `shaders/terrain.frag`: the standard lit shader with the voxel light
/// term folded into the albedo, so the engine keeps binding and evaluating the
/// sun, its cascaded shadows, the ambient and the sky-coloured fog exactly as the
/// stock material does (a raw `ShaderMaterial` gets none of them). The only extra
/// input is the `TerrainInfo` block: [skyIntensity] and [emissionMix].
///
/// The shader bundle is an asset of this package compiled by
/// `tool/build_shaders.dart`; [loadLibrary] must finish before a material that
/// draws is constructed. A material built without it (unit tests, which never
/// draw) stays a stock PBR material.
class TerrainMaterial extends PhysicallyBasedMaterial {
  /// A terrain material; without [loadLibrary] it draws as stock PBR.
  TerrainMaterial({this.emissionMix = 0.5}) {
    final lib = _library;
    if (lib == null) return;
    _shader = lib['TerrainFragment']!;
    _cubeShader = lib['TerrainCubeFragment'];
    setFragmentShader(_shader!);
    setRadianceCubeFragmentShader(_cubeShader);
  }

  /// A package asset, so its key carries the package name.
  static const String asset = 'packages/voxel_scene/assets/shaders/terrain.shaderbundle';
  static gpu.ShaderLibrary? _library;

  /// [loadLibrary] has finished.
  static bool get loaded => _library != null;

  /// Loads the terrain shader bundle once. Throws when the bundle holds no
  /// shader this Flutter engine can read: a bundle is tied to the engine that
  /// compiled it.
  static Future<void> loadLibrary() async {
    if (_library != null) return;
    final lib = await gpu.loadShaderLibraryAsync(asset);
    if (lib == null || lib['TerrainFragment'] == null) {
      throw Exception(
        '$asset holds no TerrainFragment this engine can read; recompile it with '
        '`dart tool/build_shaders.dart` from packages/voxel_scene (a bundle is tied to the Flutter engine that built it)',
      );
    }
    _library = lib;
  }

  /// How much of the baked skylight shows: 1.0 noon, 0.35 night, 0.0 none.
  double skyIntensity = 1.0;

  /// The share of the lit albedo added back as emission, so a torch-lit wall
  /// reads at night when the sun and the ambient are almost off.
  double emissionMix;

  gpu.Shader? _shader;
  gpu.Shader? _cubeShader;
  final Float32List _info = Float32List(4);

  @override
  void bind(gpu.RenderPass pass, TransientWriter transientsBuffer, Lighting lighting) {
    super.bind(pass, transientsBuffer, lighting);
    final shader = _shader;
    if (shader == null) return;
    // The same choice Material.fragmentShaderForLighting made for the pipeline:
    // the cube twin when the bound environment uses the cube radiance layout.
    final cube = _cubeShader;
    final drawn = lighting.environmentMap.usesCubeRadianceLayout && cube != null ? cube : shader;
    _info[0] = skyIntensity;
    _info[1] = emissionMix;
    pass.bindUniform(drawn.getUniformSlot('TerrainInfo'), transientsBuffer.emplace(ByteData.sublistView(_info)));
  }
}
