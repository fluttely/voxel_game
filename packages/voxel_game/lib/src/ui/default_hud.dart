import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/voxel_game.dart';
import '../input/input_device.dart';
import '../input/voxel_action.dart';
import 'hud_selector.dart';

/// The kit's HUD: a crosshair, the hotbar with counts, health, how far the
/// aimed block is mined, and "click to play" while the mouse is free and no
/// screen is open (the death screen is one: `DeathMenu`). Pass
/// your own `HudBuilder` to replace it, or build on its pieces.
///
/// It is built once; each piece that changes is a [HudSelector] on
/// [VoxelGame.frames], rebuilt only when the value it reads changes.
///
/// **The hotbar is a finger's too**, unless the game declared no
/// `VoxelGameSpec.touchControls`. A tap on a slot picks it; a hold on the slot
/// in hand drops one of what it holds, after the spec's `dropHold`; and while
/// the last device was a finger, a `⋯` after the last slot opens the bag. Each
/// slot claims the finger that lands on it (`InputMap.claimTouch`), so that
/// finger is never also a tap on the world. A mouse over the hotbar is still
/// the world's: only a touch picks a slot. Every other piece is behind an
/// [IgnorePointer], so a touch there reaches whatever is under the HUD.
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
    final touch = game.spec.touchControls;
    assert(touch == null || touch.dropHold > Duration.zero, 'TouchControlsSpec.dropHold must be positive');
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              HudSelector(
                frames: frames,
                select: () => p.hurtFlash,
                builder: (context, flash) => flash > 0.0
                    ? ColoredBox(color: Colors.red.withValues(alpha: 0.35 * flash))
                    : const SizedBox.shrink(),
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
              HudSelector(
                frames: frames,
                select: () => (
                  hidden: game.input.wantCapture || game.screen.value != null,
                  touch: game.input.lastDevice == InputDevice.touch,
                ),
                builder: (context, s) => s.hidden
                    ? const SizedBox.shrink()
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Text(
                            s.touch
                                ? 'Tap to play'
                                : 'Click to play  -  WASD move, Space jump, mouse look, left mine, right place, V view, E bag, Esc menu',
                            style: const TextStyle(fontSize: 14, shadows: _shadow),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IgnorePointer(
                  child: HudSelector(
                    frames: frames,
                    select: () => p.hp,
                    builder: (context, hp) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < (p.maxHp / 2).ceil(); i++)
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
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < inv.hotbarSize; i++)
                      HudSelector(
                        frames: frames,
                        select: () => (id: inv.idAt(i), count: inv.countAt(i), selected: i == p.selectedSlot),
                        builder: (context, slot) {
                          final face = _slot(slot.id, slot.count, selected: slot.selected);
                          if (touch == null) return face;
                          return _touchable(
                            onTap: () => game.input.touchDigit(i),
                            onHold: slot.selected
                                ? (after: touch.dropHold, run: () => game.input.touchPress(VoxelAction.drop))
                                : null,
                            child: face,
                          );
                        },
                      ),
                    if (touch != null)
                      HudSelector(
                        frames: frames,
                        select: () => game.input.lastDevice == InputDevice.touch,
                        builder: (context, fingers) => fingers
                            ? _touchable(
                                onTap: () => game.input.touchPress(VoxelAction.inventory),
                                child: _box(
                                  selected: false,
                                  child: const Icon(Icons.more_horiz, color: Colors.white, size: 24),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
                IgnorePointer(
                  child: HudSelector(
                    frames: frames,
                    select: () => inv.isEmptySlot(p.selectedSlot) ? null : game.items[p.heldItem].name,
                    builder: (context, name) => name == null
                        ? const SizedBox.shrink()
                        : Text(name, style: const TextStyle(fontSize: 13, shadows: _shadow)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// [child] answering a finger: [onTap] on a tap, and [onHold]'s `run` once
  /// the finger has stayed its `after` (when given). The finger is claimed as
  /// it lands, so the world never reads it; a mouse passes through to the
  /// world.
  Widget _touchable({
    required VoidCallback onTap,
    ({Duration after, VoidCallback run})? onHold,
    required Widget child,
  }) {
    const touch = {PointerDeviceKind.touch};
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.touch) game.input.claimTouch(e.pointer);
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(supportedDevices: touch),
            (r) => r.onTap = onTap,
          ),
          if (onHold != null)
            LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: onHold.after, supportedDevices: touch),
              (r) => r.onLongPress = onHold.run,
            ),
        },
        child: child,
      ),
    );
  }

  /// A hotbar slot holding [count] of item [id] (`''` for an empty one).
  Widget _slot(String id, int count, {required bool selected}) => _box(
    selected: selected,
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

  /// The square every hotbar cell is drawn in, lit while [selected].
  static Widget _box({required bool selected, Widget? child}) => Container(
    width: 44,
    height: 44,
    margin: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Colors.black45,
      border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1),
    ),
    child: child,
  );
}
