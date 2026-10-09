import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_scene/voxel_scene.dart';

/// Whether the flatbuffer [bundle] holds the string [name] exactly: its
/// little-endian length, its bytes, then the terminating zero.
bool _holds(Uint8List bundle, String name) {
  final bytes = ascii.encode(name);
  final view = ByteData.sublistView(bundle);
  for (var i = 4; i + bytes.length < bundle.length; i++) {
    if (view.getUint32(i - 4, Endian.little) != bytes.length || bundle[i + bytes.length] != 0) continue;
    var same = true;
    for (var j = 0; j < bytes.length && same; j++) {
      same = bundle[i + j] == bytes[j];
    }
    if (same) return true;
  }
  return false;
}

void main() {
  test('the committed bundle holds every entry a terrain material draws with', () {
    // Tests never load the bundle (no GPU), so this is what catches a shader
    // added to the material and to the build tool, but not compiled.
    final bundle = File('assets/shaders/terrain.shaderbundle').readAsBytesSync();
    for (final name in TerrainMaterial.entries) {
      expect(_holds(bundle, name), isTrue, reason: '$name; run `dart tool/build_shaders.dart`');
    }
    expect(_holds(bundle, 'TerrainMissingFragment'), isFalse);
  });

  test('the build tool compiles every entry, each twin from terrain.frag', () {
    final tool = File('tool/build_shaders.dart').readAsStringSync();
    final manifest = RegExp(r"'(Terrain\w+)': \{'type': '\w+', 'file': '([\w/.]+)'\}");
    final files = {for (final m in manifest.allMatches(tool)) m.group(1)!: m.group(2)!};
    expect(files.keys, unorderedEquals(TerrainMaterial.entries));
    for (final MapEntry(key: name, value: path) in files.entries) {
      if (!name.endsWith('Fragment') || path == 'shaders/terrain.frag') continue;
      expect(File(path).readAsStringSync(), contains('#include <terrain.frag>'), reason: name);
    }
  });
}
