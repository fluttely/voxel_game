import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // The process arguments reach Dart's main, which is how the benchmark
    // (lib/benchmark.dart) is told what to run.
    let arguments = Array(CommandLine.arguments.dropFirst())
    let project = FlutterDartProject()
    project.dartEntrypointArguments = arguments
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // `--window=WxH` fixes the content size in points, so two benchmark runs
    // draw the same number of pixels.
    if let window = arguments.first(where: { $0.hasPrefix("--window=") }) {
      let size = window.dropFirst("--window=".count).split(separator: "x").compactMap { Double($0) }
      if size.count == 2 {
        self.setContentSize(NSSize(width: size[0], height: size[1]))
        self.center()
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
