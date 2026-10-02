import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('master app icon exists and is valid', () {
    final master = File('assets/icon/app_icon.png');
    expect(master.existsSync(), isTrue);
    expect(master.lengthSync(), greaterThan(10000));
  });

  test(
    'Android launcher icons and adaptive resources exist across densities',
    () {
      const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      for (final density in densities) {
        final dir = 'android/app/src/main/res/mipmap-$density';
        expect(
          File('$dir/ic_launcher.png').existsSync(),
          isTrue,
          reason: 'Missing ic_launcher.png in $dir',
        );
        expect(
          File('$dir/ic_launcher_round.png').existsSync(),
          isTrue,
          reason: 'Missing ic_launcher_round.png in $dir',
        );
        expect(
          File('$dir/ic_launcher_foreground.png').existsSync(),
          isTrue,
          reason: 'Missing ic_launcher_foreground.png in $dir',
        );
      }

      final anyDpi = 'android/app/src/main/res/mipmap-anydpi-v26';
      expect(File('$anyDpi/ic_launcher.xml').existsSync(), isTrue);
      expect(File('$anyDpi/ic_launcher_round.xml').existsSync(), isTrue);
      expect(
        File('android/app/src/main/res/values/colors.xml').existsSync(),
        isTrue,
      );
    },
  );

  test('iOS AppIcon.appiconset files match Contents.json catalog', () {
    final contentsFile = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
    );
    expect(contentsFile.existsSync(), isTrue);
    final json =
        jsonDecode(contentsFile.readAsStringSync()) as Map<String, dynamic>;
    final images = json['images'] as List<dynamic>;
    for (final item in images) {
      final filename = item['filename'] as String?;
      if (filename != null) {
        final iconFile = File(
          'ios/Runner/Assets.xcassets/AppIcon.appiconset/$filename',
        );
        expect(
          iconFile.existsSync(),
          isTrue,
          reason: 'Missing iOS icon: $filename',
        );
        expect(iconFile.lengthSync(), greaterThan(0));
      }
    }
  });
}
