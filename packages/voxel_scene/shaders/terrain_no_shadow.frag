// terrain.frag for a draw with no shadow atlas bound (flutter_scene's
// flutter_scene_standard_no_shadow.frag): the define compiles the cascade sampling out,
// with the shadow_map sampler, roughly halving the program.
#define FLUTTER_SCENE_SKIP_SHADOWS
#include <terrain.frag>
