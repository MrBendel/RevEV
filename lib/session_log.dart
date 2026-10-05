import 'dart:convert';
import 'dart:io';

/// Append-only JSON Lines: complete lines remain readable after interruption.
/// All I/O is serialized; memory usage stays bounded even on long drives.
class SessionLog {
  SessionLog(this.directory);
  final Directory directory;
  Future<void> _pending = Future.value();
  RandomAccessFile? _file;
  final Stopwatch _clock = Stopwatch();
  String? error;
  String? activePath;
  int _samples = 0;

  Future<void> _enqueue(Future<void> Function() action) {
    _pending = _pending.then((_) async {
      try {
        await action();
      } catch (e) {
        error = 'Session logging failed: $e';
        final failed = _file;
        _file = null;
        activePath = null;
        try {
          await failed?.close();
        } catch (_) {}
      }
    });
    return _pending;
  }

  Future<void> start(Map<String, Object?> metadata) => _enqueue(() async {
    await _close('Restarted');
    error = null;
    await directory.create(recursive: true);
    final now = DateTime.now().toUtc();
    final file = File(
      '${directory.path}/session-${now.toIso8601String().replaceAll(':', '-')}.jsonl',
    );
    _file = await file.open(mode: FileMode.writeOnly);
    activePath = file.path;
    _samples = 0;
    _clock
      ..reset()
      ..start();
    await _line({
      'type': 'start',
      'schemaVersion': 1,
      'startedAt': now.toIso8601String(),
      'sampleIntervalMs': 150,
      ...metadata,
    });
    await _file!.flush();
  });

  Future<void> sample(Map<String, Object?> values) {
    final seconds = _clock.elapsedMicroseconds / 1000000;
    return _enqueue(() async {
      if (_file == null) return;
      await _line({'type': 'sample', 'seconds': seconds, ...values});
      // Flush roughly once a second, and always at stop.
      if (++_samples % 7 == 0) await _file!.flush();
    });
  }

  Future<void> stop(String reason) => _enqueue(() => _close(reason));

  Future<void> _close(String reason) async {
    if (_file == null) return;
    await _line({
      'type': 'stop',
      'reason': reason,
      'samples': _samples,
      'seconds': _clock.elapsedMicroseconds / 1000000,
      'endedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _file!.flush();
    await _file!.close();
    _file = null;
    activePath = null;
    _clock.stop();
  }

  Future<void> _line(Map<String, Object?> value) async {
    await _file!.writeString('${jsonEncode(value)}\n');
  }

  Future<List<File>> files() async {
    await _pending;
    if (!await directory.exists()) return [];
    final result = await directory
        .list()
        .where(
          (e) =>
              e is File &&
              e.path.endsWith('.jsonl') &&
              e.absolute.uri !=
                  (activePath == null ? null : File(activePath!).absolute.uri),
        )
        .cast<File>()
        .toList();
    result.sort((a, b) => b.path.compareTo(a.path));
    return result;
  }
}
