/// The kind of device a player is playing with, as [InputMap.lastDevice]
/// reports it: what a HUD shows its hints and its on-screen controls for.
enum InputDevice {
  /// A keyboard, a mouse or a trackpad (a stylus reads as a mouse too).
  keyboardMouse,

  /// A gamepad.
  gamepad,

  /// A finger on the screen.
  touch,
}
