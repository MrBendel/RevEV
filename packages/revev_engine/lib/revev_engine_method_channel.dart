import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'revev_engine_platform_interface.dart';

/// An implementation of [RevevEnginePlatform] that uses method channels.
class MethodChannelRevevEngine extends RevevEnginePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('revev_engine');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
