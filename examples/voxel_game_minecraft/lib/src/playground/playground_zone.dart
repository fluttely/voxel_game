/// One exhibit of the playground: a [size] square of the plaza at grid
/// cell ([gx], [gz]) about the hub, its [title] and the [hint] its card
/// gives the player who walks in (`ZoneCard`).
class PlaygroundZone {
  /// The exhibit [id] at grid cell ([gx], [gz]).
  const PlaygroundZone(this.id, this.gx, this.gz, this.title, this.hint);

  /// Blocks along a side.
  static const int size = 48;

  /// Blocks from the middle to a side.
  static const int half = size ~/ 2;

  /// The world x and z of the hub's middle, the grid's origin.
  static const int originX = 8, originZ = 8;

  /// What the playground keys it by (its build in the save, its creatures'
  /// tag).
  final String id;

  /// Its cell in the 3 x 3 grid, the hub at (0, 0), north at -1.
  final int gx, gz;

  /// The card's title.
  final String title;

  /// What to try there, the card's text.
  final String hint;

  /// The world x of its middle.
  int get cx => originX + gx * size;

  /// The world z of its middle.
  int get cz => originZ + gz * size;

  /// Whether the column at ([x], [z]) is in it.
  bool contains(double x, double z) => x >= cx - half && x < cx + half && z >= cz - half && z < cz + half;
}
