import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmlink/core/app_credentials.dart';
import 'package:tmlink/core/app_settings.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27);
  final bundled = AppCredentials(
    clientId: 'bundled-client',
    clientSecret: 'bundled-secret',
    expiresAt: DateTime.utc(2027, 6, 8),
    source: CredentialSource.bundled,
  );

  test(
    'release-tool fixture decodes at runtime without plaintext definitions',
    () {
      final defines =
          jsonDecode(
                File(
                  'test/fixtures/bundled_credentials.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final credentials = AppCredentials.decodeBundle(
        defines['TMLINK_CREDENTIAL_PAYLOAD'] as String,
        defines['TMLINK_CREDENTIAL_MASK'] as String,
      );
      expect(credentials.clientId, 'synthetic-client-for-release-tests');
      expect(credentials.clientSecret, 'synthetic-secret-for-release-tests');
      expect(credentials.expiresAt, DateTime.utc(2099, 6, 8));
      expect(credentials.isBundled, true);
    },
  );

  test(
    'missing bundles allow development; corrupt bundles request an update',
    () {
      expect(AppCredentials.decodeBundle('', '').source, CredentialSource.none);
      for (final pair in [
        ('invalid', 'bad'),
        ('aGVsbG8=', ''),
        ('', 'aGVsbG8='),
      ]) {
        final corrupt = AppCredentials.decodeBundle(pair.$1, pair.$2);
        expect(corrupt.updateNotice(now), AppCredentials.updateMessage);
        expect(() => corrupt.validate(now: now), throwsA(isA<AppException>()));
      }
    },
  );

  test(
    'expiry blocks precisely at UTC boundary and warns thirty days before',
    () {
      expect(bundled.updateNotice(now), isNull);
      final expiry = bundled.expiresAt!;
      expect(
        bundled.updateNotice(expiry.subtract(const Duration(days: 30))),
        contains('needed soon'),
      );
      expect(
        bundled.isExpired(expiry.subtract(const Duration(milliseconds: 1))),
        false,
      );
      expect(bundled.isExpired(expiry), true);
      expect(bundled.updateNotice(expiry), AppCredentials.updateMessage);
      expect(() => bundled.validate(now: expiry), throwsA(isA<AppException>()));
    },
  );

  test('saved settings cannot override build-specific credentials', () {
    expect(const AppSettings().resolveCredentials(bundled), same(bundled));
    final ignoredSavedPair = const AppSettings(
      clientId: 'manual-client',
      clientSecret: 'manual-secret',
    ).resolveCredentials(bundled);
    expect(ignoredSavedPair, same(bundled));
    final incompleteSavedPair = const AppSettings(
      clientId: 'manual-client',
    ).resolveCredentials(bundled);
    expect(incompleteSavedPair, same(bundled));
  });
}
