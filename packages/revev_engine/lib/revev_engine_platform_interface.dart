import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'revev_engine_method_channel.dart';

abstract class RevevEnginePlatform extends PlatformInterface {
  /// Constructs a RevevEnginePlatform.
  RevevEnginePlatform() : super(token: _token);

  static final Object _token = Object();

  static RevevEnginePlatform _instance = MethodChannelRevevEngine();

  /// The default instance of [RevevEnginePlatform] to use.
  ///
  /// Defaults to [MethodChannelRevevEngine].
  static RevevEnginePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [RevevEnginePlatform] when
  /// they register themselves.
  static set instance(RevevEnginePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
