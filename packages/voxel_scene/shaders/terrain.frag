// Stage 31: the terrain's lit surface, Godot's terrain.gdshader + terrain_light.gdshaderinc.
//
// This is flutter_scene 0.23's `flutter_scene_standard.frag` with one change in Surface():
// the mesher writes block tint x face tint x AO into the vertex colour and the two light
// levels into texture_coords_1 (x = sky / 15, y = block / 15); the sky half is scaled by
// `sky_intensity` (1.0 noon, 0.35 night, 0.0 underworld, set once per frame by the game),
// the brighter of the two wins, and the level goes through Godot's fourth-power curve.
// The albedo is multiplied by that light and an `emission_mix` share of the lit albedo is
// added as emission, so a torch-lit wall reads at night when the sun and the ambient are
// almost off. Everything else (the sun with its cascaded shadows, the constant-diffuse
// ambient, the sky-coloured fog) is the engine's own lighting, bound by
// PhysicallyBasedMaterial.bind: that is why the file keeps every declaration and texture
// read of the standard shader (a sampler the compiler strips but the material still binds
// by name would crash the draw).
//
// Compiled by `dart tool/build_shaders.dart` into assets/shaders/terrain.shaderbundle.
#include <material_varyings.glsl>
#include <normals.glsl>
#include <pbr.glsl>
#include <texture.glsl>
#include <material_engine_lighting.glsl>
#include <material_inputs.glsl>
#include <material_lighting.glsl>
#include <lod_fade.glsl>

uniform sampler2D base_color_texture;
uniform sampler2D emissive_texture;
uniform sampler2D metallic_roughness_texture;
uniform sampler2D normal_texture;
uniform sampler2D occlusion_texture;

uniform TextureTransforms {
  vec4 base_color_transform;
  vec4 base_color_rotation;
  vec4 metallic_roughness_transform;
  vec4 metallic_roughness_rotation;
  vec4 normal_transform;
  vec4 normal_rotation;
  vec4 emissive_transform;
  vec4 emissive_rotation;
  vec4 occlusion_transform;
  vec4 occlusion_rotation;
}
texture_transforms;

// Godot's two shader uniforms. std140: two floats, padded to 8 bytes.
uniform TerrainInfo {
  float sky_intensity;
  float emission_mix;
}
terrain_info;

// A block-sandbox light map, replacing Godot's 0.02 + 0.98 * level^4 (which left a
// moonlit field almost black once ACES had its toe on it).
//   brightness(l) = l / (4 - 3 l)                    l = level / 15
//   sky factor    = 0.24 at night .. 1.0 at noon     (0.2 * 0.95 + 0.05)
//   value         = min(sky * factor + block, 1)
//   gamma 0.5     = mix(v, 1 - (1 - v)^4, 0.5)       (the default brightness)
//   floor         = v * 0.96 + 0.03                  (a cave is never pure black)
// The usual light map multiplies the sRGB texture by that value; the albedo here is linear,
// so the value is raised to 2.2 before it multiplies.
// sky_intensity arrives as the game's own scale (0.35 night, 1.0 noon, 0.0 in
// the underworld) and is mapped onto the light map's 0.24 .. 1.0 sky factor.
float McBrightness(float l) {
  return l / (4.0 - 3.0 * l);
}

float TerrainLight(vec2 uv1) {
  float s = terrain_info.sky_intensity;
  float sky_factor = s >= 0.35 ? mix(0.24, 1.0, (s - 0.35) / 0.65)
                               : s / 0.35 * 0.24;
  float v = min(McBrightness(uv1.x) * sky_factor + McBrightness(uv1.y), 1.0);
  float inv = 1.0 - v;
  v = mix(v, 1.0 - inv * inv * inv * inv, 0.5);
  v = v * 0.96 + 0.03;
  return pow(v, 2.2);
}

void Surface(inout MaterialInputs material) {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  bool transformed_uvs = texture_transforms.base_color_rotation.w > 0.5;
  vec2 base_color_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.base_color_transform,
            texture_transforms.base_color_rotation)
      : GetUV0();
  vec4 base_color_srgb = texture(base_color_texture, base_color_uv);
  float light = TerrainLight(GetUV1());
  vec3 albedo = SRGBToLinear(base_color_srgb.rgb) * vertex_color.rgb *
                frag_info.color.rgb * light;
  float alpha = base_color_srgb.a * vertex_color.a * frag_info.color.a;
  if (frag_info.alpha_mode == 1.0) {
    if (alpha < frag_info.alpha_cutoff) {
      discard;
    }
    alpha = 1.0;
  }
  material.base_color = vec4(albedo, alpha);

  vec3 normal = GetWorldNormal();
  if (frag_info.has_normal_map > 0.5) {
    vec2 normal_uv = transformed_uvs
        ? MaterialTextureUv(
              texture_transforms.normal_transform,
              texture_transforms.normal_rotation)
        : GetUV0();
    normal = PerturbNormal(normal_texture, normal, v_viewvector,
                           normal_uv, frag_info.normal_scale);
  }
  material.normal = normal;

  vec2 metallic_roughness_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.metallic_roughness_transform,
            texture_transforms.metallic_roughness_rotation)
      : GetUV0();
  vec4 metallic_roughness =
      texture(metallic_roughness_texture, metallic_roughness_uv);
  material.metallic = clamp(metallic_roughness.b * frag_info.metallic_factor,
                            0.0, 1.0);
  material.roughness =
      clamp(metallic_roughness.g * frag_info.roughness_factor, kMinRoughness,
            1.0);

  vec2 occlusion_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.occlusion_transform,
            texture_transforms.occlusion_rotation)
      : GetUV0();
  float occlusion = texture(occlusion_texture, occlusion_uv).r;
  material.occlusion = 1.0 - (1.0 - occlusion) * frag_info.occlusion_strength;

  vec2 emissive_uv = transformed_uvs
      ? MaterialTextureUv(
            texture_transforms.emissive_transform,
            texture_transforms.emissive_rotation)
      : GetUV0();
  material.emissive = SRGBToLinear(texture(emissive_texture, emissive_uv).rgb) *
                      frag_info.emissive_factor.rgb *
                      frag_info.emissive_factor.a +
                      albedo * terrain_info.emission_mix;

  PrepareMaterial(material);
}

void main() {
  ApplyLodFade(frag_info.fade);
  MaterialInputs material = InitMaterialInputs();
  Surface(material);
  frag_color = EvaluateLighting(material);
}
