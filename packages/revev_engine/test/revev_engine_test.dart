import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('decodes native engine diagnostics', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('revev_engine'),
          (call) async => {
            'rpm': 1700,
            'workMs': 4.2,
            'underruns': 2,
            'playing': true,
            'failed': false,
            'boost': 0.85,
          },
        );
    final stats = await RevevEngine().stats();
    expect(stats.rpm, 1700);
    expect(stats.playing, isTrue);
    expect(stats.boost, 0.85);
  });
}
