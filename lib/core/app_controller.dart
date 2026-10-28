import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tmlink/core/app_credentials.dart';
import 'package:tmlink/core/app_settings.dart';
import 'package:tmlink/core/config.dart';
import 'package:tmlink/core/obs_client.dart';
import 'package:tmlink/core/tm_api_client.dart';
import 'package:tmlink/core/simulated_tm_client.dart';
import 'package:tmlink/core/team_assets_folder.dart';
import 'package:tmlink/core/upcoming_match.dart';

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
  final TmClientFactory? _tmFactory;
  final ObsClientFactory _obsFactory;
  final AppCredentials defaultCredentials;
  final DateTime Function() _now;
  AppController({
    SettingsRepository? repository,
    TmClientFactory? tmFactory,
    ObsClientFactory? obsFactory,
    AppCredentials? defaultCredentials,
    DateTime Function()? now,
  }) : repository = repository ?? LocalSettingsRepository(),
       _tmFactory = tmFactory,
       defaultCredentials = defaultCredentials ?? Config.credentials,
       _now = now ?? DateTime.now,
       _obsFactory =
           obsFactory ??
           ((s) => ObsClient(
             wsUrl: normalizeObsUrl(s.obsUrl).toString(),
             password: s.obsPassword,
           ));

  AppSettings settings = const AppSettings();
  UpcomingSettings upcoming = const UpcomingSettings();
  UpcomingMatch? queuedMatch;
  bool importingAssets = false;
  bool eliminationsMode = false;
  bool get loadingMatches => _matchLoading != null;
  final Map<String, UpcomingMatch> _matches = {};
  Future<void>? _matchLoading;
  int _matchLoadRevision = -1;
  DateTime? _lastElimsRefresh;
  Timer? _elimsTimer;
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
  bool _authorizationUpdateRequired = false;
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
  bool get locked =>
      monitoring || starting || savingSettings || importingAssets;
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
    if (!developerMode &&
        credentials.isBundled &&
        (!credentials.isConfigured ||
            credentials.expiresAt == null ||
            credentials.isExpired(_now()))) {
      return AppCredentials.updateMessage;
    }
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
    if (!scenes.contains(upcoming.scene)) {
      return 'Choose an available Upcoming Match scene before monitoring.';
    }
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

  AppCredentials get credentials => defaultCredentials;
  String? get authorizationNotice => developerMode
      ? null
      : _authorizationUpdateRequired
      ? 'App authorization needs an update. Install the latest ATS version. If it continues, contact the app maintainer.'
      : credentials.updateNotice(_now());

  TmApiClient _createTmClient(String id) {
    if (developerMode) return SimulatedTmClient(id);
    // Test/custom factories own their authorization; production validates even
    // before contacting DWAB so known expiry produces a clear update prompt.
    if (_tmFactory != null) return _tmFactory(settings, id);
    credentials.validate(now: _now());
    return TmApiClient(
      baseUrl: normalizeTmUrl(settings.tmHost).toString(),
      apiKey: settings.tmApiKey,
      fieldSetId: id,
      appCredentials: credentials,
    );
  }

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
    _elimsTimer?.cancel();
    eliminationsMode = false;
    queuedMatch = null;
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

  void simulateMatchQueue(String id) {
    if (_disposed || !developerMode || !monitoring) return;
    final client = _monitorTm;
    if (client is SimulatedTmClient) client.queueMatch(id);
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
      upcoming = await repository.loadUpcoming();
      try {
        final folder = await TeamAssetsFolder.restore();
        if (folder != null) {
          final roster = File('$folder/teams.csv');
          final teams = await roster.exists()
              ? parseTeamCsv(await roster.readAsString())
              : upcoming.teams;
          upcoming = upcoming.copyWith(assetsDirectory: folder, teams: teams);
          await repository.saveUpcoming(upcoming);
        }
      } catch (_) {
        // Non-macOS builds and first launches have no saved folder bookmark.
      }
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

  Future<bool> setAdvancedUserMode(bool enabled) async {
    if (_disposed || locked || connecting || testingScene) return false;
    savingSettings = true;
    notice = null;
    _changed();
    try {
      await repository.saveAdvancedUserMode(enabled);
      if (_disposed) return false;
      settings = settings.copyWith(advancedUserMode: enabled);
      return true;
    } catch (_) {
      notice = 'Could not save the user mode setting.';
      return false;
    } finally {
      savingSettings = false;
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
      _matches.clear();
      _elimsTimer?.cancel();
      eliminationsMode = false;
      _authorizationUpdateRequired = false;
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
    _matches.clear();
    queuedMatch = null;
    _elimsTimer?.cancel();
    eliminationsMode = false;
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
      _authorizationUpdateRequired = false;
      tmMessage = developerMode
          ? 'TM bypassed. Three simulated fields available.'
          : '${sets.length} field set${sets.length == 1 ? '' : 's'} available';
      _log(
        developerMode ? 'TM simulator ready.' : 'Tournament Manager connected.',
      );
      if (!developerMode) await _refreshMatches();
      if (selectedFieldSetId != null) await selectFieldSet(selectedFieldSetId!);
      if (!developerMode) await _syncTeamRosterFromTm(client, revision);
    } catch (error) {
      client?.dispose();
      if (_disposed || revision != _tmRevision) return;
      if (error is AppAuthorizationUpdateRequired) {
        _authorizationUpdateRequired = true;
      }
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

  Future<bool> saveUpcomingSettings(UpcomingSettings value) async {
    if (_disposed || locked || connecting || testingScene) return false;
    if (value.scene.trim().isEmpty ||
        int.tryParse(value.divisionId) == null ||
        int.parse(value.divisionId) < 1) {
      notice = 'Choose an upcoming scene and a positive TM division ID.';
      _changed();
      return false;
    }
    savingSettings = true;
    _changed();
    try {
      await repository.saveUpcoming(value);
      if (_disposed) return false;
      final divisionChanged = upcoming.divisionId != value.divisionId;
      upcoming = value;
      if (divisionChanged) {
        _matches.clear();
        await _refreshMatches();
      }
      _log('Upcoming match settings saved.');
      return true;
    } catch (_) {
      notice =
          'Could not save upcoming match settings. Retry before monitoring.';
      return false;
    } finally {
      savingSettings = false;
      _changed();
    }
  }

  Future<void> importUpcomingAssets(String directory) async {
    if (_disposed || locked || connecting || testingScene) return;
    importingAssets = true;
    _changed();
    try {
      final imported = await importPythonAssets(Directory(directory), upcoming);
      await repository.saveUpcoming(imported);
      if (_disposed) return;
      upcoming = imported;
      _log(
        'Imported upcoming match assets and ${upcoming.teams.length} team records.',
      );
    } on AppException catch (error) {
      notice = error.message;
    } catch (_) {
      notice =
          'Could not import team assets. Check folder access and the teams.csv format.';
    } finally {
      importingAssets = false;
      _changed();
    }
  }

  Future<void> chooseTeamAssetsFolder() async {
    if (_disposed || locked || connecting || testingScene) return;
    importingAssets = true;
    _changed();
    try {
      final folder = await TeamAssetsFolder.chooseDocumentsFolder();
      if (folder == null || _disposed) return;
      final roster = File('$folder/teams.csv');
      final existingTeams = await roster.exists()
          ? parseTeamCsv(await roster.readAsString())
          : const <String, TeamInfo>{};
      final teams = existingTeams.isEmpty ? upcoming.teams : existingTeams;
      final updated = upcoming.copyWith(assetsDirectory: folder, teams: teams);
      await repository.saveUpcoming(updated);
      if (_disposed) return;
      upcoming = updated;
      _log('Team asset folder ready at $folder.');
      final client = _tm;
      if (!developerMode &&
          client != null &&
          tmState == ServiceState.connected) {
        await _syncTeamRosterFromTm(client, _tmRevision);
      } else if (existingTeams.isEmpty && teams.isNotEmpty) {
        final records = [
          for (final entry in teams.entries)
            {
              'number': entry.key,
              'name': entry.value.name,
              'organization': entry.value.organization,
            },
        ];
        await TeamAssetsFolder.writeRoster(folder, teamRosterCsv(records));
      }
    } on AppException catch (error) {
      notice = error.message;
    } catch (_) {
      notice = 'Could not set up the Documents/ATS team asset folder.';
    } finally {
      importingAssets = false;
      _changed();
    }
  }

  Future<void> openTeamAssetsFolder() async {
    try {
      await TeamAssetsFolder.open(upcoming.assetsDirectory);
    } catch (_) {
      notice = 'Set up the Documents/ATS folder before opening it.';
      _changed();
    }
  }

  Future<void> _syncTeamRosterFromTm(TmApiClient client, int revision) async {
    try {
      final records = await client.getTeams();
      if (_disposed || client != _tm || revision != _tmRevision) return;
      final contents = teamRosterCsv(records);
      if (upcoming.assetsDirectory.isNotEmpty) {
        await TeamAssetsFolder.writeRoster(upcoming.assetsDirectory, contents);
      }
      final teams = parseTeamCsv(contents);
      final updated = upcoming.copyWith(teams: teams);
      await repository.saveUpcoming(updated);
      if (_disposed || client != _tm || revision != _tmRevision) return;
      upcoming = updated;
      _log(
        upcoming.assetsDirectory.isEmpty
            ? 'Loaded ${teams.length} teams from Tournament Manager.'
            : 'Loaded ${teams.length} teams from TM and updated teams.csv.',
      );
    } on AppException catch (error) {
      if (!_disposed && client == _tm && revision == _tmRevision) {
        _log(
          'Could not refresh the TM team list: ${error.message}',
          error: true,
        );
      }
    } catch (_) {
      if (!_disposed && client == _tm && revision == _tmRevision) {
        _log(
          'Could not save the TM team list to the asset folder.',
          error: true,
        );
      }
    }
  }

  Future<void> refreshTeamRoster() async {
    if (_disposed || upcoming.assetsDirectory.isEmpty || locked) {
      return;
    }
    try {
      final roster = File('${upcoming.assetsDirectory}/teams.csv');
      final teams = await roster.exists()
          ? parseTeamCsv(await roster.readAsString())
          : <String, TeamInfo>{};
      final updated = upcoming.copyWith(teams: teams);
      await repository.saveUpcoming(updated);
      if (_disposed) return;
      upcoming = updated;
      notice = null;
      _log('Loaded ${teams.length} team records from teams.csv.');
    } on AppException catch (error) {
      notice = error.message;
    } catch (_) {
      notice = 'Could not read teams.csv from the team asset folder.';
    } finally {
      _changed();
    }
  }

  Future<void> refreshMatches() => _refreshMatches();

  Future<void> _refreshMatches({bool eliminationsOnly = false}) async {
    final client = _tm;
    if (_disposed || developerMode || client == null) return;
    final revision = _tmRevision;
    if (_matchLoading != null && _matchLoadRevision == revision) {
      return _matchLoading!;
    }
    _matchLoadRevision = revision;
    final job = () async {
      try {
        final raw = await client.getMatches(upcoming.divisionId);
        if (_disposed || revision != _tmRevision) return;
        final loaded = <String, UpcomingMatch>{};
        for (final item in raw) {
          if (item is! Map<String, dynamic>) continue;
          final info = item['matchInfo'] is Map<String, dynamic>
              ? item['matchInfo'] as Map<String, dynamic>
              : item;
          final match = UpcomingMatch.fromTm(info);
          if (eliminationsOnly && match.qualification) continue;
          loaded['${match.qualification ? 'QUAL' : 'ELIMS'}|${match.label}'] =
              match;
        }
        if (eliminationsOnly) {
          _matches.removeWhere((key, _) => key.startsWith('ELIMS|'));
        } else {
          _matches.clear();
        }
        _matches.addAll(loaded);
        _log('TM match list refreshed.');
      } catch (_) {
        if (!_disposed && revision == _tmRevision) {
          _log(
            'TM match list could not be refreshed. Queued-match event data will be used.',
            error: true,
          );
        }
      }
    }();
    _matchLoading = job;
    _changed();
    try {
      await job;
    } finally {
      if (identical(_matchLoading, job)) _matchLoading = null;
      _changed();
    }
  }

  Future<void> startEliminations() async {
    if (_disposed || developerMode || tmState != ServiceState.connected) return;
    eliminationsMode = true;
    _lastElimsRefresh = null;
    await _refreshEliminations();
    if (_disposed || !eliminationsMode || tmState != ServiceState.connected)
      return;
    _elimsTimer?.cancel();
    _elimsTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_refreshEliminations()),
    );
    _changed();
  }

  Future<void> _refreshEliminations() async {
    if (_disposed ||
        !eliminationsMode ||
        tmState != ServiceState.connected ||
        loadingMatches) {
      return;
    }
    final now = _now();
    if (_lastElimsRefresh != null &&
        now.difference(_lastElimsRefresh!) < const Duration(seconds: 5)) {
      return;
    }
    _lastElimsRefresh = now;
    await _refreshMatches(eliminationsOnly: true);
  }

  UpcomingMatch _queuedMatchForEvent(Map<String, dynamic> event) {
    final data = event['data'] is Map<String, dynamic>
        ? event['data'] as Map<String, dynamic>
        : event;
    final raw = data['match'];
    var match = UpcomingMatch.fromTm(
      raw is Map<String, dynamic> ? raw : const {},
    );
    final cached =
        _matches['${match.qualification ? 'QUAL' : 'ELIMS'}|${match.label}'];
    if (cached != null && cached.teams.isNotEmpty) {
      match = match.withTeams(cached.teams);
    }
    return match;
  }

  Future<void> startMonitoring() async {
    if (!canStart) return;
    final revision = ++_monitorRevision;
    starting = true;
    notice = null;
    _changed();
    final client = _createTmClient(selectedFieldSetId!);
    _monitorTm = client;
    Map<String, dynamic>? initialEvent;
    var activationRevision = 0;
    void route(String id, Map<String, dynamic> event) {
      final activation = ++activationRevision;
      final assigned = event['type'] == 'fieldMatchAssigned';
      final match = assigned ? _queuedMatchForEvent(event) : null;
      // Serialize transitions and cancel queued work on Stop/disconnect.
      _switchQueue = _switchQueue.then((_) async {
        if (_disposed ||
            revision != _monitorRevision ||
            !monitoring ||
            activation != activationRevision) {
          return;
        }
        final scene = assigned ? upcoming.scene : sceneFor(id);
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
          activeFieldId = assigned ? null : id;
          currentScene = scene;
          _log('Switched OBS to “$scene”.');
          if (match != null) {
            queuedMatch = match;
            final updates = await upcomingInputUpdates(match, upcoming);
            final missing = <String>[];
            for (final update in updates) {
              if (_disposed ||
                  revision != _monitorRevision ||
                  !monitoring ||
                  activation != activationRevision) {
                return;
              }
              try {
                await _obs!.setInputSettings(update.name, update.settings);
              } catch (_) {
                missing.add(update.name);
              }
            }
            if (missing.isNotEmpty) {
              _log(
                'Upcoming preview inputs could not be updated: ${missing.join(', ')}. Check the OBS source names.',
                error: true,
              );
            }
            _changed();
          }
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
        if (event['type'] == 'fieldActivated') {
          // Native TM emits this automatically when a match is queued. The
          // Python integration intentionally waits for matchStarted to show
          // the camera, keeping the upcoming preview visible in the meantime.
          _log(
            'TM field activation received; keeping the queued-match preview until match start.',
          );
          return;
        }
        if (eliminationsMode &&
            {
              'matchStarted',
              'matchFinished',
              'matchScored',
            }.contains(event['type'])) {
          unawaited(_refreshEliminations());
        }
        final id = fieldIdForEvent(event, fields);
        if (id == null) {
          if (_sceneRoutingEventTypes.contains(event['type'])) {
            _log(
              'Ignored TM ${event['type']}: the field is missing or is not in the selected field set.',
            );
          }
          return;
        }
        final name = fields.firstWhere((field) => field.id == id).name;
        _log(
          event['type'] == 'matchStarted'
              ? 'TM match started on $name.'
              : 'TM queued a match on $name.',
        );
        if (starting) {
          initialEvent = event;
        } else {
          route(id, event);
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
      if (initialEvent != null) {
        route(fieldIdForEvent(initialEvent!, fields)!, initialEvent!);
      }
      _healthTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        if (_disposed || revision != _monitorRevision || _healthChecking) {
          return;
        }
        _healthChecking = true;
        try {
          final available = await _obs!.getSceneNames();
          if (_disposed || revision != _monitorRevision) return;
          scenes = available.toSet().toList()..sort();
          if (mappedCount != fields.length ||
              !scenes.contains(upcoming.scene)) {
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
        if (error is AppAuthorizationUpdateRequired) {
          _authorizationUpdateRequired = true;
        }
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

  static const _sceneRoutingEventTypes = {'fieldMatchAssigned', 'matchStarted'};

  /// TM's native packets use fieldID. Accept fieldId and explicit zero-based
  /// fieldIndex adapters too, without treating an unknown ID as a position.
  static String? fieldIdForEvent(
    Map<String, dynamic> event,
    List<TmField> fields,
  ) {
    if (!_sceneRoutingEventTypes.contains(event['type'])) return null;
    final data = event['data'] is Map<String, dynamic>
        ? event['data'] as Map<String, dynamic>
        : event;
    final containers = [event, if (!identical(data, event)) data];
    final explicitIds = [
      for (final container in containers)
        for (final key in ['fieldID', 'fieldId'])
          if (container.containsKey(key)) container[key],
    ];
    if (explicitIds.isNotEmpty) {
      if (explicitIds.any((id) => id is! int && id is! String)) return null;
      final ids = explicitIds.map((id) => id.toString()).toSet();
      if (ids.length != 1) return null;
      final id = ids.single;
      return fields.any((field) => field.id == id) ? id : null;
    }
    final index = int.tryParse('${data['fieldIndex'] ?? event['fieldIndex']}');
    if (index == null || index < 0 || index >= fields.length) return null;
    return fields[index].id;
  }

  Future<void> stopMonitoring({String? reason}) async {
    _monitorRevision++;
    monitoring = false;
    starting = false;
    _healthTimer?.cancel();
    _elimsTimer?.cancel();
    eliminationsMode = false;
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
    _elimsTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    unawaited(_obsErrors?.cancel());
    _monitorTm?.dispose();
    _tm?.dispose();
    _obs?.dispose();
    super.dispose();
  }
}
