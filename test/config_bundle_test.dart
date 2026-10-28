import 'package:flutter_test/flutter_test.dart';
import 'package:tmlink/core/app_credentials.dart';
import 'package:tmlink/core/config.dart';

void main() {
  test('masked build definitions reach runtime configuration', () {
    if (const bool.hasEnvironment('TMLINK_CREDENTIAL_PAYLOAD')) {
      // Run with --dart-define-from-file=test/fixtures/bundled_credentials.json.
      expect(
        Config.bundledCredentials.clientId,
        'synthetic-client-for-release-tests',
      );
      expect(
        Config.bundledCredentials.clientSecret,
        'synthetic-secret-for-release-tests',
      );
      expect(Config.bundledCredentials.expiresAt, DateTime.utc(2099, 6, 8));
      expect(Config.bundledCredentials.source, CredentialSource.bundled);
    } else {
      expect(Config.bundledCredentials.source, CredentialSource.none);
    }
  });
}
