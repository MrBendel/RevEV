import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revev/drive_test_panel.dart';
import 'package:revev/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('steady speed produces stable actual RPM without gear hunting', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('SPEED SIM'));
    await tester.pumpAndSettle();
    final reports = <Object?>[];
    final metrics = <Object?>[];
    for (final scenario in ['steady', 'ripple']) {
      final button = find.byKey(Key('scenario-$scenario'));
      await tester.scrollUntilVisible(button, 250);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        final panel = tester.widget<DriveTestPanel>(
          find.byType(DriveTestPanel),
        );
        if (!panel.active && panel.recording != null) break;
      }
      final report = tester
          .widget<DriveTestPanel>(find.byType(DriveTestPanel))
          .recording!;
      final settled = report.samples.where((s) {
        final input = s['input'] as Map?;
        return input != null &&
            input['phase'] == 'Cruising' &&
            (input['seconds'] as num) >= 23;
      }).toList();
      final rpms = settled.map((s) => s['rpm'] as double).toList()..sort();
      final spread = rpms.isEmpty
          ? double.infinity
          : rpms[(rpms.length * .95).floor()] -
                rpms[(rpms.length * .05).floor()];
      final meanError = settled.isEmpty
          ? double.infinity
          : settled
                    .map(
                      (s) =>
                          ((s['rpm'] as num) -
                                  ((s['motion'] as Map)['targetRpm'] as num))
                              .abs(),
                    )
                    .reduce((a, b) => a + b) /
                settled.length;
      reports.add(jsonDecode(report.json()));
      metrics.add({
        'scenario': scenario,
        'cruiseRpmP95MinusP5': spread.isFinite ? spread : null,
        'cruiseMeanAbsoluteRpmError': meanError.isFinite ? meanError : null,
      });
      binding.reportData = {'driveReports': reports, 'cruiseMetrics': metrics};
      expect(report.status, 'Completed');
      expect(settled.length, greaterThan(30));
      expect(settled.map((s) => s['gear']).toSet().length, 1);
      expect(
        settled.map((s) => s['speedMps'] as double).reduce(math.max) -
            settled.map((s) => s['speedMps'] as double).reduce(math.min),
        lessThan(scenario == 'steady' ? .1 : .4),
      );
      expect(
        spread,
        lessThan(scenario == 'steady' ? 5 : 100),
        reason: 'Steady inputs must not produce rhythmic RPM surges',
      );
      expect(
        meanError,
        lessThan(5),
        reason: 'Stable RPM must still track requested RPM',
      );
    }
    await tester.pumpWidget(const SizedBox());
  });
}
