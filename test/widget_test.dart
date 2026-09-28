import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev/main.dart';
import 'package:revev/debug_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('revev_engine');
  late List<MethodCall> calls;
  late bool playing;
  setUp(() {
    calls = [];
    playing = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'start') playing = true;
          if (call.method == 'stop') playing = false;
          if (call.method == 'stats') {
            return {
              'playing': playing,
              'rpm': 1500.0,
              'workMs': 3.0,
              'underruns': 0,
              'failed': false,
            };
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  Future<void> mountTest(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RevEvApp());
  }

  DebugDashboard dashboard(WidgetTester tester) =>
      tester.widget<DebugDashboard>(find.byType(DebugDashboard));

  for (final fail in [false, true]) {
    testWidgets(
      'pending rev control cannot continue after ${fail ? 'failure' : 'background'}',
      (tester) async {
        final pendingRev = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              if (call.method == 'start') playing = true;
              if (call.method == 'stop') playing = false;
              if (call.method == 'controls' &&
                  call.arguments['throttle'] == 0.35) {
                await pendingRev.future;
              }
              if (call.method == 'stats') {
                return {'playing': playing, 'rpm': 1500.0, 'workMs': 3.0};
              }
              return null;
            });
        await mountTest(tester);
        dashboard(tester).onRunTest!();
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        if (fail) {
          pendingRev.completeError(PlatformException(code: 'controls_failed'));
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          pendingRev.complete();
        }
        await tester.pump();
        final count = calls.where((c) => c.method == 'controls').length;
        await tester.pump(const Duration(seconds: 20));
        expect(calls.where((c) => c.method == 'controls').length, count);
        expect(playing, isFalse);
        expect(
          dashboard(tester).session.testResult,
          fail ? 'Failed: controls unavailable' : 'Cancelled on background',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        if (!fail) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      },
    );
  }

  testWidgets(
    'repeatable test runs idle rev idle then stops and keeps report',
    (tester) async {
      await mountTest(tester);
      dashboard(tester).onRunTest!();
      await tester.pump();
      expect(dashboard(tester).testPhase, contains('Initial idle'));
      expect(
        tester.widget<Slider>(find.byKey(const Key('throttle'))).onChanged,
        isNull,
      );
      expect(
        tester.widget<Slider>(find.byKey(const Key('volume'))).onChanged,
        isNull,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(dashboard(tester).testPhase, contains('Rev at 35%'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(dashboard(tester).testPhase, contains('Return to idle'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      final session = dashboard(tester).session;
      expect(session.testResult, 'Completed');
      expect(session.testPhases.map((p) => p['throttle']), [0.0, 0.35, 0.0]);
      expect(
        calls
            .where((c) => c.method == 'controls')
            .map((c) => c.arguments['throttle']),
        [0.0, 0.0, 0.35, 0.0],
      );
      expect(playing, isFalse);
      expect(session.samples, greaterThan(0));
      expect(dashboard(tester).onRunTest, isNotNull);
      dashboard(tester).onRunTest!();
      await tester.pump();
      expect(dashboard(tester).session.testPhases.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  for (final background in [false, true]) {
    testWidgets(
      'test cancellation prevents later throttle commands: background=$background',
      (tester) async {
        await mountTest(tester);
        dashboard(tester).onRunTest!();
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        final session = dashboard(tester).session;
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        } else {
          dashboard(tester).onCancelTest!();
        }
        await tester.pump();
        final controlCount = calls.where((c) => c.method == 'controls').length;
        await tester.pump(const Duration(seconds: 20));
        expect(calls.where((c) => c.method == 'controls').length, controlCount);
        expect(playing, isFalse);
        expect(session.testResult, startsWith('Cancelled'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      },
    );
  }

  testWidgets(
    'engine focus loss interrupts the test without later rev commands',
    (tester) async {
      await mountTest(tester);
      dashboard(tester).onRunTest!();
      await tester.pump();
      playing = false;
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(dashboard(tester).session.testResult, 'Interrupted');
      await tester.pump(const Duration(seconds: 20));
      expect(
        calls.where(
          (c) => c.method == 'controls' && c.arguments['throttle'] > 0,
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'starts at zero throttle, forwards controls, stops on background',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const RevEvApp());
      expect(
        tester.widget<Slider>(find.byKey(const Key('throttle'))).onChanged,
        isNull,
      );
      await tester.tap(find.byKey(const Key('start')));
      await tester.pump();
      expect(calls.first.method, 'controls');
      expect(calls.first.arguments['throttle'], 0.0);
      expect(find.text('STOP'), findsOneWidget);
      tester.widget<Slider>(find.byKey(const Key('throttle'))).onChanged!(0.4);
      await tester.pump();
      expect(calls.last.arguments['throttle'], 0.4);
      await tester.pump(const Duration(milliseconds: 150));
      final diagnostics = tester
          .widget<DebugDashboard>(find.byType(DebugDashboard))
          .session;
      expect(diagnostics.samples, greaterThan(0));
      expect(diagnostics.averageMs, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls.last.method, 'stop');
      expect(find.text('START'), findsOneWidget);
      expect(diagnostics.status, 'Stopped on background');
      expect(diagnostics.averageMs, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
  testWidgets('shows startup failures without claiming the engine is running', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'start') {
            throw PlatformException(
              code: 'audio_start',
              message: 'Unavailable',
            );
          }
          return null;
        });
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RevEvApp());
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    expect(find.textContaining('Could not start'), findsOneWidget);
    expect(find.text('ENGINE OFF'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('backgrounding cancels a pending start', (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pendingControls = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'controls') await pendingControls.future;
          return null;
        });
    await tester.pumpWidget(const RevEvApp());
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    pendingControls.complete();
    await tester.pump();
    expect(calls.where((call) => call.method == 'start'), isEmpty);
    expect(find.text('ENGINE OFF'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  testWidgets('fits a small phone with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RevEvApp());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
