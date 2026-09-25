import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
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
    stats.addFrame(simMs: 0.5, steps: 1);
    stats.addFrame(simMs: 1.5, steps: 2);
    stats.addEncode(1.0);
    stats.addGpu(12.0);
    stats.addGpuLag(1);
    final report = stats.stopRecording();
    expect(report.buildMs, [2.0, 2.0, 2.0, 2.0, 9.0]);
    expect(report.rasterMs.every((r) => r == 1.0), isTrue);
    expect(report.intervalMs.length, 4);
    expect(report.hitches(1000 / 60), 1);
    expect(report.steps, 3);
    expect(report.gpuMs, [12.0]);
    expect(stats.recording, isFalse);
    final json = report.toJson(1000 / 60);
    expect(json['frames'], 5);
    expect((json['buildMs'] as Map)['max'], 9.0);
  });

  test('stopping without starting is a mistake', () {
    expect(() => FrameStats().stopRecording(), throwsStateError);
  });

  test('copyWith replaces only what it is given', () {
    const spec = VoxelGameSpec(blocks: [BlockType('stone', color: 0x808080)], world: WorldGenSpec(biomes: [Biome('plain', top: 'stone')]), seed: 7);
    final far = spec.copyWith(renderDistance: 12);
    expect(far.renderDistance, 12);
    expect(far.seed, 7);
    expect(far.blocks, same(spec.blocks));
    expect(far.world, same(spec.world));
  });
}
