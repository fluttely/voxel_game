import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:vector_math/vector_math.dart';

/// What the frames cost, measured where each cost is paid.
///
/// Flutter's [FrameTiming]s give the frames that reached the screen: the gap
/// between the vsyncs that started two frames (the frame rate the player
/// sees), the UI thread's build and the raster thread's composite. The build
/// holds all of the kit's work, because flutter_scene records its GPU commands
/// on the UI thread, inside paint; the kit adds the two halves of it it owns,
/// the simulation ([addFrame]'s `simMs`) and the scene's encoding (`encodeMs`),
/// and how long a scene frame waited and ran on the GPU (`gpuLatencyMs`,
/// `gpuLagFrames`). The camera each frame drew with ([addView]) says how evenly
/// the view moved, which none of the timings can: a frame presented on time may
/// show the same view as the one before.
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

  /// One tick of the kit's own: [seconds] since the last one, [simMs] in
  /// `VoxelGame.frame`, [steps] fixed steps run.
  void addFrame({required double seconds, required double simMs, required int steps}) {
    _recentFrames.add(_clock.elapsedMicroseconds);
    final r = _recording;
    if (r == null) return;
    r.simMs.add(simMs);
    if (steps > 0) r.stepMs.add(simMs / steps);
    r.steps += steps;
    r.tickSeconds = seconds;
    r.viewed = false;
  }

  /// How far in front of the eye a view's travel is weighed: a point this many
  /// metres ahead moves on screen by about the angle the eye's travel subtends.
  static const double viewDepth = 10.0;

  /// The camera the last tick drew with: its [eye] and unit [forward]. The
  /// first view of a tick counts, so a camera built twice in one tick moved
  /// once.
  void addView(Vector3 eye, Vector3 forward) {
    final r = _recording;
    if (r == null || r.viewed) return;
    r.viewed = true;
    final lastEye = r.lastEye, lastForward = r.lastForward;
    if (lastEye != null && lastForward != null && r.tickSeconds > 0.0) {
      final turn = math.atan2(lastForward.cross(forward).length, lastForward.dot(forward));
      r.viewMotion.add(turn + lastEye.distanceTo(eye) / viewDepth);
      r.viewSeconds.add(r.tickSeconds);
    }
    r.lastEye = eye.clone();
    r.lastForward = forward.clone();
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
  double tickSeconds = 0.0;
  bool viewed = false;
  Vector3? lastEye, lastForward;
  final List<double> intervalMs = [],
      buildMs = [],
      rasterMs = [],
      simMs = [],
      stepMs = [],
      encodeMs = [],
      gpuLatencyMs = [],
      gpuLagFrames = [],
      viewMotion = [],
      viewSeconds = [];

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
    viewMotion: viewMotion,
    viewSeconds: viewSeconds,
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
    required this.viewMotion,
    required this.viewSeconds,
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

  /// How far the view moved each tick: the angle its forward turned, plus its
  /// eye's travel over [FrameStats.viewDepth].
  final List<double> viewMotion;

  /// How long each tick of [viewMotion] took.
  final List<double> viewSeconds;

  /// The view's mean speed: all its motion over all its time; 0 for a view
  /// that did not move.
  double get _viewSpeed {
    var motion = 0.0, time = 0.0;
    for (var i = 0; i < viewMotion.length; i++) {
      motion += viewMotion[i];
      time += viewSeconds[i];
    }
    return motion < 1e-6 ? 0.0 : motion / time;
  }

  /// How unevenly the view moved: the root mean square, over the ticks, of each
  /// tick's speed against the mean speed, minus one. 0 for a view that moved by
  /// exactly the time each tick took; about 1 for one that moved every other
  /// tick (a 60 Hz step drawn at 120 Hz). Null for a view that did not move.
  double? get viewJudder {
    final mean = _viewSpeed;
    if (mean == 0.0) return null;
    var sum = 0.0;
    for (var i = 0; i < viewMotion.length; i++) {
      final e = viewMotion[i] / viewSeconds[i] / mean - 1.0;
      sum += e * e;
    }
    return math.sqrt(sum / viewMotion.length);
  }

  /// Ticks whose view moved less than a quarter of its mean speed: shown still,
  /// or nearly. Null for a view that did not move.
  int? get stillFrames {
    final mean = _viewSpeed;
    if (mean == 0.0) return null;
    var n = 0;
    for (var i = 0; i < viewMotion.length; i++) {
      if (viewMotion[i] / viewSeconds[i] < mean * 0.25) n++;
    }
    return n;
  }

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
    if (viewJudder case final judder?) 'view': {'judder': _round(judder), 'stillFrames': stillFrames!},
  };
}
