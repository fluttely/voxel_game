import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:voxel_game/voxel_game.dart';

import 'src/spec/game_spec.dart';
import 'src/spec/game_title.dart';
import 'src/ui/game_hud.dart';
import 'src/ui/title_vista.dart';

/// The game on the kit: its title (the credits read off the bundled roadmap)
/// over a world of its own, orbited to the meadow's music; the worlds made
/// there in the app's support folder (`worlds/`, with `settings.json` beside
/// it); and the kit's HUD with the game's own pieces on it.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final credits = creditsOf(await rootBundle.loadString(roadmapAsset));
  await runVoxelGame(
    gameSpec,
    title: 'Voxel Minecraft',
    menu: gameTitle(credits: credits, background: TitleVista.builder),
    hud: GameHud.builder,
  );
}
