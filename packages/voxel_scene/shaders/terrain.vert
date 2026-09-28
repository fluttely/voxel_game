// The terrain's vertex stage: flutter_scene 0.23's `flutter_scene_unskinned_body.glsl`
// over the 16-byte vertex voxel_scene's PackedSurface writes instead of the engine's
// 72-byte one. Two streams of two 32-bit words:
//
//   slot 0  packed_position    x | z << 16,  y             1/256 m from the region's corner
//   slot 1  packed_attributes  r | g << 8 | b << 16 | a << 24
//                              nx | ny << 8 | nz << 16 | sky << 24 | block << 28
//
// rgb is the square root of the linear colour, alpha as it is; the normal is biased by
// 128 in 1/127 steps; the light levels are 0..15 and leave as texture_coords_1
// (level / 15), where terrain.frag reads them. The outputs are the engine's standard
// varyings, so any material's fragment stage shades the terrain. The model transform
// arrives as the engine's 80-byte instance record in the slot after the streams (2).
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
in uvec2 packed_attributes;

in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;
in vec4 instance_color;

void main() {
  mat4 model_transform = mat4(model_transform_0, model_transform_1,
                              model_transform_2, model_transform_3);
  vec3 world_position =
      (model_transform * vec4(UnpackPosition(packed_position), 1.0)).xyz;
  uint word = packed_attributes.y;
  vec3 normal = vec3(UnpackBiased8(word), UnpackBiased8(word >> 8u),
                     UnpackBiased8(word >> 16u));
  uint colour = packed_attributes.x;
  vec3 rgb = vec3(float(colour & 0xFFu), float((colour >> 8u) & 0xFFu),
                  float((colour >> 16u) & 0xFFu)) /
             255.0;

  v_position = world_position;
  vec3 draw_position = ApplyDepthBias(
      world_position, frame_info.camera_position, frame_info.depth_bias);
  gl_Position = frame_info.camera_transform * vec4(draw_position, 1.0);
  v_viewvector = frame_info.camera_position - world_position;
  v_normal = mat3(model_transform) * normal;
  v_texture_coords = vec2(0.0);
  v_texture_coords_1 =
      vec2(float((word >> 24u) & 0xFu), float(word >> 28u)) / 15.0;
  v_color = vec4(rgb * rgb, float(colour >> 24u) / 255.0) * instance_color;
  v_tangent = vec4(0.0);
}
