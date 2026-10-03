/// A block that blows up (`SignalSpec.explosives`). Powered, it is lit: the
/// block goes and a copy of it flashes where it stood, falling as a body
/// does, for [fuse] seconds; then it bursts (`VoxelGame.explode`), up to
/// [damage] to every body within 1.5 × [radius] and the blocks within
/// [radius] broken. Another explosive the blast reaches is not broken but
/// lit, on a fuse of its own from [chainFuse] to three times that, so a row
/// of them goes off one after another. The numbers are Minecraft's TNT's.
class Explosive {
  /// A blast of [radius] and [damage], [fuse] seconds after it is lit.
  const Explosive({this.radius = 3.5, this.damage = 18.0, this.fuse = 3.2, this.chainFuse = 0.5})
    : assert(radius > 0.0 && damage >= 0.0 && fuse > 0.0 && chainFuse > 0.0);

  /// How far the blast breaks blocks, in metres.
  final double radius;

  /// What the blast deals at its middle, falling to nothing 1.5 × [radius]
  /// off.
  final double damage;

  /// Seconds from lit (a wire, a plate) to the blast.
  final double fuse;

  /// The shortest fuse of one lit by another's blast.
  final double chainFuse;
}
