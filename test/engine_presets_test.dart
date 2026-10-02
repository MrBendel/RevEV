import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev/main.dart';
import 'package:revev/dashboard.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('revev_engine');
  testWidgets(
    'preset choice reaches native and shutdown retains coasting controls',
    (tester) async {
      final calls = <MethodCall>[];
      var playing = false;
      var stopping = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'start') playing = true;
            if (call.method == 'shutdown') stopping = true;
            if (call.method == 'stop') playing = false;
            if (call.method == 'stats') {
              return {'playing': playing, 'stopping': stopping, 'rpm': 2400.0};
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
      DropdownButtonFormField<String> selector() =>
          tester.widget(find.byKey(const Key('engine-preset')));
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .items!
            .length,
        9,
      );
      selector().onChanged!('porsche/911_turbo_33');
      await tester.pump();
      expect(
        tester.widget<InstrumentCluster>(find.byType(InstrumentCluster)).maxRpm,
        8000,
      );
      selector().onChanged!('porsche/911_carrera_32');
      await tester.pump();
      expect(
        tester.widget<InstrumentCluster>(find.byType(InstrumentCluster)).maxRpm,
        8000,
      );
      await tester.tap(find.byKey(const Key('start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(calls.singleWhere((c) => c.method == 'start').arguments, {
        'preset': 'porsche/911_carrera_32',
      });
      expect(selector().onChanged, isNull);
      final mixSelector = tester.widget<DropdownButtonFormField<ListeningMode>>(
        find.byKey(const Key('listening-mode')),
      );
      mixSelector.onChanged!(ListeningMode.cabinRumble);
      await tester.pump();
      expect(calls.lastWhere((c) => c.method == 'listeningMix').arguments, {
        'mode': 2,
        'strength': 0.5,
      });
      tester
          .widget<Slider>(find.byKey(const Key('rumble-strength')))
          .onChanged!(0.8);
      await tester.pump();
      expect(calls.lastWhere((c) => c.method == 'listeningMix').arguments, {
        'mode': 2,
        'strength': 0.8,
      });
      await tester.tap(find.byKey(const Key('start')));
      await tester.pump();
      expect(calls.where((c) => c.method == 'shutdown'), hasLength(1));
      expect(calls.where((c) => c.method == 'stop'), isEmpty);
      expect(find.text('STOPPING'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<ListeningMode>>(
              find.byKey(const Key('listening-mode')),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester.widget<InstrumentCluster>(find.byType(InstrumentCluster)).rpm,
        2400,
      );
      expect(
        tester.widget<Slider>(find.byKey(const Key('throttle'))).onChanged,
        isNull,
      );
      expect(selector().onChanged, isNull);
      playing = false;
      stopping = false;
      await tester.pump(const Duration(milliseconds: 150));
      expect(selector().onChanged, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  test('stats decode coasting state and preserve compatibility', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {'playing': true, 'stopping': true, 'rpm': 325},
        );
    final stats = await RevevEngine().stats();
    expect(stats.stopping, isTrue);
    expect(stats.rpm, 325);
    expect(stats.failed, isFalse);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
