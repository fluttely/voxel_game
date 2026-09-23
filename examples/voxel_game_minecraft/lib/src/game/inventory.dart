import 'package:voxel_engine/content.dart' as content;

import '../core/items.dart';

export 'package:voxel_engine/content.dart' show ItemStack;

/// VK3.3: voxel_content's [content.Inventory] with this game's sizes (36 slots,
/// a hotbar of 9) and its item table's stack sizes and wear. Slot 0..8 is the
/// hotbar.
class Inventory extends content.Inventory {
  Inventory() : super(stackSize: Items.stackSize, maxDurability: Items.durabilityOf, capacity: size, hotbarSize: hotbar);

  static const int hotbar = 9;
  static const int size = 36;

  /// Reads a save back; stacks of items this game no longer has are dropped.
  @override
  void fromJson(List<Object?> data, {bool Function(String id)? known}) => super.fromJson(data, known: known ?? Items.has);
}
