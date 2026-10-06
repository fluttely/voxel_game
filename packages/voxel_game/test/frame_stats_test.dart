import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';
import 'package:voxel_game/voxel_game.dart';

/// A frame that started at [vsyncUs], built for [buildUs] and rastered for [rasterUs].
FrameTiming frame(int vsyncUs, {int buildUs = 2000, int rasterUs = 1000}) => FrameTiming(
  vsyncStart: vsyncUs,
  buildStart: vsyncUs,
  buildFinish: vsyncUs + buildUs,
  rasterStart: vsyncUs + buildUs,
  rasterFinish: vsyncUs + buildUs + rasterUs,
  rasterFinishWallTime: vsyncUs + buildUs + rasterUs,
);

void main() {
  test('percentile is the nearest rank, 0 for no samples', () {
    final xs = [for (var i = 1; i <= 100; i++) i.toDouble()];
    expect(FrameReport.percentile(xs, 50), 50.0);
    expect(FrameReport.percentile(xs, 99), 99.0);
    expect(FrameReport.percentile(xs, 100), 100.0);
    expect(FrameReport.percentile([7.0], 1), 7.0);
    expect(FrameReport.percentile([], 50), 0.0);
  });

  test('a recording keeps the frames between start and stop, and counts the ones shown twice', () {
    final stats = FrameStats();
    stats.addTimings([frame(0)]); // before the recording: dropped
    stats.startRecording();
    // Four frames at 60 Hz, then one that missed a vsync.
    stats.addTimings([frame(16667), frame(33333), frame(50000), frame(66667), frame(100000, buildUs: 9000)]);
    stats.addFrame(seconds: 1 / 60, simMs: 0.5, steps: 1);
    stats.addFrame(seconds: 1 / 60, simMs: 1.5, steps: 2);
    stats.addFrame(seconds: 1 / 60, simMs: 0.1, steps: 0); // ran no step: no step cost
    stats.addEncode(1.0);
    stats.addGpuLatency(12.0);
    stats.addGpuLag(1);
    final report = stats.stopRecording();
    expect(report.buildMs, [2.0, 2.0, 2.0, 2.0, 9.0]);
    expect(report.rasterMs.every((r) => r == 1.0), isTrue);
    expect(report.intervalMs.length, 4);
    expect(report.hitches(1000 / 60), 1);
    expect(report.steps, 3);
    expect(report.stepMs, [0.5, 0.75]);
    expect(report.gpuLatencyMs, [12.0]);
    expect((report.rendered, report.shown), (0, 0), reason: 'no scene painted');
    expect(stats.recording, isFalse);
    final json = report.toJson(1000 / 60);
    expect(json['frames'], 5);
    expect((json['buildMs'] as Map)['max'], 9.0);
  });

  test('the view: even motion reads 0, a view moved every other tick reads 1 and half its ticks still', () {
    FrameReport record(double Function(int tick) x) {
      final stats = FrameStats()..startRecording();
      for (var i = 0; i < 120; i++) {
        stats.addFrame(seconds: 1 / 120, simMs: 0.1, steps: i.isEven ? 1 : 0);
        stats.addView(Vector3(x(i), 0, 0), Vector3(0, 0, -1));
        stats.addView(Vector3(99, 0, 0), Vector3(0, 0, -1)); // built again in the tick: not a view
      }
      return stats.stopRecording();
    }

    final even = record((i) => i * 0.1);
    expect(even.viewMotion.length, 119, reason: 'the first view has nothing to move from');
    expect(even.viewJudder, closeTo(0.0, 1e-4));
    expect(even.stillFrames, 0);
    // The eye moves 0.2 m on the ticks that ran a step and stands on the others.
    final stepped = record((i) => (i ~/ 2) * 0.2);
    expect(stepped.viewJudder, closeTo(1.0, 0.01));
    expect(stepped.stillFrames, 60);
    expect((stepped.toJson(1000 / 120)['view'] as Map)['stillFrames'], 60);

    final turning = FrameStats()..startRecording();
    for (var i = 0; i < 10; i++) {
      turning.addFrame(seconds: 1 / 60, simMs: 0.1, steps: 1);
      turning.addView(Vector3.zero(), Vector3(-math.sin(i * 0.01), 0, -math.cos(i * 0.01)));
    }
    final turned = turning.stopRecording();
    expect(turned.viewMotion, everyElement(closeTo(0.01, 1e-6)), reason: 'a turn counts its angle');

    final still = FrameStats()..startRecording();
    still
      ..addFrame(seconds: 1 / 60, simMs: 0.1, steps: 1)
      ..addView(Vector3.zero(), Vector3(0, 0, -1))
      ..addFrame(seconds: 1 / 60, simMs: 0.1, steps: 1)
      ..addView(Vector3.zero(), Vector3(0, 0, -1));
    final report = still.stopRecording();
    expect(report.viewJudder, isNull, reason: 'a view that never moved is not judged');
    expect(report.toJson(1000 / 60).containsKey('view'), isFalse);
  });

  test("the readout is the scene's frames drawn, not the ticks", () {
    final stats = FrameStats();
    // A paced scene at 120 Hz: every tick runs, the world is drawn every other
    // one, and each Flutter frame shows the last frame finished.
    for (var i = 1; i <= 20; i++) {
      stats.addFrame(seconds: 1 / 120, simMs: 0.1, steps: i.isEven ? 1 : 0);
      stats.addScene(rendered: i ~/ 2, shown: i);
    }
    expect(stats.ticksPerSecond, 40.0, reason: 'twenty ticks in the last half second');
    expect(stats.fps, 20.0, reason: 'ten scene frames in it');
    // A hidden window: the timer ticks, nothing is painted.
    for (var i = 0; i < 10; i++) {
      stats.addFrame(seconds: 1 / 60, simMs: 0.1, steps: 1);
    }
    expect(stats.ticksPerSecond, 60.0);
    expect(stats.fps, 20.0, reason: 'a tick draws nothing');
    expect(FrameStats().fps, 0.0, reason: 'a headless game draws nothing');
  });

  test("a recording counts the scene frames rendered and shown from the scene's totals", () {
    final stats = FrameStats();
    stats.addScene(rendered: 5, shown: 6); // before the recording: not counted
    stats.startRecording();
    stats.addScene(rendered: 5, shown: 6); // a paint with nothing finished: nothing grew
    stats.addScene(rendered: 6, shown: 7);
    stats.addScene(rendered: 6, shown: 8); // the same frame shown again
    stats.addScene(rendered: 7, shown: 9);
    final report = stats.stopRecording();
    expect(report.rendered, 2);
    expect(report.shown, 3);
    expect(report.sceneFps, 2 / report.seconds);
    final json = report.toJson(1000 / 60);
    expect((json['rendered'], json['shown']), (2, 3));
    expect(json.containsKey('sceneFps'), isTrue);
    stats.startRecording();
    stats.addScene(rendered: 8, shown: 10);
    expect(stats.stopRecording().rendered, 1, reason: 'counted from the last totals, not from zero');
  });

  test('stopping without starting is a mistake', () {
    expect(() => FrameStats().stopRecording(), throwsStateError);
  });

  test('copyWith replaces only what it is given', () {
    const spec = VoxelGameSpec(
      blocks: [BlockType('stone', color: 0x808080)],
      world: WorldGenSpec(biomes: [Biome('plain', top: 'stone')]),
      seed: 7,
    );
    final far = spec.copyWith(renderDistance: 12);
    expect(far.renderDistance, 12);
    expect(far.seed, 7);
    expect(far.blocks, same(spec.blocks));
    expect(far.world, same(spec.world));
    expect(far.touchControls, same(TouchControlsSpec.standard));
  });

  test('copyWith can ask for null, and keeps a nullable field it is not given', () {
    const spec = VoxelGameSpec(
      blocks: [BlockType('stone', color: 0x808080)],
      world: WorldGenSpec(biomes: [Biome('plain', top: 'stone')]),
      graphics: GraphicsSpec.phone,
    );
    final bare = spec.copyWith(touchControls: () => null);
    expect(bare.touchControls, isNull);
    expect(bare.graphics, same(GraphicsSpec.phone));
    final plain = spec.copyWith(graphics: () => null);
    expect(plain.graphics, isNull);
    expect(plain.touchControls, same(TouchControlsSpec.standard));
    final kept = spec.copyWith(seed: 2);
    expect(kept.graphics, same(GraphicsSpec.phone));
    expect(kept.touchControls, same(TouchControlsSpec.standard));
  });
}
