import 'dart:math' as math;

/// A fixed simulation step under a variable frame rate: the frame time is
/// banked and spent in whole [step]s, at most [maxSteps] a frame so a hitch
/// does not become a spiral of catch-up.
class FixedStepLoop {
  /// A loop of [step] seconds.
  FixedStepLoop({this.step = 1 / 60, this.maxSteps = 4, this.maxFrame = 0.1});

  /// Seconds per simulation step.
  final double step;

  /// The most steps one frame may run.
  final int maxSteps;

  /// A longer frame counts as this long.
  final double maxFrame;

  double _bank = 0.0;

  /// Banks [dt] and runs [tick] once per whole step it covers; returns how
  /// many steps ran.
  int advance(double dt, void Function(double step) tick) {
    _bank += math.min(dt, maxFrame);
    var steps = 0;
    while (_bank >= step && steps < maxSteps) {
      tick(step);
      _bank -= step;
      steps++;
    }
    if (steps == maxSteps) _bank = math.min(_bank, step);
    return steps;
  }

  /// How far into the next step the bank is, 0..1: for smoothing a pose
  /// between two steps.
  double get alpha => (_bank / step).clamp(0.0, 1.0);
}
