/// How an item is held, and so how its icon is turned to the eye.
enum ItemGrip {
  /// A box carried against the palm (a block, a slab); its icon is seen from a
  /// top corner.
  block,

  /// A flat piece standing up out of the fist (a tool, a weapon, a door), drawn
  /// in its model's XY plane; its icon faces the eye.
  flat,

  /// A small solid thing standing up out of the fist (a torch, a flower, food);
  /// its icon is seen from a top corner.
  upright,
}
