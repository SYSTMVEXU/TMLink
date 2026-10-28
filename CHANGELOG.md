# Changelog

## 0.0.1 — 2026-10-27

Initial public release of Automated Tournament Stream (ATS).

- Connect to local VEX Tournament Manager using DWAB OAuth authorization and signed API requests, and control OBS Studio through WebSocket 5.x.
- Show the upcoming-match preview when a match is queued, then switch to its mapped field scene when the match starts.
- Automatically refresh the team roster from TM and write `Documents/ATS/teams.csv`, including team names and organizations.
- Manage robot images and team photos in the Documents/ATS folder, with a searchable Photos gallery and image previews.
- Offer basic and advanced settings, with saved scene mappings and connection credentials stored in the system keychain.
- Add optional macOS music automation: pause supported players at match start and resume the players ATS paused at match end.
- Use TM's documented `matchStopped` event to resume music; queuing or scoring a match never resumes playback.
- Check/request macOS Automation permission when music automation is enabled, and provide a two-second pause/resume test independent of TM.
- Identify DWAB HTTP 429 responses as authorization rate limits rather than internet outages.
- Build macOS, Windows, and Linux release packages in GitHub Actions with bundled app authorization, credential-literal scans, checksums, and separately encrypted debug symbols.

macOS music automation is available only on macOS. TIDAL menu control also requires Accessibility approval. Desktop packages are not publisher signed or notarized.

## Pre-release development history

### TM scene trigger compatibility

- Restored the Python flow: `fieldMatchAssigned` shows Upcoming Match, the automatic `fieldActivated` packet is ignored, and `matchStarted` switches to the mapped field scene.
- Recognized native TM `fieldID` identifiers as well as `fieldId` for match-start routing.
- Preserved native `fieldID`/`fieldSetID` values when parsing API field metadata.
- Added safe Activity entries for received scene triggers and missing/unknown field identifiers.
- Added regression packets from the original Python log and a test replaying them through TM and OBS WebSocket connections.

### ATS branding and team image folder

- Renamed the visible application to **Automated Tournament Stream (ATS)** and the macOS app bundle to `ATS.app`.
- Added a one-time Documents folder selection. ATS creates `ATS/teams.csv`, `ATS/robot_images/`, and `ATS/team_photos/`, and macOS access is restored from a saved security-scoped bookmark.
- Added Finder and roster refresh controls, plus setup guidance for team-number image filenames and fallback images.
- Added a **Photos** workspace with roster and filename discovery, team search, robot/team photo filters, large previews, and visible fallback or missing-image states.

Historical development summary through October 27, 2026, before the initial 0.0.1 release. Some intermediate setup flows described below were superseded during development.

### Bundled desktop app authorization

- Added protected, manual macOS/Windows/Linux release builds using GitHub environment secrets, random per-build string masking, and Flutter release obfuscation.
- Kept bundled credentials out of editable settings and OS credential storage; retained an optional manual pair under **Advanced authorization** with atomic override selection.
- Added a persistent update banner in the 30 days before credential expiration, a download action, and clear errors for expired or rejected bundled authorization.
- Added distribution scans for raw credential literals and debug files, package checksums, and separate AES-256 encrypted debug-symbol downloads.
- Kept original credentials out of Flutter child-process environments and removed temporary definitions/staging files after release builds.
- Retained in-memory OAuth caching and cleared cached tokens when a connection is disposed.
- Added cross-language credential fixtures, expiration/override tests, automatic-authorization UI coverage, and release-tool encryption checks.
- Selected Xcode 16.4 on the release runner to avoid Xcode 27's multi-architecture `lipo` incompatibility with the pinned Flutter SDK.

### GitHub Actions and DWAB credential setup

- Added CI analysis and tests without access to DWAB credentials.
- Added a manual, default-branch-only DWAB authorization check using the `dwab` GitHub environment and step-scoped client ID/secret values.
- Added a local authorization diagnostic that reports sanitized results without printing credentials or OAuth tokens.
- Documented local Keychain setup, GitHub environment secrets, access controls, credential rotation, and the limitations of secrets embedded in desktop builds.

### macOS build and desktop support

- Raised the minimum macOS deployment target from 10.15 to 12.0 in the Runner project and CocoaPods configuration to resolve Xcode deployment-target build failures.
- Added a CocoaPods post-install check that raises older pod deployment targets to 12.0 while preserving dependencies that require a newer version.
- Updated native plugin registration, CocoaPods integration, and macOS network entitlements for the current dependencies.
- Replaced the custom window dependency with native macOS window controls, a transparent title bar, a 1240 × 820 initial window, and a 760 × 560 minimum window size.
- Updated the supported development environment to Dart 3.10+ and Flutter 3.38+.

### Interface and setup

- Rebuilt the desktop interface with an Apple-inspired visual style, system typography, Cupertino icons, consistent panels, and light and dark themes.
- Added a workspace with **Scene Routing**, **Connections**, and **Activity** pages.
- Added a sidebar for larger windows and bottom navigation for narrower layouts.
- Added responsive layouts and support for larger text sizes.
- Added independent TM and OBS connection checks with progress, status, and actionable error messages.
- Added **Save & Connect**, local TM server discovery, and editable server/WebSocket addresses.
- Added masked credential fields with show/hide controls and OBS setup instructions.
- Added confirmation before manually testing a scene, since the test changes the live OBS program scene.
- Added a session Activity log capped at the latest 100 entries and an option to clear it.
- Disabled conflicting actions during connection checks, scene tests, settings saves, and monitoring.

### OBS WebSocket fixes

- Updated OBS integration to WebSocket 5.x with RPC version 1.
- Fixed the connection's single-subscription stream handling: one persistent listener now handles the handshake and subsequent requests.
- Added OBS challenge-response authentication and clear missing/incorrect-password errors.
- Correlated responses by request ID to support repeated, concurrent, and out-of-order requests.
- Added bounded connection and request timeouts, protocol checks, and disconnect handling.
- Rejected pending requests when the connection closes and allowed a subsequent reconnect.
- Confirmed scene-switch responses before reporting a switch as successful.
- Paused monitoring after an OBS disconnect, failed switch, or loss of access to mapped scenes.

### TM authentication and connectivity

- Preserved the DWAB client-credentials OAuth exchange and HMAC-SHA256 request signing with the local TM server API key.
- Added token caching, expiration checks, shared token loading for concurrent requests, and renewal after an unauthorized response.
- Added request timeouts and bounded signature compatibility retries; unrelated server failures do not trigger authentication retry loops.
- Added host/URL validation supporting explicit ports, IPv6, HTTPS, and secure WebSocket addresses.
- Added compatible field-set/field response parsing and limited endpoint fallbacks to appropriate HTTP failures.
- Added stream readiness checks and explicit handling of malformed events and stream disconnections.
- Compared the Flutter connection flow with the original Python apps and corrected the WebSocket handshake to use `/api/fieldsets/{id}` with an RFC1123 date and OAuth authorization in a header.
- Removed the access token from the WebSocket URL and aligned the primary signed request with the Python client's headers.
- Restored **Client ID** and **Client secret** under **Connections → Client authorization** after investigating the proposed API-key replacement.
- Retained launch-environment credential fallback and added Flutter build-definition support for app authorization configuration.
- Clarified that the supplied VEX Events Swagger document describes the online VEX Events API, rather than the local TM API or field event stream. No VEX Events bearer-key replacement is included in the final TM authentication flow.

### Routing and monitoring reliability

- Introduced a central app controller and separate settings, TM, and OBS clients with injectable dependencies.
- Stored routing by TM server, field-set ID, and field ID, and remembered the selected field set per server.
- Migrated legacy positional mappings only when the corresponding server and fields were available.
- Distinguished field IDs from zero-based field indices; unknown or malformed field activations do not select a default scene.
- Added monitoring readiness checks for verified connections, available fields/scenes, complete routing, and successful persistence.
- Serialized scene switches and coalesced queued activations to the latest field.
- Buffered field activations received while the monitoring connection was starting.
- Cancelled queued scene switches on Stop and ignored stale network responses after reconnection or disposal.
- Added periodic OBS scene checks and paused monitoring when mapped scenes disappear.
- Added routing-save retries and a verified backup before resetting unreadable routing.

### Credential storage

- Added OS-backed secure storage for connection settings, API keys, client credentials, and OBS passwords.
- Configured macOS storage to use the legacy Keychain implementation without requiring a data-protection Keychain entitlement.
- Migrated legacy secrets out of preferences only after verifying the secure-storage write; failed migrations preserve the original values.
- Saved connection settings as one verified credential bundle and retained the active configuration when a save failed.
- Preserved OBS password and client-secret whitespace rather than silently altering credentials.
- Kept credentials, OAuth tokens, signed headers, and raw authentication error bodies out of application logs.
- Added Git ignore rules for the local credential script and environment files.

### Developer mode

- Added a **Developer mode** switch in Connections to bypass TM for the current session without TM credentials or a server API key.
- Added three simulated fields and manual **Activate Test Field** controls.
- Routed simulated activations through the normal event handling, scene mapping, switch queue, and real OBS client.
- Added **Start simulation** and **Stop simulation** controls and explicit simulated-TM status labels.
- Kept developer routing and field-set selection separate from tournament routing.
- Retained OBS connection verification, mapping requirements, switch acknowledgments, and failure handling during simulation.
- Prevented mode changes during monitoring, connection checks, discovery, or other conflicting operations.
- Made developer mode reset on app restart; returning to normal mode requires a real TM connection before monitoring can start.
- Documented that simulated activations still change OBS's real program scene.

### Documentation, tools, and dependencies

- Expanded the README with setup, credential storage, API compatibility, developer-mode testing, and platform requirements.
- Added utilities for TM server discovery and field-set endpoint diagnostics.
- Removed unused dependencies, including the custom desktop window package and unused testing libraries.
- Updated dependency lockfiles and generated native plugin integration.
- Replaced the original placeholder widget test with controller, storage, protocol, and UI regression coverage.
- Added optional UI preview rendering for visual review.

### Authentication investigation

- Verified that both supplied Python versions exchange their client ID/secret for a DWAB token before signing TM requests with the separate server API key.
- Tested the supplied legacy credential pair directly against the DWAB OAuth endpoint, independently of Flutter, using both form credentials and HTTP Basic authentication.
- Both requests returned **HTTP 401 / `invalid_client`** and issued no token. The failure identifies a rejected credential pair, but does not establish whether the ID expired, authorization was revoked, or the secret was incorrect.
- Identified authentication problems in the old Python code: logging the bearer token inside the string to sign, no token-request timeout, and no token renewal handling.

### Validation and remaining limits

- Latest complete regression run: **54 tests passed**.
- Flutter analysis completed without issues, and the macOS debug application built successfully.
- Tests cover OAuth request encoding, token reuse/renewal, signed requests, OBS authentication and concurrent requests, timeouts, disconnections, routing migration/persistence, queued activations, monitoring guards, and developer-mode isolation.
- Widget checks cover light/dark themes, 1240 × 820, 760 × 560, and 480 × 760 layouts, larger text, credential masking, credential editing, and the simulation workflow.
- Reviewed rendered developer-mode screens at desktop and narrow window sizes.
- Authenticated live TM monitoring remains unverified because the supplied legacy DWAB credential pair is rejected. Automated simulator switching tests use an injected OBS client; they do not establish live OBS switching in every installation.
- Windows and Linux builds have not been verified in this session.
