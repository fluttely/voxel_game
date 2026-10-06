/// Where a `VoxelGameWidget` is on its way to the first frame it shows. The
/// loading screen is up in every stage but [playing].
enum LoadingStage {
  /// The game is being made: its worker isolates, a save read, a host joined.
  starting,

  /// The game runs, undrawn: the chunks of the window around the player are
  /// generated, meshed and built (`VoxelGame.filled`).
  filling,

  /// The renderer compiles every pipeline the filled window draws with
  /// (`Scene.warmUp`), so the first frames shown do not stall on it.
  warming,

  /// The game is shown.
  playing,
}
