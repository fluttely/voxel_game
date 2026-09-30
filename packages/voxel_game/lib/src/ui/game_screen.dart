import 'package:voxel_engine/core.dart' show IVec3;

/// What is open over the world: `VoxelGame.screen` holds one, or null while
/// the player plays. Every screen gates the controls, never the world: the
/// game keeps stepping behind each one (a hosted session is authoritative).
///
/// The states and how they change are the game's (`VoxelGame.openScreen`,
/// `closeScreen`, `respawn`); `GameSurface` shows each as its widget.
///
/// | From | To | On |
/// |:---|:---|:---|
/// | none | [BagScreen] | a press of inventory; use on a station |
/// | none | [StorageScreen] | use on a block with a `storage` |
/// | none | [PauseScreen] | a press of pause; the pointer lost |
/// | none | [DeclaredScreen] | the game's code; a button in the game menu |
/// | [BagScreen], [StorageScreen] | none | a press of inventory or pause; its close button |
/// | [PauseScreen], [DeclaredScreen] | none | a press of pause; its own buttons |
/// | [StorageScreen] | none | its block broken |
/// | any | [DeathScreen] | the player dies |
/// | [DeathScreen] | none | a respawn, and only that |
sealed class GameScreen {
  const GameScreen();
}

/// The bag, and crafting in the hand or at a [station].
final class BagScreen extends GameScreen {
  /// The bag, crafting at [station] (`''`, the default, for the hand).
  const BagScreen({this.station = ''});

  /// The block crafted at, a station some recipe names; `''` in the hand.
  final String station;

  @override
  bool operator ==(Object other) => other is BagScreen && other.station == station;

  @override
  int get hashCode => Object.hash(BagScreen, station);
}

/// The store of the block at [cell] beside the bag. Only the authority opens
/// one: a client's would be its own copy of what the host keeps.
final class StorageScreen extends GameScreen {
  /// The store at [cell].
  const StorageScreen(this.cell);

  /// Where the block that stores stands.
  final IVec3 cell;

  @override
  bool operator ==(Object other) => other is StorageScreen && other.cell == cell;

  @override
  int get hashCode => Object.hash(StorageScreen, cell);
}

/// The game menu: resume, the game's own screens (`ScreenSpec.menu`), quit.
final class PauseScreen extends GameScreen {
  /// The game menu.
  const PauseScreen();

  @override
  bool operator ==(Object other) => other is PauseScreen;

  @override
  int get hashCode => (PauseScreen).hashCode;
}

/// The player is dead. Only the player's death opens it, and only a respawn
/// (`VoxelGame.respawn`) closes it.
final class DeathScreen extends GameScreen {
  /// The death screen.
  const DeathScreen();

  @override
  bool operator ==(Object other) => other is DeathScreen;

  @override
  int get hashCode => (DeathScreen).hashCode;
}

/// A screen of the game's own, declared as `VoxelGameSpec.screens[id]`.
final class DeclaredScreen extends GameScreen {
  /// The game's screen [id].
  const DeclaredScreen(this.id);

  /// Its key in `VoxelGameSpec.screens`.
  final String id;

  @override
  bool operator ==(Object other) => other is DeclaredScreen && other.id == id;

  @override
  int get hashCode => Object.hash(DeclaredScreen, id);
}
