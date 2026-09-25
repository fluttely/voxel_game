import 'dart:math' as math;

import 'wav.dart';

const double _tau = math.pi * 2;
double _sn(double v) => math.sin(v);
double _pw(double b, double e) => math.pow(b, e).toDouble();
double _rnd(math.Random r) => r.nextDouble() * 2.0 - 1.0;
double _half(math.Random r) => r.nextDouble() - 0.5;

/// The material families a block sounds like.
abstract final class SoundFamily {
  /// Rock, brick, ore.
  static const String stone = 'stone';

  /// Logs, planks, doors.
  static const String wood = 'wood';

  /// Dirt, grass, sand, gravel, snow.
  static const String earth = 'earth';

  /// Leaves, flowers, grass tufts, wool.
  static const String plant = 'plant';

  /// Glass, ice.
  static const String glass = 'glass';

  /// Iron, gold, machines.
  static const String metal = 'metal';

  /// Water, lava.
  static const String liquid = 'liquid';

  /// Every family.
  static const List<String> all = [stone, wood, earth, plant, glass, metal, liquid];
}

/// The kit's stock sounds, every one synthesised (the set the kit was first
/// played with, and footsteps made the same way). Per material family `break_<family>`,
/// `place_<family>` and `step_<family>`; and `dig`, `hit`, `hurt`, `pickup`,
/// `swing`, `shoot`, `splash`, `eat`, `click`, `door`, `levelup`, `explode`,
/// `thunder`, `heartbeat`, `hurt_small`, `hurt_large`, `hurt_undead`,
/// `hurt_flying`.
abstract final class StockSounds {
  /// Every stock recipe by name.
  static final Map<String, SoundRecipe> all = {
    'dig': SoundRecipe(0.08, (t, p, r) => _rnd(r) * (1.0 - p) * 0.5),
    'hit': SoundRecipe(0.12, (t, p, r) => (_sn(t * 90.0 * _tau) + _half(r)) * _pw(1.0 - p, 2.0) * 0.7),
    'hurt': SoundRecipe(0.25, (t, p, r) => _sn(t * (300.0 - p * 200.0) * _tau) * (1.0 - p) * 0.6),
    'pickup': SoundRecipe(0.15, (t, p, r) => _sn(t * (600.0 + p * 700.0) * _tau) * (1.0 - p) * 0.4),
    'levelup': SoundRecipe(
      0.6,
      (t, p, r) => _sn(t * const [440.0, 554.0, 659.0, 880.0][(p * 4.0).toInt().clamp(0, 3)] * _tau) * (1.0 - p) * 0.4,
    ),
    'swing': SoundRecipe(0.12, (t, p, r) => _rnd(r) * _sn(p * math.pi) * 0.25),
    'shoot': SoundRecipe(0.15, (t, p, r) => _sn(t * (900.0 - p * 600.0) * _tau) * (1.0 - p) * 0.35),
    'splash': SoundRecipe(0.3, (t, p, r) => _rnd(r) * _sn(p * math.pi) * 0.35),
    'eat': SoundRecipe(0.2, (t, p, r) => _rnd(r) * ((p * 6.0).toInt() % 2 == 0 ? 1.0 : 0.2) * 0.3 * (1.0 - p)),
    'click': SoundRecipe(0.04, (t, p, r) => _sn(t * 1200.0 * _tau) * (1.0 - p) * 0.3),
    'door': SoundRecipe(
      0.22,
      (t, p, r) => (_sn(t * (140.0 - p * 60.0) * _tau) * 0.6 + _half(r) * 0.3) * _sn(p * math.pi) * 0.5,
    ),
    'explode': SoundRecipe(
      0.9,
      (t, p, r) => (_rnd(r) * 0.8 + _sn(t * (60.0 - p * 30.0) * _tau) * 0.5) * _pw(1.0 - p, 2.0) * 0.9,
    ),
    'thunder': SoundRecipe(1.6, (t, p, r) => _rnd(r) * _pw(1.0 - p, 1.5) * (0.5 + 0.5 * _sn(t * 9.0 * _tau)) * 0.7),
    'heartbeat': SoundRecipe(0.32, (t, p, r) {
      final beat = _pw(math.max(1.0 - p * 4.0, 0.0), 2.0) + 0.7 * _pw(math.max(1.0 - (p - 0.45).abs() * 5.0, 0.0), 2.0);
      return _sn(t * 55.0 * _tau) * beat * 0.7;
    }),
    'hurt_small': SoundRecipe(0.14, (t, p, r) => _sn(t * (700.0 + p * 300.0) * _tau) * (1.0 - p) * 0.4),
    'hurt_large': SoundRecipe(
      0.35,
      (t, p, r) => (_sn(t * (140.0 - p * 60.0) * _tau) * 0.7 + _half(r) * 0.3) * (1.0 - p) * 0.6,
    ),
    'hurt_undead': SoundRecipe(
      0.30,
      (t, p, r) => (_sn(t * (180.0 - p * 90.0) * _tau) * _sn(t * 13.0 * _tau) + _half(r) * 0.4) * (1.0 - p) * 0.55,
    ),
    'hurt_flying': SoundRecipe(
      0.12,
      (t, p, r) => _sn(t * (1400.0 - p * 500.0) * _tau) * ((p * 8.0).toInt() % 2 == 0 ? 1.0 : 0.3) * (1.0 - p) * 0.35,
    ),
    'break_stone': SoundRecipe(
      0.20,
      (t, p, r) => (_rnd(r) * 0.7 + _sn(t * 160.0 * _tau) * 0.3) * _pw(1.0 - p, 2.0) * 0.8,
    ),
    'break_wood': SoundRecipe(
      0.22,
      (t, p, r) =>
          (_sn(t * 110.0 * _tau) * 0.5 + _rnd(r) * 0.4) *
          _pw(1.0 - p, 1.5) *
          ((p * 9.0).toInt() % 2 == 0 ? 1.0 : 0.4) *
          0.7,
    ),
    'break_earth': SoundRecipe(
      0.24,
      (t, p, r) => _rnd(r) * _pw(1.0 - p, 3.0) * 0.55 * (0.6 + 0.4 * _sn(t * 40.0 * _tau)),
    ),
    'break_metal': SoundRecipe(
      0.30,
      (t, p, r) =>
          (_sn(t * 880.0 * _tau) * 0.5 + _sn(t * 1320.0 * _tau) * 0.3 + _half(r) * 0.2) * _pw(1.0 - p, 2.5) * 0.6,
    ),
    'break_glass': SoundRecipe(
      0.28,
      (t, p, r) => (_sn(t * (2400.0 + _sn(t * 90.0) * 800.0) * _tau) * 0.5 + _rnd(r) * 0.5) * _pw(1.0 - p, 1.2) * 0.5,
    ),
    'break_plant': SoundRecipe(
      0.16,
      (t, p, r) => _rnd(r) * _sn(p * math.pi) * ((p * 14.0).toInt() % 3 != 0 ? 1.0 : 0.3) * 0.35,
    ),
    'break_liquid': SoundRecipe(
      0.26,
      (t, p, r) => _rnd(r) * _sn(p * math.pi) * (0.5 + 0.5 * _sn(t * 25.0 * _tau)) * 0.4,
    ),
    'place_stone': SoundRecipe(
      0.10,
      (t, p, r) => (_sn(t * 150.0 * _tau) * 0.7 + _half(r) * 0.3) * _pw(1.0 - p, 3.0) * 0.6,
    ),
    'place_wood': SoundRecipe(
      0.12,
      (t, p, r) => (_sn(t * 220.0 * _tau) * 0.6 + _sn(t * 95.0 * _tau) * 0.4) * _pw(1.0 - p, 3.0) * 0.6,
    ),
    'place_earth': SoundRecipe(0.12, (t, p, r) => _rnd(r) * _pw(1.0 - p, 4.0) * 0.45),
    'place_metal': SoundRecipe(
      0.16,
      (t, p, r) => (_sn(t * 660.0 * _tau) * 0.6 + _sn(t * 990.0 * _tau) * 0.3) * _pw(1.0 - p, 3.0) * 0.5,
    ),
    'place_glass': SoundRecipe(0.12, (t, p, r) => _sn(t * 1800.0 * _tau) * _pw(1.0 - p, 3.0) * 0.4),
    'place_plant': SoundRecipe(0.10, (t, p, r) => _rnd(r) * _sn(p * math.pi) * 0.25),
    'place_liquid': SoundRecipe(
      0.20,
      (t, p, r) => _rnd(r) * _sn(p * math.pi) * (0.6 + 0.4 * _sn(t * 18.0 * _tau)) * 0.35,
    ),
    'step_stone': SoundRecipe(
      0.09,
      (t, p, r) => (_rnd(r) * 0.5 + _sn(t * 120.0 * _tau) * 0.5) * _pw(1.0 - p, 5.0) * 0.35,
    ),
    'step_wood': SoundRecipe(
      0.10,
      (t, p, r) => (_sn(t * 90.0 * _tau) * 0.6 + _rnd(r) * 0.3) * _pw(1.0 - p, 4.0) * 0.35,
    ),
    'step_earth': SoundRecipe(
      0.10,
      (t, p, r) => _rnd(r) * _pw(1.0 - p, 4.0) * 0.35 * (0.6 + 0.4 * _sn(t * 60.0 * _tau)),
    ),
    'step_plant': SoundRecipe(
      0.12,
      (t, p, r) => _rnd(r) * _sn(p * math.pi) * ((p * 10.0).toInt() % 2 == 0 ? 1.0 : 0.5) * 0.22,
    ),
    'step_glass': SoundRecipe(
      0.07,
      (t, p, r) => (_sn(t * 1400.0 * _tau) * 0.6 + _rnd(r) * 0.4) * _pw(1.0 - p, 6.0) * 0.25,
    ),
    'step_metal': SoundRecipe(
      0.09,
      (t, p, r) => (_sn(t * 500.0 * _tau) * 0.7 + _half(r) * 0.3) * _pw(1.0 - p, 5.0) * 0.3,
    ),
    'step_liquid': SoundRecipe(
      0.16,
      (t, p, r) => _rnd(r) * _sn(p * math.pi) * (0.5 + 0.5 * _sn(t * 20.0 * _tau)) * 0.3,
    ),
  };
}
