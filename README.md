# TMLink

A desktop workspace that connects VEX Tournament Manager field activations to OBS Studio scenes.

See [CHANGELOG.md](CHANGELOG.md) for the development history and validation results.

## Getting started

1. Enable the local API on your Tournament Manager server and obtain its local server API key and DWAB client ID/secret.
2. In OBS, enable **Tools → WebSocket Server Settings**. Use the displayed port and password (the default address is `ws://localhost:4455/`).
3. Open **Connections** in TMLink. Enter the TM host and local server API key, expand **Client authorization** to enter your DWAB client ID/secret, and enter the OBS settings. Choose **Save & Connect**. Each service is checked independently; checking connections does not switch scenes.
4. Open **Scene Routing**, choose a field set, and assign an available OBS scene to every field. Changes save automatically. **Test** explicitly switches the live OBS program scene after confirmation.
5. Choose **Start monitoring**. **Stop monitoring** cancels queued switches. Connection failure, failed scene switching, or missing mapped scenes pauses monitoring; review the Activity log and reconnect before restarting.

Routing is stored by TM server, field-set ID, and field ID. Prior positional mappings are migrated when the corresponding fields are loaded. Your selected field set is remembered per server. Unreadable routing can be reset after the original data is backed up. Missing/removed scenes are shown explicitly and prevent monitoring. The Activity log contains the latest 100 entries for the current session.

## Testing without TM

In **Connections**, enable **Developer mode** to bypass TM for the current session. Connect OBS normally; no TM client credentials or API key are needed. In **Scene Routing**, map the three test fields to OBS scenes and choose **Start simulation**. Use **Activate Test Field 1/2/3** to send simulated field activations through the normal routing and switching flow. OBS changes its real program scene. You can also use each mapping's **Test** button before starting simulation.

Test routing and field-set selection are stored separately from your tournament routing. Stop simulation before changing modes. Disabling developer mode requires a real TM connection before monitoring can restart. Developer mode resets when the app restarts.

## Credentials

Passwords, API keys, client credentials, and connection settings use the OS credential store (Keychain on macOS). Legacy API keys, OBS passwords, and the previously unused TM password migrate from preferences only after the keychain write has been verified. If storage is unavailable, unlock the system keychain and retry. No credential or signed-request header is printed to the application log.

Client ID/secret can be entered in **Connections → Client authorization** and saved to the system keychain. Leave both blank to use `VEX_TM_CLIENT_ID` and `VEX_TM_CLIENT_SECRET` from the launch environment or build definitions. Finder launches usually do not inherit shell variables; saving credentials in Connections supports both launch methods. Build definitions are embedded in the app and are not a secure secret vault. The local `set-credentials.sh` file and `.env` files are ignored by Git.

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

TMLink uses the local TM `/api/fieldsets` request and `fieldActivated` event adapter, with bounded signature compatibility retries. The WebSocket handshake follows the Python client: `/api/fieldsets/{id}`, OAuth bearer authorization in a header, an RFC1123 date, and a signature made with the local TM key. Tokens are not included in URLs. It handles both `fieldsets` and `fieldSets` payload names. Field IDs are distinct from zero-based `fieldIndex`; unknown or malformed events never switch scenes. Verify monitoring against your Tournament Manager version before using it at an event.

`docs/api/swagger.yml` documents the **Public VEX Events API**, not the local Tournament Manager API or its event stream. It is retained as reference and is not used as evidence for the local TM protocol. OBS uses [WebSocket 5.x, RPC version 1](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md).
