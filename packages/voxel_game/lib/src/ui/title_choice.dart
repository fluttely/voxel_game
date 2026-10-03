/// What the player picked on the `TitleScreen`: the game `VoxelGameHome`
/// starts next.
sealed class TitleChoice {
  const TitleChoice();
}

/// A world of the list, played here, and hosted on [hostPort] when given.
final class PlayWorld extends TitleChoice {
  /// The world in [slot].
  const PlayWorld(this.slot, {this.hostPort});

  /// Its slot under `WorldSaves.directory`.
  final String slot;

  /// The port others join it on, or null for a world played alone.
  final int? hostPort;
}

/// Somebody else's world, joined at [address] with the [options] the join
/// form picked.
final class JoinHost extends TitleChoice {
  /// The host at [address] (`host` or `host:port`).
  const JoinHost(this.address, {this.options = const {}});

  /// Where the host is.
  final String address;

  /// The game's own choices this player joins with (`WorldOption.join`).
  final Map<String, String> options;
}
