import 'package:voxel_scene/voxel_scene.dart';

import '../core/blocks.dart';
import '../world/voxel_world.dart';

/// The POC's body: voxel_scene's [NodeBody] (VK1.5) plus what only this game
/// needs — the world it lives in typed as the POC's facade, and lava named as
/// a liquid kind.
class SceneBody extends NodeBody {
  late VoxelWorld world;

  @override
  void setup(covariant VoxelWorld q, double hw, double h) {
    world = q;
    super.setup(q, hw, h);
  }

  static final int _lava = Blocks.liquidKinds.indexOf('lava');

  /// Lava at the feet or the head.
  bool get inLava => feetLiquid == _lava || headLiquid == _lava;
}
