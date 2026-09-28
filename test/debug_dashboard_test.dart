import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev/debug_dashboard.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  test('keeps session totals while bounding recent percentile samples', () {
    final session = DebugSession()..begin();
    for (var i = 1; i <= 500; i++) {
      session.record(
        EngineStats(workMs: i.toDouble(), underruns: i),
        Duration(milliseconds: i * 150),
      );
    }
    expect(session.samples, 500);
    expect(session.averageMs, 250.5);
    expect(session.peakMs, 500);
    expect(session.recentMs.length, 400);
    expect(session.p95Ms, 480);
    final report = jsonDecode(session.report()) as Map<String, dynamic>;
    expect(report['underrunsAtLastPoll'], 500);
    expect(report['durationSeconds'], 75);
    session.begin();
    expect(session.samples, 0);
    expect(session.recentMs, isEmpty);
    expect(session.latest.underruns, 0);
    expect(session.averageMs, 0);
  });

  testWidgets('expanded dashboard fits enlarged text and copies a report', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final session = DebugSession()
      ..begin()
      ..record(
        const EngineStats(rpm: 1650, workMs: 3.5, underruns: 2),
        const Duration(seconds: 5),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(26),
            children: [DebugDashboard(session: session)],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Debug dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('3.50 ms'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Copy debug report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy debug report'));
    await tester.pumpAndSettle();
    expect(jsonDecode(copied!)['underrunsAtLastPoll'], 2);
    expect(find.text('Debug report copied'), findsOneWidget);
  });
}
