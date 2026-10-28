import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tmlink/core/upcoming_match.dart';

void main() {
  test(
    'match labels follow Python qualification and elimination instance rules',
    () {
      for (final sample in [
        ({'round': 'QUAL', 'match': 7, 'instance': 2}, 'QUAL 7'),
        ({'round': 'F', 'match': 1, 'instance': 3}, 'F 3'),
        (
          {
            'matchTuple': {'round': 'R16', 'match': 4, 'instance': 1},
          },
          'R16 4',
        ),
        ({'roundName': 'SF', 'round': 4, 'match': 1, 'instance': 2}, 'SF 2'),
      ]) {
        expect(UpcomingMatch.fromTm(sample.$1).label, sample.$2);
      }
      expect(UpcomingMatch.fromTm(const {}).displayTeams, [
        '0001',
        '0002',
        '0003',
        '0004',
      ]);
    },
  );

  test('team CSV preserves leading zeros and Python column aliases', () {
    final teams = parseTeamCsv(
      '\uFEFF Team Number ,Team Name,Organization\r\n0001,"Team, One",School One\r\n2B,Team Two,School Two\r\n',
    );
    expect(teams['0001']!.name, 'Team, One');
    expect(teams['0001']!.organization, 'School One');
    expect(teams['2B']!.name, 'Team Two');
    expect(
      parseTeamCsv(
        'Number,Short Name,School\n9A,Ninth,High School\n',
      )['9A']!.organization,
      'High School',
    );
  });

  test(
    'OBS updates use the original source names and four team positions',
    () async {
      final config = UpcomingSettings(
        teams: {
          '111A': const TeamInfo(name: 'Alpha', organization: 'School A'),
        },
      );
      final updates = await upcomingInputUpdates(
        const UpcomingMatch(
          label: 'QUAL 7',
          qualification: true,
          teams: ['111A', '222B', '333C', '444D'],
        ),
        config,
      );
      expect(updates.first.name, 'MatchStr');
      expect(updates.first.settings, {'text': 'QUAL 7'});
      expect(updates.firstWhere((u) => u.name == 'Team1Name').settings, {
        'text': 'Alpha',
      });
      expect(updates.firstWhere((u) => u.name == 'Team1Org').settings, {
        'text': 'School A',
      });
      expect(updates.firstWhere((u) => u.name == 'Team4Number').settings, {
        'text': '444D',
      });
      expect(updates, hasLength(13));
    },
  );

  test(
    'Python asset import persists a private copy and uses image fallbacks',
    () async {
      final root = await Directory.systemTemp.createTemp('tmlink-assets-test-');
      addTearDown(() => root.delete(recursive: true));
      final source = await Directory(p.join(root.path, 'python')).create();
      final storage = await Directory(p.join(root.path, 'app')).create();
      await File(
        p.join(source.path, 'teams.csv'),
      ).writeAsString('Team,Team Name,School\n111A,Alpha,School A\n');
      final images = await Directory(
        p.join(source.path, 'robot_images'),
      ).create();
      final photos = await Directory(
        p.join(source.path, 'team_photos'),
      ).create();
      await File(p.join(images.path, '111A.png')).writeAsBytes([1, 2]);
      await File(p.join(images.path, 'default_robot.png')).writeAsBytes([3]);
      await File(p.join(photos.path, 'default_robot.jpg')).writeAsBytes([4]);
      final config = await importPythonAssets(
        source,
        const UpcomingSettings(),
        storage: storage,
      );
      expect(config.teams['111A']!.name, 'Alpha');
      await source.delete(recursive: true);
      final updates = await upcomingInputUpdates(
        const UpcomingMatch(
          label: 'QUAL 7',
          qualification: true,
          teams: ['111A', '222B', '333C', '444D'],
        ),
        config,
      );
      expect(updates, hasLength(21));
      expect(
        updates.firstWhere((u) => u.name == 'Team1IMG').settings['file'],
        p.join(config.assetsDirectory, 'robot_images', '111A.png'),
      );
      expect(
        updates.firstWhere((u) => u.name == 'Team2IMG').settings['file'],
        p.join(config.assetsDirectory, 'robot_images', 'default_robot.png'),
      );
      expect(
        updates.firstWhere((u) => u.name == 'Team1Photo').settings['file'],
        p.join(config.assetsDirectory, 'team_photos', 'default_robot.jpg'),
      );
    },
  );

  test(
    'failed asset imports preserve current settings and remove partial copies',
    () async {
      final root = await Directory.systemTemp.createTemp('tmlink-assets-test-');
      addTearDown(() => root.delete(recursive: true));
      final source = await Directory(p.join(root.path, 'empty')).create();
      final storage = await Directory(p.join(root.path, 'app')).create();
      await expectLater(
        importPythonAssets(source, const UpcomingSettings(), storage: storage),
        throwsException,
      );
      expect(
        await Directory(p.join(storage.path, 'preview-assets')).list().toList(),
        isEmpty,
      );
    },
  );
}
