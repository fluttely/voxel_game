import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Stage 30: the credits — engine, fonts, audio, lineage, then every stage of
/// the roadmap — scrolling up from the bottom. Esc (or the button) closes it.
///
/// Godot reads `res://ROADMAP.md` through `FileAccess`. A Flutter app has no
/// project folder at runtime, so this project's `ROADMAP.md` is declared as a
/// plain asset in `pubspec.yaml` (no build hook) and read with
/// `rootBundle.loadString`; the unit test parses the same file from disk.
class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key, required this.onClosed, this.startSeconds = 0.0});
  final VoidCallback onClosed;

  /// A probe capture starts part-way through the scroll.
  final double startSeconds;

  static const String roadmapAsset = 'ROADMAP.md';
  static const double speed = 42.0; // px per second

  /// Every `| N | title ...` row of the roadmap's stage table, as
  /// "Stage N — title": the bold lead when the row has one, else the stage cell
  /// cut at its first sentence.
  static List<String> parseStages(String text) {
    final row = RegExp(r'^\|\s*(\d+[ab]?)\s*\|\s*(.+?)\s*\|');
    final bold = RegExp(r'^\*\*(.+?)\*\*');
    final out = <String>[];
    for (final line in text.split('\n')) {
      final m = row.firstMatch(line);
      if (m == null) continue;
      final cell = m.group(2)!;
      final b = bold.firstMatch(cell);
      var title = b != null ? b.group(1)! : cell.split('. ').first.split(' (').first;
      if (title.endsWith('.')) title = title.substring(0, title.length - 1);
      out.add('Stage ${m.group(1)} — $title');
    }
    return out;
  }

  static Future<List<String>> loadStages() async => parseStages(await rootBundle.loadString(roadmapAsset));

  static List<String> creditsLines(List<String> stages) => [
        'VOXEL MINECRAFT', '', 'a Minecraft clone built on voxel_game, made to be played', '',
        'Engine', 'Flutter + flutter_scene 0.23 (Flutter GPU / Impeller), Dart ${Platform.version.split(' ').first}',
        'Dart for the game, a pool of isolates for chunk generation and meshing', '',
        'Fonts', 'the system fallback font (no font files)', '',
        'Music and sound', 'music and footsteps from Dawnforge (the 2D game): the Cozy Games pack and "Rites of Passage"', 'every other sound procedural, rendered in Dart, all played through SoLoud', '',
        'Lineage', 'the Godot POC (GDScript + C#), ported file by file; before it, the dev_3d_spike probe', '',
        'Stages',
        ...stages,
        '', '', 'Thanks for playing.', '', 'Esc closes',
      ];

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> with SingleTickerProviderStateMixin {
  static const TextStyle _style = TextStyle(fontSize: 20, height: 1.45, color: Colors.white);

  late final Ticker _ticker;
  final FocusNode _focus = FocusNode(debugLabel: 'credits');

  /// The scroll clock. It is a notifier and not a field behind `setState`
  /// because only the moving text should be rebuilt sixty times a second: when
  /// the whole screen was rebuilt instead, the Back button's own subtree was
  /// replaced under every press and the button never fired (Esc, which does not
  /// go through a gesture, always worked — which is what made it look like a
  /// button that simply did nothing).
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0.0);
  List<String> _lines = CreditsScreen.creditsLines(const []);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _seconds.value = widget.startSeconds;
    CreditsScreen.loadStages().then((stages) {
      if (mounted) setState(() => _lines = CreditsScreen.creditsLines(stages));
    });
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      _seconds.value += dt;
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _lines.join('\n');
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClosed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: const Color.fromRGBO(8, 10, 20, 0.92),
        child: LayoutBuilder(builder: (context, box) {
          // How tall the roll is, measured rather than read back off the laid
          // out Text: a widget has no business asking another widget's render
          // object for its size while layout is still running.
          final painter = TextPainter(
            text: TextSpan(text: text, style: _style),
            textAlign: TextAlign.center,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: box.maxWidth);
          // Up from the bottom edge; once the last line has left the top, again.
          final travel = box.maxHeight + painter.height;
          painter.dispose();
          return Stack(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: _seconds,
                builder: (context, seconds, child) => Positioned(
                  left: 0,
                  right: 0,
                  top: box.maxHeight - (seconds * CreditsScreen.speed) % travel,
                  child: child!,
                ),
                child: Text(text, textAlign: TextAlign.center, style: _style),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: SizedBox(width: 120, height: 36, child: FilledButton(onPressed: widget.onClosed, child: const Text('Back (Esc)'))),
              ),
            ],
          );
        }),
      ),
    );
  }
}
