import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmlink/core/obs_client.dart';

void main() {
  late _ObsServer server;
  late ObsClient client;

  setUp(() async {
    server = await _ObsServer.start();
    client = ObsClient(wsUrl: server.url);
  });

  tearDown(() async {
    client.dispose();
    await server.close();
  });

  test(
    'one connection handles handshake, repeated and concurrent requests',
    () async {
      await Future.wait([client.connect(), client.connect()]);
      expect(await client.getSceneNames(), ['Main', 'Break']);
      expect(await client.getSceneNames(), ['Main', 'Break']);

      final requests = <Map<String, dynamic>>[];
      server.onRequest = (socket, request) {
        requests.add(request);
        if (requests.length == 2) {
          // Reverse responses and interleave an unrelated event/response.
          socket.add(
            jsonEncode({
              'op': 5,
              'd': {'eventType': 'CurrentProgramSceneChanged'},
            }),
          );
          _respond(socket, {
            'requestId': 'unknown',
            'requestType': 'GetSceneList',
          });
          for (final pending in requests.reversed) {
            _respond(
              socket,
              pending,
              responseData: pending['requestType'] == 'GetSceneList'
                  ? {
                      'scenes': [
                        {'sceneName': 'Concurrent'},
                      ],
                    }
                  : null,
            );
          }
        }
      };
      final scenes = client.getSceneNames();
      final switchScene = client.setCurrentScene('Main');
      expect(await scenes, ['Concurrent']);
      await switchScene;
      expect(server.connections, 1);
      expect(server.identifies.single['eventSubscriptions'], 0);
      expect(requests.last['requestData'], {'sceneName': 'Main'});
    },
  );

  test('authenticates using OBS SHA256 challenge-response', () async {
    server.authentication = {
      'challenge': '+IxH4CnCiqpX1rM9scsNynZzbOe4KhDeYcTNS3PDaeY=',
      'salt': 'lM1GncleQOaCu9lT1yeUZhFYnqhsLLP1G5lAGo3ixaI=',
    };
    client = ObsClient(wsUrl: server.url, password: 'supersecretpassword');
    await client.connect();
    // Independently calculated with Python hashlib/base64.
    expect(
      server.identifies.single['authentication'],
      '1Ct943GAT+6YQUUX47Ia/ncufilbe6+oD6lY+5kaCu4=',
    );
    expect(await client.getSceneNames(), isNotEmpty);
  });

  test('reports missing and rejected passwords', () async {
    server.authentication = {'challenge': 'challenge', 'salt': 'salt'};
    await expectLater(
      client.connect(),
      throwsA(
        isA<ObsException>().having(
          (e) => e.message,
          'message',
          contains('requires a WebSocket password'),
        ),
      ),
    );
    client = ObsClient(wsUrl: server.url, password: 'wrong');
    server.onIdentify = (socket, _) =>
        socket.close(4009, 'Authentication failed');
    await expectLater(
      client.connect(),
      throwsA(
        isA<ObsException>().having(
          (e) => e.message,
          'message',
          contains('rejected the WebSocket password'),
        ),
      ),
    );
  });

  test(
    'waits for scene-switch acknowledgement and surfaces OBS failures',
    () async {
      await client.connect();
      late WebSocket socket;
      late Map<String, dynamic> request;
      final received = Completer<void>();
      server.onRequest = (s, r) {
        socket = s;
        request = r;
        received.complete();
      };
      var completed = false;
      final switching = client.setCurrentScene('Missing');
      final assertion = expectLater(
        switching,
        throwsA(
          isA<ObsException>().having(
            (e) => e.message,
            'message',
            contains('Scene not found'),
          ),
        ),
      );
      unawaited(
        switching.then((_) {
          completed = true;
        }, onError: (Object _) {}),
      );
      await received.future;
      expect(completed, false);
      _respond(socket, request, success: false, comment: 'Scene not found');
      await assertion;
    },
  );

  test(
    'disconnect rejects pending requests and permits reconnecting',
    () async {
      await client.connect();
      server.onRequest = (socket, _) => socket.close(1001, 'Server restarting');
      await expectLater(client.getSceneNames(), throwsA(isA<ObsException>()));
      server.onRequest = null;
      await client.connect();
      expect(await client.getSceneNames(), ['Main', 'Break']);
      expect(server.connections, 2);
    },
  );

  test(
    'greeting timeout fails instead of claiming a legacy connection',
    () async {
      server.sendHello = false;
      client = ObsClient(
        wsUrl: server.url,
        timeout: const Duration(milliseconds: 100),
      );
      await expectLater(
        client.connect(),
        throwsA(
          isA<ObsException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      server.sendHello = true;
      await client.connect();
      expect(await client.getSceneNames(), ['Main', 'Break']);
    },
  );

  test(
    'request timeout and late reply do not corrupt subsequent requests',
    () async {
      client = ObsClient(
        wsUrl: server.url,
        timeout: const Duration(milliseconds: 100),
      );
      await client.connect();
      late WebSocket socket;
      late Map<String, dynamic> expired;
      server.onRequest = (s, r) {
        socket = s;
        expired = r;
      };
      await expectLater(
        client.getSceneNames(),
        throwsA(
          isA<ObsException>().having(
            (e) => e.message,
            'message',
            contains('did not respond'),
          ),
        ),
      );
      _respond(socket, expired);
      server.onRequest = null;
      expect(await client.getSceneNames(), ['Main', 'Break']);
    },
  );

  test(
    'disposing during identification rejects connection and closes socket',
    () async {
      final identifyReceived = Completer<void>();
      server.onIdentify = (socket, identify) {
        identifyReceived.complete();
      };
      final connection = client.connect();
      final assertion = expectLater(connection, throwsA(isA<ObsException>()));
      await identifyReceived.future;
      client.dispose();
      await assertion;
      await expectLater(client.getSceneNames(), throwsA(isA<ObsException>()));
    },
  );

  test('malformed hello fails and permits a fresh connection', () async {
    server.authentication = {'salt': 123, 'challenge': 'challenge'};
    client = ObsClient(wsUrl: server.url, password: 'password');
    await expectLater(client.connect(), throwsA(isA<ObsException>()));
    server.authentication = null;
    await client.connect();
    expect(await client.getSceneNames(), ['Main', 'Break']);
  });

  test('unreachable server and invalid URLs fail clearly', () async {
    final unused = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final url = 'ws://127.0.0.1:${unused.port}/';
    await unused.close(force: true);
    client = ObsClient(wsUrl: url);
    await expectLater(client.connect(), throwsA(isA<ObsException>()));
    client = ObsClient(wsUrl: 'http://localhost:4455/');
    await expectLater(client.connect(), throwsA(isA<ObsException>()));
  });
}

void _respond(
  WebSocket socket,
  Map<String, dynamic> request, {
  Map<String, dynamic>? responseData,
  bool success = true,
  String? comment,
}) {
  socket.add(
    jsonEncode({
      'op': 7,
      'd': {
        'requestId': request['requestId'],
        'requestType': request['requestType'],
        'requestStatus': {
          'result': success,
          'code': success ? 100 : 600,
          if (comment != null) 'comment': comment,
        },
        if (responseData != null) 'responseData': responseData,
      },
    }),
  );
}

class _ObsServer {
  final HttpServer server;
  final sockets = <WebSocket>[];
  final identifies = <Map<String, dynamic>>[];
  int connections = 0;
  bool sendHello = true;
  Map<String, dynamic>? authentication;
  void Function(WebSocket, Map<String, dynamic>)? onIdentify;
  void Function(WebSocket, Map<String, dynamic>)? onRequest;

  _ObsServer(this.server) {
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      connections++;
      if (sendHello) {
        socket.add(
          jsonEncode({
            'op': 0,
            'd': {
              'rpcVersion': 1,
              if (authentication != null) 'authentication': authentication,
            },
          }),
        );
      }
      socket.listen((message) {
        final packet = jsonDecode(message as String) as Map<String, dynamic>;
        final data = packet['d'] as Map<String, dynamic>;
        if (packet['op'] == 1) {
          identifies.add(data);
          if (onIdentify != null) {
            onIdentify!(socket, data);
          } else {
            socket.add(
              jsonEncode({
                'op': 2,
                'd': {'negotiatedRpcVersion': 1},
              }),
            );
          }
        } else if (packet['op'] == 6) {
          if (onRequest != null) {
            onRequest!(socket, data);
          } else {
            _respond(
              socket,
              data,
              responseData: data['requestType'] == 'GetSceneList'
                  ? {
                      'scenes': [
                        {'sceneName': 'Main'},
                        {'sceneName': 'Break'},
                      ],
                    }
                  : null,
            );
          }
        }
      });
    });
  }

  String get url => 'ws://127.0.0.1:${server.port}/';

  static Future<_ObsServer> start() async =>
      _ObsServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Future<void> close() async {
    await Future.wait(sockets.map((socket) => socket.close()));
    await server.close(force: true);
  }
}
