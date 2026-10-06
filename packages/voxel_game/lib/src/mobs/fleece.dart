/// What a creature grows that a tool takes off it (a sheep's wool): a use on
/// it with a tool of [tool] in hand shears it of [count] of [item], dropped
/// beside it, and the fleece grows back in [regrow] seconds. Shorn, its body
/// is drawn smaller.
class Fleece {
  /// A fleece of [item], the defaults a sheep's.
  const Fleece(this.item, {this.tool = 'shears', this.count = (1, 3), this.regrow = 120.0})
    : assert(regrow > 0.0, 'a fleece grows back');

  /// The item it is shorn of.
  final String item;

  /// The tool kind that shears it (`ItemType.tool`).
  final String tool;

  /// How many of [item] a shearing gives, fewest and most.
  final (int, int) count;

  /// Seconds it takes to grow back.
  final double regrow;
}
