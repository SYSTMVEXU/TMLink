# Automated Tournament Stream (ATS)

A desktop workspace that connects VEX Tournament Manager match queues and starts to OBS Studio preview and field scenes.

See [CHANGELOG.md](CHANGELOG.md) for the development history and validation results.

## Getting started

1. Enable the local API on your Tournament Manager server and obtain its local server API key. Official releases handle DWAB app authorization automatically.
2. In OBS, enable **Tools → WebSocket Server Settings**. Use the displayed port and password (the default address is `ws://localhost:4455/`).
3. Open **Connections** in ATS. Enter the TM host, local server API key, and OBS settings, then choose **Save & Connect**. Each service is checked independently; checking connections does not switch scenes.
4. Open **Scene Routing**, choose a field set, and assign an available OBS scene to every field. Changes save automatically. **Test** explicitly switches the live OBS program scene after confirmation.
5. Choose **Start monitoring**. **Stop monitoring** cancels queued switches. Connection failure, failed scene switching, or missing mapped scenes pauses monitoring; review the Activity log and reconnect before restarting.

When a match is queued, ATS updates the Upcoming Match scene and its team sources. When the match starts, ATS switches to the mapped field camera scene.

In **Upcoming Match preview**, set up the team asset folder once. ATS creates `Documents/ATS/teams.csv`, `Documents/ATS/robot_images/`, and `Documents/ATS/team_photos/`. ATS refreshes the team number, name, and organization in the CSV when it connects to TM. You can edit the CSV manually and choose **Refresh roster**. Add robot images named `{team-number}.png` and team photos named `{team-number}.jpg`; optional fallbacks are `default_robot.png` and `default_robot.jpg`. The **Photos** workspace offers search, filters, and image previews. macOS asks you to grant folder access once and remembers it.

Settings includes **Advanced user mode**. Basic mode keeps the match preview workspace streamlined; advanced mode exposes the division, match refresh, eliminations, and OBS input-name controls. On macOS, advanced settings can also pause supported Music, Spotify, and TIDAL players when a match starts, then resume only the players ATS paused when TM sends `matchStopped` at match end. Queuing and scoring matches do not resume music. macOS Automation approval is required, and TIDAL may also require Accessibility approval.

Routing is stored by TM server, field-set ID, and field ID. Prior positional mappings are migrated when the corresponding fields are loaded. Your selected field set is remembered per server. Unreadable routing can be reset after the original data is backed up. Missing/removed scenes are shown explicitly and prevent monitoring. The Activity log contains the latest 100 entries for the current session.

## Credentials

See [DWAB credentials and GitHub Actions](docs/credentials.md) for local setup,
GitHub environment secrets, obfuscated desktop release builds, encrypted debug
symbols, and credential rotation. Ordinary CI checks do not receive the DWAB credentials.

The TM API key and OBS password use the OS credential store (Keychain on macOS); connection addresses are stored with the app's settings. Legacy API keys, OBS passwords, and the previously unused TM password migrate from preferences only after the keychain write has been verified. If storage is unavailable, unlock the system keychain and retry. DWAB client credentials are not saved by the app or printed to its log.

Official release builds contain a masked DWAB credential pair that is decoded in memory and never copied into saved connection settings. A shared secret in a desktop binary remains recoverable despite obfuscation. An update notice appears before expiration, with a **Download update** action; expired app credentials block new TM connections. OAuth tokens stay in memory.

Debug builds use the launching process environment (`VEX_TM_CLIENT_ID` and `VEX_TM_CLIENT_SECRET`); official Release builds use the GitHub-built credential bundle. Finder launches usually do not inherit shell variables. Use `tool/run_debug.sh` for local macOS development. The local `set-credentials.sh` file and `.env` files are ignored by Git.

A VEX Events bearer API key is for `https://events.vex.com/api/v2`. It is not a supported substitute for the DWAB OAuth token or the local TM server signing key. TM requests send both the app's OAuth bearer token and an HMAC-SHA256 signature made with the local server key.

## Development

Requires Dart 3.10+, Flutter 3.38+, and macOS 12+ for the macOS build. Native desktop window controls are retained. Linux secure storage requires libsecret and a running Secret Service/keyring; see the [secure storage package documentation](https://pub.dev/packages/flutter_secure_storage). Windows requires Flutter desktop build tooling and the C++ ATL components.

```sh
flutter pub get
flutter test
flutter analyze
flutter build macos --debug
```

The network clients and app controller accept injected dependencies for deterministic tests. Tests cover OBS handshake/authentication, concurrent requests, timeouts, disconnects, TM request handling, routing persistence, monitoring guards, field identity, and widget layout.

## API compatibility

ATS follows the Python program's match flow: `fieldMatchAssigned` updates the Upcoming Match scene, automatic `fieldActivated` packets are ignored, and `matchStarted` switches to the mapped field scene. The local TM `/api/fieldsets` requests use bounded signature compatibility retries. The WebSocket handshake follows the Python client: `/api/fieldsets/{id}`, OAuth bearer authorization in a header, an RFC1123 date, and a signature made with the local TM key. Tokens are not included in URLs. It handles both `fieldsets` and `fieldSets` payload names. Field IDs are distinct from zero-based `fieldIndex`; unknown, conflicting, or malformed event IDs never switch scenes. Activity records recognized triggers and ignored triggers with missing/unknown fields without logging raw packets. Verify monitoring against your Tournament Manager version before using it at an event.

`docs/api/swagger.yml` documents the **Public VEX Events API**, not the local Tournament Manager API or its event stream. It is retained as reference and is not used as evidence for the local TM protocol. OBS uses [WebSocket 5.x, RPC version 1](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md).
