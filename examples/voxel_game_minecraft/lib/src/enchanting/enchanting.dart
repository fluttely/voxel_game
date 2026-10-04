import 'package:voxel_game/voxel_game.dart';

/// The enchanting table's use: the weapon or tool in hand gains 1 to
/// [maxGain] to its bonus (`ItemStack.bonus`, what a blow and a shot add to
/// their damage), for [dust] magic dust and one level. Short of either, or
/// with nothing to enchant in hand, the player is told so and nothing is
/// spent.
abstract final class Enchanting {
  /// The block that enchants.
  static const String table = 'enchanting_table';

  /// What an enchantment is paid in, besides a level.
  static const String dustItem = 'magic_dust';

  /// How much of [dustItem] an enchantment takes.
  static const int dust = 2;

  /// The most an enchantment adds to the bonus.
  static const int maxGain = 3;

  /// Whether [t] can be enchanted: a weapon (one that hits harder than a
  /// fist, or shoots) or a tool.
  static bool enchantable(ItemType t) => t.tool != null || t.damage > 1 || t.launcher != null;

  /// Enchants what [game]'s player holds: the use of an enchanting table
  /// (`VoxelGameSpec.blockUses`). Returns the bonus gained, 0 for none.
  static int use(VoxelGame game, IVec3 cell) {
    final p = game.player;
    final slot = p.selectedSlot;
    final bag = p.inventory;
    final held = bag.slots[slot];
    if (held == null || !enchantable(game.items[held.id])) {
      game.notify('Hold a weapon or a tool to enchant it');
      return 0;
    }
    if (p.level < 1) {
      game.notify('Enchanting takes a level');
      return 0;
    }
    if (bag.countOf(dustItem) < dust) {
      game.notify('Enchanting takes $dust magic dust');
      return 0;
    }
    final gain = 1 + game.random.nextInt(maxGain);
    bag.remove(dustItem, dust);
    p.level -= 1;
    bag.setSlot(slot, ItemStack(held.id, held.count, bonus: held.bonus + gain, dur: held.dur));
    game.notify('${game.items[held.id].name} enchanted: +${held.bonus + gain}');
    game.playSound('levelup', volumeDb: -6.0);
    return gain;
  }
}
