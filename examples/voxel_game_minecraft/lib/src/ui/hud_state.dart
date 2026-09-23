import 'dart:math' as math;

import '../core/items.dart';
import '../game/game.dart';
import '../game/sfx.dart';

/// Which map is on screen: none, the corner window or the full panel. M
/// steps through them in that order; there is never more than one.
enum MapView {
  off,
  corner,
  full;

  MapView get next => MapView.values[(index + 1) % MapView.values.length];
}

/// One pickup toast: [n] of [id], [t] seconds left, [since] the last merge.
class Toast {
  Toast(this.id, this.n);
  final String id;
  int n;
  double t = HudState.toastSeconds;
  double since = 0.0;
}

/// Stage 32: the HUD's own animated state (Godot's `hud.gd` `_process`). The
/// painter is stateless, so the vignette, the pickup toasts, the hotbar tween,
/// the low-health pulse, the XP tween and the boss bar's shake live here and
/// `Game.onFrame` advances them once per rendered frame.
class HudState {
  static const double vignetteSeconds = 0.4;
  static const double toastMergeSeconds = 1.0;
  static const double toastSeconds = 3.0;
  static const double lowHp = 0.25;
  static const double slotTweenSeconds = 0.08;

  double _vignette = 0.0; // the red hit vignette, 1 -> 0 over 0.4 s
  final List<Toast> toasts = [];
  double slotScale = 1.0; // the selected hotbar slot's scale (1.1 after its tween)
  int _lastSlot = -1;
  double _slotT = 1.0;
  double _heartbeat = 0.0;
  double _lowHpPulse = 0.0; // the pulsing vignette's alpha under 25% HP
  double? _xpShown; // the XP bar's tweened fill
  double _bossHpSeen = -1.0;
  double bossShake = 0.0;
  final math.Random _rng = math.Random();

  /// The player took a hit; the red vignette fades over 0.4 s.
  void onPlayerHurt() => _vignette = 1.0;

  double vignetteAlpha() => _vignette * 0.9 + _lowHpPulse;
  bool lowHpPulsing() => _lowHpPulse > 0.0;
  double xpShown(Game game) => _xpShown ?? game.player.xp / game.player.xpToNext();

  /// A pickup toast; a repeat of the same item within a second merges into it.
  void addPickup(String id, int n) {
    for (final t in toasts) {
      if (t.id == id && t.since < toastMergeSeconds) {
        t.n += n;
        t.t = toastSeconds;
        t.since = 0.0;
        return;
      }
    }
    toasts.add(Toast(id, n));
    if (toasts.length > 6) toasts.removeRange(0, toasts.length - 6);
  }

  List<String> toastTexts() => [for (final t in toasts) '+${t.n} ${Items.displayName(t.id)}'];

  /// A random jolt for the boss bar while it shakes (pixels, [k] the range).
  double shakeJitter(double k) => bossShake > 0.0 ? (_rng.nextDouble() * 2.0 - 1.0) * k * bossShake / 0.25 : 0.0;

  void update(double dt, Game game) {
    for (final t in toasts) {
      t.t -= dt;
      t.since += dt;
    }
    toasts.removeWhere((t) => t.t <= 0.0);
    _vignette = math.max(_vignette - dt / vignetteSeconds, 0.0);
    final player = game.player;
    // Under a quarter of the health the vignette pulses and the heart is heard.
    if (player.hp < player.maxHp * lowHp && !player.isDead) {
      _lowHpPulse = 0.35 + 0.2 * math.sin(DateTime.now().millisecondsSinceEpoch / 150.0);
      _heartbeat -= dt;
      if (_heartbeat <= 0.0) {
        _heartbeat = 0.9;
        Sfx.play('heartbeat', -6.0);
      }
    } else {
      _lowHpPulse = 0.0;
      _heartbeat = 0.0;
    }
    // The selected slot tweens 1.0 -> 1.1 over 80 ms (Godot: EASE_OUT on a
    // linear transition, which is linear).
    if (player.selectedSlot != _lastSlot) {
      _lastSlot = player.selectedSlot;
      _slotT = 0.0;
    }
    _slotT = math.min(_slotT + dt / slotTweenSeconds, 1.0);
    slotScale = 1.0 + 0.1 * _slotT;
    final xpRatio = player.xp / player.xpToNext();
    final shown = _xpShown ?? xpRatio;
    _xpShown = xpRatio < shown - 0.5 ? xpRatio : shown + (xpRatio - shown) * math.min(dt * 6.0, 1.0);
    final boss = game.boss;
    if (boss != null && !boss.removed) {
      if (_bossHpSeen >= 0.0 && boss.hp < _bossHpSeen) bossShake = 0.25;
      _bossHpSeen = boss.hp;
    } else {
      _bossHpSeen = -1.0;
    }
    bossShake = math.max(bossShake - dt, 0.0);
  }
}
