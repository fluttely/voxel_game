// The terrain's vertex stage: flutter_scene 0.24.3's `flutter_scene_unskinned_body.glsl`
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
// FrameInfo is the engine's own block, bound by the encoder for this shader as for its
// own unskinned one; there is no Vertex() hook, since no material variant reads this
// vertex.
//
// Compiled by `dart tool/build_shaders.dart` into assets/shaders/terrain.shaderbundle.
#include <material_vertex.glsl>

uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
  float depth_bias;
  // The draw's depth-layer offset (xy) and one instance tie-break rank's
  // (zw), see ApplyDepthOffset.
  vec4 depth_offset;
  // The same as slope-scaled offsets: x the draw's layer, z its tie-break
  // rank, y one instance rank's. See ApplySlopedDepthOffset.
  vec4 depth_slope;
}
frame_info;

#include <depth_bias.glsl>
#include <normal_transform.glsl>
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
  vec3 world_normal = WorldNormalMatrix(mat3(model_transform)) * normal;
  uint colour = packed_attributes.x;
  vec3 rgb = vec3(float(colour & 0xFFu), float((colour >> 8u) & 0xFFu),
                  float((colour >> 16u) & 0xFFu)) /
             255.0;

  v_position = world_position;
  vec3 draw_position = ApplyDepthBias(
      world_position, frame_info.camera_transform,
      frame_info.camera_position, frame_info.depth_bias);
  vec4 clip_position = frame_info.camera_transform * vec4(draw_position, 1.0);
  gl_Position = ApplySlopedDepthOffset(
      clip_position, frame_info.depth_offset, frame_info.depth_slope,
      model_transform_3.xyz, frame_info.camera_transform, draw_position,
      frame_info.camera_position, world_normal);
  v_viewvector = frame_info.camera_position - world_position;
  // Unit length before interpolation (UnitOrZero, normal_transform.glsl).
  v_normal = UnitOrZero(world_normal);
  v_texture_coords = vec2(0.0);
  v_texture_coords_1 =
      vec2(float((word >> 24u) & 0xFu), float(word >> 28u)) / 15.0;
  v_color = vec4(rgb * rgb, float(colour >> 24u) / 255.0) * instance_color;
  v_tangent = vec4(0.0);
}
