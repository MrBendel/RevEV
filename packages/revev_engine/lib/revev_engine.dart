import 'package:flutter/services.dart';

class EngineStats {
  const EngineStats({
    this.rpm = 0,
    this.workMs = 0,
    this.underruns = 0,
    this.playing = false,
    this.failed = false,
  });
  final double rpm, workMs;
  final int underruns;
  final bool playing, failed;
}

class RevevEngine {
  static const _channel = MethodChannel('revev_engine');
  Future<void> start() => _channel.invokeMethod<void>('start');
  Future<void> stop() => _channel.invokeMethod<void>('stop');
  Future<void> controls(double throttle, double volume) => _channel
      .invokeMethod<void>('controls', {'throttle': throttle, 'volume': volume});
  Future<EngineStats> stats() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('stats') ?? {};
    return EngineStats(
      rpm: (data['rpm'] as num? ?? 0).toDouble(),
      workMs: (data['workMs'] as num? ?? 0).toDouble(),
      underruns: (data['underruns'] as num? ?? 0).toInt(),
      playing: data['playing'] == true,
      failed: data['failed'] == true,
    );
  }
}
