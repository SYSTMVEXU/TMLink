import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmlink/core/app_credentials.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:tmlink/core/auth_manager.dart';
import 'package:tmlink/core/tm_api_client.dart';
import 'package:tmlink/core/tm_instance_detector.dart';

void main() {
  test('native fieldID and fieldSetID metadata preserve stable IDs', () {
    final sets = TmFieldSet.parse([
      {
        'fieldSetID': 7,
        'name': 'Competition',
        'fields': [
          {'fieldID': 10, 'name': 'A'},
          {'fieldID': 20, 'name': 'B'},
        ],
      },
    ]);
    expect(sets.single.id, '7');
    expect(sets.single.fields.map((field) => field.id), ['10', '20']);
  });

  test('expired bundled credentials fail before any network request', () async {
    var requests = 0;
    final tm = TmApiClient(
      baseUrl: 'http://localhost:8080',
      apiKey: 'local-key',
      fieldSetId: '1',
      appCredentials: AppCredentials(
        clientId: 'expired-client',
        clientSecret: 'expired-secret',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
        source: CredentialSource.bundled,
      ),
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      tm.getFieldsets(),
      throwsA(isA<AppAuthorizationUpdateRequired>()),
    );
    expect(requests, 0);
    tm.dispose();
  });

  test(
    'revoked bundled authorization requests an update without exposing DWAB responses',
    () async {
      final tm = TmApiClient(
        baseUrl: 'http://localhost:8080',
        apiKey: 'local-key',
        fieldSetId: '1',
        appCredentials: AppCredentials(
          clientId: 'bundled-client',
          clientSecret: 'bundled-secret',
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 365)),
          source: CredentialSource.bundled,
        ),
        httpClient: MockClient((request) async {
          expect(request.url.host, 'auth.vextm.dwabtech.com');
          return http.Response('sensitive-rejection-body', 401);
        }),
      );
      await expectLater(
        tm.getFieldsets(),
        throwsA(
          isA<AppAuthorizationUpdateRequired>().having(
            (e) => e.message,
            'safe update message',
            allOf(
              contains('latest ATS'),
              isNot(contains('sensitive-rejection-body')),
            ),
          ),
        ),
      );
      tm.dispose();
    },
  );

  Future<OAuthToken> token() async =>
      OAuthToken('test-token', DateTime.now().add(const Duration(hours: 1)));
  TmApiClient client(
    http.Client httpClient, {
    Duration timeout = const Duration(seconds: 1),
    Future<OAuthToken> Function()? tokens,
  }) => TmApiClient(
    baseUrl: 'http://localhost:8080',
    apiKey: 'key',
    fieldSetId: '1',
    httpClient: httpClient,
    timeout: timeout,
    tokenProvider: tokens ?? token,
  );

  test(
    'signed requests include path, port and headers without console logging',
    () async {
      final output = <String>[];
      final tm = client(
        MockClient((request) async {
          expect(request.url.path, '/api/fieldsets');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.headers['X-TM-Date'], endsWith('GMT'));
          expect(request.headers.containsKey('X-TM-Api-Key'), false);
          expect(request.headers['X-TM-Signature'], hasLength(64));
          final date = request.headers['X-TM-Date']!;
          final expected = AuthManager.signString(
            'key',
            AuthManager.createStringToSign(
              method: 'GET',
              pathWithQuery: '/api/fieldsets',
              token: 'test-token',
              host: 'localhost:8080',
              dateStr: date,
            ),
          );
          expect(request.headers['X-TM-Signature'], expected);
          return http.Response('{"fieldSets":[]}', 200);
        }),
      );
      await runZoned(
        () async {
          expect(await tm.getFieldsets(), isEmpty);
        },
        zoneSpecification: ZoneSpecification(
          print: (_, parent, zone, line) {
            output.add(line);
          },
        ),
      );
      expect(output, isEmpty);
      tm.dispose();
    },
  );

  test('concurrent HTTP requests share a single OAuth token request', () async {
    var loads = 0;
    final tm = client(
      MockClient((_) async => http.Response('{"fieldsets":[]}', 200)),
      tokens: () async {
        loads++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return token();
      },
    );
    await Future.wait([tm.getFieldsets(), tm.getFieldsets()]);
    expect(loads, 1);
    tm.dispose();
  });

  test(
    'DWAB client credentials obtain the bearer used to sign TM requests',
    () async {
      final methods = <String>[];
      final tm = TmApiClient(
        baseUrl: 'http://localhost:8080',
        apiKey: 'local-signing-key',
        fieldSetId: '1',
        clientId: 'app-client',
        clientSecret: 'app-secret',
        httpClient: MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'POST') {
            expect(
              request.url.toString(),
              'https://auth.vextm.dwabtech.com/oauth2/token',
            );
            expect(Uri.splitQueryString(request.body), {
              'grant_type': 'client_credentials',
              'client_id': 'app-client',
              'client_secret': 'app-secret',
            });
            return http.Response(
              '{"access_token":"dwab-token","expires_in":3600}',
              200,
            );
          }
          expect(request.url.host, 'localhost');
          expect(request.headers['Authorization'], 'Bearer dwab-token');
          expect(
            request.headers['X-TM-Signature'],
            AuthManager.signString(
              'local-signing-key',
              'GET\n/api/fieldsets\ntoken:dwab-token\nhost:localhost:8080\nx-tm-date:${request.headers['X-TM-Date']}\n',
            ),
          );
          return http.Response('{"fieldsets":[]}', 200);
        }),
      );
      expect(await tm.getFieldsets(), isEmpty);
      expect(await tm.getFieldsets(), isEmpty);
      expect(methods, ['POST', 'GET', 'GET']);
      tm.dispose();
    },
  );

  test(
    'server failures do not trigger authentication fallback loops',
    () async {
      var attempts = 0;
      final tm = client(
        MockClient((_) async {
          attempts++;
          return http.Response('secret upstream detail', 503);
        }),
      );
      await expectLater(
        tm.getFieldsets(),
        throwsA(
          isA<TmApiException>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(attempts, 1);
      tm.dispose();
    },
  );

  test('expired tokens refresh once on an unauthorized response', () async {
    var calls = 0;
    var loads = 0;
    final tm = client(
      MockClient(
        (_) async => ++calls == 1
            ? http.Response('', 401)
            : http.Response('{"fieldsets":[]}', 200),
      ),
      tokens: () async {
        loads++;
        return token();
      },
    );
    expect(await tm.getFieldsets(), isEmpty);
    expect(loads, 2);
    tm.dispose();
  });

  test(
    'endpoint fallbacks handle 404 but preserve authentication failures',
    () async {
      final paths = <String>[];
      final tm = client(
        MockClient((request) async {
          paths.add(request.url.path);
          return request.url.path.endsWith('/fields')
              ? http.Response('', 404)
              : http.Response(
                  '{"fieldset":{"fields":[{"id":7,"name":"A"}]}}',
                  200,
                );
        }),
      );
      expect((await tm.getFieldsForFieldset('1')).length, 1);
      expect(paths, ['/api/fieldsets/1/fields', '/api/fieldsets/1']);
      tm.dispose();
      final failed = client(MockClient((_) async => http.Response('', 403)));
      await expectLater(
        failed.getFieldsForFieldset('1'),
        throwsA(
          isA<TmApiException>().having((e) => e.statusCode, 'status', 403),
        ),
      );
      failed.dispose();
    },
  );

  test(
    'unreadable payload and slow requests produce useful failures',
    () async {
      final bad = client(
        MockClient((_) async => http.Response('<html>error</html>', 200)),
      );
      await expectLater(bad.getFieldsets(), throwsA(isA<TmApiException>()));
      bad.dispose();
      final slow = client(
        MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response('{"fieldsets":[]}', 200);
        }),
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        slow.getFieldsets(),
        throwsA(
          isA<TmApiException>().having(
            (e) => e.message,
            'message',
            contains('in time'),
          ),
        ),
      );
      slow.dispose();
    },
  );

  test(
    'OAuth sends encoded form fields and rejects unsafe error responses',
    () async {
      final token = await AuthManager.fetchToken(
        client: MockClient((request) async {
          expect(Uri.splitQueryString(request.body)['client_secret'], 'a&b +c');
          return http.Response(
            jsonEncode({'access_token': 'token', 'expires_in': 3600}),
            200,
          );
        }),
        clientId: 'id',
        clientSecret: 'a&b +c',
      );
      expect(token.value, 'token');
      expect(token.isExpired, false);
      await expectLater(
        AuthManager.fetchToken(
          client: MockClient((_) async => http.Response('sensitive body', 401)),
          clientId: 'id',
          clientSecret: 'secret',
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            isNot(contains('sensitive')),
          ),
        ),
      );
    },
  );

  test(
    'stream readiness, malformed packets and disconnects are surfaced',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<WebSocket>();
      server.listen((request) async {
        expect(request.uri.path, '/api/fieldsets/1');
        expect(request.uri.hasQuery, false);
        expect(request.headers.value('Authorization'), 'Bearer test-token');
        expect(request.headers.value('x-tm-date'), endsWith('GMT'));
        expect(request.headers.value('x-tm-signature'), hasLength(64));
        accepted.complete(await WebSocketTransformer.upgrade(request));
      });
      final tm = TmApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'key',
        fieldSetId: '1',
        tokenProvider: token,
      );
      final errors = <Object>[];
      final events = <Map<String, dynamic>>[];
      final subscription = tm.eventStream.listen(
        events.add,
        onError: errors.add,
      );
      await tm.connectWebSocket();
      final socket = await accepted.future;
      socket.add('{"type":"fieldActivated","fieldId":20}');
      socket.add('not json');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events.single['fieldId'], 20);
      expect(errors.single, isA<AppException>());
      await socket.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(errors.length, 2);
      await subscription.cancel();
      tm.dispose();
      await server.close(force: true);
    },
  );

  test('discovery accepts TM evidence and preserves HTTPS and ports', () async {
    final detector = TmInstanceDetector(
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://example.local:8443/api/fieldsets',
        );
        return http.Response('', 401, headers: {'server': 'TM/1.0'});
      }),
    );
    expect(
      (await detector.verifyHost('https://example.local:8443')).isValid,
      true,
    );
    detector.dispose();
    final other = TmInstanceDetector(
      client: MockClient((_) async => http.Response('VEX team website', 200)),
    );
    expect((await other.verifyHost('localhost')).isValid, false);
    other.dispose();
  });
}
