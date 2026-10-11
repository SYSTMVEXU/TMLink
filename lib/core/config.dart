import 'dart:io';

class Config {
  static const String defaultTmIp = "127.0.0.1";
  static const String defaultTmPassword = "";
  static const String defaultObsWsUrl = "ws://localhost:4455/";
  static const String defaultObsWsPassword = "";
  static const String defaultFieldSetId = "1";

  // Deployment credentials are distinct from the user's local server API key.
  // Build definitions support Finder launches without a shell environment.
  static const _buildClientId = String.fromEnvironment('VEX_TM_CLIENT_ID');
  static const _buildClientSecret = String.fromEnvironment(
    'VEX_TM_CLIENT_SECRET',
  );
  static String get clientId => _buildClientId.isNotEmpty
      ? _buildClientId
      : Platform.environment['VEX_TM_CLIENT_ID'] ?? "";
  static String get clientSecret => _buildClientSecret.isNotEmpty
      ? _buildClientSecret
      : Platform.environment['VEX_TM_CLIENT_SECRET'] ?? "";
}
