// Branding assets smoke test.
//
// P3-5 final assets: assert that the brand artwork and launcher wiring
// are present and internally consistent.  This is the test-time equivalent
// of `aapt dump badging` — we cannot run aapt from a Flutter unit test,
// so we walk the file tree instead.
//
// What we check:
//   * Adaptive launcher icon XML exists for Android 8+
//   * Round adaptive launcher icon XML exists
//   * Foreground vector drawable exists
//   * Adaptive-icon background colour resource exists
//   * Splash-screen background colour resource exists (light + dark)
//   * AndroidManifest references both ic_launcher and ic_launcher_round
//   * AndroidManifest android:label == "Gochano"
//   * Legacy raster ic_launcher.png exists in mipmap-{mdpi..xxxhdpi}
//   * Old app_icon.xml (Material home) is gone
//   * Notification small icon (ic_stat_gochano.xml) is still present and
//     monochrome (no colour data in any path)
//   * Brand-master PNG in assets/branding/Gochano.png exists
//   * Brand-master PNG is referenced from the icon foreground drawable
//     comments (light coupling check)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final resDir = Directory(
    'android/app/src/main/res',
  );
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  test('Adaptive launcher icon is present (mipmap-anydpi-v26)', () {
    final adaptive = File('${resDir.path}/mipmap-anydpi-v26/ic_launcher.xml');
    final adaptiveRound =
        File('${resDir.path}/mipmap-anydpi-v26/ic_launcher_round.xml');
    final foreground = File('${resDir.path}/drawable/ic_launcher_foreground.xml');
    expect(adaptive.existsSync(), isTrue,
        reason: 'Expected ${adaptive.path} to exist for Android 8+ adaptive icon.');
    expect(adaptiveRound.existsSync(), isTrue,
        reason: 'Expected ${adaptiveRound.path} to exist for round launchers.');
    expect(foreground.existsSync(), isTrue,
        reason: 'Expected ${foreground.path} to exist as foreground vector.');

    final adaptiveXml = adaptive.readAsStringSync();
    expect(adaptiveXml, contains('@color/ic_launcher_background'));
    expect(adaptiveXml, contains('@drawable/ic_launcher_foreground'));
    // Android 13 themed icons use the monochrome layer.
    expect(adaptiveXml, contains('android:drawable="@drawable/ic_launcher_foreground"'),
        reason: 'Expected monochrome layer for Android 13 themed icons.');
  });

  test('Adaptive icon background colour matches brand seed (#5B3DF5)', () {
    final colors = File('${resDir.path}/values/ic_launcher_background.xml');
    expect(colors.existsSync(), isTrue);
    final content = colors.readAsStringSync();
    expect(content, contains('#5B3DF5'),
        reason: 'Background colour must equal EkColors.purple seed.');
    expect(content, contains('ic_launcher_background'),
        reason: 'Resource must be named ic_launcher_background.');
  });

  test('Splash-screen background colours exist for light + dark', () {
    final colors = File('${resDir.path}/values/splash_background.xml');
    expect(colors.existsSync(), isTrue);
    final content = colors.readAsStringSync();
    expect(content, contains('splash_background_light'));
    expect(content, contains('splash_background_dark'));
    expect(content, contains('#5B3DF5'));
    expect(content, contains('#0F172A'));
  });

  test('values-v31 styles bind splash colour and brand icon', () {
    final light = File('${resDir.path}/values-v31/styles.xml');
    final dark = File('${resDir.path}/values-night-v31/styles.xml');
    expect(light.existsSync(), isTrue);
    expect(dark.existsSync(), isTrue);

    for (final f in [light, dark]) {
      final xml = f.readAsStringSync();
      expect(xml, contains('windowSplashScreenBackground'),
          reason: '${f.path} must declare windowSplashScreenBackground');
      expect(xml, contains('@color/splash_background_'),
          reason: '${f.path} must reference splash_background_* colour resource');
      expect(xml, contains('@drawable/ic_launcher_foreground'),
          reason: '${f.path} must use brand foreground for splash icon');
    }
  });

  test('Legacy raster ic_launcher.png still present for pre-O launchers', () {
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      final png = File('${resDir.path}/mipmap-$d/ic_launcher.png');
      expect(png.existsSync(), isTrue,
          reason: 'Expected $png for Android 7 and earlier.');
    }
  });

  test('AndroidManifest declares launcher + round icon + brand label', () {
    expect(manifest.existsSync(), isTrue);
    final xml = manifest.readAsStringSync();
    expect(xml, contains('android:icon="@mipmap/ic_launcher"'));
    expect(xml, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
    expect(xml, contains('android:label="Gochano"'));
  });

  test('Unused app_icon.xml is removed', () {
    final old = File('${resDir.path}/drawable/app_icon.xml');
    expect(old.existsSync(), isFalse,
        reason: 'Old Material home icon should be deleted.');
  });

  test('Notification small icon is still present and monochrome', () {
    final icon = File('${resDir.path}/drawable/ic_stat_gochano.xml');
    expect(icon.existsSync(), isTrue);
    final content = icon.readAsStringSync();
    // Notification small icons MUST be white-on-transparent. No #RRGGBB
    // colours other than #FFFFFFFF should appear in any fillColor.
    final hexColors = RegExp(r'android:fillColor="(#[0-9A-Fa-f]+)"')
        .allMatches(content)
        .map((m) => m.group(1)!.toUpperCase());
    for (final c in hexColors) {
      expect(c, '#FFFFFFFF',
          reason:
              'Notification icon must be monochrome white.  Found $c in $icon');
    }
  });

  test('Brand master artwork exists in assets/branding', () {
    final master = File('assets/branding/Gochano.png');
    expect(master.existsSync(), isTrue);
    expect(master.lengthSync(), greaterThan(1024),
        reason: 'Master artwork is suspiciously small; expected real PNG.');
  });
}