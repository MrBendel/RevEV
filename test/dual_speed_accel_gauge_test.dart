import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev/dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DualSpeedAccelGauge Widget', () {
    testWidgets('renders dual speed (top) and acceleration (bottom) with correct semantics and values', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: DualSpeedAccelGauge(
                  speedMps: 20.0, // 20 m/s ≈ 44.7 mph (rounds to 45 MPH)
                  accelMps2: 2.3, // +2.3 m/s² forward acceleration
                  running: true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final gaugeFinder = find.byType(DualSpeedAccelGauge);
      expect(gaugeFinder, findsOneWidget);

      final widget = tester.widget<DualSpeedAccelGauge>(gaugeFinder);
      expect(widget.speedMph.round(), 45);
      expect(widget.accelMps2, 2.3);
      expect(widget.running, isTrue);

      final semantics = tester.getSemantics(gaugeFinder);
      expect(semantics.label, contains('Speed: 45 MPH'));
      expect(semantics.label, contains('Acceleration: 2.3 m/s²'));
    });

    testWidgets('handles deceleration / braking (negative acceleration) and clamps bounds', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: DualSpeedAccelGauge(
                  speedMps: 0.0,
                  accelMps2: -4.2, // Deceleration / braking
                  running: true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final gaugeFinder = find.byType(DualSpeedAccelGauge);
      final semantics = tester.getSemantics(gaugeFinder);
      expect(semantics.label, contains('Speed: 0 MPH'));
      expect(semantics.label, contains('Acceleration: -4.2 m/s²'));
    });
  });

  group('InstrumentCluster Right Dial Replacement', () {
    testWidgets('InstrumentCluster uses DualSpeedAccelGauge on right dial', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 350,
                child: InstrumentCluster(
                  rpm: 3200,
                  throttle: 0.45,
                  volume: 0.20,
                  running: true,
                  speedMps: 15.0, // ~34 MPH
                  accelMps2: 1.8,
                  gear: 2,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dual-speed-accel-gauge')), findsOneWidget);

      final dualGauge = tester.widget<DualSpeedAccelGauge>(find.byKey(const Key('dual-speed-accel-gauge')));
      expect(dualGauge.speedMph.round(), 34);
      expect(dualGauge.accelMps2, 1.8);
      expect(dualGauge.running, isTrue);
    });
  });

  group('In-Car Screen Styling (Android Auto)', () {
    test('CarInstrumentClusterRenderer exists and paints analog cluster artwork', () {
      final rendererFile = File('android/app/src/main/kotlin/dev/revev/revev/auto/CarInstrumentClusterRenderer.kt');
      expect(rendererFile.existsSync(), isTrue);
      final content = rendererFile.readAsStringSync().replaceAll('\r\n', '\n');

      expect(content, contains('object CarInstrumentClusterRenderer'));
      expect(content, contains('render(state: EngineBridge.State'));
      expect(content, contains('drawMainTachometer'));
      expect(content, contains('drawAuxGauge'));
      expect(content, contains('drawDualSpeedAccelGauge'));
      expect(content, contains('NEEDLE_RED'));
      expect(content, contains('DIAL_IVORY'));
    });

    test('RevEvDashboardScreen sets CarIcon cluster artwork and shows live dual telemetry', () {
      final screenFile = File('android/app/src/main/kotlin/dev/revev/revev/auto/RevEvDashboardScreen.kt');
      expect(screenFile.existsSync(), isTrue);
      final content = screenFile.readAsStringSync().replaceAll('\r\n', '\n');

      expect(content, contains('CarInstrumentClusterRenderer.render'));
      expect(content, contains('paneBuilder.setImage'));
      expect(content, contains('CarIcon.Builder'));
      expect(content, contains('engineState.speedMph'));
      expect(content, contains('engineState.accelMps2'));
      expect(content, contains('Live Telemetry'));
    });
  });
}
