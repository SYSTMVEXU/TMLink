import 'dart:async';

import 'package:tmlink/core/tm_api_client.dart';

/// Supplies field events locally while OBS remains a real connection.
class SimulatedTmClient extends TmApiClient {
  static const fieldSet = TmFieldSet(
    id: 'simulated-fields',
    name: 'Developer test fields',
    fields: [
      TmField(id: 'test-1', name: 'Test Field 1'),
      TmField(id: 'test-2', name: 'Test Field 2'),
      TmField(id: 'test-3', name: 'Test Field 3'),
    ],
  );
  final _simulatedEvents = StreamController<Map<String, dynamic>>.broadcast();
  bool _closed = false;
  bool _listening = false;

  SimulatedTmClient(String fieldSetId)
    : super(baseUrl: 'http://localhost', apiKey: '', fieldSetId: fieldSetId);

  @override
  Stream<Map<String, dynamic>> get eventStream => _simulatedEvents.stream;

  @override
  Future<List<dynamic>> getFieldsets() async => [
    {
      'id': fieldSet.id,
      'name': fieldSet.name,
      'fields': [
        for (final field in fieldSet.fields)
          {'id': field.id, 'name': field.name},
      ],
    },
  ];

  @override
  Future<void> initialize({bool connectStream = true}) async {
    if (connectStream) await connectWebSocket();
  }

  @override
  Future<void> connectWebSocket() async {
    if (!_closed) _listening = true;
  }

  void activate(String fieldId) {
    if (_closed ||
        !_listening ||
        !fieldSet.fields.any((field) => field.id == fieldId)) {
      return;
    }
    _simulatedEvents.add({'type': 'fieldActivated', 'fieldId': fieldId});
  }

  @override
  Future<void> disconnectWebSocket() async {
    _listening = false;
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _listening = false;
    unawaited(_simulatedEvents.close());
    super.dispose();
  }
}
