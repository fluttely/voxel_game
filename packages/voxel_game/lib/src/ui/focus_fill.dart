import 'package:flutter/material.dart';

import 'screen_focus.dart';

/// Fills [child] with [ScreenFocus.fill] while the focus is on it or under
/// it: what a row that holds the focus with nothing to press needs to show
/// it. On a screen ([ScreenFocus] navigates directionally) every `InkWell`
/// takes the focus, a disabled one too — a `ListTile` with no `onTap`, a
/// recipe the bag cannot make yet — so a pad can stop on it and a list
/// scrolls under it; but Flutter paints a disabled `InkWell`'s focus fully
/// transparent, and the focus would be there unseen.
///
/// The fill is a `Material` of its own, so a `ListTile`'s background and
/// splashes, which paint on the nearest one, are drawn over it; it takes the
/// place of the child's own focus (its `focusColor` is cleared), so a row
/// that can be pressed is not filled twice.
class FocusFill extends StatelessWidget {
  /// The row [child], filled while it holds the focus.
  const FocusFill({super.key, required this.child});

  /// The row.
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    // A node of its own that never takes the focus, so it knows when one
    // under it does.
    canRequestFocus: false,
    skipTraversal: true,
    child: Builder(
      builder: (context) => Material(
        color: Focus.of(context).hasFocus ? ScreenFocus.fill : Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(focusColor: Colors.transparent),
          child: child,
        ),
      ),
    ),
  );
}
