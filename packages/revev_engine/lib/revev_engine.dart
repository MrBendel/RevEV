import 'package:flutter/services.dart';

export 'engine_presets.dart';

enum ListeningMode {
  original('Original'),
  cabin('Cabin'),
  cabinRumble('Cabin + Rumble');

  const ListeningMode(this.label);
  final String label;
}

enum DriveMode {
  manual('Manual Rev'),
  gpsDrive('GPS Drive'),
  simDrive('Speed Sim');

  const DriveMode(this.label);
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
    this.gear = 0,
    this.vehicleSpeed = 0.0,
    this.tireSquealLevel = 0.0,
    this.accelMps2 = 0.0,
  });
  final double rpm, workMs, boost, vehicleSpeed, tireSquealLevel, accelMps2;
  final int underruns, gear;
  final bool playing, failed, stopping;

  double get speedKmh => vehicleSpeed * 3.6;
  double get speedMph => vehicleSpeed * 2.23694;
  double get accelG => accelMps2 / 9.80665;
  String get gearDisplay => gear <= 0 ? 'N' : 'D$gear';
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
  Future<void> driveTelemetry({
    double speedMps = 0.0,
    double accelMps2 = 0.0,
    double aggressiveness = 0.5,
    DriveMode driveMode = DriveMode.manual,
    String mountingPosition = 'auto',
    double lateralAccelMps2 = 0.0,
    double tireSquealSensitivity = 0.5,
  }) => _channel.invokeMethod<void>('driveTelemetry', {
        'speedMps': speedMps,
        'accelMps2': accelMps2,
        'aggressiveness': aggressiveness,
        'driveMode': driveMode.index,
        'mountingPosition': mountingPosition,
        'lateralAccelMps2': lateralAccelMps2,
        'tireSquealSensitivity': tireSquealSensitivity,
      });

  Future<bool> hasLocationPermission() async {
    final granted = await _channel.invokeMethod<bool>('hasLocationPermission');
    return granted ?? false;
  }

  Future<bool> requestLocationPermission() async {
    final granted = await _channel.invokeMethod<bool>('requestLocationPermission');
    return granted ?? false;
  }

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
      gear: (data['gear'] as num? ?? 0).toInt(),
      vehicleSpeed: (data['vehicleSpeed'] as num? ?? 0).toDouble(),
      tireSquealLevel: (data['tireSquealLevel'] as num? ?? 0).toDouble(),
      accelMps2: (data['accelMps2'] as num? ?? 0).toDouble(),
    );
  }

  void setRemoteCommandHandler({
    void Function(String preset)? onRemoteStart,
    void Function()? onRemoteStop,
    void Function(String preset)? onRemoteSetPreset,
    void Function(DriveMode mode)? onRemoteSetDriveMode,
    void Function(double aggressiveness)? onRemoteSetAggressiveness,
    void Function(bool granted)? onLocationPermissionResult,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onRemoteStart':
          final preset = call.arguments?['preset'] as String? ?? 'porsche/911_carrera_32';
          onRemoteStart?.call(preset);
          break;
        case 'onRemoteStop':
          onRemoteStop?.call();
          break;
        case 'onRemoteSetPreset':
          final preset = call.arguments?['preset'] as String?;
          if (preset != null) onRemoteSetPreset?.call(preset);
          break;
        case 'onRemoteSetDriveMode':
          final modeIndex = call.arguments?['driveMode'] as int?;
          if (modeIndex != null && modeIndex >= 0 && modeIndex < DriveMode.values.length) {
            onRemoteSetDriveMode?.call(DriveMode.values[modeIndex]);
          }
          break;
        case 'onRemoteSetAggressiveness':
          final aggr = (call.arguments?['aggressiveness'] as num?)?.toDouble();
          if (aggr != null) onRemoteSetAggressiveness?.call(aggr);
          break;
        case 'onLocationPermissionResult':
          final granted = call.arguments?['granted'] as bool? ?? false;
          onLocationPermissionResult?.call(granted);
          break;
      }
    });
  }
}
