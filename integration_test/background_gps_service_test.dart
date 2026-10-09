import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'GPS sensors survive screen lock and media Stop releases playback',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Text('GPS background test')),
      );
      final engine = RevevEngine();
      addTearDown(engine.stop);
      debugPrint('GPS_PERMISSION_READY');
      await Future<void>.delayed(const Duration(seconds: 5));
      await engine.driveTelemetry(driveMode: DriveMode.gpsDrive);
      await engine.start();
      await Future<void>.delayed(const Duration(seconds: 8));
      debugPrint('GPS_LOCK_READY');
      final samples = <Map<String, Object?>>[];
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final s = await engine.stats();
        expect(s.playing, isTrue);
        expect(s.failed, isFalse);
        expect(s.motion['backgroundPlaybackActive'], isTrue);
        expect(s.motion['sensorsActive'], isTrue);
        final age = s.motion['sensorAgeSeconds'] as num?;
        expect(age, isNotNull);
        expect(age, lessThan(1.0));
        samples.add(Map<String, Object?>.from(s.motion));
      }
      binding.reportData = {'gpsBackgroundSamples': samples};
      debugPrint('MEDIA_STOP_READY');
      var stopped = false;
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!(await engine.stats()).playing) {
          stopped = true;
          break;
        }
      }
      expect(stopped, isTrue, reason: 'External media Stop must stop engine');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(
        (await engine.stats()).motion['backgroundPlaybackActive'],
        isFalse,
      );
    },
  );
}
