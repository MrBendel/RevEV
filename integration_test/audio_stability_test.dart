import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'audio survives long drive, transient focus and repeated starts',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Audio stability harness')),
        ),
      );
      final engine = RevevEngine();
      final runs = <Object?>[];
      addTearDown(engine.stop);
      for (var run = 0; run < 3; run++) {
        await engine.controls(.15, .5);
        await engine.driveTelemetry(
          speedMps: 10,
          driveMode: DriveMode.simDrive,
        );
        await engine.start();
        await Future<void>.delayed(const Duration(seconds: 8));
        final initial = await engine.stats();
        expect(initial.playing, isTrue);
        final samples = <Map<String, Object?>>[];
        if (run == 0) debugPrint('AUDIO_SOAK_READY');
        final watch = Stopwatch()..start();
        final duration = run == 0 ? 120 : 30;
        while (watch.elapsed.inSeconds < duration) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final s = await engine.stats();
          expect(
            s.playing,
            isTrue,
            reason: 'Temporary focus loss must preserve the session',
          );
          expect(s.failed, isFalse);
          samples.add({
            'seconds': watch.elapsedMilliseconds / 1000,
            'rpm': s.rpm,
            'workMs': s.workMs,
            'underruns': s.underruns,
            'focusGain': s.motion['audioFocusGain'],
          });
          await tester.pump();
        }
        final finalStats = await engine.stats();
        final work = samples.map((s) => s['workMs'] as double).toList()..sort();
        final underruns = finalStats.underruns - initial.underruns;
        runs.add({
          'run': run,
          'seconds': watch.elapsedMilliseconds / 1000,
          'underruns': underruns,
          'medianWorkMs': work[work.length ~/ 2],
          'p95WorkMs': work[(work.length * .95).floor()],
          'samples': samples,
        });
        binding.reportData = {'audioRuns': runs};
        expect(
          work[work.length ~/ 2],
          lessThan(10),
          reason: 'Producer must keep up with 10 ms audio blocks',
        );
        expect(
          underruns / watch.elapsed.inSeconds,
          lessThan(2),
          reason: 'Sustained playback must not starve',
        );
        expect(
          samples.map((s) => s['rpm'] as double).reduce(math.max) -
              samples.map((s) => s['rpm'] as double).reduce(math.min),
          lessThan(5),
        );
        if (run == 0 &&
            const bool.fromEnvironment('EXPECT_AUDIO_FOCUS_INTERRUPTION')) {
          expect(
            samples.where((s) => s['focusGain'] == 0).length,
            greaterThan(3),
          );
          expect(samples.last['focusGain'], 1.0);
        }
        await engine.stop();
        expect((await engine.stats()).playing, isFalse);
      }
    },
  );
}
