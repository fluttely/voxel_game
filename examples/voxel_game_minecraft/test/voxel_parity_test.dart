// VP0.3 (docs/VOXEL_PACKAGES_PLAN_2026-09-14.md): the byte-level proof that a change
// moves no world it did not mean to. Pinned before the world layer moved into packages
// and only ever re-pinned when a step changes the world on purpose; a hash that moves
// otherwise is a regression.
//
// Re-pinned at VA-Zm (2026-10-04) on the kit's `GameWorld` over the app's spec, seed 1337:
// the app's own generator, mesher calls and edit delta are gone, and the kit's generator
// grows a different world from the same rows (VAD16). The chunks hashed, the ring order
// and the edits written are the ones pinned since `b57cf2a2`.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_game/voxel_game.dart';
import 'package:voxel_game_minecraft/src/spec/game_spec.dart';

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

/// Pinned at VA-Zm (2026-10-04). An empty surface hashes to 0x811c9dc5.
const Map<String, int> _expected = {
  'gen 0,0': 0x13b10325,
  'mesh 0,0 solid positions': 0xdc6d2a6d,
  'mesh 0,0 solid normals': 0x336ea345,
  'mesh 0,0 solid colors': 0xae7224e3,
  'mesh 0,0 solid light': 0x80ae4fcd,
  'mesh 0,0 solid indices': 0x8fe6a3b1,
  'mesh 0,0 liquid positions': 0xb2ce00f9,
  'mesh 0,0 liquid normals': 0xfbe5c7e5,
  'mesh 0,0 liquid colors': 0x9a7961b5,
  'mesh 0,0 liquid light': 0xe6523ba5,
  'mesh 0,0 liquid indices': 0x5c75aba7,
  'mesh 0,0 cutout positions': 0xb07f6de9,
  'mesh 0,0 cutout normals': 0x84b1a505,
  'mesh 0,0 cutout colors': 0xfa11e775,
  'mesh 0,0 cutout light': 0x26835565,
  'mesh 0,0 cutout indices': 0xf50c0885,
  'mesh 0,0 glow positions': 0x811c9dc5,
  'mesh 0,0 glow normals': 0x811c9dc5,
  'mesh 0,0 glow colors': 0x811c9dc5,
  'mesh 0,0 glow light': 0x811c9dc5,
  'mesh 0,0 glow indices': 0x811c9dc5,
  'mesh 0,0 sky': 0x0f2da756,
  'mesh 0,0 block': 0x9b5a52a6,
  'gen 5,-3': 0xf76e7545,
  'mesh 5,-3 solid positions': 0x641cf695,
  'mesh 5,-3 solid normals': 0xcfbbaba5,
  'mesh 5,-3 solid colors': 0x802f0354,
  'mesh 5,-3 solid light': 0x237e883d,
  'mesh 5,-3 solid indices': 0x6f94651b,
  'mesh 5,-3 liquid positions': 0x811c9dc5,
  'mesh 5,-3 liquid normals': 0x811c9dc5,
  'mesh 5,-3 liquid colors': 0x811c9dc5,
  'mesh 5,-3 liquid light': 0x811c9dc5,
  'mesh 5,-3 liquid indices': 0x811c9dc5,
  'mesh 5,-3 cutout positions': 0xb39e920d,
  'mesh 5,-3 cutout normals': 0xdf9da445,
  'mesh 5,-3 cutout colors': 0x9c59d0cd,
  'mesh 5,-3 cutout light': 0x7eae4ae5,
  'mesh 5,-3 cutout indices': 0x9e937d05,
  'mesh 5,-3 glow positions': 0x811c9dc5,
  'mesh 5,-3 glow normals': 0x811c9dc5,
  'mesh 5,-3 glow colors': 0x811c9dc5,
  'mesh 5,-3 glow light': 0x811c9dc5,
  'mesh 5,-3 glow indices': 0x811c9dc5,
  'mesh 5,-3 sky': 0x4a50c453,
  'mesh 5,-3 block': 0x21cafed0,
  'gen underworld 0,0': 0xa1ac8e10,
  'edit delta': 0x1c48a9ef,
};

void main() {
  test('generator, mesher and edit delta hash as pinned', () {
    final actual = <String, int>{};
    final blocks = gameSpec.buildBlocks();
    final world = GameWorld.headless(blocks, gameSpec.dimensionWorlds, gameSpec.seed, liquids: gameSpec.liquids);
    final mesher = blocks.table.mesher();

    for (final (cx, cz) in const [(0, 0), (5, -3)]) {
      // The world's ring order: c, nx, px, nz, pz, nxnz, pxnz, nxpz, pxpz.
      Uint8List at(int dx, int dz) => world.generators.generateIn(cx + dx, cz + dz, 0);
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
    actual['gen underworld 0,0'] = _fnv(world.generators.generateIn(0, 0, 1));

    // No chunk is loaded, so every edit is stored, not drawn.
    world.storeEdit(const IVec3(3, 40, 7), blocks.indexOf('stone'));
    world.storeEdit(const IVec3(15, 64, 0), blocks.indexOf('lamp'));
    world.storeEdit(const IVec3(-9, 12, 40), blocks.indexOf('oak_planks'));
    world.storeEditIn(1, const IVec3(100, 30, -20), blocks.indexOf('cobblestone'));
    final codec = WorldSaves.codecFor(gameSpec.dimensionWorlds.length);
    actual['edit delta'] = _fnv(codec.encode(gameSpec.seed, world.edits));

    final report = [for (final e in actual.entries) "  '${e.key}': 0x${e.value.toRadixString(16).padLeft(8, '0')},"]
        .join('\n');
    expect(actual, _expected, reason: 'actual hashes:\n$report');
  });
}
