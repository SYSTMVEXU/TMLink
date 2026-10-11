import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tmlink/core/endpoints.dart';

class DetectedTmInstance {
  final String hostForInput;
  final String label;
  final String evidence;

  const DetectedTmInstance({
    required this.hostForInput,
    required this.label,
    required this.evidence,
  });
}

class TmVerificationResult {
  final bool isValid;
  final String evidence;

  const TmVerificationResult({required this.isValid, required this.evidence});
}

class TmInstanceDetector {
  TmInstanceDetector({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  bool _disposed = false;

  static const Duration _tcpProbeTimeout = Duration(milliseconds: 140);
  static const Duration _httpProbeTimeout = Duration(milliseconds: 450);

  Future<List<DetectedTmInstance>> scanLocalNetwork() async {
    final networkContext = await _buildNetworkContext();
    final hosts = _prioritizeHosts(
      networkContext.candidateHosts,
      preferredLocalHost: networkContext.preferredLocalHost,
    );

    final results = <DetectedTmInstance>[];
    final responsiveHosts = <String>[];
    const int tcpChunkSize = 32;
    const int verifyChunkSize = 8;

    // Pass 1: Fast TCP probe to skip dead hosts before HTTP verification.
    for (var i = 0; i < hosts.length; i += tcpChunkSize) {
      if (_disposed) return [];
      final end = (i + tcpChunkSize < hosts.length)
          ? i + tcpChunkSize
          : hosts.length;
      final chunk = hosts.sublist(i, end);
      final chunkResponsive = await Future.wait(
        chunk.map((host) async {
          final isOpen = await _isHttpPortOpen(host);
          return isOpen ? host : null;
        }),
      );
      responsiveHosts.addAll(chunkResponsive.whereType<String>());
    }

    // Pass 2: TM verification only on responsive hosts.
    for (var i = 0; i < responsiveHosts.length; i += verifyChunkSize) {
      if (_disposed) return [];
      final end = (i + verifyChunkSize < responsiveHosts.length)
          ? i + verifyChunkSize
          : responsiveHosts.length;
      final chunk = responsiveHosts.sublist(i, end);
      final chunkResults = await Future.wait(
        chunk.map((host) async {
          final verification = await verifyHost(host);
          if (!verification.isValid) {
            return null;
          }

          return DetectedTmInstance(
            hostForInput: host,
            label: host,
            evidence: verification.evidence,
          );
        }),
      );

      results.addAll(chunkResults.whereType<DetectedTmInstance>());
    }

    final localAliases = {
      'localhost',
      '127.0.0.1',
      ...networkContext.localIpv4Hosts,
    };
    final localResults = results.where(
      (instance) => localAliases.contains(instance.hostForInput),
    );
    final localMatch = localResults.isEmpty
        ? null
        : localResults.first.hostForInput;
    final filtered = results
        .where(
          (instance) =>
              !localAliases.contains(instance.hostForInput) ||
              instance.hostForInput == localMatch,
        )
        .toList(growable: false);

    filtered.sort((a, b) => a.hostForInput.compareTo(b.hostForInput));
    return _dedupeByHost(filtered);
  }

  Future<TmVerificationResult> verifyHost(String rawHost) async {
    Uri base;
    try {
      base = normalizeTmUrl(rawHost);
    } catch (_) {
      return const TmVerificationResult(
        isValid: false,
        evidence: 'Invalid server address.',
      );
    }
    if (_disposed) {
      return const TmVerificationResult(
        isValid: false,
        evidence: 'Discovery cancelled.',
      );
    }
    final uri = base.resolve('/api/fieldsets');
    final response = await _safeGet(uri);

    if (response != null) {
      final serverHeader = response.headers['server']?.toLowerCase();
      if (serverHeader != null && serverHeader.startsWith('tm/')) {
        return TmVerificationResult(
          isValid: true,
          evidence: 'server header: ${response.headers['server']}',
        );
      }

      final tmHeaderEvidence = _tmHeaderEvidence(response);
      if (tmHeaderEvidence != null) {
        return TmVerificationResult(isValid: true, evidence: tmHeaderEvidence);
      }

      final parsedJson = _safeJson(response.body);
      if (parsedJson is Map<String, dynamic> &&
          (parsedJson['fieldsets'] is List ||
              parsedJson['fieldSets'] is List)) {
        return const TmVerificationResult(
          isValid: true,
          evidence: '/api/fieldsets returned TM fieldset payload',
        );
      }

      final body = response.body.toLowerCase();
      if (body.contains('tournament manager') || body.contains('vex tm')) {
        return const TmVerificationResult(
          isValid: true,
          evidence: 'TM wording found in response body',
        );
      }

      if ((response.statusCode == 401 || response.statusCode == 403) &&
          (body.contains('x-tm-signature') ||
              body.contains('x-tm-date') ||
              body.contains('api key'))) {
        return const TmVerificationResult(
          isValid: true,
          evidence: 'TM auth challenge detected on /api/fieldsets',
        );
      }
    }

    final rootResponse = await _safeGet(base.resolve('/'));
    if (rootResponse != null) {
      final body = rootResponse.body.toLowerCase();
      if (body.contains('tournament manager') ||
          body.contains('vex tournament manager')) {
        return const TmVerificationResult(
          isValid: true,
          evidence: 'TM wording found on root page',
        );
      }
    }

    return const TmVerificationResult(
      isValid: false,
      evidence: 'No Tournament Manager API signature detected.',
    );
  }

  Future<_NetworkContext> _buildNetworkContext() async {
    final hosts = <String>{'127.0.0.1', 'localhost'};
    final localIpv4Hosts = <String>{};
    String? preferredLocalHost;

    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    var subnetCount = 0;
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final ip = address.address;
        if (!_isPrivateIpv4(ip)) {
          continue;
        }

        localIpv4Hosts.add(ip);
        preferredLocalHost ??= ip;
        hosts.add(ip);

        final octets = ip.split('.');
        if (octets.length != 4) {
          continue;
        }

        if (++subnetCount > 4) continue;
        final subnetPrefix = '${octets[0]}.${octets[1]}.${octets[2]}';
        for (var host = 1; host <= 254; host++) {
          final candidate = '$subnetPrefix.$host';
          if (candidate == ip) {
            continue;
          }
          hosts.add(candidate);
        }
      }
    }

    return _NetworkContext(
      candidateHosts: hosts.toList(growable: false),
      localIpv4Hosts: localIpv4Hosts,
      preferredLocalHost: preferredLocalHost,
    );
  }

  bool _isPrivateIpv4(String ip) {
    final octets = ip.split('.');
    if (octets.length != 4) return false;

    final a = int.tryParse(octets[0]);
    final b = int.tryParse(octets[1]);
    if (a == null || b == null) return false;

    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  String? _tmHeaderEvidence(http.Response response) {
    final headerKeys = response.headers.keys
        .map((k) => k.toLowerCase())
        .toSet();
    if (headerKeys.contains('x-tm-date')) {
      return 'x-tm-date header present';
    }
    if (headerKeys.contains('x-tm-signature')) {
      return 'x-tm-signature header present';
    }
    if (headerKeys.contains('x-tm-api-key')) {
      return 'x-tm-api-key header present';
    }
    return null;
  }

  dynamic _safeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  Future<http.Response?> _safeGet(Uri uri) async {
    try {
      return await _client.get(uri).timeout(_httpProbeTimeout);
    } on Exception {
      return null;
    }
  }

  Future<bool> _isHttpPortOpen(String rawHost) async {
    if (_disposed) return false;
    Uri endpoint;
    try {
      endpoint = normalizeTmUrl(rawHost);
    } catch (_) {
      return false;
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: _tcpProbeTimeout,
      );
      return true;
    } on Exception {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  List<String> _prioritizeHosts(
    List<String> hosts, {
    required String? preferredLocalHost,
  }) {
    final ordered = [...hosts];
    ordered.sort((a, b) {
      int rank(String host) {
        if (preferredLocalHost != null && host == preferredLocalHost) return 0;
        if (host == '127.0.0.1') return 1;
        if (host == 'localhost') return 2;
        return 3;
      }

      final ra = rank(a);
      final rb = rank(b);
      if (ra != rb) return ra.compareTo(rb);
      return a.compareTo(b);
    });
    return ordered;
  }

  void dispose() {
    _disposed = true;
    _client.close();
  }

  List<DetectedTmInstance> _dedupeByHost(List<DetectedTmInstance> instances) {
    final byHost = <String, DetectedTmInstance>{};
    for (final instance in instances) {
      byHost[instance.hostForInput] = instance;
    }
    return byHost.values.toList(growable: false);
  }
}

class _NetworkContext {
  final List<String> candidateHosts;
  final Set<String> localIpv4Hosts;
  final String? preferredLocalHost;

  const _NetworkContext({
    required this.candidateHosts,
    required this.localIpv4Hosts,
    required this.preferredLocalHost,
  });
}
