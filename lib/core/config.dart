import 'dart:io';

import 'package:tmlink/core/app_credentials.dart';

class Config {
  static const String defaultTmIp = "127.0.0.1";
  static const String defaultTmPassword = "";
  static const String defaultObsWsUrl = "ws://localhost:4455/";
  static const String defaultObsWsPassword = "";
  static const String defaultFieldSetId = "1";

  static const releasesUrl =
      'https://github.com/SYSTMVEXU/TMLink/releases/latest';

  // Release builds receive only masked bytes; plaintext build definitions are
  // deliberately unsupported. Both pieces remain recoverable from the binary.
  static final bundledCredentials = AppCredentials.decodeBundle(
    const String.fromEnvironment('TMLINK_CREDENTIAL_PAYLOAD'),
    const String.fromEnvironment('TMLINK_CREDENTIAL_MASK'),
  );

  static AppCredentials get credentials {
    // Official release artifacts explicitly opt into their GitHub-built bundle.
    // Local Debug runs only read the process environment, never an incidental
    // release bundle copied into a developer build.
    if (const bool.fromEnvironment('TMLINK_RELEASE_BUILD')) {
      return bundledCredentials;
    }
    final id = Platform.environment['VEX_TM_CLIENT_ID'] ?? '';
    final secret = Platform.environment['VEX_TM_CLIENT_SECRET'] ?? '';
    if (id.isNotEmpty || secret.isNotEmpty) {
      // Never mix part of an override with part of the bundled credential pair.
      return AppCredentials(
        clientId: id,
        clientSecret: secret,
        source: CredentialSource.environment,
      );
    }
    return const AppCredentials();
  }

  static String get clientId => credentials.clientId;
  static String get clientSecret => credentials.clientSecret;
}
