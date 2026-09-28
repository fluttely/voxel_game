// The words of voxel_scene's packed terrain vertex, shared by terrain.vert and
// terrain_depth.vert. See terrain.vert for the layout.

// A packed position (x | z << 16, y) in metres from the region's corner.
vec3 UnpackPosition(uvec2 words) {
  return vec3(float(words.x & 0xFFFFu), float(words.y & 0xFFFFu),
              float(words.x >> 16u)) /
         256.0;
}

// The low byte of [word], a component in -1..1 biased by 128 in 1/127 steps.
float UnpackBiased8(uint word) {
  return (float(word & 0xFFu) - 128.0) / 127.0;
}
