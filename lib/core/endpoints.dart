class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}

Uri normalizeTmUrl(String value) {
  final text = value.trim();
  final uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
      RegExp(r'[\s%]').hasMatch(uri.host)) {
    throw const AppException(
      'Enter a TM host or URL, such as 192.168.1.10:8080.',
    );
  }
  return uri.replace(path: '');
}

Uri normalizeObsUrl(String value) {
  final text = value.trim();
  final uri = Uri.tryParse(text.contains('://') ? text : 'ws://$text');
  if (uri == null ||
      !['ws', 'wss'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
      RegExp(r'[\s%]').hasMatch(uri.host)) {
    throw const AppException(
      'Enter an OBS WebSocket URL, such as ws://localhost:4455/.',
    );
  }
  return uri.replace(
    port: uri.hasPort ? uri.port : (uri.scheme == 'wss' ? 443 : 4455),
    path: uri.path.isEmpty ? '/' : uri.path,
  );
}
