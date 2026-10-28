import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

Future<void> settleMusic() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.ats.media_controls');
  late AppFixture fixture;
  late List<MethodCall> calls;
  Future<Object?> Function(MethodCall)? response;

  setUp(() {
    fixture = AppFixture();
    calls = [];
    response = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (response != null) return response!(call);
          return switch (call.method) {
            'requestPermission' => ['Music'],
            'pausePlaying' => ['com.apple.Music'],
            _ => null,
          };
        });
  });

  tearDown(() async {
    fixture.app.dispose();
    await settleMusic();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> enableMusic() async {
    await fixture.app.setAdvancedUserMode(true);
    expect(await fixture.app.setMatchMusicAutomation(true), isTrue);
  }

  test('enabling music requests permission before monitoring starts', () async {
    await fixture.ready();
    await enableMusic();
    expect(calls.map((call) => call.method), ['requestPermission']);
    expect(fixture.app.monitoring, isFalse);
  });

  test(
    'queue leaves music playing; match start pauses and end resumes',
    () async {
      await fixture.ready();
      await enableMusic();
      await fixture.app.startMonitoring();
      fixture.monitor.events.add({
        'type': 'fieldMatchAssigned',
        'fieldID': 10,
        'match': {'round': 'QUAL', 'match': 1},
      });
      await settleMusic();
      expect(calls.map((call) => call.method), ['requestPermission']);
      fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': 10});
      await settleMusic();
      fixture.monitor.events.add({'type': 'matchStopped', 'fieldID': 10});
      await settleMusic();
      expect(calls.map((call) => call.method), [
        'requestPermission',
        'pausePlaying',
        'resumePlayers',
      ]);
      expect(calls.last.arguments, {
        'players': ['com.apple.Music'],
      });
      expect(fixture.obs.switches, ['Upcoming Match', 'Main']);
    },
  );

  test('basic mode never controls music on match events', () async {
    await fixture.ready();
    await fixture.app.startMonitoring();
    fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': 10});
    fixture.monitor.events.add({'type': 'matchStopped', 'fieldID': 10});
    await settleMusic();
    expect(calls, isEmpty);
    expect(fixture.obs.switches, ['Main']);
  });

  test('music errors do not stop field scene switching', () async {
    await fixture.ready();
    await enableMusic();
    response = (call) async {
      throw PlatformException(code: 'media_control_failed');
    };
    await fixture.app.startMonitoring();
    fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': 10});
    await settleMusic();
    expect(fixture.obs.switches, ['Main']);
    expect(fixture.app.monitoring, isTrue);
    expect(
      fixture.app.activity.any(
        (entry) =>
            entry.error && entry.message.contains('Music automation failed'),
      ),
      isTrue,
    );
  });

  test(
    'scoring and queuing do not resume music; only match stop does',
    () async {
      await fixture.ready();
      await enableMusic();
      await fixture.app.startMonitoring();
      fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': 10});
      await settleMusic();

      fixture.monitor.events.add({'type': 'matchScored', 'fieldID': 10});
      fixture.monitor.events.add({
        'type': 'fieldMatchAssigned',
        'fieldID': 20,
        'match': {'round': 'QUAL', 'match': 2},
      });
      fixture.monitor.events.add({'type': 'fieldActivated', 'fieldID': 20});
      await settleMusic();
      expect(calls.map((call) => call.method), [
        'requestPermission',
        'pausePlaying',
      ]);

      fixture.monitor.events.add({'type': 'matchStopped', 'fieldID': 10});
      await settleMusic();
      fixture.monitor.events.add({'type': 'matchStopped', 'fieldID': 10});
      fixture.monitor.events.add({'type': 'matchScored', 'fieldID': 10});
      await settleMusic();
      expect(calls.map((call) => call.method), [
        'requestPermission',
        'pausePlaying',
        'resumePlayers',
      ]);
      expect(fixture.obs.switches, ['Main', 'Upcoming Match']);
    },
  );

  test('a pause that finishes after Stop is immediately resumed', () async {
    await fixture.ready();
    await enableMusic();
    final pause = Completer<Object?>();
    response = (call) async =>
        call.method == 'pausePlaying' ? pause.future : null;
    await fixture.app.startMonitoring();
    fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': 10});
    await settleMusic();
    await fixture.app.stopMonitoring();
    pause.complete(['com.apple.Music']);
    await settleMusic();
    expect(calls.map((call) => call.method), [
      'requestPermission',
      'pausePlaying',
      'resumePlayers',
    ]);
    expect(fixture.app.monitoring, isFalse);
  });
}
