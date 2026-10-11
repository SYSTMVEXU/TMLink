import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmlink/core/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> secureValues;
  var failWrite = false;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureValues = {};
    failWrite = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final arguments = call.arguments as Map;
          final key = arguments['key'] as String;
          if (call.method == 'read') return secureValues[key];
          if (call.method == 'write') {
            if (failWrite) throw PlatformException(code: 'locked');
            secureValues[key] = arguments['value'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('URL validation supports hostnames, IPv6, TLS and explicit ports', () {
    expect(
      normalizeTmUrl('host.local:8080').toString(),
      'http://host.local:8080',
    );
    expect(normalizeTmUrl('https://[::1]:8443').port, 8443);
    expect(normalizeObsUrl('localhost').toString(), 'ws://localhost:4455/');
    expect(normalizeObsUrl('wss://example.local').port, 443);
    for (final value in [
      '',
      'http://',
      'ftp://host',
      'user:password@host',
      'host/a',
      'host:99999',
      'bad host',
    ]) {
      expect(
        () => normalizeTmUrl(value),
        throwsA(isA<AppException>()),
        reason: value,
      );
    }
    expect(() => normalizeObsUrl('http://host'), throwsA(isA<AppException>()));
  });

  test('legacy secrets migrate only after verified keychain writes', () async {
    SharedPreferences.setMockInitialValues({
      'tm_api_key': 'api',
      'obs_ws_password': ' obs password ',
    });
    final repo = LocalSettingsRepository();
    final loaded = await repo.load();
    expect(loaded.tmApiKey, 'api');
    expect(loaded.obsPassword, ' obs password ');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('tm_api_key'), false);
    expect(prefs.containsKey('obs_ws_password'), false);
    expect(secureValues['tm_api_key'], 'api');
  });

  test('failed secret migration preserves original preferences', () async {
    SharedPreferences.setMockInitialValues({'tm_api_key': 'original'});
    failWrite = true;
    await expectLater(
      LocalSettingsRepository().load(),
      throwsA(isA<AppException>()),
    );
    expect(
      (await SharedPreferences.getInstance()).getString('tm_api_key'),
      'original',
    );
  });

  test(
    'settings persist in one verified bundle and preserve password spaces',
    () async {
      final repo = LocalSettingsRepository();
      await repo.save(
        const AppSettings(
          tmHost: 'host:8080',
          obsUrl: 'localhost',
          tmApiKey: 'api',
          clientId: 'client',
          clientSecret: 'secret',
          obsPassword: ' password ',
        ),
      );
      final loaded = await repo.load();
      expect(loaded.tmHost, 'http://host:8080');
      expect(loaded.obsUrl, 'ws://localhost:4455/');
      expect(loaded.obsPassword, ' password ');
      expect(
        jsonDecode(secureValues['connection_credentials_v1']!)['clientSecret'],
        'secret',
      );
      expect(
        (await SharedPreferences.getInstance()).getString('obs_ws_password'),
        null,
      );
    },
  );

  test(
    'routing reset makes a verified backup before clearing assignments',
    () async {
      SharedPreferences.setMockInitialValues({
        'scene_mappings_v2': 'corrupt-data',
        'scene_mappings_by_fieldset': '{"1":["Main"]}',
      });
      final repo = LocalSettingsRepository();
      await repo.resetMappings();
      final prefs = await SharedPreferences.getInstance();
      final backupKey = prefs.getKeys().singleWhere(
        (key) => key.startsWith('scene_mappings_backup_'),
      );
      final backup = jsonDecode(prefs.getString(backupKey)!) as Map;
      expect(backup['scene_mappings_v2'], 'corrupt-data');
      expect(backup['scene_mappings_by_fieldset'], '{"1":["Main"]}');
      expect(await repo.loadMappings(), isEmpty);
      expect(await repo.loadLegacyMappings(), isEmpty);
    },
  );

  test(
    'corrupt mappings are reported and original data is preserved',
    () async {
      SharedPreferences.setMockInitialValues({'scene_mappings_v2': 'not-json'});
      await expectLater(
        LocalSettingsRepository().loadMappings(),
        throwsA(isA<AppException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).getString('scene_mappings_v2'),
        'not-json',
      );
    },
  );
}
