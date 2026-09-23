import 'package:flutter/material.dart';

import '../game/playground.dart';

/// Stage 33: the playground's exhibit card — the exhibit's title and what to
/// try there, below the clock and the boss bar, for the first seconds after
/// the player walks into it (`Playground.cardSeconds`). Styled like the
/// tutorial card, in blue.
class ZoneCard extends StatelessWidget {
  const ZoneCard({super.key, required this.playground});

  final Playground playground;

  static const Color blue = Color.fromRGBO(115, 191, 255, 1);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playground,
      builder: (context, _) {
        final z = playground.current;
        if (z == null || !playground.cardVisible) return const SizedBox.shrink();
        return IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 84), // below the clock and the boss bar
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  width: 640,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(13, 18, 31, 0.82),
                    border: Border.all(color: blue, width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Text('Playground   ', style: TextStyle(fontSize: 13, color: blue)),
                        Text(z.title, style: const TextStyle(fontSize: 20, color: Colors.white)),
                      ]),
                      const SizedBox(height: 4),
                      Text(z.hint, style: const TextStyle(fontSize: 15, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
