import 'dart:typed_data';

import 'package:voxel_game_minecraft/src/core/blocks.dart';
import 'package:voxel_game_minecraft/src/core/items.dart';
import 'package:voxel_engine/core.dart';
import 'package:voxel_game_minecraft/src/entities/boat.dart';
import 'package:voxel_game_minecraft/src/entities/item_drop.dart';
import 'package:voxel_game_minecraft/src/game/inventory.dart';
import 'package:voxel_game_minecraft/src/game/net.dart';
import 'package:voxel_game_minecraft/src/world/voxel_world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Stage 25's pure pieces (Godot `--stage25` covers the wire in the app): the
/// bag room check, the prediction bookkeeping, the chest accounting, the
/// batched flow tick and the replica lerps.
void main() {
  test('roomFor counts empty slots and part stacks, capped at the count asked', () {
    final inv = Inventory();
    expect(inv.roomFor('iron_ingot', 3), 3);
    expect(inv.hasEmptySlot, isTrue);
    // The probe's bag: every slot full of stone, the last one iron short by one.
    for (var i = 0; i < Inventory.size; i++) {
      inv.setSlot(i, ItemStack('stone', Items.stackSize('stone')));
    }
    inv.setSlot(Inventory.size - 1, ItemStack('iron_ingot', Items.stackSize('iron_ingot') - 1));
    expect(inv.roomFor('iron_ingot', 3), 1);
    expect(inv.roomFor('stone', 5), 0);
    expect(inv.roomFor('apple', 1), 0);
    expect(inv.hasEmptySlot, isFalse);
    // What does not fit is what `give_rest` hands back.
    expect(inv.add('iron_ingot', 3), 2);
  });

  test('a prediction owns its cell until the ack; a differing id asks for a rollback', () {
    final p = BlockPrediction();
    const a = IVec3(8, 45, 8), b = IVec3(9, 45, 8);
    final planks = Blocks.indexOf('oak_planks'), stone = Blocks.indexOf('stone');
    final sa = p.predict(a, planks);
    final sb = p.predict(b, planks);
    expect([sa, sb], [1, 2]);
    expect(p.owns(a) && p.owns(b), isTrue);
    // The host refused a: the id that stands is stone, the world shows planks.
    expect(p.ack(sa, a, stone, planks), isTrue);
    expect(p.owns(a), isFalse);
    // The host took b.
    expect(p.ack(sb, b, planks, planks), isFalse);
    expect(p.pending, isEmpty);
    // Two edits on one cell: the first ack does not release the second's claim.
    final s3 = p.predict(a, planks);
    final s4 = p.predict(a, Blocks.air);
    expect(p.ack(s3, a, planks, Blocks.air), isTrue);
    expect(p.owns(a), isTrue);
    p.ack(s4, a, Blocks.air, Blocks.air);
    expect(p.owns(a), isFalse);
  });

  test('another peer\'s edit is never dropped: a loaded cell is written and heard, an unloaded one waits for its chunk', () {
    final w = VoxelWorld(seedValue: 42, loadRadius: 1);
    w.chunks[(x: 0, z: 0)] = Uint8List(VoxelWorld.volume);
    final heard = <IVec3>[];
    w.onBlockChanged = (b, old, id) => heard.add(b);
    final glass = Blocks.indexOf('glass');
    const near = IVec3(3, 20, 3);
    w.storeEdit(VoxelWorld.dimOverworld, near, glass);
    expect([w.getBlock(near), heard], [glass, [near]]);
    // Chunk (6, 6) is not loaded: a host's placement there, and a break (air
    // over whatever the generator will put there), both wait in the delta.
    const placed = IVec3(100, 20, 100), broken = IVec3(101, 10, 100);
    w.storeEdit(VoxelWorld.dimOverworld, placed, glass);
    w.storeEdit(VoxelWorld.dimOverworld, broken, Blocks.air);
    expect([w.isLoaded(placed), heard.length, w.editCountIn(VoxelWorld.dimOverworld)], [false, 1, 3]);
    // The delta is what lands on the chunk when it generates.
    final far = VoxelWorld.saveCodec.decode(w.editsToBytes()).edits[VoxelWorld.dimOverworld]![(x: 6, z: 6)]!;
    expect(far, {ChunkSize.index(4, 20, 4): glass, ChunkSize.index(5, 10, 4): Blocks.air});
  });

  group('chest edits are paid for from the declared bag or the escrow', () {
    Inventory bagWith(String id, int n) => Inventory()..add(id, n);

    test('from the bag: debited once, refused when the bag is short', () {
      final bag = bagWith('stone', 3);
      final escrow = <String, int>{};
      expect(Net.chestEditVerdict(null, {'id': 'stone', 'count': 2}, true, bag, escrow), isTrue);
      expect(bag.countOf('stone'), 1);
      expect(Net.chestEditVerdict(null, {'id': 'stone', 'count': 2}, true, bag, escrow), isFalse);
      expect(bag.countOf('stone'), 1);
      // A peer that never declared a bag cannot pay from it.
      expect(Net.chestEditVerdict(null, {'id': 'stone', 'count': 1}, true, null, escrow), isFalse);
    });

    test('taking out fills the escrow; putting back spends it; anything else is refused', () {
      final escrow = <String, int>{};
      expect(Net.chestEditVerdict(ItemStack('apple', 5), <String, dynamic>{}, false, null, escrow), isTrue);
      expect(escrow['apple'], 5);
      expect(Net.chestEditVerdict(null, {'id': 'apple', 'count': 3}, false, null, escrow), isTrue);
      expect(escrow['apple'], 2);
      expect(Net.chestEditVerdict(null, {'id': 'apple', 'count': 3}, false, null, escrow), isFalse);
      expect(Net.chestEditVerdict(null, {'id': 'diamond', 'count': 1}, false, null, escrow), isFalse);
      // A swap: the apples leave into the escrow, the stone that enters is paid from it.
      escrow['stone'] = 1;
      expect(Net.chestEditVerdict(ItemStack('apple', 2), {'id': 'stone', 'count': 1}, false, null, escrow), isTrue);
      expect(escrow['stone'], 0);
      expect(escrow['apple'], 4);
      // Topping up a stack only pays for the difference.
      final bag = bagWith('stone', 1);
      expect(Net.chestEditVerdict(ItemStack('stone', 4), {'id': 'stone', 'count': 5}, true, bag, escrow), isTrue);
      expect(bag.countOf('stone'), 0);
    });
  });

  test('the flow tick leaves as one batch a tick: 24 cells over 4 batches for the walled pool', () {
    const floorY = 10;
    const dt = 1.0 / 60.0;
    final w = VoxelWorld(seedValue: 42, loadRadius: 1);
    final c = Uint8List(VoxelWorld.volume);
    for (var i = 0; i < 16 * 16 * floorY; i++) {
      c[i] = Blocks.indexOf('stone');
    }
    w.chunks[(x: 0, z: 0)] = c;
    const centre = IVec3(8, floorY, 8);
    for (var dx = -3; dx < 4; dx++) {
      for (var dz = -3; dz < 4; dz++) {
        if (dx.abs() == 3 || dz.abs() == 3) w.setBlock(centre + IVec3(dx, 0, dz), Blocks.indexOf('stone'));
      }
    }
    final net = Net.instance;
    net.mode = NetMode.host;
    net.stats['flow_batch_rpcs'] = 0;
    net.stats['flow_batch_cells'] = 0;
    addTearDown(() => net.mode = NetMode.solo);
    w.onBlockChanged = net.onBlockChanged;
    w.setBlock(centre, Blocks.indexOf('water')); // a single edit, outside any batch
    for (var i = 0; i < 180; i++) {
      net.beginBlockBatch();
      w.tickFlow(dt);
      net.endBlockBatch();
    }
    expect(net.stats['flow_batch_cells'], 24);
    expect(net.stats['flow_batch_rpcs'], 4);
  });

  test('a batch over 200 cells splits, as Godot keeps its reliable packets', () {
    final net = Net.instance;
    net.mode = NetMode.host;
    net.stats['flow_batch_rpcs'] = 0;
    net.stats['flow_batch_cells'] = 0;
    addTearDown(() => net.mode = NetMode.solo);
    net.beginBlockBatch();
    for (var i = 0; i < 450; i++) {
      net.onBlockChanged(IVec3(i, 50, 0), Blocks.air, Blocks.indexOf('water_flow'));
    }
    net.endBlockBatch();
    expect(net.stats['flow_batch_rpcs'], 3);
    expect(net.stats['flow_batch_cells'], 450);
  });

  test('replicas never simulate: a drop and a boat lerp to the streamed pose, a far jump snaps', () {
    final drop = ItemDrop()..replica = true;
    drop.setNetPose(Vector3(4, 50, 4));
    expect(drop.position, Vector3(4, 50, 4));
    drop.setNetPose(Vector3(5, 50, 4));
    expect(drop.netPoseDelta(), closeTo(1.0, 1e-9));
    for (var i = 0; i < 60; i++) {
      drop.update(1.0 / 60.0);
    }
    expect(drop.netPoseDelta(), lessThan(0.001));
    expect(drop.velocity.length, 0.0);
    drop.setNetPose(Vector3(20, 50, 4));
    expect(drop.netPoseDelta(), 0.0);

    final boat = Boat()..replica = true;
    boat.setNetPose(Vector3(12.5, 50.9, 0.5), 0.0);
    boat.setNetPose(Vector3(12.5, 50.9, -1.5), 0.6);
    for (var i = 0; i < 60; i++) {
      boat.update(1.0 / 60.0);
    }
    expect((boat.position - Vector3(12.5, 50.9, -1.5)).length, lessThan(0.001));
    expect(boat.yaw, closeTo(0.6, 1e-3));
  });
}
