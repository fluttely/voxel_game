import 'package:voxel_game/voxel_game.dart';

/// The player's heart, heard while its health is low ([isLow]): a beat at
/// once, then one every [period] seconds until the health is back over
/// [lowHealth] or the player is dead. The HUD's red edge pulses on the same
/// rule (`GameHud`).
class Heartbeat with GameSystem {
  /// The share of its most health under which the player's heart is heard.
  static const double lowHealth = 0.25;

  /// Seconds between two beats.
  static const double period = 0.9;

  /// Whether [player] is alive with its health under [lowHealth] of its most.
  static bool isLow(PlayerEntity player) => !player.isDead && player.hp < player.maxHp * lowHealth;

  double _next = 0.0;

  @override
  void tick(VoxelGame game, double dt) {
    if (!isLow(game.player)) {
      _next = 0.0;
      return;
    }
    _next -= dt;
    if (_next > 0.0) return;
    _next = period;
    game.playSound('heartbeat', volumeDb: -6.0);
  }
}
