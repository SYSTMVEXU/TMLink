import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ObsException implements Exception {
  final String message;

  const ObsException(this.message);

  @override
  String toString() => message;
}

/// A persistent OBS WebSocket 5.x connection (RPC version 1).
class ObsClient {
  final String wsUrl;
  final String password;
  final Duration timeout;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _handshake;
  Future<void>? _connecting;
  final _pendingRequests = <String, Completer<Map<String, dynamic>>>{};
  int _requestId = 0;
  bool _connected = false;
  bool _identifySent = false;
  final _errors = StreamController<ObsException>.broadcast();
  bool _disposed = false;

  Stream<ObsException> get errors => _errors.stream;
  bool get isConnected => _connected;

  ObsClient({
    required this.wsUrl,
    this.password = '',
    this.timeout = const Duration(seconds: 5),
  });

  Future<void> connect() {
    if (_disposed) {
      return Future.error(
        const ObsException('OBS connection has been closed.'),
      );
    }
    if (_connected) return Future.value();
    return _connecting ??= _openConnection().whenComplete(() {
      _connecting = null;
    });
  }

  Future<void> _openConnection() async {
    final uri = Uri.tryParse(wsUrl.trim());
    if (uri == null ||
        !const ['ws', 'wss'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const ObsException(
        'Enter a valid OBS WebSocket URL, such as ws://localhost:4455/.',
      );
    }

    final channel = WebSocketChannel.connect(uri);
    final handshake = Completer<void>();
    _channel = channel;
    _handshake = handshake;
    _identifySent = false;

    // Attach once, before waiting for the handshake. Requests share this
    // listener and are matched by ID, even when responses arrive out of order.
    _subscription = channel.stream.listen(
      (event) => _handleMessage(channel, event),
      onError: (Object error) => _disconnect(
        channel,
        const ObsException(
          'Could not reach OBS. Check that its WebSocket server is enabled '
          'and the host and port are correct.',
        ),
      ),
      onDone: () => _disconnect(channel, _closeError(channel)),
    );

    try {
      await Future.wait([
        channel.ready,
        handshake.future,
      ], eagerError: true).timeout(
        timeout,
        onTimeout: () {
          throw const ObsException(
            'OBS connection timed out. Enable the OBS WebSocket 5.x server '
            'and check the URL (normally ws://localhost:4455/).',
          );
        },
      );
      if (_channel != channel) {
        throw const ObsException('OBS disconnected during setup.');
      }
      _connected = true;
    } catch (error) {
      final failure = error is ObsException
          ? error
          : const ObsException(
              'Could not connect to OBS. Check the WebSocket server and URL.',
            );
      _disconnect(channel, failure);
      throw failure;
    }
  }

  void _handleMessage(WebSocketChannel channel, dynamic event) {
    if (_channel != channel) return;
    try {
      final decoded = jsonDecode(
        event is String ? event : utf8.decode(event as List<int>),
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['d'] is! Map<String, dynamic>) {
        throw const ObsException('Expected an OBS WebSocket 5.x message.');
      }
      final data = decoded['d'] as Map<String, dynamic>;
      switch (decoded['op']) {
        case 0:
          if (_identifySent) {
            throw const ObsException('OBS sent an unexpected greeting.');
          }
          final auth = data['authentication'];
          String? token;
          if (auth != null) {
            if (password.isEmpty) {
              throw const ObsException(
                'OBS requires a WebSocket password. Enter the password '
                'from OBS Tools → WebSocket Server Settings.',
              );
            }
            if (auth is! Map<String, dynamic> ||
                auth['salt'] is! String ||
                auth['challenge'] is! String) {
              throw const ObsException(
                'OBS sent an invalid authentication challenge.',
              );
            }
            token = _buildAuth(
              auth['salt'] as String,
              auth['challenge'] as String,
            );
          }
          _identifySent = true;
          channel.sink.add(
            jsonEncode({
              'op': 1,
              'd': {
                'rpcVersion': 1,
                'eventSubscriptions': 0,
                if (token != null) 'authentication': token,
              },
            }),
          );
          break;
        case 2:
          if (!_identifySent || data['negotiatedRpcVersion'] != 1) {
            throw const ObsException(
              'OBS negotiated an unsupported WebSocket protocol.',
            );
          }
          if (!_handshake!.isCompleted) _handshake!.complete();
          break;
        case 7:
          final pending = _pendingRequests.remove(data['requestId']);
          if (pending != null) pending.complete(data);
          break;
        // Events and responses for expired requests do not affect other requests.
      }
    } catch (error) {
      _disconnect(
        channel,
        error is ObsException
            ? error
            : const ObsException('OBS sent an invalid WebSocket message.'),
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String requestType, [
    Map<String, dynamic>? requestData,
  ]) async {
    final channel = _channel;
    if (!_connected || channel == null) {
      throw const ObsException('OBS is disconnected. Connect to OBS again.');
    }
    final id = (_requestId++).toString();
    final pending = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = pending;
    // Register the response handler before sending, including error handling.
    final response = pending.future.timeout(
      timeout,
      onTimeout: () {
        throw ObsException('OBS did not respond to $requestType in time.');
      },
    );
    try {
      try {
        channel.sink.add(
          jsonEncode({
            'op': 6,
            'd': {
              'requestType': requestType,
              'requestId': id,
              if (requestData != null) 'requestData': requestData,
            },
          }),
        );
      } catch (_) {
        _disconnect(
          channel,
          const ObsException('Could not send a request to OBS.'),
        );
      }
      final data = await response;
      final status = data['requestStatus'];
      if (status is! Map<String, dynamic> || status['result'] != true) {
        final detail = status is Map<String, dynamic>
            ? status['comment'] ?? 'error code ${status['code']}'
            : 'invalid response status';
        throw ObsException('OBS $requestType failed: $detail');
      }
      final result = data['responseData'];
      return result is Map<String, dynamic> ? result : <String, dynamic>{};
    } finally {
      _pendingRequests.remove(id);
    }
  }

  Future<void> setCurrentScene(String sceneName) async {
    await _request('SetCurrentProgramScene', {'sceneName': sceneName});
  }

  Future<List<String>> getSceneNames() async {
    final response = await _request('GetSceneList');
    final scenes = response['scenes'];
    if (scenes is! List) {
      throw const ObsException('OBS returned an invalid scene list.');
    }
    return scenes
        .whereType<Map>()
        .map((scene) => scene['sceneName'])
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  ObsException _closeError(WebSocketChannel channel) {
    if (channel.closeCode == 4009) {
      return const ObsException(
        'OBS rejected the WebSocket password. Check the password in '
        'OBS Tools → WebSocket Server Settings.',
      );
    }
    if (channel.closeCode == 4010) {
      return const ObsException(
        'Use the OBS WebSocket 5.x server (normally port 4455).',
      );
    }
    return ObsException(
      'OBS disconnected'
      '${channel.closeCode == null ? '' : ' (code ${channel.closeCode})'}'
      '${channel.closeReason?.isNotEmpty == true ? ': ${channel.closeReason}' : '.'}',
    );
  }

  void _disconnect(WebSocketChannel channel, ObsException error) {
    if (_channel != channel) return;
    _channel = null;
    if (_connected && !_disposed) _errors.add(error);
    _connected = false;
    if (_handshake != null && !_handshake!.isCompleted) {
      _handshake!.completeError(error);
    }
    for (final request in _pendingRequests.values) {
      request.completeError(error);
    }
    _pendingRequests.clear();
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(channel.sink.close().then<void>((_) {}, onError: (Object _) {}));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final channel = _channel;
    if (channel != null) {
      _disconnect(channel, const ObsException('OBS connection closed.'));
    }
    unawaited(_errors.close());
  }

  static Future<ObsClient> fromSettings() async {
    final settings = await LocalSettingsRepository().load();
    return ObsClient(
      wsUrl: normalizeObsUrl(settings.obsUrl).toString(),
      password: settings.obsPassword,
    );
  }

  String _buildAuth(String salt, String challenge) {
    final secret = base64.encode(
      sha256.convert(utf8.encode(password + salt)).bytes,
    );
    return base64.encode(sha256.convert(utf8.encode(secret + challenge)).bytes);
  }
}
