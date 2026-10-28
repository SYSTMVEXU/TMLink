import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tmlink/core/app_credentials.dart';
import 'package:tmlink/core/endpoints.dart';
import 'package:tmlink/core/config.dart';

class OAuthToken {
  final String value;
  final DateTime expiresAt;
  const OAuthToken(this.value, this.expiresAt);
  bool get isExpired => DateTime.now()
      .toUtc()
      .add(const Duration(seconds: 30))
      .isAfter(expiresAt);
}

class AuthManager {
  static Future<OAuthToken> fetchToken({
    required http.Client client,
    required String clientId,
    required String clientSecret,
    bool bundled = false,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (clientId.isEmpty || clientSecret.isEmpty) {
      throw const AppException(
        'App authorization is unavailable. Set the DWAB environment variables for a Debug run, or install the official ATS release.',
      );
    }
    try {
      final response = await client
          .post(
            Uri.parse('https://auth.vextm.dwabtech.com/oauth2/token'),
            body: {
              'grant_type': 'client_credentials',
              'client_id': clientId,
              'client_secret': clientSecret,
            },
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        if (bundled &&
            (response.statusCode == 400 || response.statusCode == 401)) {
          throw const AppAuthorizationUpdateRequired(
            'App authorization was rejected. Install the latest ATS version and retry. If it continues, contact the app maintainer.',
          );
        }
        throw AppException(switch (response.statusCode) {
          400 || 401 =>
            'TM authorization was rejected. Check the app credentials and retry.',
          429 =>
            'DWAB is rate limiting ATS authorization requests (HTTP 429). Wait a few minutes before retrying.',
          _ =>
            'DWAB authorization service is unavailable (HTTP ${response.statusCode}). Check internet access and retry.',
        });
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['access_token'];
      if (token is! String || token.isEmpty) {
        throw const AppException('TM authorization returned an invalid token.');
      }
      final seconds = int.tryParse('${data['expires_in']}') ?? 300;
      return OAuthToken(
        token,
        DateTime.now().toUtc().add(Duration(seconds: seconds)),
      );
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'Could not reach the TM authorization service. Check your internet connection and retry.',
      );
    }
  }

  static Future<String> getOAuthToken() async {
    final credentials = Config.credentials;
    credentials.validate();
    final client = http.Client();
    try {
      return (await fetchToken(
        client: client,
        clientId: credentials.clientId,
        clientSecret: credentials.clientSecret,
        bundled: credentials.isBundled,
      )).value;
    } finally {
      client.close();
    }
  }

  static String createStringToSign({
    required String method,
    required String pathWithQuery,
    required String token,
    required String host,
    required String dateStr,
    String? apiKeyHeader,
    bool includeApiKeyInSignature = false,
  }) {
    final lines = [
      method.toUpperCase(),
      pathWithQuery,
      'token:$token',
      'host:$host',
      'x-tm-date:$dateStr',
      if (includeApiKeyInSignature &&
          apiKeyHeader != null &&
          apiKeyHeader.isNotEmpty)
        'x-tm-api-key:$apiKeyHeader',
    ];
    return '${lines.join('\n')}\n';
  }

  static String signString(String apiKey, String stringToSign) => Hmac(
    sha256,
    utf8.encode(apiKey),
  ).convert(utf8.encode(stringToSign)).toString();
}
