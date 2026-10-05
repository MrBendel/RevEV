import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:revev/main.dart' as app;
import 'package:revev_engine/revev_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('start and stop persist separate diagnostic files', (
    tester,
  ) async {
    final directory = Directory(await RevevEngine().sessionLogDirectory());
    final before = (await directory.list().toList()).map((f) => f.path).toSet();
    app.main();
    await tester.pumpAndSettle();
    for (var run = 0; run < 2; run++) {
      await tester.ensureVisible(find.byKey(const Key('start')));
      await tester.tap(find.byKey(const Key('start')));
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 3));
      await tester.pump();
      await tester.tap(find.byKey(const Key('start')));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        if (find.text('START').evaluate().isNotEmpty) break;
      }
      expect(find.text('START'), findsOneWidget);
    }
    final files = (await directory.list().toList())
        .whereType<File>()
        .where((f) => !before.contains(f.path))
        .toList();
    expect(files.length, 2);
    for (final file in files) {
      final rows = (await file.readAsLines()).map(jsonDecode).toList();
      expect(rows.first['type'], 'start');
      expect(rows.last['type'], 'stop');
      final samples = rows.where((r) => r['type'] == 'sample').toList();
      expect(samples.length, greaterThan(5));
      expect(samples.first['motion'].containsKey('targetRpm'), isTrue);
      expect(samples.last['rpm'], isA<num>());
    }
    await tester.scrollUntilVisible(find.text('Session logs'), 300);
    await tester.tap(find.text('Session logs'));
    await tester.pumpAndSettle();
    expect(find.text(files.first.uri.pathSegments.last), findsOneWidget);
    if (const bool.fromEnvironment('TEST_EXPORT')) {
      await RevevEngine()
          .exportSessionLog(files.first.uri.pathSegments.last)
          .timeout(const Duration(seconds: 60));
    }
  });
}
