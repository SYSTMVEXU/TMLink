import 'package:flutter/services.dart';

/// Controls a supported macOS media player without taking over its playlist.
class MediaControls {
  static const _channel = MethodChannel('com.ats.media_controls');

  Future<List<String>> requestPermission() async {
    final checked = await _channel.invokeListMethod<String>(
      'requestPermission',
    );
    return checked ?? const [];
  }

  Future<List<String>> pausePlaying() async {
    final players = await _channel.invokeListMethod<String>('pausePlaying');
    return players ?? const [];
  }

  Future<void> resumePlayers(List<String> players) =>
      _channel.invokeMethod<void>('resumePlayers', {'players': players});
}
