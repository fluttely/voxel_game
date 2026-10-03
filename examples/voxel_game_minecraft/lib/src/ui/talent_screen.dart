import 'package:flutter/material.dart';
import 'package:voxel_game/voxel_game.dart';

import '../classes/class_system.dart';
import '../classes/talent.dart';

/// The journal (J): the class's talents, a point from each level to spend
/// on one ([ClassSystem.learn]), each talent up to `Talent.maxRank`.
class TalentScreen extends StatefulWidget {
  /// The talents of [game]'s player.
  const TalentScreen(this.game, {super.key});

  /// A `ScreenBuilder` of this screen.
  static Widget builder(BuildContext context, VoxelGame game) => TalentScreen(game);

  /// The game whose player learns.
  final VoxelGame game;

  @override
  State<TalentScreen> createState() => _TalentScreenState();
}

class _TalentScreenState extends State<TalentScreen> {
  late final ClassSystem _classes = ClassSystem.of(widget.game);

  @override
  Widget build(BuildContext context) {
    final c = _classes;
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${c.playerClass.name} talents', style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 4),
                  Text('Talent points: ${c.points}   (you get one each level)'),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(child: Column(children: [for (final t in c.talents) _row(t)])),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: widget.game.closeScreen, child: const Text('Back to the game')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(Talent t) {
    final rank = _classes.rank(t.id);
    final maxed = rank >= Talent.maxRank;
    return ListTile(
      leading: CircleAvatar(backgroundColor: Color(0xFF000000 | t.color), radius: 14),
      title: Text('${t.name}  $rank/${Talent.maxRank}'),
      subtitle: Text(t.description),
      trailing: FilledButton(
        onPressed: maxed || _classes.points <= 0 ? null : () => setState(() => _classes.learn(t.id)),
        child: Text(maxed ? 'Maxed' : 'Learn'),
      ),
    );
  }
}
