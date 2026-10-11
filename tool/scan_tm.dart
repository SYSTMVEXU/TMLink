// ignore_for_file: avoid_print
import 'package:tmlink/core/tm_instance_detector.dart';

Future<void> main() async {
  final detector = TmInstanceDetector();
  try {
    final instances = await detector.scanLocalNetwork();
    print('Detected count: ${instances.length}');
    for (final i in instances) {
      print('${i.hostForInput}\t${i.evidence}');
    }
  } finally {
    detector.dispose();
  }
}
