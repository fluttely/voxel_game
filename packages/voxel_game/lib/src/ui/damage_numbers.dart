import 'package:vector_math/vector_math.dart';

/// One number of [DamageNumbers]: [amount] dealt at [at] (world space),
/// shown for [age] seconds so far.
typedef DamageNumber = ({int id, Vector3 at, double amount, double age});

/// The damage dealt to creatures, as a HUD shows it over them: each hit a
/// number that rises [rise] metres over [riseSeconds] from where it landed
/// and fades from [fadeDelay] to [seconds].
///
/// Its clock is the frame's (`VoxelGame.frame` advances it), as
/// `Notices`' is.
class DamageNumbers {
  /// Seconds a number is shown.
  static const double seconds = 1.0;

  /// Seconds it rises for.
  static const double riseSeconds = 0.8;

  /// Metres it rises.
  static const double rise = 1.0;

  /// Seconds before it starts to fade.
  static const double fadeDelay = 0.2;

  /// The most shown at once; a new one pushes out the oldest.
  static const int kept = 24;

  final List<_Number> _numbers = [];
  int _nextId = 0;

  /// [amount] was dealt at [at]. Throws for an amount that is not above 0.
  void add(Vector3 at, double amount) {
    if (!(amount > 0.0)) throw ArgumentError.value(amount, 'amount', 'a hit deals some damage');
    _numbers.add(_Number(_nextId++, at.clone(), amount));
    if (_numbers.length > kept) _numbers.removeRange(0, _numbers.length - kept);
  }

  /// Ages every number by [dt] seconds and drops those past [seconds].
  void advance(double dt) {
    for (final n in _numbers) {
      n.age += dt;
    }
    _numbers.removeWhere((n) => n.age >= seconds);
  }

  /// The numbers shown, oldest first.
  List<DamageNumber> get shown => [for (final n in _numbers) (id: n.id, at: n.at, amount: n.amount, age: n.age)];

  /// How far a number [age] seconds old has risen, metres: fast, then easing.
  static double risenAt(double age) {
    final t = (age / riseSeconds).clamp(0.0, 1.0);
    return rise * (1.0 - (1.0 - t) * (1.0 - t));
  }

  /// How opaque a number [age] seconds old is, 1..0.
  static double opacityAt(double age) =>
      age < fadeDelay ? 1.0 : (1.0 - (age - fadeDelay) / (seconds - fadeDelay)).clamp(0.0, 1.0);

  /// [amount] as a HUD writes it: whole, or to a tenth under 10.
  static String label(double amount) {
    final whole = amount.roundToDouble();
    return (amount - whole).abs() < 0.05 || amount >= 10.0 ? '${whole.toInt()}' : amount.toStringAsFixed(1);
  }
}

class _Number {
  _Number(this.id, this.at, this.amount);

  final int id;
  final Vector3 at;
  final double amount;
  double age = 0.0;
}
