import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revev/main.dart' as app;
import 'package:revev_engine/revev_engine.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native engine starts, revs, stops, and restarts', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    final off = await binding.takeScreenshot('dashboard-off');
    binding.reportData!.remove('screenshots');
    binding.reportData!['dashboard-off'] = base64Encode(off);
    final engine = RevevEngine();
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 5));
    await tester.pump();
    final idle = await engine.stats();
    expect(idle.playing, isTrue);
    expect(idle.failed, isFalse);
    expect(idle.rpm, greaterThan(500));
    await tester.scrollUntilVisible(
      find.byKey(const Key('listening-mode')),
      250,
    );
    for (final mode in [ListeningMode.cabin, ListeningMode.cabinRumble]) {
      tester
          .widget<DropdownButtonFormField<ListeningMode>>(
            find.byKey(const Key('listening-mode')),
          )
          .onChanged!(mode);
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
      expect((await engine.stats()).playing, isTrue);
      expect((await engine.stats()).failed, isFalse);
    }
    final listening = await binding.takeScreenshot('listening-controls');
    binding.reportData!.remove('screenshots');
    binding.reportData!['listening-controls'] = base64Encode(listening);
    await tester.scrollUntilVisible(find.byKey(const Key('throttle')), -250);
    final slider = tester.widget<Slider>(find.byKey(const Key('throttle')));
    slider.onChanged!(0.35);
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 4));
    await tester.pump();
    final rev = await engine.stats();
    expect(rev.failed, isFalse);
    expect(rev.rpm, greaterThan(idle.rpm + 500));
    await tester.scrollUntilVisible(find.byKey(const Key('start')), -250);
    // Render intermediate animation frames before capturing the needle.
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final running = await binding.takeScreenshot('dashboard-running');
    binding.reportData!.remove('screenshots');
    binding.reportData!['dashboard-running'] = base64Encode(running);
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'idleRpm': idle.rpm,
      'revRpm': rev.rpm,
      'blockMs': rev.workMs,
      'underruns': rev.underruns,
    });
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    expect((await engine.stats()).stopping, isTrue);
    for (var i = 0; i < 120 && (await engine.stats()).playing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    expect((await engine.stats()).playing, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.scrollUntilVisible(
      find.byKey(const Key('engine-preset')),
      -250,
    );
    final selector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('engine-preset')),
    );
    selector.onChanged!('porsche/911_turbo_33');
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('start')), 250);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    await Future<void>.delayed(const Duration(seconds: 5));
    await tester.pump();
    expect((await engine.stats()).playing, isTrue);
    expect((await engine.stats()).rpm, greaterThan(500));
    await engine.stop();
    await tester.pumpWidget(const SizedBox());
  });
}
