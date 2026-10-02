import 'package:flutter/services.dart';

export 'engine_presets.dart';

enum ListeningMode {
  original('Original'),
  cabin('Cabin'),
  cabinRumble('Cabin + Rumble');

  const ListeningMode(this.label);
  final String label;
}

class EngineStats {
  const EngineStats({
    this.rpm = 0,
    this.workMs = 0,
    this.underruns = 0,
    this.playing = false,
    this.failed = false,
    this.stopping = false,
    this.boost = 0.0,
  });
  final double rpm, workMs, boost;
  final int underruns;
  final bool playing, failed, stopping;
}

class RevevEngine {
  static const _channel = MethodChannel('revev_engine');
  Future<void> start({String preset = 'porsche/911_carrera_32'}) =>
      _channel.invokeMethod<void>('start', {'preset': preset});
  Future<void> shutdown() => _channel.invokeMethod<void>('shutdown');
  Future<void> stop() => _channel.invokeMethod<void>('stop');
  Future<void> listeningMix(ListeningMode mode, double strength) =>
      _channel.invokeMethod<void>('listeningMix', {
        'mode': mode.index,
        'strength': strength,
      });
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
      stopping: data['stopping'] == true,
      boost: (data['boost'] as num? ?? 0).toDouble(),
    );
  }
}
