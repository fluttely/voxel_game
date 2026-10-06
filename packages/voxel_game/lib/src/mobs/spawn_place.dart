/// Where a `SpawnRule` lets a creature appear.
///
/// In a dimension that is all cavern (`WorldGenSpec.cavern`) there is no
/// surface: every spawn there is in a pocket of air, and a [surface] rule
/// takes it as its ground.
enum SpawnPlace {
  /// On the ground at the top of a column.
  surface,

  /// In a pocket of air under the surface, near the height of a player who
  /// is underground.
  cave,

  /// Either.
  anywhere,
}
