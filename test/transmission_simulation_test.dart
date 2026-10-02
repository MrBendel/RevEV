import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev/main.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('revev_engine');

  group('Engine preset gear configurations', () {
    test('all presets define typical gear counts and ratios', () {
      final turbo = enginePresets.firstWhere((p) => p.id == 'porsche/911_turbo_33');
      expect(turbo.gearCount, 4);
      expect(turbo.gearRatios.length, 4);

      final carrera = enginePresets.firstWhere((p) => p.id == 'porsche/911_carrera_32');
      expect(carrera.gearCount, 5);
      expect(carrera.gearRatios.length, 5);

      final vtec = enginePresets.firstWhere((p) => p.id == 'atg-video-1/05_honda_vtec');
      expect(vtec.gearCount, 5);

      final ferrari = enginePresets.firstWhere((p) => p.id == 'atg-video-2/08_ferrari_f136_v8');
      expect(ferrari.gearCount, 7);
      expect(ferrari.gearRatios.length, 7);

      final ls = enginePresets.firstWhere((p) => p.id == 'atg-video-2/07_gm_ls');
      expect(ls.gearCount, 6);

      final supra = enginePresets.firstWhere((p) => p.id == 'atg-video-2/03_2jz');
      expect(supra.gearCount, 6);

      final lfa = enginePresets.firstWhere((p) => p.id == 'atg-video-2/10_lfa_v10');
      expect(lfa.gearCount, 6);
    });

    test('EngineStats decodes gear and vehicleSpeed with unit conversion helpers', () {
      const stats = EngineStats(
        rpm: 3200,
        gear: 3,
        vehicleSpeed: 20.0, // 20 m/s = 72 km/h ≈ 44.7 mph
      );
      expect(stats.gear, 3);
      expect(stats.gearDisplay, 'D3');
      expect(stats.speedKmh.round(), 72);
      expect(stats.speedMph.round(), 45);

      const neutralStats = EngineStats(gear: 0);
      expect(neutralStats.gearDisplay, 'N');
    });
  });

  group('Drive Mode and Telemetry Widgets', () {
    testWidgets('UI switches drive mode and adjusts aggressiveness', (tester) async {
      final calls = <MethodCall>[];
      var playing = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'start') playing = true;
            if (call.method == 'stop' || call.method == 'shutdown') playing = false;
            if (call.method == 'stats') {
              return {
                'playing': playing,
                'rpm': 2500.0,
                'gear': 2,
                'vehicleSpeed': 15.0,
              };
            }
            return null;
          });

      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const RevEvApp());
      expect(find.byKey(const Key('drive-mode')), findsOneWidget);

      // Default is manual revving mode
      expect(find.byKey(const Key('throttle')), findsOneWidget);
      expect(find.byKey(const Key('sim-speed')), findsNothing);

      // Switch to Speed Sim mode
      await tester.tap(find.text('SPEED SIM'));
      await tester.pump();

      expect(find.byKey(const Key('sim-speed')), findsOneWidget);
      expect(find.byKey(const Key('shift-aggressiveness')), findsOneWidget);

      // Adjust aggressiveness slider
      tester.widget<Slider>(find.byKey(const Key('shift-aggressiveness'))).onChanged!(0.9);
      await tester.pump();

      final aggrCall = calls.lastWhere((c) => c.method == 'driveTelemetry');
      expect(aggrCall.arguments['aggressiveness'], 0.9);
      expect(aggrCall.arguments['driveMode'], DriveMode.simDrive.index);

      // Switch to GPS Drive mode
      await tester.tap(find.text('GPS DRIVE'));
      await tester.pump();

      expect(find.text('Automatic transmission driven by phone GPS speed & accelerometer g-force.'), findsOneWidget);
      expect(calls.lastWhere((c) => c.method == 'driveTelemetry').arguments['driveMode'], DriveMode.gpsDrive.index);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
