import '../blocks/block_type.dart';
import 'item_type.dart';

/// How long blocks take to break: a block's hardness, divided by the speed
/// of the right tool's tier.
class MiningRules {
  /// Tools of tier `i` mine at [tierSpeed]`[i]` times the hand's speed; the
  /// hand is tier 0.
  const MiningRules({this.tierSpeed = const [1.0, 2.0, 4.0, 6.0, 9.0], this.wrongToolPenalty = 3.0});

  /// Speed per tool tier, the hand first.
  final List<double> tierSpeed;

  /// How many times longer a block takes without its tool.
  final double wrongToolPenalty;

  /// Seconds to break [block] holding [item] (null for the bare hand), or -1
  /// when it cannot be broken at all: unbreakable, or its tool is needed at a
  /// tier the item lacks.
  double mineTime(BlockType block, ItemType? item) {
    final hardness = block.hardness;
    if (hardness < 0.0) return -1.0;
    if (hardness == 0.0) return 0.05;
    final neededTool = block.tool;
    final neededTier = block.tier;
    final tool = item?.tool;
    final tier = item?.tier ?? 0;
    if (neededTool != null && (tool != neededTool || tier < neededTier)) {
      if (neededTier > 0 && tier < neededTier) return -1.0;
      return hardness * wrongToolPenalty;
    }
    final speed = tool != null && tool == neededTool ? tierSpeed[tier] : 1.0;
    return hardness / speed;
  }

  /// Whether breaking [block] with [item] yields its drop: its tool at its
  /// tier, when it asks for a tier.
  bool drops(BlockType block, ItemType? item) =>
      block.tier == 0 || (item != null && item.tool == block.tool && item.tier >= block.tier);
}
