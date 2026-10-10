import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revev/main.dart' as app;
import 'package:revev_engine/revev_engine.dart';

class _LifecycleProbe with WidgetsBindingObserver {
  bool paused = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) paused = true;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'screen lock preserves playback and repeated starts stay healthy',
    (tester) async {
      final probe = _LifecycleProbe();
      WidgetsBinding.instance.addObserver(probe);
      addTearDown(() => WidgetsBinding.instance.removeObserver(probe));
      app.main();
      await tester.pumpAndSettle();
      await tester.tap(find.text('SPEED SIM'));
      await tester.pumpAndSettle();
      final engine = RevevEngine();
      addTearDown(engine.stop);
      final runs = <Map<String, Object?>>[];
      for (var run = 0; run < 3; run++) {
        await tester.ensureVisible(find.byKey(const Key('start')));
        await tester.tap(find.byKey(const Key('start')));
        await tester.pumpAndSettle();
        await engine.controls(.15, .5);
        tester.widget<Slider>(find.byKey(const Key('sim-speed'))).onChanged!(
          36,
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(seconds: 8));
        final initial = await engine.stats();
        expect(initial.playing, isTrue);
        expect(initial.motion['backgroundPlaybackActive'], isTrue);
        if (run == 0) debugPrint('SCREEN_LOCK_READY');
        final samples = <Map<String, Object?>>[];
        final watch = Stopwatch()..start();
        while (watch.elapsed.inSeconds < (run == 0 ? 40 : 20)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final s = await engine.stats();
          expect(
            s.playing,
            isTrue,
            reason: 'Screen-off must not stop the native session',
          );
          expect(s.failed, isFalse);
          expect(s.motion['backgroundPlaybackActive'], isTrue);
          samples.add({
            'rpm': s.rpm,
            'workMs': s.workMs,
            'workCpuMs': s.motion['workCpuMs'],
            'underruns': s.underruns,
          });
          // Do not request Flutter frames while the actual display is asleep.
        }
        final finalStats = await engine.stats();
        final work = samples.map((s) => s['workMs'] as double).toList()..sort();
        final rpms = samples.map((s) => s['rpm'] as double);
        final underruns = finalStats.underruns - initial.underruns;
        runs.add({
          'run': run,
          'durationSeconds': watch.elapsedMilliseconds / 1000,
          'medianCpuMs': (samples.map((s) => s['workCpuMs'] as num).toList()..sort())[samples.length ~/ 2],
          'underruns': underruns,
          'medianWorkMs': work[work.length ~/ 2],
          'p95WorkMs': work[(work.length * .95).floor()],
          'samples': samples,
        });
        binding.reportData = {
          'screenLockObserved': probe.paused,
          'audioRuns': runs,
        };

        expect(rpms.reduce(math.max) - rpms.reduce(math.min), lessThan(5));
        await engine.stop();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect((await engine.stats()).playing, isFalse);
        expect(
          (await engine.stats()).motion['backgroundPlaybackActive'],
          isFalse,
        );
        await tester.pump();
      }
      for (final run in runs) {
        expect(run['medianWorkMs'] as num, lessThan(10));
        expect((run['underruns'] as num) / (run['durationSeconds'] as num), lessThan(2));
      }
      if (const bool.fromEnvironment('EXPECT_SCREEN_LOCK')) {
        expect(probe.paused, isTrue);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
