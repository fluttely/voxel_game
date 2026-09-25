/// A voxel sandbox in a few lines: declare blocks, world generation, the
/// player and mobs in a [VoxelGameSpec] and run it. The kit over voxel_engine,
/// voxel_scene and sound_recipes; it re-exports the parts of voxel_engine and
/// sound_recipes a game declares with, so a game imports this one library.
library;

export 'package:flutter_scene/scene.dart' show AntiAliasingMode;

export 'package:sound_recipes/sound_recipes.dart'
    show MusicDirector, SilentSounds, SoundBank, SoundFamily, SoundPlayer, SoundRecipe, StockSounds;
export 'package:voxel_engine/content.dart';
export 'package:voxel_engine/core.dart' show BlockShape, IVec3;
export 'package:voxel_engine/worldgen.dart'
    show
        Biome,
        CaveSpec,
        Climate,
        Ore,
        Plant,
        StructureSite,
        StructureSpec,
        TerrainRecipe,
        TreeShape,
        TreeSpec,
        WorldGenSpec;

export 'src/camera/shoulder_orbit.dart';
export 'src/camera/view_bob.dart';
export 'src/camera/view_camera.dart';
export 'src/core/voxel_game.dart';
export 'src/entities/game_entity.dart';
export 'src/entities/item_pickup.dart';
export 'src/entities/projectile.dart';
export 'src/entities/target.dart';
export 'src/input/input_map.dart';
export 'src/input/voxel_action.dart';
export 'src/loop/fixed_step_loop.dart';
export 'src/loop/frame_stats.dart';
export 'src/mobs/behaviors.dart';
export 'src/mobs/goal.dart';
export 'src/mobs/mob.dart';
export 'src/mobs/mob_spec.dart';
export 'src/mobs/rig.dart';
export 'src/mobs/rig_animator.dart';
export 'src/mobs/spawner.dart';
export 'src/player/character_motor.dart';
export 'src/player/player_entity.dart';
export 'src/player/player_spec.dart';
export 'src/spec/graphics_spec.dart';
export 'src/spec/sky_spec.dart';
export 'src/spec/voxel_game_spec.dart';
export 'src/world/game_world.dart';
export 'src/ui/default_hud.dart';
export 'src/ui/voxel_game_widget.dart';
export 'src/ui/inventory_screen.dart';
export 'src/world/world_save.dart';
export 'src/camera/first_person_view.dart';
export 'src/spec/sound_spec.dart';

export 'package:voxel_engine/signals.dart'
    show SignalNetwork, SignalReaction, SignalReactions, SignalRules, RailGraph, RailVariant;

export 'src/spec/signal_spec.dart';
export 'src/net/remote_player.dart';
export 'src/net/sessions.dart';
