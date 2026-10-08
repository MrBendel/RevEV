import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'one hertz delayed GPS and IMU produce immediate continuous RPM',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('GPS smoothing')));
      final engine = RevevEngine();
      addTearDown(engine.stop);
      await engine.controls(.15, .5);
      await engine.driveTelemetry(speedMps: 10, driveMode: DriveMode.simDrive);
      await engine.start();
      await Future<void>.delayed(const Duration(seconds: 8));
      int? settledUnderruns;
      final samples = <Map<String, Object?>>[];
      final watch = Stopwatch()..start();
      var lastGps = -1;
      var checked = 0, flat = 0, wrongDirection = 0;
      var maxRpmStep = 0.0;
      var maxSpeedError = 0.0;
      EngineStats? previous;
      var lastShift = 0.0;
      while (watch.elapsed.inSeconds < 22) {
        final t = watch.elapsedMicroseconds / 1e6;
        final speed = t < 3
            ? 10.0
            : t < 9
            ? 10 + (t - 3) * .5
            : t < 12
            ? 13.0
            : t < 18
            ? 13 - (t - 12) * .5
            : 10.0;
        final tick = t.floor();
        await engine.driveTelemetry(
          driveMode: DriveMode.simDrive,
          testSample: {
            'timeSeconds': t,
            'accelMps2': t >= 3 && t < 9
                ? .5
                : t >= 12 && t < 18
                ? -.5
                : 0.0,
            'reset': lastGps < 0,
            if (tick != lastGps) ...{
              'gpsTimeSeconds': math.max(0.0, t - .3),
              'gpsSpeedMps': t < 3.3
                  ? 10.0
                  : t < 9.3
                  ? 10 + (t - 3.3) * .5
                  : t < 12.3
                  ? 13.0
                  : t < 18.3
                  ? 13 - (t - 12.3) * .5
                  : 10.0,
            },
          },
        );
        lastGps = tick;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final s = await engine.stats();
        expect(s.playing, isTrue);
        expect(s.failed, isFalse);
        if (t >= 3) settledUnderruns ??= s.underruns;
        if (previous != null && previous.gear != s.gear) lastShift = t;
        samples.add({
          'seconds': t,
          'inputSpeed': speed,
          'speed': s.vehicleSpeed,
          'rpm': s.rpm,
          'gear': s.gear,
          'workMs': s.workMs,
          'underruns': s.underruns,
          'motion': s.motion,
        });
        if (previous != null &&
            previous.gear == s.gear &&
            t - lastShift > .8 &&
            ((t > 5 && t < 8.5) || (t > 14 && t < 17.5))) {
          final delta = s.rpm - previous.rpm;
          final expectedSpeed = speed;
          maxSpeedError = math.max(
            maxSpeedError,
            (s.vehicleSpeed - expectedSpeed).abs(),
          );
          maxRpmStep = math.max(maxRpmStep, delta.abs());
          checked++;
          if (delta.abs() < .1) flat++;
          if ((t < 9 && delta < -.1) || (t > 12 && delta > .1)) {
            wrongDirection++;
          }
        }
        previous = s;
        await tester.pump();
      }
      final finalStats = await engine.stats();
      binding.reportData = {
        'gpsSmoothing': {
          'samples': samples,
          'checked': checked,
          'flat': flat,
          'wrongDirection': wrongDirection,
          'maxRpmStep': maxRpmStep,
          'maxSpeedErrorMps': maxSpeedError,
          'underruns': finalStats.underruns - settledUnderruns!,
        },
      };
      expect(checked, greaterThan(80));
      expect(flat / checked, lessThan(.1));
      expect(wrongDirection, 0);
      expect(maxRpmStep, lessThan(40));
      expect(
        maxSpeedError,
        lessThan(.1),
        reason: 'Speed must track current motion without a one-second delay',
      );
      expect(finalStats.vehicleSpeed, closeTo(10, .1));
      // Same rate budget as audio_stability_test; emulator scheduling can cause
      // isolated underruns. Preserve the count in the report, not a zero-loss claim.
      expect(
        (finalStats.underruns - settledUnderruns) /
            (watch.elapsedMilliseconds / 1000 - 3),
        lessThan(2),
      );
    },
  );
}
