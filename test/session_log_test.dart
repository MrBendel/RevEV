import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:revev/session_log.dart';

void main() {
  test(
    'sessions persist ordered samples and stop records independently',
    () async {
      final directory = await Directory.systemTemp.createTemp('revev-log-test');
      addTearDown(() => directory.delete(recursive: true));
      final log = SessionLog(directory);
      await log.start({'preset': 'test'});
      final first = log.activePath!;
      for (var i = 0; i < 20; i++) {
        // Deliberately enqueue without waiting to exercise stop/write ordering.
        log.sample({
          'rpm': i,
          'motion': {'gpsSpeedMps': 5.0},
        });
      }
      await log.stop('Stopped');
      final rows = (await File(first).readAsLines()).map(jsonDecode).toList();
      expect(rows.first['type'], 'start');
      expect(rows.length, 22);
      expect(rows[20]['rpm'], 19);
      expect(rows.last['samples'], 20);
      await log.start({'preset': 'second'});
      expect(log.activePath, isNot(first));
      expect((await log.files()).length, 1);
      await log.stop('Backgrounded');
      expect((await SessionLog(directory).files()).length, 2);
      expect(log.error, isNull);
    },
  );

  test(
    'flushed samples can be read before stop and failures do not escape',
    () async {
      final directory = await Directory.systemTemp.createTemp('revev-log-test');
      addTearDown(() => directory.delete(recursive: true));
      final log = SessionLog(directory);
      await log.start({});
      for (var i = 0; i < 7; i++) {
        await log.sample({'rpm': 1500});
      }
      expect((await File(log.activePath!).readAsLines()).length, 8);
      await log.stop('Stopped');
      final blocker = File('${directory.path}/not-a-directory');
      await blocker.writeAsString('block');
      final broken = SessionLog(Directory(blocker.path));
      await broken.start({});
      await broken.sample({'rpm': 42});
      await broken.stop('Stopped');
      expect(broken.error, contains('Session logging failed'));
    },
  );
}
