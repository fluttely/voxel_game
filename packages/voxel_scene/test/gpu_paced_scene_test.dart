import 'package:flutter_test/flutter_test.dart';
import 'package:voxel_scene/voxel_scene.dart';

void main() {
  test("flutter_scene's own GPU pacing is off (VDD5)", () {
    // ScenePacer is the pacing; flutter_scene's would re-present the last
    // image on a frame the scene renders and counts. A Scene needs a GPU to
    // be built, so the test reads the value the constructor sets.
    expect(GpuPacedScene.gpuFramesInFlight, 0);
  });
}
