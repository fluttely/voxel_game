// Lean twin of terrain.frag (flutter_scene's flutter_scene_standard_lean.frag): the
// define compiles out the lighting features a scene can leave off, which size the register
// allocation even unused, so the full program spills on mobile GPUs. TerrainMaterial picks
// it when the engine would pick its own lean entries (see FLUTTER_SCENE_LEAN_LIGHTING in
// flutter_scene's material_lighting.glsl).
#define FLUTTER_SCENE_LEAN_LIGHTING
#include <terrain.frag>
