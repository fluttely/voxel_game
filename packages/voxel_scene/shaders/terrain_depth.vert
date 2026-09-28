// The terrain's vertex stage for the depth-style passes (the sun's shadow cascades,
// the camera's depth prepass, the selection mask): flutter_scene 0.23's
// `flutter_scene_unskinned_depth_body.glsl` over terrain.vert's first stream only, the
// 8-byte packed position, and the model transform alone (64 bytes) in slot 1. The
// engine binds FrameInfo with the unskinned layout below. Every standard varying is
// written, as the engine's depth shader does, so the paired depth fragment shaders
// match; only v_position and v_viewvector carry data.
//
// Compiled by `dart tool/build_shaders.dart` into assets/shaders/terrain.shaderbundle.
#include <material_vertex.glsl>

uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
  float depth_bias;
}
frame_info;

#include <depth_bias.glsl>
#include <terrain_unpack.glsl>

in uvec2 packed_position;

in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;

void main() {
  mat4 model_transform = mat4(model_transform_0, model_transform_1,
                              model_transform_2, model_transform_3);
  vec3 world_position =
      (model_transform * vec4(UnpackPosition(packed_position), 1.0)).xyz;

  v_position = world_position;
  vec3 draw_position = ApplyDepthBias(
      world_position, frame_info.camera_position, frame_info.depth_bias);
  gl_Position = frame_info.camera_transform * vec4(draw_position, 1.0);
  v_viewvector = frame_info.camera_position - world_position;
  v_normal = vec3(0.0);
  v_texture_coords = vec2(0.0);
  v_texture_coords_1 = vec2(0.0);
  v_color = vec4(0.0);
  v_tangent = vec4(0.0);
}
