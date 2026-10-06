/// What a block must lean on to stay: a torch on the floor, a wall torch or a
/// ladder on a wall, a crop on farmland. Once that neighbour is gone the block
/// breaks and drops, and a player cannot place it where it would not stand.
class Support {
  /// A solid block below; one of [on] (block ids) when it is not empty.
  const Support.below({this.on = const {}}) : side = false;

  /// An opaque block beside it, on any of the four horizontal sides: what a
  /// wall torch and a ladder lean on.
  const Support.side() : on = const {}, side = true;

  /// The blocks it may stand on; empty for any solid block. Only [Support.below].
  final Set<String> on;

  /// Whether it leans on a side rather than stands on the block below.
  final bool side;
}
