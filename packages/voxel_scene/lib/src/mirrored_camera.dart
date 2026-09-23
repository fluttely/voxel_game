import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// A perspective camera for voxel_core's right-handed world.
///
/// voxel_core meshes wind clockwise seen from the face's normal side (+X east,
/// -Z north, +Y up). flutter_scene's view is left-handed: `PerspectiveCamera`
/// builds `right = up x forward`, so that world lands mirrored left-right and
/// every chunk face culls the wrong way. This camera negates clip-space x once,
/// and nothing else in the game needs to know.
///
/// What follows from the mirror:
/// - The sun's shadow pass is not mirrored, so a [SunLight] over voxel meshes
///   draws [shadowCasterFaces].
/// - flutter_scene's own primitives (`CuboidGeometry`, `SphereGeometry`) wind
///   for its native handedness; add them through [primitive] or
///   [primitiveNode], mirrored nodes the engine re-winds.
/// - `Camera.worldToScreen` and `getFrustum` read `getViewTransform`, so
///   screen projection and frustum culling follow the mirror.
/// - The engine's `cameraRight` (SSAO, SSR, GI, contact shadows, refraction)
///   disagrees with the view; those effects are not supported under it.
class MirroredCamera extends PerspectiveCamera {
  /// A camera at [position] looking at [target]; the lens is flutter_scene's
  /// perspective one with x mirrored.
  MirroredCamera({
    required Vector3 super.position,
    required Vector3 super.target,
    super.up,
    super.fovRadiansY,
    super.fovNear,
    super.fovFar,
  });

  /// The shadow caster faces for a [SunLight] over voxel meshes seen through
  /// this camera: the front faces, because the shadow pass is not mirrored.
  static const ShadowCasterFaces shadowCasterFaces = ShadowCasterFaces.front;

  @override
  CameraProjection get projection => MirroredProjection(fovRadiansY: fovRadiansY, near: fovNear, far: fovFar);

  /// [mesh] (an engine primitive, symmetric about its local x = 0) as a node
  /// mirrored in x, so its faces cull the right way under this camera. Move
  /// the returned node's parent, never its scale; [primitiveNode] builds one.
  static Node primitive(Mesh mesh, {bool castsShadows = true}) => Node(mesh: mesh)
    ..scale = Vector3(-1, 1, 1)
    ..castsShadows = castsShadows;

  /// A node holding [primitive] of [mesh], free to move, scale and rotate.
  static Node primitiveNode(Mesh mesh, {bool castsShadows = true}) =>
      Node()..add(primitive(mesh, castsShadows: castsShadows))..castsShadows = castsShadows;
}

/// flutter_scene's perspective lens with clip-space x negated. A
/// [PerspectiveProjection], because the shadow cascades cast the camera's
/// projection to one.
class MirroredProjection extends PerspectiveProjection {
  /// The mirrored lens with the same field of view and clip planes.
  MirroredProjection({required super.fovRadiansY, required super.near, required super.far});

  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) {
    final m = super.getProjectionMatrix(aspectRatio, jitter: jitter);
    m.setRow(0, -m.getRow(0));
    return m;
  }
}
