import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tmlink/core/config.dart';

class AuthManager {
  /// Retrieves an OAuth token using client credentials.
  ///
  /// Throws an [HttpException] if the request fails.
  static Future<String> getOAuthToken() async {
    const String url = "https://auth.vextm.dwabtech.com/oauth2/token";

    final Map<String, String> data = {
      "grant_type": "client_credentials",
      "client_id": Config.clientId,
      "client_secret": Config.clientSecret,
    };

    try {
      final http.Response response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseBody = jsonDecode(response.body);
        return responseBody["access_token"] ?? "";
      } else {
        throw HttpException(
          "OAuth token request failed: ${response.statusCode} ${response.body}",
        );
      }
    } on SocketException {
      throw HttpException("Failed to connect to authentication server.");
    } catch (e) {
      throw HttpException("OAuth token request failed: $e");
    }
  }

  /// Creates a string to sign for authentication.
  ///
  /// - [method]: HTTP method (e.g., 'GET', 'POST'). Default is 'GET'.
  /// - [pathWithQuery]: Path with query parameters (e.g., '/api/matches?division=1').
  /// - [token]: OAuth access token.
  /// - [host]: Host of the request (e.g., '127.0.0.1:5000').
  /// - [dateStr]: Timestamp in RFC 1123 format.
  ///
  /// Returns a formatted string to be signed.
  static String createStringToSign({
    required String pathWithQuery,
    required String token,
    required String host,
    required String dateStr,
    String method = "GET",
  }) {
    return "$method\n"
        "$pathWithQuery\n"
        "token:$token\n"
        "host:$host\n"
        "x-tm-date:$dateStr\n";
  }

  /// Generates an HMAC-SHA256 signature for a given string using the API key.
  ///
  /// - [apiKey]: API key for signing.
  /// - [stringToSign]: The string to be signed.
  ///
  /// Returns a hex-encoded HMAC-SHA256 signature.
  static String signString(String apiKey, String stringToSign) {
    final hmacSha256 = Hmac(sha256, utf8.encode(apiKey));
    final digest = hmacSha256.convert(utf8.encode(stringToSign));
    return digest.toString();
  }
}
