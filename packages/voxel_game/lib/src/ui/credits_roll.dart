import 'package:flutter/material.dart';

/// [lines] rolling up at [speed] pixels a second, from below the box to past
/// its top; a drag or the wheel moves them by hand. The first line is the
/// heading. Back leaves.
class CreditsRoll extends StatefulWidget {
  /// The credits [lines]; [onBack] leaves.
  const CreditsRoll({super.key, required this.lines, required this.onBack, this.speed = 40.0}) : assert(speed > 0);

  /// A line each; an empty one is a gap.
  final List<String> lines;

  /// Pixels a second.
  final double speed;

  /// Back to the menu.
  final VoidCallback onBack;

  @override
  State<CreditsRoll> createState() => _CreditsRollState();
}

class _CreditsRollState extends State<CreditsRoll> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _roll());
  }

  // Rolls to the end once the lines are laid out, and only once: a hand that
  // takes the scroll stops it.
  void _roll() {
    if (!mounted) return;
    final end = _scroll.position.maxScrollExtent;
    final seconds = end / widget.speed;
    _scroll.animateTo(
      end,
      duration: Duration(milliseconds: (seconds * 1000).round()),
      curve: Curves.linear,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Flexible(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            controller: _scroll,
            // The lines start below the box and leave past its top.
            padding: EdgeInsets.symmetric(vertical: box.maxHeight.isFinite ? box.maxHeight : 0),
            child: Column(
              children: [
                for (final (i, line) in widget.lines.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      line,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: i == 0 ? 24 : 15, fontWeight: i == 0 ? FontWeight.bold : null),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: OutlinedButton(onPressed: widget.onBack, child: const Text('Back')),
      ),
    ],
  );
}
