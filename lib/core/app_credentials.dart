import 'dart:convert';

import 'package:tmlink/core/endpoints.dart';

enum CredentialSource { none, bundled, environment }

class AppAuthorizationUpdateRequired extends AppException {
  const AppAuthorizationUpdateRequired([
    super.message = AppCredentials.updateMessage,
  ]);
}

/// App authorization stays in memory and comes from the build-specific source.
class AppCredentials {
  final String clientId;
  final String clientSecret;
  final DateTime? expiresAt;
  final CredentialSource source;
  const AppCredentials({
    this.clientId = '',
    this.clientSecret = '',
    this.expiresAt,
    this.source = CredentialSource.none,
  });

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  bool get isBundled => source == CredentialSource.bundled;
  bool isExpired(DateTime now) =>
      expiresAt != null && !now.toUtc().isBefore(expiresAt!);

  static const updateMessage =
      'This version of ATS needs an update to connect to Tournament Manager. Download and install the latest version.';

  String? updateNotice(DateTime now) {
    if (!isBundled) return null;
    if (!isConfigured || expiresAt == null || isExpired(now)) {
      return updateMessage;
    }
    if (expiresAt!.difference(now.toUtc()) <= const Duration(days: 30)) {
      return 'An update to ATS is needed soon. Install the latest version before ${expiresAt!.toIso8601String().substring(0, 10)} (UTC) to keep connecting to Tournament Manager.';
    }
    return null;
  }

  void validate({DateTime? now}) {
    if (isBundled &&
        (!isConfigured ||
            expiresAt == null ||
            isExpired(now ?? DateTime.now()))) {
      throw const AppAuthorizationUpdateRequired();
    }
    if (!isConfigured) {
      throw const AppException(
        'App authorization is unavailable. Set VEX_TM_CLIENT_ID and VEX_TM_CLIENT_SECRET for a Debug run, or install the official ATS release.',
      );
    }
  }

  /// Concealment against literal searches, not a cryptographic trust boundary.
  /// Keep decoding at runtime rather than inlining a reconstructed constant.
  @pragma('vm:never-inline')
  static AppCredentials decodeBundle(String payload, String mask) {
    if (payload.isEmpty && mask.isEmpty) return const AppCredentials();
    try {
      final bytes = base64Decode(payload);
      final pad = base64Decode(mask);
      if (bytes.isEmpty || pad.length != bytes.length) {
        throw const FormatException();
      }
      final data =
          jsonDecode(
                utf8.decode(
                  List.generate(bytes.length, (i) => bytes[i] ^ pad[i]),
                ),
              )
              as Map<String, dynamic>;
      final id = data['clientId'] as String;
      final secret = data['clientSecret'] as String;
      final expiry = DateTime.parse(data['expiresAt'] as String);
      if (data['version'] != 1 ||
          id.isEmpty ||
          secret.isEmpty ||
          !expiry.isUtc) {
        throw const FormatException();
      }
      return AppCredentials(
        clientId: id,
        clientSecret: secret,
        expiresAt: expiry,
        source: CredentialSource.bundled,
      );
    } catch (_) {
      // No parsing errors may include the reconstructed payload in logs.
      return const AppCredentials(source: CredentialSource.bundled);
    }
  }
}
