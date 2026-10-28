import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tmlink/core/app_credentials.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:tmlink/core/auth_manager.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class TmField {
  final String id;
  final String name;
  const TmField({required this.id, required this.name});
}

class TmFieldSet {
  final String id;
  final String name;
  final List<TmField> fields;
  const TmFieldSet({
    required this.id,
    required this.name,
    this.fields = const [],
  });

  static List<TmField> parseFields(List<dynamic> data) {
    final fields = <TmField>[];
    final ids = <String>{};
    for (var i = 0; i < data.length; i++) {
      final raw = data[i];
      if (raw is! Map) continue;
      final id = (raw['id'] ?? raw['fieldID'] ?? raw['fieldId'] ?? i)
          .toString();
      if (!ids.add(id)) continue;
      fields.add(
        TmField(
          id: id,
          name:
              (raw['name'] ??
                      raw['fieldName'] ??
                      raw['displayName'] ??
                      raw['label'] ??
                      'Field ${i + 1}')
                  .toString(),
        ),
      );
    }
    return fields;
  }

  static List<TmFieldSet> parse(List<dynamic> data) {
    final sets = <TmFieldSet>[];
    final ids = <String>{};
    for (final raw in data) {
      if (raw is! Map) continue;
      final id =
          raw['id'] ??
          raw['fieldSetID'] ??
          raw['fieldsetID'] ??
          raw['fieldsetId'] ??
          raw['fieldSetId'];
      if (id == null || id.toString().isEmpty || !ids.add(id.toString())) {
        continue;
      }
      sets.add(
        TmFieldSet(
          id: id.toString(),
          name: (raw['name'] ?? raw['title'] ?? 'Field set $id').toString(),
          fields: raw['fields'] is List
              ? parseFields(raw['fields'] as List)
              : const [],
        ),
      );
    }
    return sets;
  }
}

class TmApiException extends AppException {
  final int? statusCode;
  const TmApiException(super.message, {this.statusCode});
}

class TmApiClient {
  final String baseUrl;
  final String apiKey;
  final String fieldSetId;
  final String clientId;
  final String clientSecret;
  final AppCredentials? appCredentials;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsHttp;
  final Future<OAuthToken> Function()? _tokenProvider;
  OAuthToken? _token;
  Future<void>? _tokenLoading;
  WebSocketChannel? _wsChannel;
  StreamSubscription<dynamic>? _wsSubscription;
  bool _disposed = false;
  final _events = StreamController<Map<String, dynamic>>.broadcast();

  TmApiClient({
    required this.baseUrl,
    required this.apiKey,
    required this.fieldSetId,
    this.clientId = '',
    this.clientSecret = '',
    this.appCredentials,
    this.timeout = const Duration(seconds: 8),
    http.Client? httpClient,
    Future<OAuthToken> Function()? tokenProvider,
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _tokenProvider = tokenProvider;

  Stream<Map<String, dynamic>> get eventStream => _events.stream;

  void _checkAlive() {
    if (_disposed) {
      throw const AppException(
        'TM connection has been closed. Reconnect to continue.',
      );
    }
  }

  Future<void> initialize({bool connectStream = true}) async {
    await _ensureAccessToken();
    if (connectStream) await connectWebSocket();
  }

  Future<void> _ensureAccessToken() async {
    _checkAlive();
    if (_tokenProvider == null) {
      (appCredentials ??
              AppCredentials(clientId: clientId, clientSecret: clientSecret))
          .validate();
    }
    if (_token != null && !_token!.isExpired) return;
    await (_tokenLoading ??= _loadToken().whenComplete(
      () => _tokenLoading = null,
    ));
    _checkAlive();
  }

  Future<void> _loadToken() async {
    final token = _tokenProvider != null
        ? await _tokenProvider()
        : await AuthManager.fetchToken(
            client: _http,
            clientId: appCredentials?.clientId ?? clientId,
            clientSecret: appCredentials?.clientSecret ?? clientSecret,
            bundled: appCredentials?.isBundled ?? false,
            timeout: timeout,
          );
    _checkAlive();
    _token = token;
  }

  Future<void> connectWebSocket() async {
    _checkAlive();
    if (fieldSetId.isEmpty) {
      throw const AppException('Choose a TM field set first.');
    }
    await _ensureAccessToken();
    await disconnectWebSocket();
    _checkAlive();
    final base = normalizeTmUrl(baseUrl);
    final path = '/api/fieldsets/${Uri.encodeComponent(fieldSetId)}';
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: path,
    );
    final headers = await _buildSignedHeaders(
      uri,
      useRfcDate: true,
      includeKey: false,
    );
    final channel = IOWebSocketChannel.connect(
      uri,
      headers: headers,
      connectTimeout: timeout,
      pingInterval: const Duration(seconds: 20),
    );
    _wsChannel = channel;
    _wsSubscription = channel.stream.listen(
      (data) {
        if (_disposed || _wsChannel != channel) return;
        try {
          final decoded = jsonDecode(
            data is String ? data : utf8.decode(data as List<int>),
          );
          if (decoded is! Map<String, dynamic>) throw const FormatException();
          _events.add(decoded);
        } catch (_) {
          _events.addError(
            const AppException(
              'TM sent an unreadable event. Monitoring was paused.',
            ),
          );
        }
      },
      onError: (Object error) {
        if (!_disposed && _wsChannel == channel) {
          _events.addError(
            const AppException(
              'The TM event stream failed. Check the server and reconnect.',
            ),
          );
        }
      },
      onDone: () {
        if (!_disposed && _wsChannel == channel) {
          _wsChannel = null;
          _events.addError(
            const AppException(
              'TM disconnected. Monitoring was paused; reconnect before continuing.',
            ),
          );
        }
      },
    );
    try {
      await channel.ready.timeout(timeout);
      _checkAlive();
    } catch (_) {
      await disconnectWebSocket();
      throw const AppException(
        'Could not open the TM event stream. Check API access and the selected field set.',
      );
    }
  }

  Future<void> disconnectWebSocket() async {
    final channel = _wsChannel;
    _wsChannel = null;
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    if (channel != null) {
      try {
        await channel.sink.close().timeout(const Duration(seconds: 1));
      } catch (_) {
        /* Best-effort close. */
      }
    }
  }

  Future<http.Response> _signedGetRaw(String path) async {
    _checkAlive();
    if (apiKey.trim().isEmpty) {
      throw const AppException('Add the TM API key in Connections.');
    }
    await _ensureAccessToken();
    final uri = normalizeTmUrl(baseUrl).resolve(path);
    http.Response? response;
    // Retain the existing server signature compatibility variants, but only
    // retry authentication failures, never unrelated server or network errors.
    for (var variant = 0; variant < 4; variant++) {
      final headers = await _buildSignedHeaders(
        uri,
        useRfcDate: variant < 2,
        includeKey: variant == 1 || variant == 2,
      );
      try {
        response = await _http.get(uri, headers: headers).timeout(timeout);
      } on TimeoutException {
        throw const TmApiException(
          'TM did not respond in time. Check the host and network, then retry.',
        );
      } catch (_) {
        throw const TmApiException(
          'Could not reach TM. Check the host and your network connection.',
        );
      }
      _checkAlive();
      if (response.statusCode == 200) return response;
      if (variant == 0 && response.statusCode == 401) {
        _token = null;
        await _ensureAccessToken();
      }
      if (![400, 401, 403].contains(response.statusCode)) break;
    }
    final code = response!.statusCode;
    throw TmApiException(
      code == 401 || code == 403 || code == 400
          ? 'TM rejected API access (HTTP $code). Check your TM server API key, client credentials, and computer clock.'
          : 'TM request failed (HTTP $code). Check that the server supports the local TM API.',
      statusCode: code,
    );
  }

  Future<Map<String, dynamic>> _signedGet(String path) async {
    final response = await _signedGetRaw(path);
    try {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) throw const FormatException();
      return data;
    } catch (_) {
      throw const TmApiException(
        'TM returned an unreadable response. Check API compatibility.',
      );
    }
  }

  Future<http.Response> debugSignedGetRaw(String path) => _signedGetRaw(path);

  Future<Map<String, String>> _buildSignedHeaders(
    Uri uri, {
    required bool useRfcDate,
    required bool includeKey,
  }) async {
    await _ensureAccessToken();
    final now = DateTime.now().toUtc();
    final date = useRfcDate ? HttpDate.format(now) : now.toIso8601String();
    final host = uri.hasPort ? uri.authority : uri.host;
    final path = '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
    final signature = AuthManager.signString(
      apiKey,
      AuthManager.createStringToSign(
        method: 'GET',
        pathWithQuery: path,
        token: _token!.value,
        host: host,
        dateStr: date,
        apiKeyHeader: apiKey,
        includeApiKeyInSignature: includeKey,
      ),
    );
    return {
      'Authorization': 'Bearer ${_token!.value}',
      'X-TM-Date': date,
      'X-TM-Signature': signature,
      if (includeKey) 'X-TM-Api-Key': apiKey,
    };
  }

  Future<List<dynamic>> getFieldsets() async {
    final data = await _signedGet('/api/fieldsets');
    final sets = data['fieldsets'] ?? data['fieldSets'];
    if (sets is! List) {
      throw const TmApiException('TM returned no recognizable field-set list.');
    }
    return sets;
  }

  Future<List<dynamic>> getMatches(String divisionId) async {
    final data = await _signedGet(
      '/api/matches/${Uri.encodeComponent(divisionId)}',
    );
    if (data['matches'] is! List) {
      throw const TmApiException('TM returned an unreadable match list.');
    }
    return data['matches'] as List;
  }

  Future<List<dynamic>> getTeams() async {
    final data = await _signedGet('/api/teams');
    if (data['teams'] is! List) {
      throw const TmApiException('TM returned an unreadable team list.');
    }
    return data['teams'] as List;
  }

  Future<List<dynamic>> getFieldsForFieldset(String fieldsetId) async {
    if (fieldsetId.isEmpty) return [];
    final id = Uri.encodeComponent(fieldsetId);
    for (final path in [
      '/api/fieldsets/$id/fields',
      '/api/fieldsets/$id',
      '/api/fieldsets/$id?includeFields=true',
      '/api/fieldsets?id=$id',
    ]) {
      Map<String, dynamic> data;
      try {
        data = await _signedGet(path);
      } on TmApiException catch (error) {
        if (error.statusCode == 404 || error.statusCode == 405) continue;
        rethrow;
      }
      final direct = data['fields'];
      if (direct is List) return direct;
      final nested = data['fieldSet'] ?? data['fieldset'];
      if (nested is Map && nested['fields'] is List) {
        return nested['fields'] as List;
      }
      final sets = data['fieldSets'] ?? data['fieldsets'];
      if (sets is List) {
        for (final set in sets.whereType<Map>()) {
          if ('${set['id'] ?? set['fieldSetID'] ?? set['fieldsetID'] ?? set['fieldSetId'] ?? set['fieldsetId']}' ==
                  fieldsetId &&
              set['fields'] is List) {
            return set['fields'] as List;
          }
        }
      }
    }
    throw const TmApiException(
      'TM did not provide fields for this field set. Try another field set or check API compatibility.',
    );
  }

  Future<int> getTotalFieldCount() async => TmFieldSet.parse(
    await getFieldsets(),
  ).fold<int>(0, (count, set) => count + set.fields.length);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _token = null;
    unawaited(disconnectWebSocket());
    if (_ownsHttp) _http.close();
    unawaited(_events.close());
  }

  static Future<TmApiClient> fromSettings() async {
    final settings = await LocalSettingsRepository().load();
    return TmApiClient(
      baseUrl: normalizeTmUrl(settings.tmHost).toString(),
      apiKey: settings.tmApiKey,
      fieldSetId: '',
      appCredentials: settings.credentials,
    );
  }
}
