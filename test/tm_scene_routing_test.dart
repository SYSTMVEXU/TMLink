import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:tmlink/core/auth_manager.dart';
import 'package:tmlink/core/tm_api_client.dart';

import 'test_support.dart';

void main() {
  test(
    'queue stays on upcoming through automatic activation then match start shows field',
    () async {
      // These exact packet shapes were captured in the original Python app's log.
      final packets =
          (jsonDecode(
                    File(
                      'test/fixtures/tm_field_events.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      final tmServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final obsServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final acceptedTm = Completer<WebSocket>();
      final sceneRequests = StreamController<String>.broadcast();
      final switched = <String>[];
      final inputUpdates = <Map<String, dynamic>>[];

      tmServer.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          expect(request.uri.path, '/api/fieldsets/1');
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          acceptedTm.complete(socket);
        } else {
          expect([
            '/api/fieldsets',
            '/api/matches/1',
          ], contains(request.uri.path));
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              request.uri.path == '/api/matches/1'
                  ? {
                      'matches': [
                        {
                          'matchInfo': {
                            ...packets.first['match'] as Map<String, dynamic>,
                            'alliances': [
                              {
                                'teams': [
                                  {'number': '111A'},
                                  {'number': '222B'},
                                ],
                              },
                              {
                                'teams': [
                                  {'number': '333C'},
                                  {'number': '444D'},
                                ],
                              },
                            ],
                          },
                        },
                      ],
                    }
                  : {
                      'fieldSets': [
                        {
                          'id': 1,
                          'name': 'Competition',
                          'fields': [
                            {'id': 1, 'name': 'Field 1'},
                            {'id': 2, 'name': 'Field 2'},
                            {'id': 3, 'name': 'Field 3'},
                          ],
                        },
                      ],
                    },
            ),
          );
          await request.response.close();
        }
      });

      obsServer.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.add(
          jsonEncode({
            'op': 0,
            'd': {'rpcVersion': 1},
          }),
        );
        socket.listen((raw) {
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          if (message['op'] == 1) {
            socket.add(
              jsonEncode({
                'op': 2,
                'd': {'negotiatedRpcVersion': 1},
              }),
            );
          } else if (message['op'] == 6) {
            final data = message['d'] as Map<String, dynamic>;
            if (data['requestType'] == 'SetCurrentProgramScene') {
              final scene = data['requestData']['sceneName'] as String;
              switched.add(scene);
              sceneRequests.add(scene);
            }
            if (data['requestType'] == 'SetInputSettings') {
              inputUpdates.add(data['requestData'] as Map<String, dynamic>);
            }
            socket.add(
              jsonEncode({
                'op': 7,
                'd': {
                  'requestId': data['requestId'],
                  'requestType': data['requestType'],
                  'requestStatus': {'result': true, 'code': 100},
                  if (data['requestType'] == 'GetSceneList')
                    'responseData': {
                      'scenes': [
                        for (final scene in [
                          'Main',
                          'Break',
                          'Skills',
                          'Upcoming Match',
                        ])
                          {'sceneName': scene},
                      ],
                    },
                },
              }),
            );
          }
        });
      });

      final settings = MemorySettings()
        ..settings = AppSettings(
          tmHost: 'http://127.0.0.1:${tmServer.port}',
          tmApiKey: 'test-signing-key',
          obsUrl: 'ws://127.0.0.1:${obsServer.port}',
        );
      final app = AppController(
        repository: settings,
        tmFactory: (settings, id) => TmApiClient(
          baseUrl: settings.tmHost,
          apiKey: settings.tmApiKey,
          fieldSetId: id,
          tokenProvider: () async => OAuthToken(
            'test-token',
            DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      );
      addTearDown(() async {
        await app.stopMonitoring();
        app.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await sceneRequests.close();
        await tmServer.close(force: true);
        await obsServer.close(force: true);
      });

      await app.initialize();
      await app.connectAll();
      await app.setMapping('1', 'Main');
      await app.setMapping('2', 'Break');
      await app.setMapping('3', 'Skills');
      expect(app.canStart, true);
      await app.startMonitoring();
      final tmSocket = await acceptedTm.future;
      for (final ignored in [
        {'type': 'fieldActivated', 'fieldID': 999, 'fieldIndex': 0},
        {'type': 'matchStarted'},
        {'type': 'matchStopped', 'fieldID': 1},
      ]) {
        tmSocket.add(jsonEncode(ignored));
      }
      final preview = sceneRequests.stream.first.timeout(
        const Duration(seconds: 2),
      );
      tmSocket.add(jsonEncode(packets.first));
      tmSocket.add(jsonEncode(packets[1]));
      expect(await preview, 'Upcoming Match');
      final previewComplete = Completer<void>();
      void checkPreview() {
        if (!previewComplete.isCompleted && inputUpdates.length == 13) {
          previewComplete.complete();
        }
      }

      app.addListener(checkPreview);
      checkPreview();
      await previewComplete.future.timeout(const Duration(seconds: 2));
      app.removeListener(checkPreview);
      expect(switched, ['Upcoming Match']);
      expect(inputUpdates.first, {
        'inputName': 'MatchStr',
        'inputSettings': {'text': 'R16 1'},
        'overlay': true,
      });
      expect(
        inputUpdates.any(
          (entry) =>
              entry['inputName'] == 'Team1Number' &&
              entry['inputSettings']['text'] == '111A',
        ),
        true,
      );
      final camera = sceneRequests.stream.first.timeout(
        const Duration(seconds: 2),
      );
      tmSocket.add(jsonEncode(packets.last));
      expect(await camera, 'Break');
      expect(switched, ['Upcoming Match', 'Break']);
      // Match start must reassert the scene even when its field was already active.
      final reasserted = sceneRequests.stream.first.timeout(
        const Duration(seconds: 2),
      );
      tmSocket.add(jsonEncode(packets.last));
      expect(await reasserted, 'Break');
      expect(switched, ['Upcoming Match', 'Break', 'Break']);
      expect(
        app.activity.any(
          (entry) => entry.message == 'TM match started on Field 2.',
        ),
        true,
      );
      expect(
        app.activity.any(
          (entry) => entry.message.contains('keeping the queued-match preview'),
        ),
        true,
      );
    },
  );
}
