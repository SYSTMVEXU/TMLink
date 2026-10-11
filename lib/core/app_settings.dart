import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmlink/core/config.dart';
import 'package:tmlink/core/endpoints.dart';

export 'package:tmlink/core/endpoints.dart';

class AppSettings {
  final String tmHost;
  final String tmApiKey;
  final String clientId;
  final String clientSecret;
  final String obsUrl;
  final String obsPassword;
  const AppSettings({
    this.tmHost = Config.defaultTmIp,
    this.tmApiKey = '',
    this.clientId = '',
    this.clientSecret = '',
    this.obsUrl = Config.defaultObsWsUrl,
    this.obsPassword = '',
  });

  String get effectiveClientId => clientId.isEmpty ? Config.clientId : clientId;
  String get effectiveClientSecret =>
      clientSecret.isEmpty ? Config.clientSecret : clientSecret;

  void validate() {
    normalizeTmUrl(tmHost);
    normalizeObsUrl(obsUrl);
    if (clientId.isEmpty != clientSecret.isEmpty) {
      throw const AppException(
        'Enter both the TM client ID and secret, or leave both blank to use your launch environment.',
      );
    }
  }
}

abstract class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
  Future<Map<String, Map<String, String>>> loadMappings();
  Future<void> saveMappings(Map<String, Map<String, String>> mappings);
  Future<Map<String, List<String>>> loadLegacyMappings();
  Future<Map<String, String>> loadSelection() async => {};
  Future<void> saveSelection(Map<String, String> selections) async {}
  Future<void> resetMappings() async {
    throw const AppException('Routing reset is unavailable.');
  }
}

/// Preferences hold routing. Connection settings live in the OS credential store.
class LocalSettingsRepository extends SettingsRepository {
  final FlutterSecureStorage _secure;
  LocalSettingsRepository({FlutterSecureStorage? secure})
    : _secure =
          secure ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  @override
  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // Migrate only after a verified credential-store write. A failed migration
      // preserves the original value so it can be retried on the next launch.
      for (final key in ['tm_api_key', 'obs_ws_password', 'tm_password']) {
        final legacy = prefs.getString(key);
        if (legacy != null) {
          if (await _secure.read(key: key) != legacy) {
            await _secure.write(key: key, value: legacy);
            if (await _secure.read(key: key) != legacy) {
              throw const AppException(
                'Credential storage could not be verified.',
              );
            }
          }
          await prefs.remove(key);
        }
      }
      final bundle = await _secure.read(key: 'connection_credentials_v1');
      final values = bundle == null
          ? <String, dynamic>{}
          : jsonDecode(bundle) as Map<String, dynamic>;
      return AppSettings(
        tmHost:
            values['tmHost'] as String? ??
            prefs.getString('tm_ip') ??
            Config.defaultTmIp,
        obsUrl:
            values['obsUrl'] as String? ??
            prefs.getString('obs_ws_url') ??
            Config.defaultObsWsUrl,
        tmApiKey:
            values['tmApiKey'] as String? ??
            await _secure.read(key: 'tm_api_key') ??
            '',
        obsPassword:
            values['obsPassword'] as String? ??
            await _secure.read(key: 'obs_ws_password') ??
            '',
        clientId: values['clientId'] as String? ?? '',
        clientSecret: values['clientSecret'] as String? ?? '',
      );
    } catch (_) {
      throw const AppException(
        'Could not read saved credentials. Unlock your system keychain and retry.',
      );
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    settings.validate();
    final prefs = await SharedPreferences.getInstance();
    final credentials = jsonEncode({
      'tmHost': normalizeTmUrl(settings.tmHost).toString(),
      'obsUrl': normalizeObsUrl(settings.obsUrl).toString(),
      'tmApiKey': settings.tmApiKey,
      'obsPassword': settings.obsPassword,
      'clientId': settings.clientId,
      'clientSecret': settings.clientSecret,
    });
    try {
      await _secure.write(key: 'connection_credentials_v1', value: credentials);
      if (await _secure.read(key: 'connection_credentials_v1') != credentials) {
        throw const AppException('Credential storage could not be verified.');
      }
      await prefs.remove('tm_api_key');
      await prefs.remove('obs_ws_password');
    } catch (_) {
      throw const AppException(
        'Could not save settings. Check access to your system keychain and retry.',
      );
    }
  }

  @override
  Future<Map<String, Map<String, String>>> loadMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('scene_mappings_v2');
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data.map(
        (scope, fields) => MapEntry(
          scope,
          (fields as Map<String, dynamic>).map(
            (id, scene) => MapEntry(id, scene as String),
          ),
        ),
      );
    } catch (_) {
      throw const AppException(
        'Saved routing could not be read. Your original data has been preserved.',
      );
    }
  }

  @override
  Future<void> saveMappings(Map<String, Map<String, String>> mappings) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('scene_mappings_v2', jsonEncode(mappings))) {
      throw const AppException('Could not save scene routing. Please retry.');
    }
  }

  @override
  Future<Map<String, List<String>>> loadLegacyMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('scene_mappings_by_fieldset');
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data.map(
        (id, scenes) => MapEntry(id, (scenes as List).cast<String>()),
      );
    } catch (_) {
      throw const AppException(
        'Previous scene routing could not be read. Your original data has been preserved.',
      );
    }
  }

  @override
  Future<Map<String, String>> loadSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('selected_fieldsets_v1');
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveSelection(Map<String, String> selections) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      'selected_fieldsets_v1',
      jsonEncode(selections),
    )) {
      throw const AppException('The selected field set could not be saved.');
    }
  }

  @override
  Future<void> resetMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final backup = jsonEncode({
      'scene_mappings_v2': prefs.getString('scene_mappings_v2'),
      'scene_mappings_by_fieldset': prefs.getString(
        'scene_mappings_by_fieldset',
      ),
    });
    final key =
        'scene_mappings_backup_${DateTime.now().microsecondsSinceEpoch}';
    if (!await prefs.setString(key, backup) || prefs.getString(key) != backup) {
      throw const AppException(
        'Routing could not be backed up. Reset was cancelled.',
      );
    }
    if (!await prefs.setString('scene_mappings_v2', '{}') ||
        !await prefs.remove('scene_mappings_by_fieldset')) {
      throw const AppException(
        'Routing reset could not complete. The original data has been backed up.',
      );
    }
  }
}
