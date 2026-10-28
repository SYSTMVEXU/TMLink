import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tmlink/core/endpoints.dart';

class TeamInfo {
  final String name;
  final String organization;
  const TeamInfo({this.name = '', this.organization = ''});
  Map<String, String> toJson() => {'name': name, 'organization': organization};
}

class UpcomingSettings {
  final String scene;
  final String divisionId;
  final String assetsDirectory;
  final Map<String, TeamInfo> teams;
  const UpcomingSettings({
    this.scene = 'Upcoming Match',
    this.divisionId = '1',
    this.assetsDirectory = '',
    this.teams = const {},
  });

  UpcomingSettings copyWith({
    String? scene,
    String? divisionId,
    String? assetsDirectory,
    Map<String, TeamInfo>? teams,
  }) => UpcomingSettings(
    scene: scene ?? this.scene,
    divisionId: divisionId ?? this.divisionId,
    assetsDirectory: assetsDirectory ?? this.assetsDirectory,
    teams: teams ?? this.teams,
  );
  Map<String, dynamic> toJson() => {
    'scene': scene,
    'divisionId': divisionId,
    'assetsDirectory': assetsDirectory,
    'teams': teams.map((key, value) => MapEntry(key, value.toJson())),
  };
  factory UpcomingSettings.fromJson(Map<String, dynamic> json) =>
      UpcomingSettings(
        scene: json['scene'] as String? ?? 'Upcoming Match',
        divisionId: json['divisionId'] as String? ?? '1',
        assetsDirectory: json['assetsDirectory'] as String? ?? '',
        teams: (json['teams'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(
            key,
            TeamInfo(
              name: value['name'] as String? ?? '',
              organization: value['organization'] as String? ?? '',
            ),
          ),
        ),
      );
}

/// Mirrors build_match_display/resolve_match_number in the original Python app.
class UpcomingMatch {
  final String label;
  final bool qualification;
  final List<String> teams;
  const UpcomingMatch({
    required this.label,
    required this.qualification,
    required this.teams,
  });

  factory UpcomingMatch.fromTm(Map<String, dynamic> match) {
    final tuple = match['matchTuple'] is Map
        ? match['matchTuple'] as Map
        : const {};
    Object? first(List<Object?> values) => values.cast<Object?>().firstWhere(
      (value) => value != null && value != '' && value != 0,
      orElse: () => '',
    );
    final round = first([
      match['roundName'],
      match['round'],
      tuple['roundName'],
      tuple['round'],
    ]).toString();
    final qualification = round.toUpperCase() == 'QUAL';
    var number = first([match['match'], tuple['match']]).toString();
    final instance = first([match['instance'], tuple['instance']]).toString();
    if (!qualification &&
        instance.isNotEmpty &&
        {'', '0', '1'}.contains(number)) {
      number = instance;
    }
    final teams = <String>[];
    for (final alliance
        in (match['alliances'] is List
            ? match['alliances'] as List
            : const [])) {
      if (alliance is! Map || alliance['teams'] is! List) continue;
      for (final team in alliance['teams'] as List) {
        if (team is Map) teams.add('${team['number'] ?? ''}');
      }
    }
    return UpcomingMatch(
      label: '$round $number'.trim(),
      qualification: qualification,
      teams: teams,
    );
  }

  UpcomingMatch withTeams(List<String> value) =>
      UpcomingMatch(label: label, qualification: qualification, teams: value);
  List<String> get displayTeams => teams.length < 4
      ? const ['0001', '0002', '0003', '0004']
      : teams.take(4).toList();
}

class ObsInputUpdate {
  final String name;
  final Map<String, dynamic> settings;
  const ObsInputUpdate(this.name, this.settings);
}

/// The exact source names and image fallback names used by Tmswitch.py.
Future<List<ObsInputUpdate>> upcomingInputUpdates(
  UpcomingMatch match,
  UpcomingSettings config,
) async {
  final updates = <ObsInputUpdate>[
    ObsInputUpdate('MatchStr', {'text': match.label}),
  ];
  for (var i = 0; i < 4; i++) {
    final number = match.displayTeams[i];
    final team = config.teams[number.trim().toUpperCase()] ?? const TeamInfo();
    final position = i + 1;
    updates.addAll([
      ObsInputUpdate('Team${position}Number', {'text': number}),
      ObsInputUpdate('Team${position}Name', {'text': team.name}),
      ObsInputUpdate('Team${position}Org', {'text': team.organization}),
    ]);
    if (config.assetsDirectory.isEmpty) continue;
    final safeNumber = RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(number)
        ? number
        : '';
    for (final asset in [
      ('robot_images', 'png', 'IMG'),
      ('team_photos', 'jpg', 'Photo'),
    ]) {
      var path = p.join(
        config.assetsDirectory,
        asset.$1,
        '$safeNumber.${asset.$2}',
      );
      if (safeNumber.isEmpty || !await File(path).exists()) {
        path = p.join(
          config.assetsDirectory,
          asset.$1,
          'default_robot.${asset.$2}',
        );
      }
      updates.add(ObsInputUpdate('Team$position${asset.$3}', {'file': path}));
    }
  }
  return updates;
}

Map<String, TeamInfo> parseTeamCsv(String source) {
  final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
      .convert(
        source
            .replaceFirst('\uFEFF', '')
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n'),
      );
  if (rows.isEmpty) throw const AppException('The team CSV is empty.');
  final headers = rows.first
      .map((value) => '$value'.trim().toLowerCase())
      .toList();
  if (!headers.any({'team', 'team number', 'number'}.contains)) {
    throw const AppException(
      'The team CSV needs a Team, Team Number, or Number column.',
    );
  }
  final teams = <String, TeamInfo>{};
  for (final row in rows.skip(1)) {
    final values = {
      for (var i = 0; i < headers.length; i++)
        headers[i]: i < row.length ? '${row[i]}'.trim() : '',
    };
    String first(List<String> keys) => keys
        .map((key) => values[key] ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final number = first(['team', 'team number', 'number']);
    if (number.isEmpty) continue;
    teams[number.toUpperCase()] = TeamInfo(
      name: first(['team name', 'name', 'short name']),
      organization: first(['organization', 'school', 'sponsor']),
    );
  }
  return teams;
}

String teamRosterCsv(List<dynamic> records) {
  final teams = <String, List<String>>{};
  String safeCell(Object? value) {
    final text = value?.toString().trim() ?? '';
    return RegExp(r'^\s*[=+@\-\t\r]').hasMatch(text) ? "'$text" : text;
  }

  for (final record in records) {
    if (record is! Map) continue;
    final number = (record['number'] ?? record['teamNumber'] ?? '')
        .toString()
        .trim();
    if (number.isEmpty) continue;
    final name =
        (record['name'] ?? record['teamName'] ?? record['shortName'] ?? '')
            .toString()
            .trim();
    final organization = (record['organization'] ?? record['school'] ?? '')
        .toString()
        .trim();
    teams[number.toUpperCase()] = [
      safeCell(number),
      safeCell(name),
      safeCell(organization),
    ];
  }
  if (teams.isEmpty) {
    throw const AppException('TM did not return any recognizable teams.');
  }
  return const ListToCsvConverter().convert([
    ['Team Number', 'Team Name', 'Organization'],
    ...teams.values,
  ]);
}

/// Import into the app's own storage so sandbox access survives app restarts.
Future<UpcomingSettings> importPythonAssets(
  Directory source,
  UpcomingSettings current, {
  Directory? storage,
}) async {
  final csv = File(p.join(source.path, 'teams.csv'));
  final hasCsv = await csv.exists();
  final teams = hasCsv ? parseTeamCsv(await csv.readAsString()) : current.teams;
  final support = storage ?? await getApplicationSupportDirectory();
  final destination = Directory(
    p.join(
      support.path,
      'preview-assets',
      '${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  await destination.create(recursive: true);
  var copied = 0;
  try {
    for (final folder in ['robot_images', 'team_photos']) {
      final input = Directory(p.join(source.path, folder));
      final output = Directory(p.join(destination.path, folder));
      await output.create();
      if (!await input.exists()) continue;
      await for (final entry in input.list(followLinks: false)) {
        if (entry is! File ||
            !RegExp(
              r'^[A-Za-z0-9_-]+\.(png|jpg|jpeg)$',
              caseSensitive: false,
            ).hasMatch(p.basename(entry.path))) {
          continue;
        }
        await entry.copy(p.join(output.path, p.basename(entry.path)));
        copied++;
      }
    }
    if (!hasCsv && copied == 0) {
      throw const AppException(
        'Choose the Python app folder containing teams.csv, robot_images, or team_photos.',
      );
    }
    return current.copyWith(teams: teams, assetsDirectory: destination.path);
  } catch (_) {
    await destination.delete(recursive: true);
    rethrow;
  }
}
