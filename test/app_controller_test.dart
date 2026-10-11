import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:tmlink/core/obs_client.dart';
import 'package:tmlink/core/tm_api_client.dart';

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
          'type': 'fieldActivated',
          'fieldId': 20,
        }, fields),
        '20',
      );
      expect(
        AppController.fieldIdForEvent({
          'type': 'fieldActivated',
          'fieldIndex': 0,
        }, fields),
        '10',
      );
      expect(
        AppController.fieldIdForEvent({
          'type': 'fieldActivated',
          'fieldId': 0,
        }, fields),
        null,
      );
      expect(
        AppController.fieldIdForEvent({'type': 'fieldActivated'}, fields),
        null,
      );
      expect(
        AppController.fieldIdForEvent({
          'type': 'fieldActivated',
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
      fixture.monitor.events.add({'type': 'fieldActivated', 'fieldId': '10'});
      await drain();
      fixture.monitor.events.add({'type': 'fieldActivated', 'fieldId': '20'});
      await drain();
      expect(fixture.obs.switches, ['Main']);
      await fixture.app.stopMonitoring();
      fixture.obs.switchGate!.complete();
      await drain();
      expect(fixture.obs.switches, ['Main']);
      expect(fixture.app.currentScene, null);
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
    fixture.monitor.events.add({'type': 'fieldActivated', 'fieldId': '10'});
    await drain();
    fixture.monitor.events.add({'type': 'fieldActivated', 'fieldId': '20'});
    fixture.monitor.events.add({'type': 'fieldActivated', 'fieldId': '20'});
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
    fixture.monitor.events.add({'type': 'fieldActivated', 'fieldId': '10'});
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
