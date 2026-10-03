import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev/main.dart';
import 'package:revev/mounting_position.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('revev_engine');

  group('MountingPosition enum and definitions', () {
    test('contains all 7 expected physical mounting positions', () {
      final names = MountingPosition.values.map((p) => p.name).toList();
      expect(names, containsAll([
        'trayTopForward',
        'trayTopRearward',
        'trayTopLeft',
        'trayTopRight',
        'uprightPortrait',
        'uprightLandscapeLeft',
        'uprightLandscapeRight',
      ]));
      expect(MountingPosition.values.length, 7);

      for (final pos in MountingPosition.values) {
        expect(pos.label.isNotEmpty, isTrue);
        expect(pos.description.isNotEmpty, isTrue);
      }
    });
  });

  group('Native RevevEnginePlugin Accelerometer Implementation', () {
    test('RevevEnginePlugin.kt implements ActivityAware and location permission checks', () {
      final pluginFile = File('packages/revev_engine/android/src/main/kotlin/dev/revev/revev_engine/RevevEnginePlugin.kt');
      expect(pluginFile.existsSync(), isTrue);
      final content = pluginFile.readAsStringSync();

      expect(content, contains('ActivityAware'));
      expect(content, contains('onAttachedToActivity'));
      expect(content, contains('requestPermissions'));
      expect(content, contains('ACCESS_FINE_LOCATION'));
    });

    test('RevevEnginePlugin.kt implements correct sensor coordinate transforms for all mounting positions', () {
      final pluginFile = File('packages/revev_engine/android/src/main/kotlin/dev/revev/revev_engine/RevevEnginePlugin.kt');
      expect(pluginFile.existsSync(), isTrue);
      final content = pluginFile.readAsStringSync();

      // Forward acceleration transforms
      expect(content, contains('"trayTopForward" -> linearY'));
      expect(content, contains('"trayTopRearward" -> -linearY'));
      expect(content, contains('"trayTopLeft" -> -linearX'));
      expect(content, contains('"trayTopRight" -> linearX'));
      expect(content, contains('"uprightPortrait", "uprightLandscapeLeft", "uprightLandscapeRight" -> -linearZ'));

      // Lateral acceleration transforms
      expect(content, contains('"trayTopForward", "trayTopRearward", "uprightPortrait" -> kotlin.math.abs(linearX)'));
      expect(content, contains('"trayTopLeft", "trayTopRight", "uprightLandscapeLeft", "uprightLandscapeRight" -> kotlin.math.abs(linearY)'));
    });

    test('RevevEnginePlugin.kt isolates gravity for raw accelerometer and smooths chassis vibration', () {
      final pluginFile = File('packages/revev_engine/android/src/main/kotlin/dev/revev/revev_engine/RevevEnginePlugin.kt');
      expect(pluginFile.existsSync(), isTrue);
      final content = pluginFile.readAsStringSync();

      // Gravity isolation filter for raw accelerometer
      expect(content, contains('Sensor.TYPE_ACCELEROMETER'));
      expect(content, contains('gravity[0]'));
      expect(content, contains('rawX - gravity[0]'));

      // Low-pass smoothing and deadband
      expect(content, contains('smoothedAccel'));
      expect(content, contains('deadbandForward'));

      // Velocity dead-reckoning fallback
      expect(content, contains('estimatedSpeedMps'));
    });

    test('RevevEnginePlugin.kt starts sensors on engine start and drive mode changes', () {
      final pluginFile = File('packages/revev_engine/android/src/main/kotlin/dev/revev/revev_engine/RevevEnginePlugin.kt');
      expect(pluginFile.existsSync(), isTrue);
      final content = pluginFile.readAsStringSync();

      // Method "start" checks currentDriveMode and starts sensors
      expect(content, contains('if (currentDriveMode == 1) {\n                            startSensors()\n                        }'));
      // onSetDriveMode checks currentDriveMode and updates sensors
      expect(content, contains('if (currentDriveMode == 1) {\n                if (!sensorsActive) startSensors()'));
      // Method "driveTelemetry" preserves native speed/accel in mode 1
      expect(content, contains('if (currentDriveMode != 1) {'));
    });
  });

  group('UI Mounting Position & Drive Telemetry Dispatch', () {
    testWidgets('changing mounting position forwards mountingPositionName to native engine', (tester) async {
      final calls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'stats') {
              return {
                'playing': false,
                'rpm': 0.0,
                'gear': 0,
                'vehicleSpeed': 0.0,
                'tireSquealLevel': 0.0,
              };
            }
            return null;
          });

      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      tester.view.physicalSize = const Size(430, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RevEvApp());
      await tester.pumpAndSettle();

      // Find and expand phone mounting tile
      final mountingTile = find.byKey(const Key('mounting-settings'));
      await tester.scrollUntilVisible(mountingTile, 300);
      expect(mountingTile, findsOneWidget);
      await tester.tap(mountingTile);
      await tester.pumpAndSettle();

      // Open mounting position dropdown
      final dropdown = find.byKey(const Key('mounting-position'));
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Select Upright · portrait
      await tester.tap(find.text(MountingPosition.uprightPortrait.label).last);
      await tester.pumpAndSettle();

      final telemetryCalls = calls.where((c) => c.method == 'driveTelemetry').toList();
      expect(telemetryCalls.isNotEmpty, isTrue);
      expect(telemetryCalls.last.arguments['mountingPosition'], 'uprightPortrait');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
