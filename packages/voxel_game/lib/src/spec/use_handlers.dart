import 'package:voxel_engine/core.dart';

import '../core/voxel_game.dart';
import '../mobs/mob.dart';

/// What a use on a block does in a game's own code (`VoxelGameSpec.blockUses`,
/// keyed by the block's name): a bed, a waypoint, an altar. Called once a
/// press of use, with the [cell] used; the block is used, not built against,
/// unless the player sneaks.
typedef BlockUse = void Function(VoxelGame game, IVec3 cell);

/// What a use on a creature does in a game's own code (`VoxelGameSpec.mobUses`,
/// keyed by the mob's id): a trade, a word. Called once a press of use, with
/// the living [mob] used; on a client it is the host's creature's replica,
/// and what the use does to it is the game's to send.
typedef MobUse = void Function(VoxelGame game, Mob mob);
