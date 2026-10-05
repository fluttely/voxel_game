import 'package:flutter/widgets.dart';

/// The other press of what the focus is on, as a right-click is a mouse's
/// beside its click ([ActivateIntent]): on a bag's slot it takes half of the
/// stack, or leaves one of the held stack (`InventoryScreen`).
///
/// `FocusBridge` invokes it for the pad's X and the X key, and only where
/// the focus has an action for it: anywhere else X is still the game's.
class SecondaryActivateIntent extends Intent {
  /// The other press.
  const SecondaryActivateIntent();
}
