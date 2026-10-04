import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev/drive_test.dart';
import 'package:revev/drive_test_panel.dart';
import 'package:revev/main.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  test(
    'motion ripple keeps GPS speed steady while acceleration alternates',
    () {
      final a = DriveScenario.ripple.at(13 + 1 / 6);
      final b = DriveScenario.ripple.at(13 + 1 / 2);
      expect(a.speed, b.speed);
      expect(a.accel, closeTo(.8, .001));
      expect(b.accel, closeTo(-.8, .001));
    },
  );
  test(
    'profiles launch, cruise, brake and finish without a speed discontinuity',
    () {
      for (final scenario in DriveScenario.values) {
        expect(scenario.at(0).speed, 0);
        expect(scenario.at(8).accel, greaterThan(0));
        expect(scenario.at(15).speed, closeTo(scenario.topSpeed, 0.001));
        expect(
          scenario
              .at(3 + scenario.rampSeconds + scenario.cruiseSeconds + 2)
              .accel,
          lessThan(0),
        );
        expect(scenario.at(scenario.duration).speed, 0);
        for (var t = 0.1; t < scenario.duration; t += 0.1) {
          final previous = scenario.at(t - 0.1);
          final current = scenario.at(t);
          expect((current.speed - previous.speed).abs(), lessThan(0.46));
        }
      }
    },
  );

  test(
    'dropout removes GPS packets but keeps acceleration and then recovers',
    () {
      final absent = DriveScenario.dropout
          .at(9)
          .packet(gpsTick: true, reset: false);
      expect(absent.containsKey('gpsSpeedMps'), isFalse);
      expect(absent['accelMps2'], greaterThan(0));
      expect(
        DriveScenario.dropout.at(13).packet(gpsTick: true, reset: false),
        contains('gpsSpeedMps'),
      );
      expect(
        DriveScenario.urban.at(4).packet(gpsTick: false, reset: false),
        isNot(contains('gpsSpeedMps')),
      );
    },
  );

  test('report bounds storage, preserves diagnostics and flags missing RPM response', () {
    final report = DriveRecording(
      kind: 'Live GPS drive',
      preset: 'test',
      mount: 'trayTopForward',
      aggressiveness: 0.5,
      volume: 0.15,
    );
    for (var i = 0; i < 1300; i++) {
      report.add(
        i * 0.15,
        const EngineStats(
          vehicleSpeed: 15,
          rpm: 900,
          motion: {'gpsAgeSeconds': 6.0, 'source': 'GPS stale'},
        ),
      );
    }
    expect(report.samples.length, DriveRecording.maxSamples);
    expect(report.observation, contains('RPM stayed near idle'));
    final json = jsonDecode(report.json()) as Map;
    expect(json['samples'][0]['motion']['gpsAgeSeconds'], 6);
    expect(json.containsKey('latitude'), isFalse);
  });

  const channel = MethodChannel('revev_engine');
  testWidgets('live capture preserves input diagnostics when audio stops', (
    tester,
  ) async {
    var playing = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'start') playing = true;
          if (call.method == 'stop') playing = false;
          if (call.method == 'hasLocationPermission') return true;
          if (call.method == 'stats') {
            return {
              'playing': playing,
              'rpm': 2300.0,
              'vehicleSpeed': 12.0,
              'motion': {
                'supported': true,
                'gpsAgeSeconds': 0.2,
                'forwardAccelMps2': 1.5,
                'mount': 'trayTopForward',
              },
            };
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const RevEvApp());
    await tester.tap(find.text('GPS DRIVE'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('start')));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('record-drive')), 300);
    await tester.ensureVisible(find.byKey(const Key('record-drive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-drive')));
    await tester.pump(const Duration(milliseconds: 160));
    playing = false; // Simulate native audio-focus loss.
    await tester.pump(const Duration(milliseconds: 160));
    final panel = tester.widget<DriveTestPanel>(find.byType(DriveTestPanel));
    expect(panel.active, isFalse);
    expect(panel.recording!.status, 'Interrupted: engine stopped');
    expect(
      panel.recording!.samples.first['motion'],
      containsPair('gpsAgeSeconds', 0.2),
    );
    expect(panel.recording!.peakRpm, 2300);
    await tester.pumpWidget(const SizedBox());
  });

  for (final termination in [
    'cancel',
    'background',
    'failure',
    'unsupported',
  ]) {
    testWidgets('replay packets reach native and stop on $termination', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      var playing = false;
      var failed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'start') playing = true;
            if (call.method == 'stop') playing = false;
            if (call.method == 'stats') {
              if (failed) throw PlatformException(code: 'diagnostics_lost');
              return {
                'playing': playing,
                'rpm': 1800.0,
                'gear': 1,
                'motion': {
                  'supported': true,
                  'replay': termination != 'unsupported',
                },
              };
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const RevEvApp());
      await tester.tap(find.text('SPEED SIM'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('scenario-urban')),
        300,
      );
      await tester.ensureVisible(find.byKey(const Key('scenario-urban')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scenario-urban')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final packets = calls
          .where(
            (c) =>
                c.method == 'driveTelemetry' &&
                c.arguments['testSample'] != null,
          )
          .toList();
      expect(packets, isNotEmpty);
      expect(packets.first.arguments['driveMode'], DriveMode.simDrive.index);
      expect(packets.first.arguments['testSample']['reset'], isTrue);
      expect(packets.first.arguments['testSample']['gpsSpeedMps'], 0);
      if (termination == 'cancel') {
        tester.widget<DriveTestPanel>(find.byType(DriveTestPanel)).onStop!();
      } else if (termination == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else if (termination == 'failure') {
        failed = true;
      }
      await tester.pump(const Duration(milliseconds: 160));
      expect(playing, isFalse);
      final count = calls.where((c) => c.method == 'driveTelemetry').length;
      await tester.pump(const Duration(seconds: 2));
      expect(calls.where((c) => c.method == 'driveTelemetry').length, count);
      final panel = tester.widget<DriveTestPanel>(find.byType(DriveTestPanel));
      expect(panel.active, isFalse);
      expect(panel.recording!.samples, isNotEmpty);
      expect(panel.recording!.status, isNot('Recording'));
      await tester.pumpWidget(const SizedBox());
      if (termination == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
    });
  }
}
