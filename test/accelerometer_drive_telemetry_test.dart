import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev/main.dart';
import 'package:revev/mounting_position.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('revev_engine');

  group('MountingPosition enum and definitions', () {
    test(
      'contains all 8 expected physical mounting positions including auto',
      () {
        final names = MountingPosition.values.map((p) => p.name).toList();
        expect(
          names,
          containsAll([
            'auto',
            'trayTopForward',
            'trayTopRearward',
            'trayTopLeft',
            'trayTopRight',
            'uprightPortrait',
            'uprightLandscapeLeft',
            'uprightLandscapeRight',
          ]),
        );
        expect(MountingPosition.values.length, 8);

        for (final pos in MountingPosition.values) {
          expect(pos.label.isNotEmpty, isTrue);
          expect(pos.description.isNotEmpty, isTrue);
        }
      },
    );
  });

  group('Native RevevEnginePlugin Accelerometer Implementation', () {
    test('RevevEnginePlugin.kt implements ActivityAware and location permission checks', () {
      final pluginFile = File(
        'packages/revev_engine/android/src/main/kotlin/dev/revev/revev_engine/RevevEnginePlugin.kt',
      );
      expect(pluginFile.existsSync(), isTrue);
      final content = pluginFile.readAsStringSync().replaceAll('\r\n', '\n');

      expect(content, contains('ActivityAware'));
      expect(content, contains('RequestPermissionsResultListener'));
      expect(content, contains('onAttachedToActivity'));
      expect(content, contains('addRequestPermissionsResultListener'));
      expect(content, contains('onRequestPermissionsResult'));
      expect(content, contains('ACCESS_FINE_LOCATION'));
    });

    test('RevevEnginePlugin.kt implements correct sensor coordinate transforms for all mounting positions', () {
      final pluginFile = File(
        'packages/revev_engine/android/src/main/kotlin/dev/revev/revev_engine/RevevEnginePlugin.kt',
      );
      expect(pluginFile.existsSync(), isTrue);
      final content = pluginFile.readAsStringSync().replaceAll('\r\n', '\n');

      // Bump rejection and gravity isolation
      expect(content, contains('gravNormSq'));
      expect(content, contains('vertDot'));

      // Forward acceleration transforms
      expect(content, contains('"trayTopForward" -> horizY'));
      expect(content, contains('"trayTopRearward" -> -horizY'));
      expect(content, contains('"trayTopLeft" -> -horizX'));
      expect(content, contains('"trayTopRight" -> horizX'));
      expect(
        content,
        contains(
          '"uprightPortrait", "uprightLandscapeLeft", "uprightLandscapeRight" -> -horizZ',
        ),
      );

      // Lateral acceleration transforms
      expect(
        content,
        contains(
          '"trayTopForward", "trayTopRearward", "uprightPortrait" -> kotlin.math.abs(horizX)',
        ),
      );
      expect(
        content,
        contains(
          '"trayTopLeft", "trayTopRight", "uprightLandscapeLeft", "uprightLandscapeRight" -> kotlin.math.abs(horizY)',
        ),
      );
    });

    test('RevevEnginePlugin.kt isolates gravity for raw accelerometer and smooths chassis vibration', () {
      final pluginFile = File(
        'packages/revev_engine/android/src/main/kotlin/dev/revev/revev_engine/RevevEnginePlugin.kt',
      );
      expect(pluginFile.existsSync(), isTrue);
      final content = pluginFile.readAsStringSync().replaceAll('\r\n', '\n');

      // Gravity isolation filter for raw accelerometer
      expect(content, contains('Sensor.TYPE_ACCELEROMETER'));
      expect(content, contains('gravity[0]'));
      expect(content, contains('rawX - gravity[0]'));

      // Low-pass smoothing and deadband
      expect(content, contains('smoothedAccel'));
      expect(content, contains('deadbandForward'));

      // Velocity dead-reckoning fallback
      expect(
        content,
        contains('motion.step(nowSeconds(), currentAccelMps2.toDouble())'),
      );
      expect(
        content,
        contains('motion.gps(now, fixTime, speed, accuracy, speedAccuracy)'),
      );
    });

    test('RevevEnginePlugin.kt starts sensors on engine start and drive mode changes', () {
      final pluginFile = File(
        'packages/revev_engine/android/src/main/kotlin/dev/revev/revev_engine/RevevEnginePlugin.kt',
      );
      expect(pluginFile.existsSync(), isTrue);
      final content = pluginFile.readAsStringSync().replaceAll('\r\n', '\n');

      // Method "start" checks currentDriveMode and starts sensors
      expect(
        content,
        contains(
          'if (currentDriveMode == 1) {\n                            startSensors()\n                        }',
        ),
      );
      // onSetDriveMode checks currentDriveMode and updates sensors
      expect(
        content,
        contains(
          'if (currentDriveMode == 1) {\n                if (!sensorsActive) startSensors()',
        ),
      );
      // Method "driveTelemetry" preserves native speed/accel in mode 1
      expect(content, contains('if (currentDriveMode != 1) {'));
    });
  });

  group('UI Mounting Position & Drive Telemetry Dispatch', () {
    testWidgets(
      'changing mounting position forwards mountingPositionName to native engine',
      (tester) async {
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

        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );

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
        await tester.tap(
          find.text(MountingPosition.uprightPortrait.label).last,
        );
        await tester.pumpAndSettle();

        final telemetryCalls = calls
            .where((c) => c.method == 'driveTelemetry')
            .toList();
        expect(telemetryCalls.isNotEmpty, isTrue);
        expect(
          telemetryCalls.last.arguments['mountingPosition'],
          'uprightPortrait',
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );

    test(
      'RevevEngine invokes hasLocationPermission and requestLocationPermission',
      () async {
        final engine = RevevEngine();
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              if (call.method == 'hasLocationPermission') return true;
              if (call.method == 'requestLocationPermission') return true;
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );

        final hasPermission = await engine.hasLocationPermission();
        expect(hasPermission, isTrue);
        expect(calls.any((c) => c.method == 'hasLocationPermission'), isTrue);

        final requested = await engine.requestLocationPermission();
        expect(requested, isTrue);
        expect(
          calls.any((c) => c.method == 'requestLocationPermission'),
          isTrue,
        );
      },
    );

    testWidgets(
      'selecting GPS Drive triggers location permission check and displays GPS telemetry',
      (tester) async {
        final calls = <MethodCall>[];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              if (call.method == 'hasLocationPermission') return false;
              if (call.method == 'requestLocationPermission') return true;
              if (call.method == 'stats') {
                return {
                  'playing': true,
                  'rpm': 2500.0,
                  'gear': 2,
                  'vehicleSpeed': 15.0, // ~34 MPH, 54 KM/H
                  'tireSquealLevel': 0.0,
                };
              }
              return null;
            });

        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );

        tester.view.physicalSize = const Size(430, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(const RevEvApp());
        await tester.pumpAndSettle();

        // Switch to GPS Drive mode
        await tester.tap(find.text('GPS DRIVE'));
        await tester.pumpAndSettle();

        // Verify requestLocationPermission was called
        expect(
          calls.any((c) => c.method == 'requestLocationPermission'),
          isTrue,
        );

        // Verify GPS drive container exists
        expect(
          find.textContaining(
            'Automatic transmission driven by phone GPS speed',
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  });
}
