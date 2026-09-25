import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

/// What the frames cost, measured where each cost is paid.
///
/// Flutter's [FrameTiming]s give the frames that reached the screen: the gap
/// between the vsyncs that started two frames (the frame rate the player
/// sees), the UI thread's build and the raster thread's composite. The build
/// holds all of the kit's work, because flutter_scene records its GPU commands
/// on the UI thread, inside paint; the kit adds the two halves of it it owns,
/// the simulation ([addFrame]'s `simMs`) and the scene's encoding (`encodeMs`),
/// and how long a scene frame waited and ran on the GPU (`gpuLatencyMs`,
/// `gpuLagFrames`).
///
/// Always on and cheap: [fps] is a readout for a HUD. Between [startRecording]
/// and [stopRecording] every sample is kept, for a benchmark.
class FrameStats {
  final Stopwatch _clock = Stopwatch()..start();
  final List<int> _recentFrames = [];
  _Samples? _recording;

  /// Frames per second over the last half second of ticks.
  double get fps {
    final now = _clock.elapsedMicroseconds;
    _recentFrames.removeWhere((t) => now - t > 500000);
    return _recentFrames.length * 2.0;
  }

  /// Whether samples are being kept.
  bool get recording => _recording != null;

  /// Starts keeping every sample, dropping any earlier recording.
  void startRecording() => _recording = _Samples(_clock.elapsedMicroseconds);

  /// Stops keeping samples and summarises them.
  FrameReport stopRecording() {
    final r = _recording;
    if (r == null) throw StateError('FrameStats.stopRecording without startRecording');
    _recording = null;
    return r.report((_clock.elapsedMicroseconds - r.startUs) / 1e6);
  }

  /// Flutter's timings: `SchedulerBinding.instance.addTimingsCallback`.
  void addTimings(List<FrameTiming> timings) {
    final r = _recording;
    if (r == null) return;
    for (final t in timings) {
      final vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
      final last = r.lastVsyncUs;
      if (last != null) r.intervalMs.add((vsync - last) / 1000.0);
      r.lastVsyncUs = vsync;
      r.buildMs.add(t.buildDuration.inMicroseconds / 1000.0);
      r.rasterMs.add(t.rasterDuration.inMicroseconds / 1000.0);
    }
  }

  /// One tick of the kit's own: [simMs] in `VoxelGame.frame`, [steps] fixed
  /// steps run.
  void addFrame({required double simMs, required int steps}) {
    _recentFrames.add(_clock.elapsedMicroseconds);
    final r = _recording;
    if (r == null) return;
    r.simMs.add(simMs);
    if (steps > 0) r.stepMs.add(simMs / steps);
    r.steps += steps;
  }

  /// One scene frame encoded in [encodeMs].
  void addEncode(double encodeMs) => _recording?.encodeMs.add(encodeMs);

  /// A scene frame the GPU finished [ms] after its encoding ended.
  void addGpuLatency(double ms) => _recording?.gpuLatencyMs.add(ms);

  /// A scene frame the GPU finished [frames] ticks after it was submitted.
  void addGpuLag(int frames) => _recording?.gpuLagFrames.add(frames.toDouble());
}

class _Samples {
  _Samples(this.startUs);
  final int startUs;
  int? lastVsyncUs;
  int steps = 0;
  final List<double> intervalMs = [], buildMs = [], rasterMs = [], simMs = [], stepMs = [], encodeMs = [], gpuLatencyMs = [], gpuLagFrames = [];

  FrameReport report(double seconds) => FrameReport(
        seconds: seconds,
        steps: steps,
        intervalMs: intervalMs,
        buildMs: buildMs,
        rasterMs: rasterMs,
        simMs: simMs,
        stepMs: stepMs,
        encodeMs: encodeMs,
        gpuLatencyMs: gpuLatencyMs,
        gpuLagFrames: gpuLagFrames,
      );
}

/// The samples of one [FrameStats] recording.
class FrameReport {
  /// A report of [seconds] of samples.
  FrameReport({
    required this.seconds,
    required this.steps,
    required this.intervalMs,
    required this.buildMs,
    required this.rasterMs,
    required this.simMs,
    required this.stepMs,
    required this.encodeMs,
    required this.gpuLatencyMs,
    required this.gpuLagFrames,
  });

  /// How long the recording ran.
  final double seconds;

  /// Fixed simulation steps run.
  final int steps;

  /// Milliseconds between the vsyncs that started two presented frames.
  final List<double> intervalMs;

  /// The UI thread's share of each presented frame.
  final List<double> buildMs;

  /// The raster thread's share of each presented frame.
  final List<double> rasterMs;

  /// `VoxelGame.frame` per tick.
  final List<double> simMs;

  /// A fixed step's own cost: each tick that ran steps, its [simMs] over the
  /// steps it ran. [simMs] grows with the steps a slow frame banks (up to
  /// `FixedStepLoop.maxSteps`); this does not, so it is what a change to the
  /// simulation moves on a device that is behind.
  final List<double> stepMs;

  /// The scene's encoding per scene frame.
  final List<double> encodeMs;

  /// How long after the end of its encoding the GPU finished each scene frame:
  /// the frame's own work plus its wait behind the frames queued before it.
  /// Not the GPU's cost: when the GPU is the bottleneck the queue fills and this
  /// grows to several frames (see `MeasuredScene`).
  final List<double> gpuLatencyMs;

  /// Ticks between a scene frame's submission and the GPU finishing it.
  final List<double> gpuLagFrames;

  /// Frames presented per second.
  double get fps => buildMs.length / seconds;

  /// Presented frames that took longer than 1.5 [periodMs]: a frame the
  /// display showed twice.
  int hitches(double periodMs) => intervalMs.where((i) => i > periodMs * 1.5).length;

  /// The [p]th percentile (0..100) of [xs], nearest rank; 0 for no samples.
  static double percentile(List<double> xs, double p) {
    if (xs.isEmpty) return 0.0;
    final sorted = List.of(xs)..sort();
    final rank = (p / 100.0 * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  /// p50, p90, p99 and max of [xs], rounded to 0.01.
  static Map<String, double> spread(List<double> xs) => {
        'p50': _round(percentile(xs, 50)),
        'p90': _round(percentile(xs, 90)),
        'p99': _round(percentile(xs, 99)),
        'max': _round(xs.isEmpty ? 0.0 : xs.reduce(math.max)),
      };

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  /// The report as JSON, [periodMs] being the display's refresh period.
  Map<String, Object> toJson(double periodMs) => {
        'seconds': _round(seconds),
        'frames': buildMs.length,
        'fps': _round(fps),
        'stepsPerSecond': _round(steps / seconds),
        'hitches': hitches(periodMs),
        'intervalMs': spread(intervalMs),
        'buildMs': spread(buildMs),
        'rasterMs': spread(rasterMs),
        'simMs': spread(simMs),
        'stepMs': spread(stepMs),
        'encodeMs': spread(encodeMs),
        'gpuLatencyMs': spread(gpuLatencyMs),
        'gpuLagFrames': spread(gpuLagFrames),
      };
}
