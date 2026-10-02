import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revev_engine/revev_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('revev_engine');

  group('Android Auto Configuration', () {
    test('automotive_app_desc.xml exists and declares template usage', () {
      final descFile = File('android/app/src/main/res/xml/automotive_app_desc.xml');
      expect(descFile.existsSync(), isTrue);
      final content = descFile.readAsStringSync();
      expect(content, contains('<automotiveApp>'));
      expect(content, contains('<uses name="template"'));
    });

    test('AndroidManifest.xml declares Android Auto metadata and service', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);
      final content = manifestFile.readAsStringSync();
      expect(content, contains('com.google.android.gms.car.application'));
      expect(content, contains('@xml/automotive_app_desc'));
      expect(content, contains('androidx.car.app.minCarApiLevel'));
      expect(content, contains('.auto.RevEvCarAppService'));
      expect(content, contains('androidx.car.app.CarAppService'));
    });
  });

  group('Android Auto Remote Command Handler', () {
    test('dispatches remote start, stop, preset, drive mode, and aggressiveness events', () async {
      final engine = RevevEngine();
      String? remoteStartedPreset;
      var remoteStopped = false;
      String? remotePresetSet;
      DriveMode? remoteDriveMode;
      double? remoteAggressiveness;

      engine.setRemoteCommandHandler(
        onRemoteStart: (preset) => remoteStartedPreset = preset,
        onRemoteStop: () => remoteStopped = true,
        onRemoteSetPreset: (preset) => remotePresetSet = preset,
        onRemoteSetDriveMode: (mode) => remoteDriveMode = mode,
        onRemoteSetAggressiveness: (aggr) => remoteAggressiveness = aggr,
      );

      final binaryMessenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      await binaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('onRemoteStart', {'preset': 'porsche/911_turbo_33'})),
        (ByteData? data) {},
      );
      expect(remoteStartedPreset, 'porsche/911_turbo_33');

      await binaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('onRemoteSetPreset', {'preset': 'atg-video-2/08_ferrari_f136_v8'})),
        (ByteData? data) {},
      );
      expect(remotePresetSet, 'atg-video-2/08_ferrari_f136_v8');

      await binaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('onRemoteSetDriveMode', {'driveMode': 1})),
        (ByteData? data) {},
      );
      expect(remoteDriveMode, DriveMode.gpsDrive);

      await binaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('onRemoteSetAggressiveness', {'aggressiveness': 0.85})),
        (ByteData? data) {},
      );
      expect(remoteAggressiveness, 0.85);

      await binaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('onRemoteStop')),
        (ByteData? data) {},
      );
      expect(remoteStopped, isTrue);
    });
  });
}
