import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // The Godot POC ran at 1600x900; open as close to that as the screen allows.
    if let window = mainFlutterWindow, let screen = window.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      let w = min(1600.0, visible.width - 40)
      let h = min(900.0, visible.height - 40)
      window.setContentSize(NSSize(width: w, height: h))
      window.center()
    }
  }
}
