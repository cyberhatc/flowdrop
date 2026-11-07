import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/core/storage/settings.dart';

void main() {
  group('AppSettings', () {
    test('round-trips through JSON including visibility', () {
      const original = AppSettings(
        deviceName: 'Pixel',
        visibility: VisibilityMode.trustedOnly,
        onboardingDone: true,
        clipboardSync: true,
      );
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.deviceName, 'Pixel');
      expect(restored.visibility, VisibilityMode.trustedOnly);
      expect(restored.onboardingDone, isTrue);
      expect(restored.clipboardSync, isTrue);
    });

    test('unknown visibility values fall back to everyone', () {
      final restored = AppSettings.fromJson({'visibility': 'bogus-mode'});
      expect(restored.visibility, VisibilityMode.everyone);
    });

    test('missing visibility also defaults to everyone', () {
      const defaults = AppSettings();
      expect(
        AppSettings.fromJson(defaults.toJson()).visibility,
        VisibilityMode.everyone,
      );
    });

    test('copyWith changes visibility only', () {
      const settings = AppSettings();
      final next = settings.copyWith(visibility: VisibilityMode.hidden);
      expect(next.visibility, VisibilityMode.hidden);
      expect(next.deviceName, settings.deviceName);
    });
  });
}
