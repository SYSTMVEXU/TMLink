// ignore_for_file: avoid_print
// Run this diagnostic through a Flutter test/session; it uses platform storage.
import 'package:flutter/widgets.dart';
import 'package:tmlink/core/tm_api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = await TmApiClient.fromSettings();
  try {
    final sets = TmFieldSet.parse(await client.getFieldsets());
    print('TM returned ${sets.length} field sets.');
    for (final set in sets) {
      final fields = set.fields.isNotEmpty
          ? set.fields
          : TmFieldSet.parseFields(await client.getFieldsForFieldset(set.id));
      print('Field set ${set.id}: ${fields.length} fields');
    }
  } catch (error) {
    print('TM diagnostic: $error');
  } finally {
    client.dispose();
  }
}
