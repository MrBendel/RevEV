import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev/main.dart';

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
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls.last.method, 'stop');
      expect(find.text('START'), findsOneWidget);
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
