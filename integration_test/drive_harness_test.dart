import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revev/drive_test.dart';
import 'package:revev/drive_test_panel.dart';
import 'package:revev/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('driving scenarios exercise native fusion, RPM and shifting', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('SPEED SIM'));
    await tester.pumpAndSettle();
    final reports = <Object?>[];
    for (final scenario in [DriveScenario.urban, DriveScenario.dropout]) {
      await tester.scrollUntilVisible(
        find.byKey(Key('scenario-${scenario.name}')),
        250,
      );
      await tester.ensureVisible(find.byKey(Key('scenario-${scenario.name}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('scenario-${scenario.name}')));
      await tester.pump();
      for (var i = 0; i < 180; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        final panel = tester.widget<DriveTestPanel>(
          find.byType(DriveTestPanel),
        );
        if (!panel.active && panel.recording != null) break;
      }
      final panel = tester.widget<DriveTestPanel>(find.byType(DriveTestPanel));
      final report = panel.recording!;
      reports.add(jsonDecode(report.json()));
      binding.reportData ??= {};
      binding.reportData!['driveReports'] = reports;
      expect(report.status, 'Completed');
      expect(report.peakSpeed, greaterThan(12));
      expect(report.peakRpm, greaterThan(1500));
      expect(report.samples.any((s) => (s['gear'] as int) > 1), isTrue);
      expect(report.samples.last['speedMps'] as double, lessThan(0.5));
      if (scenario == DriveScenario.dropout) {
        expect(
          report.samples.any(
            (s) => (s['motion'] as Map)['source'] == 'GPS stale · speed held',
          ),
          isTrue,
        );
      }
    }
    await binding.convertFlutterSurfaceToImage();
    await tester.scrollUntilVisible(
      find.byKey(const Key('copy-drive-report')),
      250,
    );
    await tester.pump();
    final screenshot = await binding.takeScreenshot('drive-test-lab');
    binding.reportData!.remove('screenshots');
    binding.reportData!['drive-test-lab'] = base64Encode(screenshot);
    await tester.pumpWidget(const SizedBox());
  });
}
