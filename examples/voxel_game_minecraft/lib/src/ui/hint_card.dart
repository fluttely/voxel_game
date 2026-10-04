import 'package:flutter/material.dart';

/// A card at the top of the screen telling the player what to try: a small
/// [label] in its [accent] colour, a [title], the [hint] under them, and a
/// button at the right when [action] is given. The tutorial's is gold
/// (`TutorialCard`); the playground's exhibits, blue.
class HintCard extends StatelessWidget {
  /// A card of [title] and [hint] under [label], edged in [accent].
  const HintCard({
    super.key,
    required this.label,
    required this.title,
    required this.hint,
    required this.accent,
    this.action,
  });

  /// The small line before the title (`Step 3/10`).
  final String label;

  /// What to try.
  final String title;

  /// How, in a line.
  final String hint;

  /// The edge's and the label's colour.
  final Color accent;

  /// A button's text and what it does, or null for none.
  final ({String text, VoidCallback onPressed})? action;

  /// The widest it grows.
  static const double width = 600.0;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(maxWidth: width),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xD10D121F),
          border: Border.all(color: accent, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$label   ', style: TextStyle(fontSize: 13, color: accent)),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 20, color: Colors.white)),
                ),
                if (action != null)
                  SizedBox(
                    height: 28,
                    child: OutlinedButton(
                      onPressed: action.onPressed,
                      child: Text(action.text, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(hint, style: const TextStyle(fontSize: 15, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
