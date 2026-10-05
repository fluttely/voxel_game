import 'package:flutter/material.dart';

import '../core/voxel_game.dart';
import '../input/input_device.dart';
import 'hud_selector.dart';

/// The death screen (`DeathScreen`): the player is dead until Respawn, which
/// wakes once `PlayerSpec.respawnDelay` has passed. A keyboard or a pad
/// stands up with jump. The world keeps running behind it.
class DeathMenu extends StatelessWidget {
  /// The death screen of [game].
  const DeathMenu(this.game, {super.key});

  /// The game.
  final VoxelGame game;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0x88600000),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'You died',
            style: TextStyle(
              fontSize: 36,
              color: Colors.white,
              shadows: [Shadow(offset: Offset(1, 1), blurRadius: 2)],
            ),
          ),
          const SizedBox(height: 24),
          HudSelector(
            frames: game.frames,
            select: () => (ready: game.canRespawn, fingers: game.input.lastDevice == InputDevice.touch),
            builder: (context, s) => Column(
              children: [
                FilledButton(onPressed: s.ready ? game.respawn : null, child: const Text('Respawn')),
                if (!s.fingers) ...[const SizedBox(height: 8), const Text('or jump')],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
