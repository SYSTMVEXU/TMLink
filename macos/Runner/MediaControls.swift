import Cocoa
import Carbon
import FlutterMacOS

final class MediaControls {
  static let shared = MediaControls()

  private let scriptablePlayers: [(id: String, title: String)] = [
    ("com.spotify.client", "Spotify"),
    ("com.apple.Music", "Music"),
  ]
  private let tidalBundleID = "com.tidal.desktop"
  private let systemEventsBundleID = "com.apple.systemevents"

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let response: Any?
        switch call.method {
        case "requestPermission":
          response = try self.requestPermissions()
        case "pausePlaying":
          response = try self.pausePlaying()
        case "resumePlayers":
          let args = call.arguments as? [String: Any]
          let players = args?["players"] as? [String] ?? []
          try self.resume(players)
          response = nil
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(response) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "media_control_failed",
            message: "\(error.localizedDescription)",
            details: nil
          ))
        }
      }
    }
  }

  private func pausePlaying() throws -> [String] {
    var paused: [String] = []
    var failures = 0

    for player in scriptablePlayers where isRunning(player.id) {
      do {
        let output = try execute("""
        tell application id "\(player.id)"
          if player state is playing then
            pause
            return "paused"
          end if
          return "notPlaying"
        end tell
        """, targetBundleID: player.id)
        if output == "paused" { paused.append(player.id) }
      } catch {
        failures += 1
      }
    }

    if isRunning(tidalBundleID) {
      do {
        let output = try execute("""
        tell application "System Events"
          tell process "TIDAL"
            if exists menu "Playback" of menu bar 1 then
              set commandTitle to name of first menu item of menu "Playback" of menu bar 1
              if commandTitle is "Pause" then
                click first menu item of menu "Playback" of menu bar 1
                return "paused"
              end if
            end if
          end tell
        end tell
        return "notPlaying"
        """, targetBundleID: systemEventsBundleID)
        if output == "paused" { paused.append(tidalBundleID) }
      } catch {
        failures += 1
      }
    }

    if paused.isEmpty && failures > 0 {
      throw MediaControlError.permissionDenied
    }
    return paused
  }

  private func resume(_ players: [String]) throws {
    var failures = 0
    for playerID in players {
      do {
        if playerID == tidalBundleID {
          _ = try execute("""
          tell application "System Events"
            tell process "TIDAL"
              if exists menu "Playback" of menu bar 1 then
                set commandTitle to name of first menu item of menu "Playback" of menu bar 1
                if commandTitle is "Play" then
                  click first menu item of menu "Playback" of menu bar 1
                end if
              end if
            end tell
          end tell
          """, targetBundleID: systemEventsBundleID)
        } else if scriptablePlayers.contains(where: { $0.id == playerID }) {
          _ = try execute(
            "tell application id \"\(playerID)\" to play",
            targetBundleID: playerID
          )
        }
      } catch {
        failures += 1
      }
    }
    if failures > 0 { throw MediaControlError.permissionDenied }
  }

  private func isRunning(_ bundleID: String) -> Bool {
    NSWorkspace.shared.runningApplications.contains {
      $0.bundleIdentifier == bundleID
    }
  }

  private func requestPermissions() throws -> [String] {
    var targets = scriptablePlayers
      .filter { isInstalled($0.id) }
      .map { (id: $0.id, title: $0.title) }
    if isInstalled(tidalBundleID) {
      targets.append((id: systemEventsBundleID, title: "TIDAL via System Events"))
    }
    guard !targets.isEmpty else {
      throw MediaControlError.noSupportedPlayerInstalled
    }

    var checked: [String] = []
    var firstError: Error?
    for target in targets {
      do {
        try requestAutomationPermission(for: target.id)
        checked.append(target.title)
      } catch {
        if firstError == nil { firstError = error }
      }
    }
    if let firstError { throw firstError }
    return checked
  }

  private func isInstalled(_ bundleID: String) -> Bool {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
  }

  private func requestAutomationPermission(for bundleID: String) throws {
    let request = {
      let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
      return AEDeterminePermissionToAutomateTarget(
        target.aeDesc,
        AEEventClass(kAECoreSuite),
        AEEventID(kAEGetData),
        true
      )
    }
    let status = Thread.isMainThread
      ? request()
      : DispatchQueue.main.sync(execute: request)
    guard status == noErr else {
      throw MediaControlError.automationPermissionDenied(bundleID, status)
    }
  }

  private func execute(_ source: String, targetBundleID: String) throws -> String {
    try requestAutomationPermission(for: targetBundleID)
    guard let script = NSAppleScript(source: source) else {
      throw MediaControlError.scriptUnavailable
    }
    var error: NSDictionary?
    let output = script.executeAndReturnError(&error)
    if let error {
      let message = error["NSAppleScriptErrorMessage"] as? String
        ?? error.description
      let number = error["NSAppleScriptErrorNumber"] as? Int
      throw MediaControlError.scriptFailed(number, message)
    }
    return output.stringValue ?? ""
  }
}

private enum MediaControlError: Error {
  case permissionDenied
  case automationPermissionDenied(String, OSStatus)
  case noSupportedPlayerInstalled
  case scriptUnavailable
  case scriptFailed(Int?, String)
}

extension MediaControlError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return "macOS denied permission to control the music app. Open System Settings → Privacy & Security → Automation and allow ATS to control the music app."
    case let .automationPermissionDenied(bundleID, status):
      return "macOS did not authorize ATS to send Apple Events to \(bundleID) (OSStatus \(status)). If you previously denied access, allow ATS in System Settings → Privacy & Security → Automation."
    case .noSupportedPlayerInstalled:
      return "Install Apple Music, Spotify, or TIDAL before enabling match music automation so ATS can request permission."
    case .scriptUnavailable:
      return "ATS could not create the macOS music control script."
    case let .scriptFailed(number, message):
      let code = number.map { " (AppleScript error \($0))" } ?? ""
      return "macOS music control failed\(code): \(message)"
    }
  }
}
