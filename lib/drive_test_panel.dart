import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:revev_engine/revev_engine.dart';

import 'drive_test.dart';

class DriveTestPanel extends StatelessWidget {
  const DriveTestPanel({
    super.key,
    required this.stats,
    required this.mode,
    required this.recording,
    required this.active,
    required this.phase,
    required this.onScenario,
    required this.onRecord,
    required this.onStop,
  });
  final EngineStats stats;
  final DriveMode mode;
  final DriveRecording? recording;
  final bool active;
  final String? phase;
  final void Function(DriveScenario)? onScenario;
  final VoidCallback? onRecord, onStop;

  String value(String key, [String unit = '']) {
    final v = stats.motion[key];
    return v is num ? '${v.toStringAsFixed(2)}$unit' : '—';
  }

  @override
  Widget build(BuildContext context) {
    final motion = stats.motion;
    final report = recording;
    return Card(
      key: const Key('drive-test-panel'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Driving test lab',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              mode == DriveMode.simDrive
                  ? 'Repeatable GPS + acceleration inputs drive the real engine and transmission. '
                        'Each run includes idle, launch, cruise, braking and a stop. Stop the engine to start a fresh run.'
                  : 'Start the engine, then record a live drive. Set up while parked; '
                        'review or copy the report after stopping. Keep the app in the foreground.',
            ),
            if (mode == DriveMode.simDrive) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final scenario in DriveScenario.values)
                    OutlinedButton(
                      key: Key('scenario-${scenario.name}'),
                      onPressed: onScenario == null
                          ? null
                          : () => onScenario!(scenario),
                      child: Text(scenario.label),
                    ),
                ],
              ),
              const Text(
                'Replays begin after sensor-axis mapping. Use GPS Drive to validate '
                'real sensor reception and the selected mount.',
              ),
            ],
            if (mode == DriveMode.gpsDrive)
              OutlinedButton(
                key: const Key('record-drive'),
                onPressed: onRecord,
                child: const Text('Record live drive · up to 3 min'),
              ),
            if (active)
              TextButton.icon(
                key: const Key('stop-drive-test'),
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: Text(
                  mode == DriveMode.simDrive
                      ? 'Cancel scenario'
                      : 'Finish recording',
                ),
              ),
            if (phase != null) Text(phase!, key: const Key('drive-test-phase')),
            const Divider(),
            Text(
              motion['supported'] == true
                  ? (motion['source'] as String? ??
                        'Waiting for motion diagnostics')
                  : 'Start an Android engine session to read motion diagnostics.',
            ),
            if (mode == DriveMode.gpsDrive) ...[
              Text(
                'Location: ${motion['locationPermission'] == true ? 'allowed' : 'not confirmed'} · '
                'GPS provider: ${motion['gpsEnabled'] == true ? 'on' : 'off / unknown'}',
              ),
              Text(
                'Accelerometer: ${motion['accelerometerAvailable'] == true ? 'available' : 'unavailable / unknown'} · '
                '${motion['sensorsActive'] == true ? 'listening' : 'not listening'}',
              ),
              Text(
                'Mount used: ${motion['mount'] ?? '—'} · Provider: ${motion['provider'] ?? '—'}',
              ),
              Text(
                'Device linear X / Y / Z: ${value('linearX')} / '
                '${value('linearY')} / ${value('linearZ')} m/s²',
              ),
              Text(
                'Gravity reference: ${motion['gravityReady'] == true ? 'ready' : 'waiting / unavailable'}',
              ),
              if (motion['locationError'] != null)
                Text('Location error: ${motion['locationError']}'),
            ],
            Text(
              'GPS age ${value('gpsAgeSeconds', ' s')} · Sensor age ${value('sensorAgeSeconds', ' s')}',
            ),
            Text(
              'GPS speed ${value('gpsSpeedMps', ' m/s')} · Accuracy ${value('gpsAccuracyM', ' m')}',
            ),
            Text(
              'Forward acceleration ${value('forwardAccelMps2', ' m/s²')} · '
              'GPS acceleration ${value('gpsAccelMps2', ' m/s²')}',
            ),
            Text(
              'Fused speed ${value('fusedSpeedMps', ' m/s')} · Rejected fixes ${motion['rejectedFixes'] ?? 0}',
            ),
            Text(
              'Engine: ${stats.rpm.round()} RPM · ${stats.gearDisplay} · ${stats.speedMph.toStringAsFixed(1)} mph',
            ),
            Text(
              'Requested RPM: ${value('targetRpm')} · Engine throttle: ${value('engineThrottle')}',
            ),
            if (report != null) ...[
              const Divider(),
              Text(
                '${report.kind} · ${report.status} · ${report.samples.length} samples',
              ),
              Text(
                'Peak ${report.peakRpm.round()} RPM · ${(report.peakSpeed * 2.23694).toStringAsFixed(1)} mph',
              ),
              if (report.kind != 'Live GPS drive')
                Text(
                  'Largest sampled speed error: ${report.maxSpeedError.toStringAsFixed(2)} m/s',
                ),
              if (report.samples.length > 1)
                SizedBox(
                  height: 90,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _TracePainter(List.of(report.samples)),
                  ),
                ),
              const Text('Blue: speed (0–70 mph) · Orange: RPM (0–10,000)'),
              if (report.observation != null) Text(report.observation!),
              TextButton.icon(
                key: const Key('copy-drive-report'),
                onPressed: report.samples.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: report.json()),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Drive report copied (no location coordinates)',
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.copy),
                label: const Text('Copy drive report'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  _TracePainter(this.samples);
  final List<Map<String, Object?>> samples;
  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final duration = (samples.last['seconds'] as double).clamp(
      0.1,
      double.infinity,
    );
    for (final (key, maxValue, color) in [
      ('speedMps', 31.2928, Colors.lightBlueAccent),
      ('rpm', 10000.0, Colors.orangeAccent),
    ]) {
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final x = (samples[i]['seconds'] as double) / duration * size.width;
        final y =
            size.height *
            (1 -
                ((samples[i][key] as num).toDouble() / maxValue).clamp(
                  0.0,
                  1.0,
                ));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TracePainter oldDelegate) => true;
}
