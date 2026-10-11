import 'dart:async';

import 'package:tmlink/core/app_controller.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:tmlink/core/obs_client.dart';
import 'package:tmlink/core/tm_api_client.dart';

class MemorySettings extends SettingsRepository {
  AppSettings settings = const AppSettings(
    tmHost: 'localhost:8080',
    tmApiKey: 'test-key',
  );
  Map<String, Map<String, String>> mappings = {};
  Map<String, List<String>> legacy = {};
  bool failSave = false;
  bool failLoad = false;
  bool failRouting = false;
  Map<String, String> selections = {};
  final savedSnapshots = <Map<String, Map<String, String>>>[];
  @override
  Future<Map<String, String>> loadSelection() async => selections;
  @override
  Future<void> saveSelection(Map<String, String> value) async {
    selections = Map.from(value);
  }

  @override
  Future<AppSettings> load() async {
    if (failLoad) throw const AppException('Storage unavailable');
    return settings;
  }

  @override
  Future<void> save(AppSettings value) async {
    if (failSave) throw const AppException('Save failed');
    settings = value;
  }

  @override
  Future<Map<String, Map<String, String>>> loadMappings() async => mappings;
  @override
  Future<Map<String, List<String>>> loadLegacyMappings() async => legacy;
  @override
  Future<void> saveMappings(Map<String, Map<String, String>> value) async {
    if (failRouting) throw const AppException('Routing save failed');
    savedSnapshots.add(value);
    mappings = value;
  }
}

class FakeTm extends TmApiClient {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  bool closed = false;
  bool failConnect = false;
  Map<String, dynamic>? eventOnConnect;
  Completer<List<dynamic>>? fieldSetGate;
  FakeTm(String fieldSetId)
    : super(
        baseUrl: 'http://localhost:8080',
        apiKey: 'test',
        fieldSetId: fieldSetId,
      );
  @override
  Stream<Map<String, dynamic>> get eventStream => events.stream;
  @override
  Future<List<dynamic>> getFieldsets() async => fieldSetGate == null
      ? [
          {
            'id': '1',
            'name': 'Competition',
            'fields': [
              {'id': '10', 'name': 'Field Alpha'},
              {'id': '20', 'name': 'Field Beta'},
            ],
          },
          {
            'id': '2',
            'name': 'Skills',
            'fields': [
              {'id': '30', 'name': 'Skills Field'},
            ],
          },
        ]
      : await fieldSetGate!.future;
  @override
  Future<void> connectWebSocket() async {
    if (failConnect) throw const AppException('Stream failed');
    if (eventOnConnect != null) {
      events.add(eventOnConnect!);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void dispose() {
    if (closed) return;
    closed = true;
    unawaited(events.close());
    super.dispose();
  }
}

class FakeObs extends ObsClient {
  final errorEvents = StreamController<ObsException>.broadcast();
  final switches = <String>[];
  List<String> sceneNames = ['Main', 'Break', 'Skills'];
  bool connected = false;
  bool closed = false;
  bool failConnect = false;
  Completer<void>? switchGate;
  bool failSwitch = false;
  FakeObs() : super(wsUrl: 'ws://localhost:4455/');
  @override
  Stream<ObsException> get errors => errorEvents.stream;
  @override
  bool get isConnected => connected;
  @override
  Future<void> connect() async {
    if (failConnect) throw const ObsException('Password rejected');
    connected = true;
  }

  @override
  Future<List<String>> getSceneNames() async => sceneNames;
  @override
  Future<void> setCurrentScene(String scene) async {
    if (failSwitch) throw const ObsException('Scene missing');
    switches.add(scene);
    if (switchGate != null) await switchGate!.future;
  }

  @override
  void dispose() {
    if (closed) return;
    closed = true;
    unawaited(errorEvents.close());
    super.dispose();
  }
}

class AppFixture {
  final repository = MemorySettings();
  final tmClients = <FakeTm>[];
  final obsClients = <FakeObs>[];
  late final AppController app = AppController(
    repository: repository,
    tmFactory: (settings, id) {
      final tm = FakeTm(id);
      tmClients.add(tm);
      return tm;
    },
    obsFactory: (settings) {
      final obs = FakeObs();
      obsClients.add(obs);
      return obs;
    },
  );
  FakeTm get monitor => tmClients.last;
  FakeObs get obs => obsClients.last;
  Future<void> ready() async {
    await app.initialize();
    await app.connectAll();
    await app.setMapping('10', 'Main');
    await app.setMapping('20', 'Break');
  }
}
