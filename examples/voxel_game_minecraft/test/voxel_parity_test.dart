// VP0.3 (docs/VOXEL_PACKAGES_PLAN_2026-09-14.md): the byte-level proof that moving the
// world layer into packages changes no behaviour. Pinned before the first move and only
// ever re-pinned when a stage changes the world on purpose. Otherwise only the imports
// follow the moves.
//
// Re-pinned at s16 (2026-09-17): stage 41 spaces the trees on a patch grid and grows them
// taller, so every overworld chunk holds different bytes. The underworld (no trees) and
// the edit delta hash as they did at `b57cf2a2`, which is the proof that nothing else moved.
//
// Touched again at s17 (2026-09-17): stage 42 drops the parts of a tree that hang off
// nothing. Both chunks generate byte for byte as they did at s16 — what moved is two
// arrays of chunk (0,0)'s solid mesh, because a tree in the ring around it lost a block
// at the border. Everything else, including the whole of (5,-3), is untouched.
import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/world/terrain_generator.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';

/// FNV-1a, 32 bits, over the raw bytes of a typed array.
int _fnv(TypedData data) {
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Pinned at POC `b57cf2a2` (2026-09-14), overworld re-pinned at s16. An empty surface
/// hashes to 0x811c9dc5.
const Map<String, int> _expected = {
  'gen 0,0': 0x3214e21d,
  'mesh 0,0 solid positions': 0xc71122b5,
  'mesh 0,0 solid normals': 0xdaac9e45,
  'mesh 0,0 solid colors': 0x4074935e,
  'mesh 0,0 solid light': 0x8d7a6255,
  'mesh 0,0 solid indices': 0x03fde051,
  'mesh 0,0 liquid positions': 0x45520479,
  'mesh 0,0 liquid normals': 0x2ea0e105,
  'mesh 0,0 liquid colors': 0xdf49b56d,
  'mesh 0,0 liquid light': 0xcc57e505,
  'mesh 0,0 liquid indices': 0x080f2e6d,
  'mesh 0,0 cutout positions': 0xc411f129,
  'mesh 0,0 cutout normals': 0x86926245,
  'mesh 0,0 cutout colors': 0x68e92f6d,
  'mesh 0,0 cutout light': 0xf1347d65,
  'mesh 0,0 cutout indices': 0x60d0b305,
  'mesh 0,0 glow positions': 0x811c9dc5,
  'mesh 0,0 glow normals': 0x811c9dc5,
  'mesh 0,0 glow colors': 0x811c9dc5,
  'mesh 0,0 glow light': 0x811c9dc5,
  'mesh 0,0 glow indices': 0x811c9dc5,
  'mesh 0,0 sky': 0x4817c9a5,
  'mesh 0,0 block': 0x150f42d5,
  'gen 5,-3': 0x8ade407b,
  'mesh 5,-3 solid positions': 0xb57fc8a5,
  'mesh 5,-3 solid normals': 0x51be5765,
  'mesh 5,-3 solid colors': 0x198b2979,
  'mesh 5,-3 solid light': 0x023a73bd,
  'mesh 5,-3 solid indices': 0x2b19f41b,
  'mesh 5,-3 liquid positions': 0xe12b8c5d,
  'mesh 5,-3 liquid normals': 0x2c797dc5,
  'mesh 5,-3 liquid colors': 0x0e9371a5,
  'mesh 5,-3 liquid light': 0x3769ddc5,
  'mesh 5,-3 liquid indices': 0xa52b60c5,
  'mesh 5,-3 cutout positions': 0x811c9dc5,
  'mesh 5,-3 cutout normals': 0x811c9dc5,
  'mesh 5,-3 cutout colors': 0x811c9dc5,
  'mesh 5,-3 cutout light': 0x811c9dc5,
  'mesh 5,-3 cutout indices': 0x811c9dc5,
  'mesh 5,-3 glow positions': 0x811c9dc5,
  'mesh 5,-3 glow normals': 0x811c9dc5,
  'mesh 5,-3 glow colors': 0x811c9dc5,
  'mesh 5,-3 glow light': 0x811c9dc5,
  'mesh 5,-3 glow indices': 0x811c9dc5,
  'mesh 5,-3 sky': 0xb35855c5,
  'mesh 5,-3 block': 0x292464f3,
  'gen underworld 0,0': 0x49c95e3e,
  'edit delta': 0xfa6c7fe8,
};

void main() {
  test('generator, mesher and edit delta hash as pinned before the package moves', () {
    final actual = <String, int>{};
    final gen = TerrainGenerator(ids: Blocks.generatorIds(), seed: 42);
    final mesher = ChunkMesher(
      palette: Blocks.palette(),
      shape: Blocks.shapes(),
      opaque: Blocks.opaqueTable(),
      emission: Blocks.emission(),
    );

    for (final (cx, cz) in const [(0, 0), (5, -3)]) {
      // The world's ring order: c, nx, px, nz, pz, nxnz, pxnz, nxpz, pxpz.
      Uint8List at(int dx, int dz) => gen.generateIn(cx + dx, cz + dz, 0);
      final ring = [at(0, 0), at(-1, 0), at(1, 0), at(0, -1), at(0, 1), at(-1, -1), at(1, -1), at(-1, 1), at(1, 1)];
      actual['gen $cx,$cz'] = _fnv(ring[0]);
      final r = mesher.build(cx, cz, ring);
      for (final (name, s) in [('solid', r.solid), ('liquid', r.liquid), ('cutout', r.cutout), ('glow', r.glow)]) {
        actual['mesh $cx,$cz $name positions'] = _fnv(s.positions);
        actual['mesh $cx,$cz $name normals'] = _fnv(s.normals);
        actual['mesh $cx,$cz $name colors'] = _fnv(s.colors);
        actual['mesh $cx,$cz $name light'] = _fnv(s.light);
        actual['mesh $cx,$cz $name indices'] = _fnv(s.indices);
      }
      actual['mesh $cx,$cz sky'] = _fnv(r.sky);
      actual['mesh $cx,$cz block'] = _fnv(r.block);
    }
    actual['gen underworld 0,0'] = _fnv(gen.generateIn(0, 0, 1));

    final world = VoxelWorld(seedValue: 42)..flowEnabled = false;
    world.chunks[(x: 0, z: 0)] = Uint8List(VoxelWorld.volume);
    world.chunks[(x: -1, z: 2)] = Uint8List(VoxelWorld.volume);
    world.setBlock(const IVec3(3, 40, 7), Blocks.indexOf('stone'));
    world.setBlock(const IVec3(15, 64, 0), Blocks.indexOf('lamp'));
    world.setBlock(const IVec3(-9, 12, 40), Blocks.indexOf('oak_planks'));
    world.storeEdit(1, const IVec3(100, 30, -20), Blocks.indexOf('cobblestone'));
    actual['edit delta'] = _fnv(world.editsToBytes());

    final report = [for (final e in actual.entries) "    '${e.key}': 0x${e.value.toRadixString(16).padLeft(8, '0')},"].join('\n');
    expect(actual, _expected, reason: 'actual hashes:\n$report');
  });
}
