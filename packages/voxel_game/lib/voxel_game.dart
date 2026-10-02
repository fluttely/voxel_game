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
        Camp,
        CavernSpec,
        CaveSpec,
        Climate,
        Cover,
        CustomStructure,
        Dungeon,
        Mine,
        Ore,
        Plant,
        Pools,
        Precipitation,
        Ruins,
        Stratum,
        Structure,
        StructureSite,
        StructureSpec,
        TerrainRecipe,
        Tower,
        TreeShape,
        TreeSpec,
        Village,
        VillageFarm,
        Well,
        WorldGenSpec;

export 'src/camera/shoulder_orbit.dart';
export 'src/camera/view_bob.dart';
export 'src/camera/view_camera.dart';
export 'src/core/voxel_game.dart';
export 'src/entities/game_entity.dart';
export 'src/entities/item_pickup.dart';
export 'src/entities/projectile.dart';
export 'src/entities/target.dart';
export 'src/input/input_device.dart';
export 'src/input/input_map.dart';
export 'src/input/voxel_action.dart';
export 'src/loop/fixed_step_loop.dart';
export 'src/loop/frame_stats.dart';
export 'src/mobs/behaviors.dart';
export 'src/mobs/goal.dart';
export 'src/mobs/hit_effect.dart';
export 'src/mobs/mob.dart';
export 'src/mobs/mob_levels.dart';
export 'src/mobs/mob_spec.dart';
export 'src/mobs/mob_split.dart';
export 'src/mobs/mount_spec.dart';
export 'src/mobs/rig.dart';
export 'src/mobs/rig_animator.dart';
export 'src/mobs/spawn_place.dart';
export 'src/mobs/spawner.dart';
export 'src/player/character_motor.dart';
export 'src/player/hunger_spec.dart';
export 'src/player/player_entity.dart';
export 'src/player/player_spec.dart';
export 'src/player/xp_spec.dart';
export 'src/settings/game_settings.dart';
export 'src/settings/settings_store.dart';
export 'src/spec/graphics_spec.dart';
export 'src/spec/portal_spec.dart';
export 'src/spec/screen_spec.dart';
export 'src/spec/sky_spec.dart';
export 'src/spec/title_spec.dart';
export 'src/spec/weather_odds.dart';
export 'src/spec/weather_spec.dart';
export 'src/spec/touch_controls_spec.dart';
export 'src/spec/voxel_game_spec.dart';
export 'src/weather/weather.dart';
export 'src/weather/weather_kind.dart';
export 'src/world/game_world.dart';
export 'src/world/portals.dart';
export 'src/world/travel.dart';
export 'src/ui/credits_roll.dart';
export 'src/ui/damage_numbers.dart';
export 'src/ui/death_menu.dart';
export 'src/ui/default_hud.dart';
export 'src/ui/game_screen.dart';
export 'src/ui/game_surface.dart';
export 'src/ui/hud_selector.dart';
export 'src/ui/voxel_game_widget.dart';
export 'src/ui/inventory_screen.dart';
export 'src/ui/item_icon.dart';
export 'src/ui/loading_screen.dart';
export 'src/ui/loading_stage.dart';
export 'src/ui/notices.dart';
export 'src/ui/pause_menu.dart';
export 'src/ui/settings_menu.dart';
export 'src/ui/settings_panel.dart';
export 'src/ui/title_choice.dart';
export 'src/ui/title_screen.dart';
export 'src/ui/touch_controls.dart';
export 'src/ui/voxel_game_home.dart';
export 'src/ui/world_list.dart';
export 'src/world/world_info.dart';
export 'src/world/world_save.dart';
export 'src/camera/first_person_view.dart';
export 'src/spec/sound_spec.dart';

export 'package:voxel_engine/signals.dart'
    show SignalNetwork, SignalReaction, SignalReactions, SignalRules, RailGraph, RailVariant;

export 'src/spec/signal_spec.dart';
export 'src/net/remote_player.dart';
export 'src/net/sessions.dart';
