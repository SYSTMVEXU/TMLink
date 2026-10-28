import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmlink/core/auth_manager.dart';
import 'package:tmlink/core/endpoints.dart';

void main() {
  test('canonical signature matches an independent HMAC-SHA256 vector', () {
    final canonical = AuthManager.createStringToSign(
      method: 'get',
      pathWithQuery: '/api/fieldsets?includeFields=true',
      token: 'test-token',
      host: 'localhost:8080',
      dateStr: 'Mon, 26 Oct 2026 19:00:00 GMT',
    );
    // Fixed vector calculated independently with Python hmac/hashlib.
    expect(
      AuthManager.signString('local-signing-key', canonical),
      '0884b4d4eb76ca3dd84b7cc06d87fdede652c9a744a65c766e5aebe12713f6d0',
    );
  });

  test('missing either credential fails before contacting DWAB', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    for (final pair in [('', ''), ('client', ''), ('', 'secret')]) {
      await expectLater(
        AuthManager.fetchToken(
          client: client,
          clientId: pair.$1,
          clientSecret: pair.$2,
        ),
        throwsA(isA<AppException>()),
      );
    }
    expect(requests, 0);
  });

  test(
    'DWAB rejection and malformed responses never expose raw bodies',
    () async {
      for (final response in [
        http.Response('sensitive-upstream-body', 400),
        http.Response('sensitive-upstream-body', 401),
        http.Response('sensitive-upstream-body', 503),
        http.Response('sensitive-upstream-body', 200),
        http.Response('{"access_token":""}', 200),
      ]) {
        final client = MockClient((_) async => response);
        addTearDown(client.close);
        await expectLater(
          AuthManager.fetchToken(
            client: client,
            clientId: 'client',
            clientSecret: 'client-secret-value',
          ),
          throwsA(
            isA<AppException>().having(
              (error) => error.message,
              'sanitized message',
              allOf(
                isNot(contains('sensitive-upstream-body')),
                isNot(contains('client-secret-value')),
              ),
            ),
          ),
        );
      }
    },
  );

  test(
    'unreachable authorization service returns a bounded safe error',
    () async {
      final client = MockClient((_) => Completer<http.Response>().future);
      addTearDown(client.close);
      await expectLater(
        AuthManager.fetchToken(
          client: client,
          clientId: 'client',
          clientSecret: 'secret',
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.message,
            'network error',
            contains('Could not reach the TM authorization service'),
          ),
        ),
      );
    },
  );

  test('OAuth token expiry includes a renewal margin', () {
    final now = DateTime.now().toUtc();
    expect(
      OAuthToken('token', now.subtract(const Duration(seconds: 1))).isExpired,
      true,
    );
    expect(
      OAuthToken('token', now.add(const Duration(seconds: 10))).isExpired,
      true,
    );
    expect(
      OAuthToken('token', now.add(const Duration(hours: 1))).isExpired,
      false,
    );
  });
}
