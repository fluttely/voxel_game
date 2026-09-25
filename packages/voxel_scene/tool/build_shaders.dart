// Compiles the terrain shaders into assets/shaders/terrain.shaderbundle.
//
//   cd packages/voxel_scene && dart tool/build_shaders.dart
//
// There is no hook/build.dart for this (the Flutter tool's hook runner rejects the
// SwiftPM plugin symlinks of an app that uses one), so the bundle is compiled by hand with
// the SDK's impellerc, with the same arguments flutter_gpu_shaders' hook passes, and
// committed as a plain asset. A bundle is tied to the engine that compiled it: run this again after a
// Flutter upgrade, or after editing shaders/*.frag. The includes come from flutter_scene's
// own shaders/ directory (the engine lighting framework the terrain shader reuses).
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

Future<void> main() async {
  final flutter = Process.runSync('which', ['flutter']).stdout.toString().trim();
  if (flutter.isEmpty) {
    stderr.writeln('flutter is not on PATH');
    exit(1);
  }
  final flutterRoot = File(File(flutter).resolveSymbolicLinksSync()).parent.parent.path;
  // macOS ships one engine artifact directory, darwin-x64, whose impellerc is a universal
  // (arm64 on Apple silicon) binary.
  final engine = '$flutterRoot/bin/cache/artifacts/engine/darwin-x64';
  final impellerc = '$engine/impellerc';
  if (!File(impellerc).existsSync()) {
    stderr.writeln('impellerc not found at $impellerc');
    exit(1);
  }
  final sceneLib = await Isolate.resolvePackageUri(Uri.parse('package:flutter_scene/scene.dart'));
  if (sceneLib == null) {
    stderr.writeln('flutter_scene is not resolvable; run flutter pub get first');
    exit(1);
  }
  final sceneShaders = sceneLib.resolve('../shaders/').toFilePath();
  Directory('assets/shaders').createSync(recursive: true);
  final manifest = jsonEncode({
    'TerrainFragment': {'type': 'fragment', 'file': 'shaders/terrain.frag'},
    'TerrainCubeFragment': {'type': 'fragment', 'file': 'shaders/terrain_cube.frag'},
  });
  final args = [
    '--sl=assets/shaders/terrain.shaderbundle',
    '--shader-bundle=$manifest',
    // flutter_scene's engine bundle passes the same (build_engine_assets.dart); without it
    // spirv_cross falls back to GLSL ES 100 texture ops and aborts on the lighting code.
    '--gles-language-version=300',
    '--include=shaders',
    '--include=$engine/shader_lib',
    '--include=$sceneShaders',
  ];
  stdout.writeln('$impellerc ${args.join(' ')}');
  final r = Process.runSync(impellerc, args);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) exit(r.exitCode);
  stdout.writeln(
    'wrote assets/shaders/terrain.shaderbundle (${File('assets/shaders/terrain.shaderbundle').lengthSync()} bytes)',
  );
}
