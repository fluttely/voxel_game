import 'package:flutter/material.dart';

import '../game/tutorial.dart';

/// Stage 30: the tutorial's card at the top of the screen — "Step N/10", the
/// title, the hint with the key to press, and the skip button (F6 does the
/// same). Godot draws it on the `Tutorial` autoload's own `CanvasLayer`; here
/// it is a widget over the HUD that rebuilds when the chain moves.
class TutorialCard extends StatelessWidget {
  const TutorialCard({super.key});

  static const Color gold = Color.fromRGBO(242, 204, 89, 1);

  @override
  Widget build(BuildContext context) {
    final t = Tutorial.instance;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final s = t.current;
        if (s == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: 600,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(13, 18, 31, 0.82),
                  border: Border.all(color: gold, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('Step ${t.index + 1}/${t.stepCount}   ', style: const TextStyle(fontSize: 13, color: gold)),
                        Text(s.title, style: const TextStyle(fontSize: 20, color: Colors.white)),
                        const Spacer(),
                        SizedBox(
                          height: 28,
                          child: OutlinedButton(
                            onPressed: t.skipAll,
                            child: const Text('Skip tutorial (F6)', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(s.hint, style: const TextStyle(fontSize: 15, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
