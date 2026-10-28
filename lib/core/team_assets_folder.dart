import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// macOS access to the user's Documents/ATS team asset folder.
class TeamAssetsFolder {
  static const _channel = MethodChannel('com.ats.team_assets');

  static Future<String?> restore() async {
    if (Platform.isMacOS) {
      return _channel.invokeMethod<String>('restoreFolder');
    }
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(documents.path, 'ATS'));
    return await folder.exists() ? folder.path : null;
  }

  static Future<String?> chooseDocumentsFolder() async {
    if (Platform.isMacOS) {
      return _channel.invokeMethod<String>('chooseDocumentsFolder');
    }
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(documents.path, 'ATS'));
    await Directory(p.join(root.path, 'robot_images')).create(recursive: true);
    await Directory(p.join(root.path, 'team_photos')).create(recursive: true);
    final roster = File(p.join(root.path, 'teams.csv'));
    if (!await roster.exists()) {
      await roster.writeAsString('Team Number,Team Name,Organization\n');
    }
    return root.path;
  }

  static Future<void> writeRoster(String folder, String contents) async {
    final roster = File(p.join(folder, 'teams.csv'));
    final temporary = File('${roster.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    try {
      await temporary.rename(roster.path);
    } on FileSystemException {
      await roster.writeAsString(contents, flush: true);
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<void> open(String path) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod<void>('openFolder', {'path': path});
      return;
    }
    final command = Platform.isWindows ? 'explorer' : 'xdg-open';
    await Process.start(command, [path]);
  }
}
