import 'package:flutter_scene/scene.dart';
import 'package:voxel_engine/core.dart';

/// voxel_core's [VoxelBody] with a scene node that carries its visuals: move
/// the body, then [syncNode].
class NodeBody extends VoxelBody {
  /// The node the body's model hangs under; add it to the scene.
  final Node node = Node();

  /// Gone from the world; whoever owns the body drops it at the end of the
  /// frame.
  bool removed = false;

  /// Pushes the position into [node]. Call after moving.
  void syncNode() => node.position = position.clone();
}
