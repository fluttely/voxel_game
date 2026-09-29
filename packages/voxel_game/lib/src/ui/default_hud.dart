import 'package:flutter/material.dart';

import '../core/voxel_game.dart';
import 'hud_selector.dart';

/// The kit's HUD: a crosshair, the hotbar with counts, health, how far the
/// aimed block is mined, and "click to play" while the mouse is free. Pass
/// your own `HudBuilder` to replace it, or build on its pieces.
///
/// It is built once; each piece that changes is a [HudSelector] on
/// [VoxelGame.frames], rebuilt only when the value it reads changes.
class DefaultHud extends StatelessWidget {
  /// The HUD of [game].
  const DefaultHud(this.game, {super.key});

  /// A `HudBuilder` of this HUD.
  static Widget builder(BuildContext context, VoxelGame game) => DefaultHud(game);

  /// The game shown.
  final VoxelGame game;

  static const _shadow = [Shadow(offset: Offset(1, 1), blurRadius: 2)];

  static Color _color(double r, double g, double b) =>
      Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());

  @override
  Widget build(BuildContext context) {
    final p = game.player;
    final inv = p.inventory;
    final frames = game.frames;
    return Stack(
      children: [
        Positioned.fill(
          child: HudSelector(
            frames: frames,
            select: () => p.hurtFlash,
            builder: (context, flash) =>
                flash > 0.0 ? ColoredBox(color: Colors.red.withValues(alpha: 0.35 * flash)) : const SizedBox.shrink(),
          ),
        ),
        const Center(child: Icon(Icons.add, color: Colors.white70, size: 22)),
        Align(
          alignment: const Alignment(0, 0.12),
          child: HudSelector(
            frames: frames,
            select: () => p.mineProgress,
            builder: (context, progress) => progress > 0.0
                ? SizedBox(
                    width: 60,
                    height: 4,
                    child: LinearProgressIndicator(value: progress, backgroundColor: Colors.black38),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HudSelector(
                  frames: frames,
                  select: () => p.hp,
                  builder: (context, hp) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < (p.spec.hp / 2).ceil(); i++)
                        Icon(
                          hp >= (i + 1) * 2
                              ? Icons.favorite
                              : (hp > i * 2 ? Icons.heart_broken : Icons.favorite_border),
                          color: Colors.redAccent,
                          size: 18,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < inv.hotbarSize; i++)
                      HudSelector(
                        frames: frames,
                        select: () => (id: inv.idAt(i), count: inv.countAt(i), selected: i == p.selectedSlot),
                        builder: (context, slot) => _slot(slot.id, slot.count, selected: slot.selected),
                      ),
                  ],
                ),
                HudSelector(
                  frames: frames,
                  select: () => inv.isEmptySlot(p.selectedSlot) ? null : game.items[p.heldItem].name,
                  builder: (context, name) => name == null
                      ? const SizedBox.shrink()
                      : Text(name, style: const TextStyle(fontSize: 13, shadows: _shadow)),
                ),
              ],
            ),
          ),
        ),
        HudSelector(
          frames: frames,
          select: () => game.input.wantCapture,
          builder: (context, captured) => captured
              ? const SizedBox.shrink()
              : const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Text(
                      'Click to play  -  WASD move, Space jump, mouse look, left mine, right place, V view, Esc free the mouse',
                      style: TextStyle(fontSize: 14, shadows: _shadow),
                    ),
                  ),
                ),
        ),
        HudSelector(
          frames: frames,
          select: () => p.isDead,
          builder: (context, dead) => dead
              ? const Center(
                  child: Text(
                    'You died',
                    style: TextStyle(fontSize: 36, color: Colors.redAccent, shadows: _shadow),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// A hotbar slot holding [count] of item [id] (`''` for an empty one).
  Widget _slot(String id, int count, {required bool selected}) => Container(
    width: 44,
    height: 44,
    margin: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Colors.black45,
      border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1),
    ),
    child: id.isEmpty
        ? null
        : Stack(
            children: [
              Center(
                child: Container(
                  width: 24,
                  height: 24,
                  color: () {
                    final t = game.items[id];
                    return _color(t.r, t.g, t.b);
                  }(),
                ),
              ),
              if (count > 1)
                Positioned(
                  right: 3,
                  bottom: 1,
                  child: Text('$count', style: const TextStyle(fontSize: 12, shadows: _shadow)),
                ),
            ],
          ),
  );
}
