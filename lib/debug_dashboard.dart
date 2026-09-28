import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:revev_engine/revev_engine.dart';

/// Aggregates polled snapshots, not every native audio block.
class DebugSession {
  DateTime? startedAt;
  Duration elapsed = Duration.zero;
  String status = 'No session';
  String? error;
  String testResult = 'Manual session';
  final List<Map<String, Object>> testPhases = [];
  EngineStats latest = const EngineStats();
  int samples = 0;
  double _sum = 0, peakMs = 0;
  final List<double> recentMs = [];

  double get averageMs => samples == 0 ? 0 : _sum / samples;
  double get p95Ms {
    if (recentMs.isEmpty) return 0;
    final sorted = [...recentMs]..sort();
    return sorted[(sorted.length * .95).ceil() - 1];
  }

  void begin() {
    startedAt = DateTime.now().toUtc();
    elapsed = Duration.zero;
    status = 'Starting';
    error = null;
    testResult = 'Manual session';
    testPhases.clear();
    latest = const EngineStats();
    samples = 0;
    _sum = peakMs = 0;
    recentMs.clear();
  }

  void record(EngineStats stats, Duration duration) {
    latest = stats;
    elapsed = duration;
    status = stats.failed
        ? 'Failed'
        : stats.playing
        ? 'Running'
        : 'Stopped';
    if (!stats.workMs.isFinite || stats.workMs <= 0) return;
    samples++;
    _sum += stats.workMs;
    peakMs = math.max(peakMs, stats.workMs);
    recentMs.add(stats.workMs);
    if (recentMs.length > 400) recentMs.removeAt(0);
  }

  String report() => const JsonEncoder.withIndent('  ').convert({
    'app': 'RevEV',
    'platform': defaultTargetPlatform.name,
    'buildMode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'startedAtUtc': startedAt?.toIso8601String(),
    'status': status,
    'error': error,
    'testResult': testResult,
    'testPhases': testPhases,
    'durationSeconds': elapsed.inMilliseconds / 1000,
    'samples': samples,
    'lastRpm': latest.rpm,
    'lastWorkMs': latest.workMs,
    'sampledAverageMs': averageMs,
    'sampledPeakMs': peakMs,
    'recentSampledP95Ms': p95Ms,
    'recentSampleCount': recentMs.length,
    'underrunsAtLastPoll': latest.underruns,
    'notes':
        'Snapshots polled every 150 ms, not every audio block. '
        'P95 uses the latest 400 samples. Underruns include startup and '
        'may miss events after the last poll. Audio blocks represent 10 ms. '
        'CPU usage and output latency are not measured.',
  });
}

class DebugDashboard extends StatelessWidget {
  const DebugDashboard({
    super.key,
    required this.session,
    this.onRunTest,
    this.onCancelTest,
    this.testPhase,
  });
  final DebugSession session;
  final VoidCallback? onRunTest, onCancelTest;
  final String? testPhase;

  @override
  Widget build(BuildContext context) {
    final hasSamples = session.samples > 0;
    String ms(double value) =>
        hasSamples ? '${value.toStringAsFixed(2)} ms' : '—';
    return ExpansionTile(
      key: const Key('debug-dashboard'),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.monitor_heart_outlined),
      title: const Text('Debug dashboard'),
      subtitle: Text(
        '${session.status} · ${session.elapsed.inSeconds}s · '
        '${session.samples} samples',
      ),
      children: [
        const Text(
          'Repeatable test: 5s idle → 5s at 35% throttle → 5s idle, '
          'then automatic stop. Uses your current output volume.',
        ),
        const SizedBox(height: 8),
        Text(testPhase ?? session.testResult),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('run-test'),
              onPressed: onRunTest,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run 15-second test'),
            ),
            if (onCancelTest != null)
              TextButton(
                key: const Key('cancel-test'),
                onPressed: onCancelTest,
                child: const Text('Cancel test'),
              ),
          ],
        ),
        const Text(
          'Stop the engine before starting a new test. '
          'Stop or leaving the app cancels the sequence.',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 330
                ? constraints.maxWidth
                : (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final metric in <(String, String)>[
                  (
                    'RPM at last poll',
                    hasSamples ? session.latest.rpm.round().toString() : '—',
                  ),
                  (
                    'Underruns at last poll',
                    hasSamples ? '${session.latest.underruns}' : '—',
                  ),
                  ('Latest block', ms(session.latest.workMs)),
                  ('Session average', ms(session.averageMs)),
                  ('Session peak', ms(session.peakMs)),
                  ('Recent P95', ms(session.p95Ms)),
                ])
                  SizedBox(
                    width: width,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metric.$1,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              metric.$2,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Recent block processing time · dashed line = 10 ms'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 90,
          width: double.infinity,
          child: CustomPaint(painter: _TimingPainter([...session.recentMs])),
        ),
        const SizedBox(height: 12),
        const Text(
          'Timing is sampled every 150 ms, not every audio block. '
          'P95 and chart use up to 400 recent samples (~60 seconds). '
          'Underruns include startup. CPU usage and speaker latency are not measured.',
        ),
        if (session.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              session.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: session.startedAt == null
              ? null
              : () async {
                  try {
                    await Clipboard.setData(
                      ClipboardData(text: session.report()),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Debug report copied')),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not copy debug report'),
                        ),
                      );
                    }
                  }
                },
          icon: const Icon(Icons.copy),
          label: const Text('Copy debug report'),
        ),
        const Text(
          'Results stay here after Stop. Starting the engine resets the session.',
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _TimingPainter extends CustomPainter {
  _TimingPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final maximum = values.fold<double>(12, math.max) * 1.1;
    double y(double value) => size.height * (1 - value / maximum);
    final line = Paint()
      ..color = const Color(0xff827969)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(
        Offset(x, y(10)),
        Offset(math.min(x + 5, size.width), y(10)),
        line,
      );
    }
    if (values.isEmpty) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / math.max(1, values.length - 1);
      if (i == 0) {
        path.moveTo(x, y(values[i]));
      } else {
        path.lineTo(x, y(values[i]));
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xffd3c6ac)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TimingPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values);
}
