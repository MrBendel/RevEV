import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revev_engine/revev_engine.dart';

double trafficSpeed(double t) {
  if (t >= 13.5) return 0;
  final phase = math.max(0.0, t) % 4.5;
  return phase < 2
      ? phase * 2
      : phase < 4
      ? 4 - (phase - 2) * 2
      : 0;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('IMU leads repeated braking and relaunch with delayed GPS', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Text('Stop and go')));
    final engine = RevevEngine();
    addTearDown(engine.stop);
    await engine.controls(.15, .5);
    await engine.driveTelemetry(driveMode: DriveMode.simDrive);
    await engine.start();
    await Future<void>.delayed(const Duration(seconds: 8));
    final initial = await engine.stats();
    final samples = <Map<String, Object?>>[];
    final brakeLatency = <double?>[null, null, null];
    final launchLatency = <double?>[null, null, null];
    final brakeInputTime = <double?>[null, null, null];
    final launchInputTime = <double?>[null, null, null];
    final brakeBaselineRpm = <double>[900, 900, 900];
    final stoppedSpeed = <double?>[null, null, null];
    final watch = Stopwatch()..start();
    var lastGps = -1;
    var maxError = 0.0;
    var maxInputGap = 0.0;
    var previousInputTime = 0.0;
    var brakingRises = 0;
    EngineStats? previous;
    while (watch.elapsedMilliseconds < 14500) {
      final t = watch.elapsedMicroseconds / 1e6;
      maxInputGap = math.max(maxInputGap, t - previousInputTime);
      previousInputTime = t;
      final cycle = (t / 4.5).floor();
      final phase = t % 4.5;
      final a = cycle >= 3
          ? 0.0
          : phase < 2
          ? 2.0
          : phase < 4
          ? -2.0
          : 0.0;
      final tick = t.floor();
      if (cycle < 3) {
        if (a > 0) launchInputTime[cycle] ??= t;
        if (a < 0) brakeInputTime[cycle] ??= t;
      }
      await engine.driveTelemetry(
        driveMode: DriveMode.simDrive,
        testSample: {
          'timeSeconds': t,
          // Runs the same forward filter used by live accelerometer events.
          'rawForwardAccelMps2': a,
          'reset': lastGps < 0,
          if (tick != lastGps) ...{
            'gpsTimeSeconds': math.max(0.0, t - .6),
            'gpsSpeedMps': trafficSpeed(t - .6),
          },
        },
      );
      lastGps = tick;
      // Match the existing native-engine harness rate. Live IMU callbacks do
      // not cross the Dart channel; Kotlin regressions also run at 50 Hz.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final s = await engine.stats();
      expect(s.playing, isTrue);
      expect(s.failed, isFalse);
      final observed = watch.elapsedMicroseconds / 1e6;
      maxError = math.max(maxError, (s.vehicleSpeed - trafficSpeed(t)).abs());
      if (cycle < 3) {
        if (phase < 2) {
          // Use the last pre-braking RPM, not the launch peak: clutch lockup
          // can lower RPM before braking and must not count as a response.
          brakeBaselineRpm[cycle] = s.rpm;
          if (s.vehicleSpeed > .15) {
            launchLatency[cycle] ??= (observed - launchInputTime[cycle]!) * 1000;
          }
        } else if (phase < 4) {
          if (s.rpm < brakeBaselineRpm[cycle] - 25) {
            brakeLatency[cycle] ??= (observed - brakeInputTime[cycle]!) * 1000;
          }
          if (phase > 2.2 &&
              previous != null &&
              s.gear == previous.gear &&
              s.rpm > previous.rpm + 5) {
            brakingRises++;
          }
        } else if (phase > 4.2) {
          stoppedSpeed[cycle] = s.vehicleSpeed;
        }
      }
      samples.add({
        'seconds': t,
        'observedSeconds': observed,
        'inputAccel': a,
        'inputSpeed': trafficSpeed(t),
        'speed': s.vehicleSpeed,
        'rpm': s.rpm,
        'gear': s.gear,
        'workMs': s.workMs,
        'underruns': s.underruns,
        'motion': s.motion,
      });
      previous = s;
    }
    final last = await engine.stats();
    final underruns = last.underruns - initial.underruns;
    binding.reportData = {
      'stopGo': {
        'brakeRpmLatencyMs': brakeLatency,
        'launchSpeedLatencyMs': launchLatency,
        'brakeInputTimeSeconds': brakeInputTime,
        'launchInputTimeSeconds': launchInputTime,
        'brakeBaselineRpm': brakeBaselineRpm,
        'stoppedSpeedMps': stoppedSpeed,
        'brakingRises': brakingRises,
        'maxSpeedErrorMps': maxError,
        'maxInputGapMs': maxInputGap * 1000,
        'underruns': underruns,
        'durationSeconds': watch.elapsedMicroseconds / 1e6,
        'samples': samples,
      },
    };
    // Latency starts at actual input dispatch, not a scheduled transition that
    // might not have been delivered. Independently fail runs with input stalls.
    expect(maxInputGap, lessThan(.15), reason: 'Synthetic IMU delivery stalled');
    for (var i = 0; i < 3; i++) {
      expect(brakeLatency[i], isNotNull);
      expect(brakeLatency[i]!, lessThan(200));
      expect(launchLatency[i], isNotNull);
      expect(launchLatency[i]!, lessThan(200));
      expect(stoppedSpeed[i], isNotNull);
      expect(stoppedSpeed[i]!, lessThan(.2));
    }
    expect(brakingRises, 0);
    expect(maxError, lessThan(.3));
    expect(last.rpm, closeTo(900, 5));
    expect(underruns / (watch.elapsedMicroseconds / 1e6), lessThan(2));
  });
}
