import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Forward the process arguments to Dart's main(args) so the screenshot
    // probe (--screenshot=<png> --frames=N --seed=N ...) works like the
    // Godot POC's `-- --flag` convention.
    let project = FlutterDartProject()
    project.dartEntrypointArguments = Array(CommandLine.arguments.dropFirst())
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Voxel Minecraft (Flutter)"
    // Never restore a saved frame: the size comes from the nib (1600x900) and
    // the app delegate, and the probe's exit(0) would otherwise pin a stale one.
    self.isRestorable = false

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
