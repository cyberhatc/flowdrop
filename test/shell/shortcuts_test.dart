import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowdrop/features/shell/shell_shortcuts.dart';

void main() {
  group('shellShortcuts', () {
    Map<ShortcutActivator, VoidCallback> build(TargetPlatform platform) =>
        shellShortcuts(
          onTab: (_) {},
          onQr: () {},
          onClipboard: () {},
          onRefresh: () {},
          platform: platform,
        );

    List<String> labelsFor(
      Map<ShortcutActivator, VoidCallback> bindings,
      bool Function(SingleActivator) test,
    ) =>
        bindings.keys
            .whereType<SingleActivator>()
            .where(test)
            .map((activator) => activator.trigger.keyLabel)
            .toList();

    test('Windows bindings use Ctrl', () {
      final bindings = build(TargetPlatform.windows);
      final digits = labelsFor(bindings, (activator) => activator.control);
      for (final label in ['1', '2', '3', '4', 'Q', 'C', 'R']) {
        expect(digits, contains(label));
      }
    });

    test('macOS gets Meta variants', () {
      final bindings = build(TargetPlatform.macOS);
      final meta = labelsFor(bindings, (activator) => activator.meta);
      for (final label in ['1', '2', '3', '4', 'Q', 'C', 'R']) {
        expect(meta, contains(label));
      }
    });

    test('non-macOS has no Meta bindings', () {
      final bindings = build(TargetPlatform.linux);
      final hasMeta = bindings.keys
          .whereType<SingleActivator>()
          .any((activator) => activator.meta);
      expect(hasMeta, isFalse);
    });

    test('tab callbacks fire with the right index', () {
      final seen = <int>[];
      final bindings = shellShortcuts(
        onTab: seen.add,
        onQr: () {},
        onClipboard: () {},
        onRefresh: () {},
      );
      final entry = bindings.entries.firstWhere(
        (entry) =>
            entry.key is SingleActivator &&
            (entry.key as SingleActivator).control,
      );
      entry.value();
      expect(seen, [0]);
    });
  });
}
