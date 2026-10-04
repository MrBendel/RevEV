import 'dart:convert';
import 'dart:math' as math;

import 'package:revev_engine/revev_engine.dart';

enum DriveScenario {
  urban('City launch · 0–30 mph', 13.4112, 10),
  brisk('Brisk launch · 0–60 mph', 26.8224, 10),
  dropout('GPS gap · launch and braking', 13.4112, 10);

  const DriveScenario(this.label, this.topSpeed, this.rampSeconds);
  final String label;
  final double topSpeed, rampSeconds;
  double get duration => 3 + rampSeconds + 5 + 6 + 3;

  DriveInput at(double seconds) {
    final t = seconds.clamp(0.0, duration);
    final rampEnd = 3 + rampSeconds;
    final cruiseEnd = rampEnd + 5;
    final brakeEnd = cruiseEnd + 6;
    final (speed, accel, phase) = t < 3
        ? (0.0, 0.0, 'Idle / GPS acquisition')
        : t < rampEnd
        ? (
            (t - 3) * topSpeed / rampSeconds,
            topSpeed / rampSeconds,
            'Accelerating',
          )
        : t < cruiseEnd
        ? (topSpeed, 0.0, 'Cruising')
        : t < brakeEnd
        ? (topSpeed * (1 - (t - cruiseEnd) / 6), -topSpeed / 6, 'Braking')
        : (0.0, 0.0, 'Stopped');
    return DriveInput(
      seconds: t,
      speed: speed,
      accel: accel,
      phase: phase,
      // Six-second loss exercises both short extrapolation and the stale limit.
      gpsAvailable: this != dropout || t < 7 || t >= 13,
    );
  }
}

class DriveInput {
  const DriveInput({
    required this.seconds,
    required this.speed,
    required this.accel,
    required this.phase,
    required this.gpsAvailable,
  });
  final double seconds, speed, accel;
  final String phase;
  final bool gpsAvailable;

  Map<String, Object?> packet({required bool gpsTick, required bool reset}) => {
    'timeSeconds': seconds,
    'accelMps2': accel,
    if (gpsTick && gpsAvailable) 'gpsSpeedMps': speed,
    'reset': reset,
  };
}

/// Bounded, local-only trace. No location coordinates are collected.
class DriveRecording {
  DriveRecording({
    required this.kind,
    required this.preset,
    required this.mount,
    required this.aggressiveness,
    required this.volume,
  });
  static const maxSamples = 1200;
  final String kind, preset, mount;
  final double aggressiveness, volume;
  final startedAt = DateTime.now().toUtc();
  final List<Map<String, Object?>> samples = [];
  String status = 'Recording';
  double peakRpm = 0, peakSpeed = 0, maxSpeedError = 0;
  String? get observation {
    if (samples.isEmpty) return null;
    if (peakSpeed < 2) return 'No significant speed observed yet.';
    if (peakRpm < 1200) {
      return 'Speed changed, but RPM stayed near idle. Inspect the trace.';
    }
    return 'Speed and RPM responded. Review shifts and sound; this is not an automatic pass.';
  }

  void add(double seconds, EngineStats stats, {DriveInput? input}) {
    if (samples.length >= maxSamples) return;
    peakRpm = math.max(peakRpm, stats.rpm);
    peakSpeed = math.max(peakSpeed, stats.vehicleSpeed);
    if (input != null) {
      maxSpeedError = math.max(
        maxSpeedError,
        (stats.vehicleSpeed - input.speed).abs(),
      );
    }
    samples.add({
      'seconds': seconds,
      'rpm': stats.rpm,
      'gear': stats.gear,
      'speedMps': stats.vehicleSpeed,
      'accelMps2': stats.accelMps2,
      'boostBar': stats.boost,
      'workMs': stats.workMs,
      'underruns': stats.underruns,
      'motion': stats.motion,
      if (input != null)
        'input': {
          'seconds': input.seconds,
          'speedMps': input.speed,
          'accelMps2': input.accel,
          'gpsAvailable': input.gpsAvailable,
          'phase': input.phase,
        },
    });
  }

  String json() => const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': 1,
    'kind': kind,
    'status': status,
    'startedAt': startedAt.toIso8601String(),
    'preset': preset,
    'mount': mount,
    'shiftAggressiveness': aggressiveness,
    'volume': volume,
    'peakRpm': peakRpm,
    'peakSpeedMps': peakSpeed,
    'maxSpeedErrorMps': maxSpeedError,
    'samples': samples,
    'note':
        'Foreground sampled trace; synthetic replay starts after sensor-axis mapping. '
        'No GPS coordinates. Not a certified acceleration timer.',
  });
}
