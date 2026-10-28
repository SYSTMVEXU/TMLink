import 'dart:io';

import 'package:tmlink/core/auth_manager.dart';
import 'package:tmlink/core/config.dart';
import 'package:tmlink/core/endpoints.dart';

/// Checks app authorization only; a local TM server is not needed.
Future<void> main() async {
  if (Config.clientId.isEmpty || Config.clientSecret.isEmpty) {
    stderr.writeln(
      'Set both VEX_TM_CLIENT_ID and VEX_TM_CLIENT_SECRET in the process environment.',
    );
    exitCode = 1;
    return;
  }
  try {
    await AuthManager.getOAuthToken();
    stdout.writeln('DWAB client authorization succeeded.');
  } on AppException catch (error) {
    // AuthManager supplies sanitized errors; never print response bodies/tokens.
    stderr.writeln(error.message);
    exitCode = 1;
  } catch (_) {
    stderr.writeln('DWAB authorization check failed.');
    exitCode = 1;
  }
}
