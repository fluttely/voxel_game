import 'package:voxel_engine/net.dart';

import '../core/voxel_game.dart';

/// What a message of a game's own does where it arrives
/// (`VoxelGameSpec.messages`, keyed by its type): on the host, a client's
/// ([from] its peer number); on a client, the host's ([from]
/// `GameSession.hostPeer`). Called as it arrives, between steps, with the
/// [message] the other side sent (`GameSession.sendToHost`, `broadcast`,
/// `sendTo`); never on the side that sent it.
typedef MessageHandler = void Function(VoxelGame game, int from, NetMessage message);
