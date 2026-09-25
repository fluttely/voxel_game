import 'package:flutter/material.dart';

import '../core/voxel_game.dart';

/// The kit's HUD: a crosshair, the hotbar with counts, health, how far the
/// aimed block is mined, and "click to play" while the mouse is free. Pass
/// your own `HudBuilder` to replace it, or build on its pieces.
class DefaultHud extends StatelessWidget {
  /// The HUD of [game].
  const DefaultHud(this.game, {super.key});

  /// A `HudBuilder` of this HUD.
  static Widget builder(BuildContext context, VoxelGame game) => DefaultHud(game);

  /// The game shown.
  final VoxelGame game;

  static Color _color(double r, double g, double b) =>
      Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());

  @override
  Widget build(BuildContext context) {
    final p = game.player;
    final inv = p.inventory;
    const shadow = [Shadow(offset: Offset(1, 1), blurRadius: 2)];
    return Stack(
      children: [
        if (p.hurtFlash > 0.0)
          Positioned.fill(
            child: ColoredBox(color: Colors.red.withValues(alpha: 0.35 * p.hurtFlash)),
          ),
        const Center(child: Icon(Icons.add, color: Colors.white70, size: 22)),
        if (p.mineProgress > 0.0)
          Align(
            alignment: const Alignment(0, 0.12),
            child: SizedBox(
              width: 60,
              height: 4,
              child: LinearProgressIndicator(value: p.mineProgress, backgroundColor: Colors.black38),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < (p.spec.hp / 2).ceil(); i++)
                      Icon(
                        p.hp >= (i + 1) * 2
                            ? Icons.favorite
                            : (p.hp > i * 2 ? Icons.heart_broken : Icons.favorite_border),
                        color: Colors.redAccent,
                        size: 18,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < inv.hotbarSize; i++)
                      Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          border: Border.all(
                            color: i == p.selectedSlot ? Colors.white : Colors.white24,
                            width: i == p.selectedSlot ? 3 : 1,
                          ),
                        ),
                        child: inv.isEmptySlot(i)
                            ? null
                            : Stack(
                                children: [
                                  Center(
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      color: () {
                                        final t = game.items[inv.idAt(i)];
                                        return _color(t.r, t.g, t.b);
                                      }(),
                                    ),
                                  ),
                                  if (inv.countAt(i) > 1)
                                    Positioned(
                                      right: 3,
                                      bottom: 1,
                                      child: Text(
                                        '${inv.countAt(i)}',
                                        style: const TextStyle(fontSize: 12, shadows: shadow),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                  ],
                ),
                if (!inv.isEmptySlot(p.selectedSlot))
                  Text(game.items[p.heldItem].name, style: const TextStyle(fontSize: 13, shadows: shadow)),
              ],
            ),
          ),
        ),
        if (!game.input.wantCapture)
          const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 80),
              child: Text(
                'Click to play  -  WASD move, Space jump, mouse look, left mine, right place, V view, Esc free the mouse',
                style: TextStyle(fontSize: 14, shadows: shadow),
              ),
            ),
          ),
        if (p.isDead)
          const Center(
            child: Text(
              'You died',
              style: TextStyle(fontSize: 36, color: Colors.redAccent, shadows: shadow),
            ),
          ),
      ],
    );
  }
}
