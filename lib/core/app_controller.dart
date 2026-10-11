import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:tmlink/core/obs_client.dart';
import 'package:tmlink/core/tm_api_client.dart';
import 'package:tmlink/core/simulated_tm_client.dart';

enum ServiceState { disconnected, connecting, connected, failed }

class ActivityEntry {
  final DateTime time;
  final String message;
  final bool error;
  ActivityEntry(this.message, {this.error = false}) : time = DateTime.now();
}

typedef TmClientFactory =
    TmApiClient Function(AppSettings settings, String fieldSetId);
typedef ObsClientFactory = ObsClient Function(AppSettings settings);

class AppController extends ChangeNotifier {
  final SettingsRepository repository;
  final TmClientFactory _tmFactory;
  final ObsClientFactory _obsFactory;
  AppController({
    SettingsRepository? repository,
    TmClientFactory? tmFactory,
    ObsClientFactory? obsFactory,
  }) : repository = repository ?? LocalSettingsRepository(),
       _tmFactory =
           tmFactory ??
           ((s, id) => TmApiClient(
             baseUrl: normalizeTmUrl(s.tmHost).toString(),
             apiKey: s.tmApiKey,
             fieldSetId: id,
             clientId: s.effectiveClientId,
             clientSecret: s.effectiveClientSecret,
           )),
       _obsFactory =
           obsFactory ??
           ((s) => ObsClient(
             wsUrl: normalizeObsUrl(s.obsUrl).toString(),
             password: s.obsPassword,
           ));

  AppSettings settings = const AppSettings();
  ServiceState tmState = ServiceState.disconnected;
  ServiceState obsState = ServiceState.disconnected;
  String tmMessage = 'Connect to load your field sets.';
  String obsMessage = 'Connect to load your scenes.';
  String? notice;
  bool initialized = false;
  bool storageAvailable = false;
  bool loadingFields = false;
  bool starting = false;
  bool monitoring = false;
  bool _developerMode = false;
  bool get developerMode => _developerMode;
  bool testingScene = false;
  bool savingSettings = false;
  bool routingSaveFailed = false;
  bool _mappingReadFailed = false;
  bool _disposed = false;
  bool _initializing = false;
  bool _healthChecking = false;
  int _tmRevision = 0;
  int _obsRevision = 0;
  int _monitorRevision = 0;
  int _pendingSaves = 0;
  Future<void> _saveQueue = Future.value();
  Future<void> _switchQueue = Future.value();
  List<TmFieldSet> fieldSets = [];
  List<String> scenes = [];
  String? selectedFieldSetId;
  String? activeFieldId;
  String? currentScene;
  List<ActivityEntry> activity = [];
  Map<String, Map<String, String>> _mappings = {};
  Map<String, List<String>> _legacy = {};
  Map<String, String> _selections = {};
  String? _legacyHost;
  bool get routingUnavailable => _mappingReadFailed;
  TmApiClient? _tm;
  TmApiClient? _monitorTm;
  ObsClient? _obs;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<ObsException>? _obsErrors;
  Timer? _healthTimer;

  bool get connecting =>
      tmState == ServiceState.connecting || obsState == ServiceState.connecting;
  bool get savingRouting => _pendingSaves > 0;
  bool get locked => monitoring || starting || savingSettings;
  TmFieldSet? get selectedFieldSet {
    for (final set in fieldSets) {
      if (set.id == selectedFieldSetId) return set;
    }
    return null;
  }

  List<TmField> get fields => selectedFieldSet?.fields ?? const [];
  String get _selectionKey => developerMode
      ? 'developer-simulator-v1'
      : normalizeTmUrl(settings.tmHost).toString();
  String get _scope => '$_selectionKey|$selectedFieldSetId';
  String? sceneFor(String fieldId) =>
      selectedFieldSetId == null ? null : _mappings[_scope]?[fieldId];
  int get mappedCount =>
      fields.where((f) => scenes.contains(sceneFor(f.id))).length;
  String? get readinessIssue {
    if (!storageAvailable) {
      return 'Resolve saved-settings access in Connections.';
    }
    if (connecting || loadingFields || savingSettings) {
      return 'Wait for connection checks to finish.';
    }
    if (!developerMode && tmState != ServiceState.connected) {
      return 'Connect Tournament Manager first.';
    }
    if (obsState != ServiceState.connected) return 'Connect OBS first.';
    if (fields.isEmpty) return 'Choose a field set with available fields.';
    if (_mappingReadFailed) {
      return 'Saved routing could not be read. Restore it before monitoring.';
    }
    if (savingRouting || routingSaveFailed) {
      return 'Save your scene routing before monitoring.';
    }
    if (mappedCount != fields.length) {
      return 'Assign an available OBS scene to every field.';
    }
    return null;
  }

  bool get canStart => !locked && !testingScene && readinessIssue == null;

  TmApiClient _createTmClient(String id) =>
      developerMode ? SimulatedTmClient(id) : _tmFactory(settings, id);

  Future<void> setDeveloperMode(bool enabled) async {
    if (_disposed ||
        !initialized ||
        !storageAvailable ||
        locked ||
        connecting ||
        loadingFields ||
        testingScene ||
        savingRouting ||
        enabled == developerMode) {
      return;
    }
    _tmRevision++;
    _tm?.dispose();
    _tm = null;
    _developerMode = enabled;
    tmState = ServiceState.disconnected;
    fieldSets = [];
    selectedFieldSetId = null;
    activeFieldId = null;
    tmMessage = enabled
        ? 'TM bypassed. Loading simulated fields…'
        : 'Connect to load your field sets.';
    notice = null;
    _log(
      enabled
          ? 'Developer mode enabled. TM is simulated; OBS scene switches are real.'
          : 'Developer mode disabled. Connect TM before monitoring.',
    );
    if (enabled) await connectTm();
  }

  void simulateFieldActivation(String id) {
    if (_disposed ||
        !developerMode ||
        !monitoring ||
        !fields.any((field) => field.id == id)) {
      return;
    }
    final client = _monitorTm;
    if (client is SimulatedTmClient) client.activate(id);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _log(String message, {bool error = false}) {
    if (_disposed) return;
    activity.insert(0, ActivityEntry(message, error: error));
    if (activity.length > 100) activity.removeLast();
    _changed();
  }

  void clearNotice() {
    notice = null;
    _changed();
  }

  void clearActivity() {
    activity.clear();
    _changed();
  }

  Future<void> initialize() async {
    if (_disposed || savingSettings || _initializing) return;
    _initializing = true;
    initialized = false;
    notice = null;
    _changed();
    try {
      final loaded = await repository.load();
      if (_disposed) return;
      settings = loaded;
      storageAvailable = true;
      _selections = await repository.loadSelection();
      try {
        _mappings = await repository.loadMappings();
        _legacy = await repository.loadLegacyMappings();
        _legacyHost = normalizeTmUrl(settings.tmHost).toString();
        _mappingReadFailed = false;
      } catch (error) {
        _mappingReadFailed = true;
        notice = '$error';
        _log(notice!, error: true);
      }
    } catch (error) {
      storageAvailable = false;
      notice = '$error';
      _log(notice!, error: true);
    } finally {
      initialized = true;
      _initializing = false;
      _changed();
    }
  }

  Future<bool> saveSettings(AppSettings value) async {
    if (_disposed || locked || connecting || loadingFields || testingScene) {
      return false;
    }
    savingSettings = true;
    notice = null;
    _changed();
    try {
      value.validate();
      await repository.save(value);
      if (_disposed) return false;
      // Saved settings become authoritative only after storage confirms them.
      settings = value;
      storageAvailable = true;
      _tmRevision++;
      _obsRevision++;
      _tm?.dispose();
      _tm = null;
      _obs?.dispose();
      _obs = null;
      await _obsErrors?.cancel();
      _obsErrors = null;
      tmState = obsState = ServiceState.disconnected;
      fieldSets = [];
      scenes = [];
      selectedFieldSetId = null;
      currentScene = null;
      activeFieldId = null;
      tmMessage = obsMessage = 'Settings saved. Connect to verify access.';
      _log('Connection settings saved securely.');
      return true;
    } catch (error) {
      notice = '$error';
      _log(notice!, error: true);
      return false;
    } finally {
      savingSettings = false;
      _changed();
    }
  }

  Future<void> connectAll() async {
    if (!storageAvailable || locked || testingScene) return;
    await Future.wait([connectTm(), connectObs()]);
  }

  Future<void> connectTm() async {
    if (_disposed ||
        locked ||
        loadingFields ||
        testingScene ||
        tmState == ServiceState.connecting) {
      return;
    }
    final revision = ++_tmRevision;
    _tm?.dispose();
    _tm = null;
    tmState = ServiceState.connecting;
    tmMessage = 'Checking API access…';
    _changed();
    TmApiClient? client;
    try {
      client = _createTmClient('');
      final sets = TmFieldSet.parse(await client.getFieldsets());
      if (_disposed || revision != _tmRevision) {
        client.dispose();
        return;
      }
      _tm?.dispose();
      _tm = client;
      fieldSets = sets;
      selectedFieldSetId ??= _selections[_selectionKey];
      if (!sets.any((s) => s.id == selectedFieldSetId)) {
        selectedFieldSetId = sets.isEmpty ? null : sets.first.id;
      }
      tmState = developerMode
          ? ServiceState.disconnected
          : ServiceState.connected;
      tmMessage = developerMode
          ? 'TM bypassed. Three simulated fields available.'
          : '${sets.length} field set${sets.length == 1 ? '' : 's'} available';
      _log(
        developerMode ? 'TM simulator ready.' : 'Tournament Manager connected.',
      );
      if (selectedFieldSetId != null) await selectFieldSet(selectedFieldSetId!);
    } catch (error) {
      client?.dispose();
      if (_disposed || revision != _tmRevision) return;
      _tm = null;
      tmState = ServiceState.failed;
      tmMessage = '$error';
      _log(tmMessage, error: true);
    }
    _changed();
  }

  Future<void> connectObs() async {
    if (_disposed ||
        locked ||
        testingScene ||
        obsState == ServiceState.connecting) {
      return;
    }
    final revision = ++_obsRevision;
    _obs?.dispose();
    _obs = null;
    unawaited(_obsErrors?.cancel());
    _obsErrors = null;
    obsState = ServiceState.connecting;
    obsMessage = 'Checking WebSocket access…';
    _changed();
    ObsClient? client;
    try {
      client = _obsFactory(settings);
      await client.connect();
      final names = await client.getSceneNames();
      if (_disposed || revision != _obsRevision) {
        client.dispose();
        return;
      }
      await _obsErrors?.cancel();
      _obs?.dispose();
      _obs = client;
      scenes = names.toSet().toList()..sort();
      obsState = ServiceState.connected;
      obsMessage =
          '${scenes.length} scene${scenes.length == 1 ? '' : 's'} available';
      _obsErrors = client.errors.listen((error) {
        if (_disposed || revision != _obsRevision) return;
        obsState = ServiceState.failed;
        obsMessage = '$error';
        if (monitoring || starting) {
          unawaited(
            stopMonitoring(reason: 'OBS disconnected. Monitoring paused.'),
          );
        }
        _log(obsMessage, error: true);
      });
      _log('OBS connected and scene access verified.');
    } catch (error) {
      client?.dispose();
      if (_disposed || revision != _obsRevision) return;
      obsState = ServiceState.failed;
      obsMessage = '$error';
      _log(obsMessage, error: true);
    }
    _changed();
  }

  Future<void> selectFieldSet(String id) async {
    if (_disposed || locked || loadingFields) return;
    final matches = fieldSets.where((s) => s.id == id);
    if (matches.isEmpty) return;
    final revision = _tmRevision;
    selectedFieldSetId = id;
    _selections[_selectionKey] = id;
    loadingFields = true;
    notice = null;
    _changed();
    try {
      var set = matches.first;
      if (set.fields.isEmpty) {
        final data = await _tm!.getFieldsForFieldset(id);
        set = TmFieldSet(
          id: set.id,
          name: set.name,
          fields: TmFieldSet.parseFields(data),
        );
      }
      if (_disposed || revision != _tmRevision) return;
      fieldSets = fieldSets.map((s) => s.id == id ? set : s).toList();
      await repository.saveSelection(_selections);
      if (!developerMode &&
          !_mappingReadFailed &&
          !_mappings.containsKey(_scope) &&
          _legacy[id] != null &&
          _legacyHost == normalizeTmUrl(settings.tmHost).toString()) {
        final previous = _legacy[id]!;
        _mappings[_scope] = {
          for (var i = 0; i < set.fields.length && i < previous.length; i++)
            set.fields[i].id: previous[i],
        };
        await saveRouting();
        notice =
            'Previous scene routing restored. Review the assignments before starting monitoring.';
        _log('Previous scene routing restored for ${set.name}.');
      }
    } catch (error) {
      if (!_disposed && revision == _tmRevision) {
        notice = '$error';
        _log(notice!, error: true);
      }
    } finally {
      if (revision == _tmRevision) loadingFields = false;
      _changed();
    }
  }

  Future<void> setMapping(String fieldId, String? scene) async {
    if (_disposed ||
        locked ||
        testingScene ||
        _mappingReadFailed ||
        !fields.any((f) => f.id == fieldId) ||
        (scene != null && !scenes.contains(scene))) {
      return;
    }
    final mappings = _mappings.putIfAbsent(_scope, () => {});
    if (scene == null || scene.isEmpty) {
      mappings.remove(fieldId);
    } else {
      mappings[fieldId] = scene;
    }
    _changed();
    await saveRouting();
  }

  Future<void> resetUnreadableRouting() async {
    if (_disposed || locked || !_mappingReadFailed) return;
    try {
      await repository.resetMappings();
      if (_disposed) return;
      _mappings = {};
      _legacy = {};
      _mappingReadFailed = false;
      routingSaveFailed = false;
      notice =
          'Routing reset. The original data has been backed up. Assign scenes before monitoring.';
      _log(notice!);
    } catch (error) {
      notice = '$error';
      _log(notice!, error: true);
    }
    _changed();
  }

  Future<void> saveRouting() async {
    if (_disposed || _mappingReadFailed) return;
    final snapshot = _mappings.map(
      (key, value) => MapEntry(key, Map<String, String>.from(value)),
    );
    _pendingSaves++;
    _changed();
    _saveQueue = _saveQueue.then((_) async {
      try {
        await repository.saveMappings(snapshot);
        routingSaveFailed = false;
      } catch (error) {
        routingSaveFailed = true;
        notice = '$error';
        _log(notice!, error: true);
      } finally {
        _pendingSaves--;
        _changed();
      }
    });
    await _saveQueue;
  }

  Future<void> startMonitoring() async {
    if (!canStart) return;
    final revision = ++_monitorRevision;
    starting = true;
    notice = null;
    _changed();
    final client = _createTmClient(selectedFieldSetId!);
    _monitorTm = client;
    String? initialField;
    var activationRevision = 0;
    void route(String id) {
      final activation = ++activationRevision;
      // Serialize transitions and cancel queued work on Stop/disconnect.
      _switchQueue = _switchQueue.then((_) async {
        if (_disposed ||
            revision != _monitorRevision ||
            !monitoring ||
            activation != activationRevision) {
          return;
        }
        final scene = sceneFor(id);
        if (scene == null || !scenes.contains(scene)) {
          await stopMonitoring(
            reason:
                'A routed OBS scene is no longer available. Refresh scenes before restarting.',
          );
          return;
        }
        try {
          await _obs!.setCurrentScene(scene);
          if (_disposed || revision != _monitorRevision) return;
          activeFieldId = id;
          currentScene = scene;
          _log('Switched OBS to “$scene”.');
        } catch (error) {
          if (revision != _monitorRevision) return;
          notice = '$error';
          obsState = ServiceState.failed;
          obsMessage = '$error';
          _log(notice!, error: true);
          await stopMonitoring(
            reason:
                'OBS could not switch scenes. Check the scene and reconnect.',
          );
        }
      });
    }

    _eventSubscription = client.eventStream.listen(
      (event) {
        if (revision != _monitorRevision || (!starting && !monitoring)) return;
        final id = fieldIdForEvent(event, fields);
        if (id == null) return;
        if (starting) {
          initialField = id;
        } else {
          route(id);
        }
      },
      onError: (Object error) {
        if (_disposed || revision != _monitorRevision) return;
        tmState = ServiceState.failed;
        tmMessage = '$error';
        unawaited(stopMonitoring(reason: '$error'));
      },
    );
    try {
      await client.connectWebSocket();
      if (_disposed || revision != _monitorRevision) return;
      starting = false;
      monitoring = true;
      if (initialField != null) route(initialField!);
      _healthTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        if (_disposed || revision != _monitorRevision || _healthChecking) {
          return;
        }
        _healthChecking = true;
        try {
          final available = await _obs!.getSceneNames();
          if (_disposed || revision != _monitorRevision) return;
          scenes = available.toSet().toList()..sort();
          if (mappedCount != fields.length) {
            await stopMonitoring(
              reason:
                  'OBS scenes changed. Review scene routing before restarting.',
            );
          }
        } catch (error) {
          if (revision == _monitorRevision) {
            obsState = ServiceState.failed;
            obsMessage = '$error';
            await stopMonitoring(
              reason: 'Lost access to OBS scenes. Reconnect to continue.',
            );
          }
        } finally {
          _healthChecking = false;
        }
        _changed();
      });
      _log(
        developerMode
            ? 'Simulation started. Activate a test field to switch OBS.'
            : 'Monitoring started for ${selectedFieldSet!.name}.',
      );
    } catch (error) {
      if (!_disposed && revision == _monitorRevision) {
        notice = '$error';
        tmState = ServiceState.failed;
        tmMessage = '$error';
        await stopMonitoring(reason: 'Monitoring could not start. $error');
      }
    } finally {
      if (revision == _monitorRevision) starting = false;
      _changed();
    }
  }

  /// Field IDs and zero-based indices are distinct. Unknown events never route
  /// to a default field, which previously caused accidental scene switches.
  static String? fieldIdForEvent(
    Map<String, dynamic> event,
    List<TmField> fields,
  ) {
    if (event['type'] != 'fieldActivated') return null;
    final data = event['data'] is Map<String, dynamic>
        ? event['data'] as Map<String, dynamic>
        : event;
    final id = data['fieldId']?.toString();
    if (id != null) return fields.any((f) => f.id == id) ? id : null;
    final index = int.tryParse('${data['fieldIndex']}');
    if (index == null || index < 0 || index >= fields.length) return null;
    return fields[index].id;
  }

  Future<void> stopMonitoring({String? reason}) async {
    _monitorRevision++;
    monitoring = false;
    starting = false;
    _healthTimer?.cancel();
    _healthTimer = null;
    final subscription = _eventSubscription;
    _eventSubscription = null;
    final client = _monitorTm;
    _monitorTm = null;
    _changed();
    await subscription?.cancel();
    client?.dispose();
    if (reason != null) notice = reason;
    _log(
      reason ?? 'Monitoring stopped. No further scene switches will be sent.',
      error: reason != null,
    );
  }

  Future<void> testScene(String scene) async {
    if (_disposed ||
        locked ||
        testingScene ||
        obsState != ServiceState.connected ||
        !scenes.contains(scene)) {
      return;
    }
    testingScene = true;
    notice = null;
    _changed();
    try {
      await _obs!.setCurrentScene(scene);
      if (_disposed) return;
      currentScene = scene;
      _log('Scene test confirmed: “$scene”.');
    } catch (error) {
      notice = '$error';
      obsState = ServiceState.failed;
      obsMessage = '$error';
      _log(notice!, error: true);
    } finally {
      testingScene = false;
      _changed();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _monitorRevision++;
    _tmRevision++;
    _obsRevision++;
    _healthTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    unawaited(_obsErrors?.cancel());
    _monitorTm?.dispose();
    _tm?.dispose();
    _obs?.dispose();
    super.dispose();
  }
}
