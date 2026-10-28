import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:tmlink/core/obs_client.dart';
import 'package:tmlink/core/tm_api_client.dart';
import 'package:tmlink/core/upcoming_match.dart';

import 'test_support.dart';

Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late AppFixture fixture;
  setUp(() {
    fixture = AppFixture();
  });
  tearDown(() {
    fixture.app.dispose();
  });

  Future<void> prepareSimulator() async {
    await fixture.app.initialize();
    await fixture.app.setDeveloperMode(true);
    await fixture.app.connectAll();
    await fixture.app.setMapping('test-1', 'Main');
    await fixture.app.setMapping('test-2', 'Break');
    await fixture.app.setMapping('test-3', 'Skills');
  }

  test(
    'elimination refresh keeps qualifications and replaces elimination participants',
    () async {
      var now = DateTime.utc(2026, 10, 27);
      Map<String, dynamic> info(String round, String team) => {
        'matchInfo': {
          'round': round,
          'match': 1,
          'instance': 2,
          'alliances': [
            {
              'teams': [
                for (final number in [team, '2B', '3C', '4D'])
                  {'number': number},
              ],
            },
          ],
        },
      };
      final clients = <FakeTm>[];
      final obs = FakeObs();
      final repository = MemorySettings()..upcoming = const UpcomingSettings();
      final app = AppController(
        repository: repository,
        now: () => now,
        tmFactory: (_, id) {
          final client = FakeTm(id)
            ..matches = [info('QUAL', '111A'), info('F', '222B')];
          clients.add(client);
          return client;
        },
        obsFactory: (_) => obs,
      );
      addTearDown(app.dispose);
      await app.initialize();
      await app.connectAll();
      clients.first.matches = [
        info('QUAL', 'unexpected-qual-change'),
        info('F', '333C'),
      ];
      await app.startEliminations();
      await app.setMapping('10', 'Main');
      await app.setMapping('20', 'Break');
      await app.startMonitoring();
      clients.last.events.add({
        'type': 'fieldMatchAssigned',
        'fieldID': 10,
        'match': {'round': 'QUAL', 'match': 1},
      });
      await drain();
      expect(
        obs.inputUpdates
            .where((u) => u['name'] == 'Team1Number')
            .last['settings'],
        {'text': '111A'},
      );
      clients.first.matches = [
        info('QUAL', 'another-qual-change'),
        info('F', '555E'),
      ];
      now = now.add(const Duration(seconds: 6));
      clients.last.events.add({'type': 'matchScored'});
      await drain();
      clients.last.events.add({
        'type': 'fieldMatchAssigned',
        'fieldID': 20,
        'match': {'round': 'F', 'match': 1, 'instance': 2},
      });
      await drain();
      expect(
        obs.inputUpdates
            .where((u) => u['name'] == 'Team1Number')
            .last['settings'],
        {'text': '555E'},
      );
      expect(app.queuedMatch!.label, 'F 2');
    },
  );

  test(
    'queue shows upcoming and automatic activation cannot overwrite it',
    () async {
      await fixture.ready();
      await fixture.app.startMonitoring();
      fixture.monitor.events.add({
        'type': 'fieldMatchAssigned',
        'fieldID': 10,
        'match': {'round': 'QUAL', 'match': 7},
      });
      fixture.monitor.events.add({'type': 'fieldActivated', 'fieldID': 10});
      await drain();
      expect(fixture.obs.switches, ['Upcoming Match']);
      expect(fixture.app.activeFieldId, isNull);
      expect(fixture.obs.inputUpdates.first, {
        'name': 'MatchStr',
        'settings': {'text': 'QUAL 7'},
      });
      fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': 10});
      await drain();
      expect(fixture.obs.switches, ['Upcoming Match', 'Main']);
      expect(fixture.app.activeFieldId, '10');
    },
  );

  test(
    'Stop cancels remaining preview updates and queued camera switches',
    () async {
      await fixture.ready();
      await fixture.app.startMonitoring();
      fixture.obs.inputGate = Completer<void>();
      fixture.monitor.events.add({'type': 'fieldMatchAssigned', 'fieldID': 10});
      await drain();
      fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': 20});
      await fixture.app.stopMonitoring();
      fixture.obs.inputGate!.complete();
      await drain();
      expect(fixture.obs.switches, ['Upcoming Match']);
      expect(fixture.obs.inputUpdates, hasLength(1));
    },
  );

  test(
    'missing overlay inputs are reported without disabling field switching',
    () async {
      await fixture.ready();
      await fixture.app.startMonitoring();
      fixture.obs.failInputs.add('MatchStr');
      fixture.monitor.events.add({'type': 'fieldMatchAssigned', 'fieldID': 10});
      await drain();
      expect(fixture.app.monitoring, true);
      expect(
        fixture.app.activity.any(
          (entry) => entry.message.contains('MatchStr') && entry.error,
        ),
        true,
      );
      fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': 20});
      await drain();
      expect(fixture.obs.switches, ['Upcoming Match', 'Break']);
    },
  );

  test(
    'missing upcoming scene blocks monitoring until an available scene is chosen',
    () async {
      await fixture.ready();
      fixture.app.scenes.remove('Upcoming Match');
      expect(fixture.app.canStart, false);
      expect(
        await fixture.app.saveUpcomingSettings(
          fixture.app.upcoming.copyWith(scene: 'Skills'),
        ),
        true,
      );
      expect(fixture.app.canStart, true);
      await fixture.app.startMonitoring();
      fixture.monitor.events.add({'type': 'fieldMatchAssigned', 'fieldID': 10});
      await drain();
      expect(fixture.obs.switches, ['Skills']);
    },
  );

  test(
    'developer queue simulation includes the native auto-activation sequence',
    () async {
      await prepareSimulator();
      await fixture.app.startMonitoring();
      fixture.app.simulateMatchQueue('test-1');
      await drain();
      expect(fixture.obs.switches, ['Upcoming Match']);
      fixture.app.simulateFieldActivation('test-1');
      await drain();
      expect(fixture.obs.switches, ['Upcoming Match', 'Main']);
    },
  );

  test(
    'developer mode bypasses TM and requires verified OBS and routing',
    () async {
      fixture.repository.settings = const AppSettings();
      final app = fixture.app;
      await app.initialize();
      expect(app.developerMode, false);
      await app.setDeveloperMode(true);
      expect(app.tmState, ServiceState.disconnected);
      expect(app.fields.length, 3);
      expect(app.canStart, false);
      await app.connectAll();
      expect(fixture.tmClients, isEmpty);
      expect(app.canStart, false);
      for (final field in app.fields) {
        await app.setMapping(field.id, 'Main');
      }
      expect(app.canStart, true);
      await app.startMonitoring();
      expect(app.monitoring, true);
      expect(fixture.tmClients, isEmpty);
    },
  );

  test(
    'simulated events use real OBS switching and Stop cancels queued activations',
    () async {
      await prepareSimulator();
      final app = fixture.app;
      app.simulateFieldActivation('test-1');
      await drain();
      expect(fixture.obs.switches, isEmpty);
      await app.startMonitoring();
      app.simulateFieldActivation('unknown');
      app.simulateFieldActivation('test-2');
      await drain();
      expect(fixture.obs.switches, ['Break']);
      expect(app.activeFieldId, 'test-2');
      expect(app.currentScene, 'Break');
      fixture.obs.switchGate = Completer<void>();
      app.simulateFieldActivation('test-1');
      await drain();
      app.simulateFieldActivation('test-3');
      await drain();
      await app.stopMonitoring();
      fixture.obs.switchGate!.complete();
      app.simulateFieldActivation('test-3');
      await drain();
      expect(fixture.obs.switches, ['Break', 'Main']);
      expect(fixture.tmClients, isEmpty);
    },
  );

  test(
    'developer routing and selections do not replace tournament routing',
    () async {
      await fixture.ready();
      final app = fixture.app;
      await app.setDeveloperMode(true);
      await app.setMapping('test-1', 'Skills');
      await app.setDeveloperMode(false);
      expect(app.canStart, false);
      expect(app.fields, isEmpty);
      await app.connectTm();
      expect(app.selectedFieldSetId, '1');
      expect(app.sceneFor('10'), 'Main');
      expect(app.sceneFor('20'), 'Break');
      await app.setDeveloperMode(true);
      expect(app.sceneFor('test-1'), 'Skills');
    },
  );

  test(
    'mode cannot change during simulation and OBS failure pauses it',
    () async {
      await prepareSimulator();
      final app = fixture.app;
      await app.startMonitoring();
      await app.setDeveloperMode(false);
      expect(app.developerMode, true);
      fixture.obs.failSwitch = true;
      app.simulateFieldActivation('test-1');
      await drain();
      expect(app.monitoring, false);
      expect(app.obsState, ServiceState.failed);
      expect(app.canStart, false);
      await app.setDeveloperMode(false);
      expect(app.developerMode, false);
    },
  );

  test('developer mode is not restored when the app restarts', () async {
    await prepareSimulator();
    final restarted = AppController(repository: fixture.repository);
    await restarted.initialize();
    expect(restarted.developerMode, false);
    expect(restarted.canStart, false);
    restarted.dispose();
  });

  test(
    'start requires verified services and a saved mapping for every field',
    () async {
      final app = fixture.app;
      await app.initialize();
      expect(app.canStart, false);
      await app.startMonitoring();
      expect(app.monitoring, false);
      await app.connectAll();
      expect(app.canStart, false);
      await app.setMapping('10', 'Main');
      expect(app.canStart, false);
      await app.setMapping('20', 'Break');
      expect(app.canStart, true);
      await app.startMonitoring();
      expect(app.monitoring, true);
      final count = fixture.tmClients.length;
      await app.startMonitoring();
      expect(fixture.tmClients.length, count);
      await app.stopMonitoring();
      expect(app.monitoring, false);
      expect(fixture.monitor.closed, true);
    },
  );

  test(
    'field IDs are not treated as indices, malformed events never route',
    () {
      const fields = [
        TmField(id: '10', name: 'A'),
        TmField(id: '20', name: 'B'),
      ];
      expect(
        AppController.fieldIdForEvent({
          'type': 'matchStarted',
          'fieldId': 20,
        }, fields),
        '20',
      );
      expect(
        AppController.fieldIdForEvent({
          'type': 'matchStarted',
          'fieldIndex': 0,
        }, fields),
        '10',
      );
      expect(
        AppController.fieldIdForEvent({
          'type': 'matchStarted',
          'fieldId': 0,
        }, fields),
        null,
      );
      expect(
        AppController.fieldIdForEvent({'type': 'matchStarted'}, fields),
        null,
      );
      expect(
        AppController.fieldIdForEvent({
          'type': 'matchStarted',
          'fieldIndex': -1,
        }, fields),
        null,
      );
      expect(
        AppController.fieldIdForEvent({
          'type': 'other',
          'fieldIndex': 0,
        }, fields),
        null,
      );
    },
  );

  test(
    'events serialize scene switches and Stop cancels queued work',
    () async {
      await fixture.ready();
      await fixture.app.startMonitoring();
      fixture.obs.switchGate = Completer<void>();
      fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': '10'});
      await drain();
      fixture.monitor.events.add({'type': 'matchStarted', 'fieldID': '20'});
      await drain();
      expect(fixture.obs.switches, ['Main']);
      await fixture.app.stopMonitoring();
      fixture.obs.switchGate!.complete();
      await drain();
      expect(fixture.obs.switches, ['Main']);
      expect(fixture.app.currentScene, null);
    },
  );

  test(
    'native activation and match-start IDs resolve without guessing field positions',
    () {
      const fields = [
        TmField(id: '10', name: 'A'),
        TmField(id: '20', name: 'B'),
      ];
      for (final type in ['fieldMatchAssigned', 'matchStarted']) {
        for (final key in ['fieldID', 'fieldId']) {
          expect(
            AppController.fieldIdForEvent({'type': type, key: 20}, fields),
            '20',
          );
          expect(
            AppController.fieldIdForEvent({
              'type': type,
              'data': {key: '20'},
            }, fields),
            '20',
          );
        }
        expect(
          AppController.fieldIdForEvent({
            'type': type,
            'fieldIndex': 0,
          }, fields),
          '10',
        );
        for (final malformed in [
          {'fieldID': 999, 'fieldIndex': 0},
          {'fieldID': null, 'fieldIndex': 0},
          {'fieldID': true},
          {'fieldID': 20.0},
          {
            'fieldID': {'id': 20},
          },
          {'fieldID': 10, 'fieldId': 20},
          {
            'fieldID': 10,
            'data': {'fieldID': 20},
          },
          {'fieldIndex': -1},
          {'fieldIndex': 2},
        ]) {
          expect(
            AppController.fieldIdForEvent({'type': type, ...malformed}, fields),
            isNull,
          );
        }
      }
      expect(
        AppController.fieldIdForEvent({
          'type': 'matchStopped',
          'fieldID': 20,
        }, fields),
        isNull,
      );
    },
  );

  test(
    'match start received during stream setup is routed once monitoring is ready',
    () async {
      final obs = FakeObs();
      final app = AppController(
        repository: MemorySettings(),
        tmFactory: (_, id) =>
            FakeTm(id)
              ..eventOnConnect = {'type': 'matchStarted', 'fieldID': 20},
        obsFactory: (_) => obs,
      );
      addTearDown(app.dispose);
      await app.initialize();
      await app.connectAll();
      await app.setMapping('10', 'Main');
      await app.setMapping('20', 'Break');
      await app.startMonitoring();
      await drain();
      expect(app.monitoring, true);
      expect(obs.switches, ['Break']);
      expect(app.activeFieldId, '20');
    },
  );

  test('TM errors and OBS disconnects pause monitoring', () async {
    await fixture.ready();
    await fixture.app.startMonitoring();
    fixture.monitor.events.addError(const AppException('TM disconnected'));
    await drain();
    expect(fixture.app.monitoring, false);
    expect(fixture.app.tmState, ServiceState.failed);
    await fixture.app.connectTm();
    await fixture.app.startMonitoring();
    fixture.obs.errorEvents.add(const ObsException('OBS disconnected'));
    await drain();
    expect(fixture.app.monitoring, false);
    expect(fixture.app.obsState, ServiceState.failed);
    expect(fixture.app.canStart, false);
  });

  test(
    'routing survives field-set changes and save failures prevent start',
    () async {
      await fixture.ready();
      await fixture.app.selectFieldSet('2');
      expect(fixture.app.sceneFor('30'), null);
      await fixture.app.setMapping('30', 'Skills');
      await fixture.app.selectFieldSet('1');
      expect(fixture.app.sceneFor('10'), 'Main');
      fixture.repository.failRouting = true;
      await fixture.app.setMapping('10', 'Break');
      expect(fixture.app.canStart, false);
      expect(fixture.app.routingSaveFailed, true);
      fixture.repository.failRouting = false;
      await fixture.app.saveRouting();
      expect(fixture.app.canStart, true);
      expect(fixture.app.sceneFor('10'), 'Break');
    },
  );

  test('legacy positional mappings migrate to stable field IDs', () async {
    fixture.repository.legacy = {
      '1': ['Main', 'Break'],
    };
    await fixture.app.initialize();
    await fixture.app.connectAll();
    expect(fixture.app.sceneFor('10'), 'Main');
    expect(fixture.app.sceneFor('20'), 'Break');
    expect(fixture.repository.savedSnapshots.single.values.single, {
      '10': 'Main',
      '20': 'Break',
    });
  });

  test('unsuccessful settings save retains active configuration', () async {
    await fixture.ready();
    final before = fixture.app.settings;
    fixture.repository.failSave = true;
    expect(
      await fixture.app.saveSettings(const AppSettings(tmHost: 'other.local')),
      false,
    );
    expect(fixture.app.settings, same(before));
    expect(fixture.app.tmState, ServiceState.connected);
    expect(fixture.app.notice, contains('Save failed'));
    expect(fixture.app.savingSettings, false);
  });

  test('settings and field sets cannot change while monitoring', () async {
    await fixture.ready();
    await fixture.app.startMonitoring();
    expect(await fixture.app.saveSettings(const AppSettings()), false);
    await fixture.app.selectFieldSet('2');
    expect(fixture.app.selectedFieldSetId, '1');
    await fixture.app.setMapping('10', 'Break');
    expect(fixture.app.sceneFor('10'), 'Main');
  });

  test(
    'failed initialization is recoverable without wiping settings',
    () async {
      fixture.repository.failLoad = true;
      await fixture.app.initialize();
      expect(fixture.app.initialized, true);
      expect(fixture.app.storageAvailable, false);
      fixture.repository.failLoad = false;
      await fixture.app.initialize();
      expect(fixture.app.storageAvailable, true);
      expect(fixture.app.notice, null);
    },
  );

  test('queued activations coalesce to the latest field', () async {
    await fixture.ready();
    await fixture.app.startMonitoring();
    fixture.obs.switchGate = Completer<void>();
    fixture.monitor.events.add({'type': 'matchStarted', 'fieldId': '10'});
    await drain();
    fixture.monitor.events.add({'type': 'matchStarted', 'fieldId': '20'});
    fixture.monitor.events.add({'type': 'matchStarted', 'fieldId': '20'});
    await drain();
    fixture.obs.switchGate!.complete();
    await drain();
    expect(fixture.obs.switches, ['Main', 'Break']);
    expect(fixture.app.currentScene, 'Break');
  });

  test('failed scene switching pauses and requires OBS revalidation', () async {
    await fixture.ready();
    await fixture.app.startMonitoring();
    fixture.obs.failSwitch = true;
    fixture.monitor.events.add({'type': 'matchStarted', 'fieldId': '10'});
    await drain();
    expect(fixture.app.monitoring, false);
    expect(fixture.app.obsState, ServiceState.failed);
    expect(fixture.app.canStart, false);
  });

  test('selected field set is restored per server', () async {
    fixture.repository.selections = {'http://localhost:8080': '2'};
    await fixture.app.initialize();
    await fixture.app.connectAll();
    expect(fixture.app.selectedFieldSetId, '2');
    await fixture.app.selectFieldSet('1');
    expect(fixture.repository.selections['http://localhost:8080'], '1');
  });

  test('legacy routing is not copied to a different TM server', () async {
    fixture.repository.legacy = {
      '1': ['Main', 'Break'],
    };
    await fixture.app.initialize();
    expect(
      await fixture.app.saveSettings(const AppSettings(tmHost: 'new-server')),
      true,
    );
    await fixture.app.connectAll();
    expect(fixture.app.sceneFor('10'), null);
    expect(fixture.app.canStart, false);
  });

  test('closed controller ignores late network responses', () async {
    await fixture.app.initialize();
    final connecting = fixture.app.connectTm();
    final tm = fixture.tmClients.last;
    // connectTm is waiting on the immediate asynchronous fake response.
    fixture.app.dispose();
    await connecting;
    expect(tm.closed, true);
    expect(fixture.app.tmState, isNot(ServiceState.connected));
  });
}
