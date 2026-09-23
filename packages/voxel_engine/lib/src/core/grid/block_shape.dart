/// How a block is drawn and what it collides with. The declaration order is a
/// contract: the mesher reads a shape as its `index` from a byte table.
enum BlockShape {
  /// A full cube. Faces against an opaque neighbour or the same block are culled.
  cube,

  /// Two crossed quads (grass, saplings), lit from their own cell.
  cross,

  /// A liquid cell: a cube whose top sits at 7/8 unless the same liquid is above.
  liquid,

  /// A standing torch: a thin stick with a full-bright flame on top.
  torch,

  /// A flower: a stem and a small coloured head.
  flower,

  /// A thin panel along the x axis at z 0 (a door or a hatch), with a knob.
  panelZ,

  /// A thin panel along the z axis at x 0, with a knob.
  panelX,

  /// A torch leaning on the first opaque horizontal neighbour.
  wallTorch,

  /// The bottom half of a cube.
  slab,

  /// A post that joins neighbouring fences and opaque blocks with two rails.
  fence,

  /// Stairs whose high step is on the north side (z 0..0.5).
  stairsN,

  /// Stairs whose high step is on the east side (x 0.5..1).
  stairsE,

  /// Stairs whose high step is on the south side (z 0.5..1).
  stairsS,

  /// Stairs whose high step is on the west side (x 0..0.5).
  stairsW,

  /// A wire lying on the floor, an eighth of a block tall.
  wire,

  // One shape per rail orientation (the mesher draws bars over ties).

  /// A straight rail running north-south.
  railNs,

  /// A straight rail running east-west.
  railEw,

  /// A curved rail joining north and east.
  railNe,

  /// A curved rail joining north and west.
  railNw,

  /// A curved rail joining south and east.
  railSe,

  /// A curved rail joining south and west.
  railSw,

  /// A rail rising toward the north.
  railSlopeN,

  /// A rail rising toward the east.
  railSlopeE,

  /// A rail rising toward the south.
  railSlopeS,

  /// A rail rising toward the west.
  railSlopeW,

  /// Rungs between two rails, flat against the first opaque horizontal
  /// neighbour (a ladder on a wall, not two crossed sheets).
  ladder,
}

/// An axis-aligned box as min / max corners: a test reads a face without
/// adding a size to a position.
class CollisionBox {
  /// The box from ([x0], [y0], [z0]) to ([x1], [y1], [z1]).
  const CollisionBox(this.x0, this.y0, this.z0, this.x1, this.y1, this.z1);

  /// The whole cell.
  static const CollisionBox full = CollisionBox(0, 0, 0, 1, 1, 1);

  /// A fence post, as tall as it is drawn: one block, so a player jumps onto
  /// it. A joined fence adds arms as tall ([fenceBoxesOf]), read from its
  /// neighbours; a body with `VoxelBody.fenceBarrier` meets them
  /// `fenceBarrierHeight` tall instead.
  static const CollisionBox fencePost = CollisionBox(0.375, 0, 0.375, 0.625, 1, 0.625);

  /// The min corner.
  final double x0, y0, z0;

  /// The max corner.
  final double x1, y1, z1;

  /// The min coordinate on [axis] (0 x, 1 y, 2 z).
  double min(int axis) => axis == 0 ? x0 : (axis == 1 ? y0 : z0);

  /// The max coordinate on [axis] (0 x, 1 y, 2 z).
  double max(int axis) => axis == 0 ? x1 : (axis == 1 ? y1 : z1);

  /// This box moved by whole cells, from block space to world space.
  CollisionBox shifted(int dx, int dy, int dz) =>
      CollisionBox(x0 + dx, y0 + dy, z0 + dz, x1 + dx, y1 + dy, z1 + dz);

  @override
  String toString() => 'Box($x0, $y0, $z0 .. $x1, $y1, $z1)';
}

/// The boxes a body collides with, in the block's own 0..1 space. Empty for a
/// block that stops no body. Stairs: the bottom slab plus the high step at the
/// back, the same halves the mesher draws (N = high step at z 0..0.5, E = at
/// x 0.5..1). A fence is its lone post here and a ladder nothing: the arms
/// and the ladder's wall depend on the neighbours, which [collisionBoxesAt]
/// reads. The lists are constants: never
/// mutate one.
List<CollisionBox> collisionBoxesOf(BlockShape shape, {required bool solid}) {
  if (!solid) return const [];
  const half = CollisionBox(0, 0, 0, 1, 0.5, 1);
  return switch (shape) {
    BlockShape.slab => const [half],
    BlockShape.fence => const [CollisionBox.fencePost],
    BlockShape.stairsN => const [half, CollisionBox(0, 0.5, 0, 1, 1, 0.5)],
    BlockShape.stairsS => const [half, CollisionBox(0, 0.5, 0.5, 1, 1, 1)],
    BlockShape.stairsE => const [half, CollisionBox(0.5, 0.5, 0, 1, 1, 1)],
    BlockShape.stairsW => const [half, CollisionBox(0, 0.5, 0, 0.5, 1, 1)],
    _ => const [CollisionBox.full],
  };
}
