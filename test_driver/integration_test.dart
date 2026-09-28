import 'dart:io';
import 'dart:convert';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) return;
      final dir = Directory('build/screenshots');
      await dir.create(recursive: true);
      for (final name in ['dashboard-off', 'dashboard-running']) {
        final encoded = data.remove(name) as String?;
        if (encoded != null) {
          await File('${dir.path}/$name.png')
              .writeAsBytes(base64Decode(encoded));
        }
      }
      await writeResponseData(data);
    },
  );
}
