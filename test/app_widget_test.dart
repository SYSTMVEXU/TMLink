import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmlink/main.dart';
import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/core/app_credentials.dart';
import 'package:tmlink/core/app_settings.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const assetsChannel = MethodChannel('com.ats.team_assets');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(assetsChannel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(assetsChannel, null);
  });
  setUpAll(() async {
    // Load the native font for human-reviewable previews on macOS.
    final font = File('/System/Library/Fonts/SFNS.ttf');
    if (await font.exists()) {
      final loader = FontLoader('.SF Pro Text')
        ..addFont(font.readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
    final icons = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await icons.load();
  });

  Future<void> preview(WidgetTester tester, String name) async {
    if (Platform.environment['TMLINK_RENDER_PREVIEWS'] != '1') return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('preview')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/ui-previews').create(recursive: true);
      await File(
        'build/ui-previews/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final size in [
    const Size(1240, 820),
    const Size(760, 560),
    const Size(480, 760),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'workspace layout ${size.width.toInt()} ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.platformBrightnessTestValue = dark
              ? Brightness.dark
              : Brightness.light;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final fixture = AppFixture();
          await fixture.ready();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('preview'),
              child: TMLinkApp(controller: fixture.app),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Field Alpha'), findsOneWidget);
          expect(find.text('Start monitoring'), findsOneWidget);
          await preview(
            tester,
            'routing-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.text('Connections').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Save & Connect'), findsOneWidget);
          await preview(
            tester,
            'connections-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.text('Activity').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Connections').first);
          await tester.pumpAndSettle();
          expect(find.text('Developer mode'), findsNothing);
          await tester.ensureVisible(find.text('Advanced user mode'));
          await tester.tap(find.text('Advanced user mode'));
          await tester.pumpAndSettle();
          expect(fixture.app.settings.advancedUserMode, true);
          await preview(
            tester,
            'advanced-connections-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.text('Scene Routing').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Match data and OBS source names'), findsOneWidget);
          await tester.ensureVisible(find.text('Start monitoring'));
          await tester.tap(find.text('Start monitoring'));
          await tester.pumpAndSettle();
          fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': 10});
          await tester.pumpAndSettle();
          expect(fixture.obs.switches, ['Main']);
          expect(fixture.app.activeFieldId, '10');
          await preview(
            tester,
            'monitoring-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.ensureVisible(find.text('Stop monitoring'));
          await tester.tap(find.text('Stop monitoring'));
          await tester.pumpAndSettle();
          expect(fixture.app.monitoring, false);
          await tester.pumpWidget(const SizedBox());
          fixture.app.dispose();
        },
      );
    }
  }

  testWidgets('connection form validates bad hosts and masks secrets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1240, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = AppFixture();
    await tester.pumpWidget(TMLinkApp(controller: fixture.app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connections').first);
    await tester.pumpAndSettle();
    final host = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Server address',
    );
    await tester.enterText(host, 'http://');
    await tester.ensureVisible(find.text('Save & Connect'));
    await tester.tap(find.text('Save & Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter a TM host'), findsOneWidget);
    expect(fixture.tmClients, isEmpty);
    final passwords = tester
        .widgetList<TextField>(find.byType(TextField))
        .where(
          (w) =>
              w.decoration?.labelText == 'TM API key' ||
              w.decoration?.labelText == 'WebSocket password',
        );
    expect(passwords.every((w) => w.obscureText), true);
    await tester.pumpWidget(const SizedBox());
    fixture.app.dispose();
  });

  testWidgets('large text stays within the narrow workspace', (tester) async {
    tester.view.physicalSize = const Size(760, 560);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fixture = AppFixture();
    await fixture.ready();
    await tester.pumpWidget(TMLinkApp(controller: fixture.app));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Connections').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    fixture.app.dispose();
  });

  testWidgets('connections do not expose client credential fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1240, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = AppFixture();
    fixture.repository.settings = const AppSettings(
      tmApiKey: 'old-server-key',
      clientId: 'internal-client',
      clientSecret: 'internal-secret',
    );
    await tester.pumpWidget(TMLinkApp(controller: fixture.app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connections').first);
    await tester.pumpAndSettle();
    expect(find.text('Advanced authorization'), findsNothing);
    expect(find.text('Client ID'), findsNothing);
    expect(find.text('Client secret'), findsNothing);
    expect(find.text('API bearer key'), findsNothing);
    final key = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'TM API key',
    );
    await tester.enterText(key, ' new-server-key ');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(fixture.repository.settings.tmApiKey, 'new-server-key');
    expect(fixture.repository.settings.clientId, isEmpty);
    expect(fixture.repository.settings.clientSecret, isEmpty);
    expect(fixture.tmClients, isEmpty);
    await tester.pumpWidget(const SizedBox());
    fixture.app.dispose();
  });

  testWidgets(
    'bundled authorization is automatic and is never copied into saved overrides',
    (tester) async {
      tester.view.physicalSize = const Size(1240, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MemorySettings();
      final app = AppController(
        repository: repository,
        defaultCredentials: AppCredentials(
          clientId: 'bundled-private-id',
          clientSecret: 'bundled-private-secret',
          expiresAt: DateTime.utc(2099),
          source: CredentialSource.bundled,
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('preview'),
          child: TMLinkApp(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connections').first);
      await tester.pumpAndSettle();
      expect(find.text('Advanced authorization'), findsNothing);
      expect(find.text('Client ID'), findsNothing);
      await preview(tester, 'automatic-authorization');
      final host = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      );
      await tester.enterText(host, 'updated-host:8080');
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(repository.settings.clientId, isEmpty);
      expect(repository.settings.clientSecret, isEmpty);
      expect(app.credentials.clientId, 'bundled-private-id');
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'expired releases show a persistent update action and explain connection failure',
    (tester) async {
      final app = AppController(
        repository: MemorySettings(),
        defaultCredentials: AppCredentials(
          clientId: 'expired-private-id',
          clientSecret: 'expired-private-secret',
          expiresAt: DateTime.utc(2026),
          source: CredentialSource.bundled,
        ),
        now: () => DateTime.utc(2027),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('preview'),
          child: TMLinkApp(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('authorization-notice')),
        findsOneWidget,
      );
      expect(find.text('Download update'), findsOneWidget);
      await preview(tester, 'expired-authorization');
      await app.connectTm();
      expect(app.tmState, ServiceState.failed);
      expect(app.tmMessage, AppCredentials.updateMessage);
      await tester.tap(find.text('Connections').first);
      await tester.pumpAndSettle();
      expect(find.text('Download update'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
