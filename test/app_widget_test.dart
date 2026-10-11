import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmlink/main.dart';
import 'package:tmlink/core/app_settings.dart';

import 'test_support.dart';

void main() {
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
          await tester.ensureVisible(find.text('Developer mode'));
          await tester.tap(find.text('Developer mode'));
          await tester.pumpAndSettle();
          expect(fixture.app.developerMode, true);
          await preview(
            tester,
            'developer-connections-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.tap(find.text('Scene Routing').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Test Field 1'), findsOneWidget);
          expect(find.text('Activate Test Field 1'), findsOneWidget);
          for (final field in fixture.app.fields) {
            await fixture.app.setMapping(field.id, 'Main');
          }
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Start simulation'));
          await tester.tap(find.text('Start simulation'));
          await tester.pumpAndSettle();
          expect(find.text('SIMULATION RUNNING'), findsOneWidget);
          await tester.ensureVisible(find.text('Activate Test Field 1'));
          await tester.tap(find.text('Activate Test Field 1'));
          await tester.pumpAndSettle();
          expect(fixture.obs.switches, ['Main']);
          expect(fixture.app.activeFieldId, 'test-1');
          await preview(
            tester,
            'simulator-${size.width.toInt()}-${dark ? 'dark' : 'light'}',
          );
          await tester.ensureVisible(find.text('Stop simulation'));
          await tester.tap(find.text('Stop simulation'));
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

  testWidgets('client authorization form saves credentials and masks secrets', (
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
    await tester.tap(find.text('Client authorization'));
    await tester.pumpAndSettle();
    expect(find.text('Client ID'), findsOneWidget);
    expect(find.text('Client secret'), findsOneWidget);
    expect(find.text('API bearer key'), findsNothing);
    final key = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'TM API key',
    );
    await tester.enterText(key, ' new-server-key ');
    final clientId = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Client ID',
    );
    final clientSecret = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Client secret',
    );
    await tester.ensureVisible(clientId);
    await tester.enterText(clientId, ' new-client ');
    await tester.ensureVisible(clientSecret);
    await tester.enterText(clientSecret, ' new-secret ');
    expect(tester.widget<TextField>(clientSecret).obscureText, true);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(fixture.repository.settings.tmApiKey, 'new-server-key');
    expect(fixture.repository.settings.clientId, 'new-client');
    expect(fixture.repository.settings.clientSecret, ' new-secret ');
    expect(fixture.tmClients, isEmpty);
    await tester.pumpWidget(const SizedBox());
    fixture.app.dispose();
  });
}
