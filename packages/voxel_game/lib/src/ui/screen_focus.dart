import 'package:flutter/material.dart';

/// What makes a screen workable by a pad and the keys ([FocusBridge]) once
/// it is open: a [FocusScope] of its own, so the widget it opens on (an
/// `autofocus`) takes the focus from the game's, and the scope itself takes
/// it when none does, so the first direction lands on the widget that way;
/// directional navigation ([NavigationMode.directional]), so up and down
/// leave a slider and a disabled button can hold the focus until it wakes;
/// and a [ring] around the focused Material button, which the stock overlay
/// draws too faintly to find across a room.
///
/// `GameSurface` puts each screen it opens in one, a game's own included.
class ScreenFocus extends StatefulWidget {
  /// The screen [child].
  const ScreenFocus({super.key, required this.child});

  /// The screen.
  final Widget child;

  /// What the focused button is outlined with.
  static const BorderSide ring = BorderSide(color: Colors.white, width: 2);

  @override
  State<ScreenFocus> createState() => _ScreenFocusState();
}

class _ScreenFocusState extends State<ScreenFocus> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'ScreenFocus');

  @override
  void initState() {
    super.initState();
    // An autofocus inside is applied after this, in the same pass, and wins:
    // it finds the scope with no focused child.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
      child: Theme(
        data: theme.copyWith(
          filledButtonTheme: FilledButtonThemeData(style: _ringed(theme.filledButtonTheme.style)),
          outlinedButtonTheme: OutlinedButtonThemeData(style: _ringed(theme.outlinedButtonTheme.style)),
          textButtonTheme: TextButtonThemeData(style: _ringed(theme.textButtonTheme.style)),
          elevatedButtonTheme: ElevatedButtonThemeData(style: _ringed(theme.elevatedButtonTheme.style)),
        ),
        child: FocusScope(node: _scope, child: widget.child),
      ),
    );
  }

  // The game's own button theme, with the ring over its side while focused.
  static ButtonStyle _ringed(ButtonStyle? style) {
    final side = style?.side;
    return (style ?? const ButtonStyle()).copyWith(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? ScreenFocus.ring : side?.resolve(states),
      ),
    );
  }
}
