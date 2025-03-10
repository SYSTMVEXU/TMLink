import 'dart:io';
// import 'package:path/path.dart' as path;

class Config {
  // -------------------- FILE LOCATIONS --------------------
  // static final String scriptDir = Directory.current.path;
  // static final String settingsFile = path.join(scriptDir, "settings.json");
  // static final String imageFolder = path.join(scriptDir, "robot_images");
  // static final String fallbackImage = path.join(imageFolder, "default.png");

  // Ensure the robot_images folder exists
  // static void ensureDirectories() {
  //   Directory(imageFolder).createSync(recursive: true);
  // }

  // -------------------- GLOBAL VARIABLES --------------------
  static const String defaultTmIp = "127.0.0.1";
  static const String defaultObsWsUrl = "ws://localhost:4455/";
  static const String defaultFieldSetId = "1";
  static const int defaultFieldNumber = 1;

  // OAuth credentials (Load from .env file)
  static final String clientId = Platform.environment['CLIENT_ID'] ?? "";
  static final String clientSecret = Platform.environment['CLIENT_SECRET'] ?? "";

  // OBS SCENE NAMES
  // static const String upcomingMatchScene = "Upcoming Match";
  // static const String lastMatchScoreScene = "Last Match Scores";
}
