import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let assetChannel = FlutterMethodChannel(name: "com.ats.team_assets", binaryMessenger: flutterViewController.engine.binaryMessenger)
    assetChannel.setMethodCallHandler { call, result in
      TeamAssetsFolderAccess.shared.handle(call, result: result)
    }

    title = "Automated Tournament Stream"
    minSize = NSSize(width: 760, height: 560)
    let screenSize = screen?.visibleFrame.size ?? NSSize(width: 1280, height: 900)
    setContentSize(NSSize(width: min(1240, screenSize.width - 80),
                          height: min(820, screenSize.height - 80)))
    center()
    titlebarAppearsTransparent = true
    backgroundColor = NSColor.windowBackgroundColor

    super.awakeFromNib()
  }
}
