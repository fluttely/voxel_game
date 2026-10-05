/// Where a new world's player first stands: on the ground of column ([x],
/// [z]), looking [yaw] (radians, as `PlayerEntity.yaw`: 0 looks down -Z).
/// What `VoxelGameSpec.spawn` answers; the player's respawn point too, until
/// a bed moves it.
class SpawnPoint {
  /// The column ([x], [z]), facing [yaw].
  const SpawnPoint({required this.x, required this.z, this.yaw = 0.0});

  /// The column's x.
  final int x;

  /// The column's z.
  final int z;

  /// Turned left or right, radians (0 looks down -Z).
  final double yaw;
}
