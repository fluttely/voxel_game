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
    void tick(VoxelGame game, double dt) {}
    final spec = VoxelGameSpec(
      blocks: const [BlockType('stone', color: 0x808080)],
      world: const WorldGenSpec(biomes: [Biome('plain', top: 'stone')]),
      graphics: GraphicsSpec.phone,
      onTick: tick,
    );
    final bare = spec.copyWith(touchControls: () => null, onTick: () => null);
    expect(bare.touchControls, isNull);
    expect(bare.onTick, isNull);
    expect(bare.graphics, same(GraphicsSpec.phone));
    final kept = spec.copyWith(seed: 2);
    expect(kept.onTick, same(spec.onTick));
    expect(kept.touchControls, same(TouchControlsSpec.standard));
  });
}
