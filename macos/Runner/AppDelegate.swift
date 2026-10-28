import Cocoa
import FlutterMacOS

final class TeamAssetsFolderAccess {
  static let shared = TeamAssetsFolderAccess()
  private let bookmarkKey = "ats.documentsFolderBookmark"
  private var documentsURL: URL?

  private init() {
    restoreBookmark()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "restoreFolder":
      result(folderURL()?.path)
    case "chooseDocumentsFolder":
      chooseDocumentsFolder(result: result)
    case "openFolder":
      guard let path = (call.arguments as? [String: Any])?["path"] as? String,
            !path.isEmpty else {
        result(FlutterError(code: "folder_not_set", message: "Choose the Documents folder first.", details: nil))
        return
      }
      let folder = URL(fileURLWithPath: path, isDirectory: true)
      NSWorkspace.shared.open(folder)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func chooseDocumentsFolder(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Choose your Documents folder"
    panel.message = "ATS will create an ATS folder here for the team roster and images."
    panel.prompt = "Use Documents folder"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    guard panel.runModal() == .OK, let selected = panel.url else {
      result(nil)
      return
    }
    do {
      stopAccess()
      documentsURL = selected
      guard selected.startAccessingSecurityScopedResource() else {
        documentsURL = nil
        result(FlutterError(code: "folder_access", message: "macOS did not grant access to that folder.", details: nil))
        return
      }
      let bookmark = try selected.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
      UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
      let folder = try makeFolder(in: selected)
      result(folder.path)
    } catch {
      stopAccess()
      result(FlutterError(code: "folder_setup", message: error.localizedDescription, details: nil))
    }
  }

  private func restoreBookmark() {
    guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
    do {
      var stale = false
      let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
      guard url.startAccessingSecurityScopedResource() else { return }
      documentsURL = url
      if stale {
        let refreshed = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
      }
    } catch {
      documentsURL = nil
    }
  }

  private func folderURL() -> URL? {
    guard let documentsURL else { return nil }
    do { return try makeFolder(in: documentsURL) } catch { return nil }
  }

  private func makeFolder(in documents: URL) throws -> URL {
    let root = documents.appendingPathComponent("ATS", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("robot_images", isDirectory: true), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("team_photos", isDirectory: true), withIntermediateDirectories: true)
    let roster = root.appendingPathComponent("teams.csv")
    if !FileManager.default.fileExists(atPath: roster.path) {
      try "Team Number,Team Name,Organization\n".write(to: roster, atomically: true, encoding: .utf8)
    }
    return root
  }

  private func stopAccess() {
    documentsURL?.stopAccessingSecurityScopedResource()
    documentsURL = nil
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    _ = TeamAssetsFolderAccess.shared
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
