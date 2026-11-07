import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desktop keyboard shortcuts for the shell (spec §7).
///
/// `onTab` switches tabs by index, `onQr` opens the QR screen, `onClipboard`
/// pushes the clipboard, `onRefresh` starts a radar refresh. macOS uses Cmd
/// instead of Ctrl for these bindings.
Map<ShortcutActivator, VoidCallback> shellShortcuts({
  required void Function(int tab) onTab,
  required VoidCallback onQr,
  required VoidCallback onClipboard,
  required VoidCallback onRefresh,
  TargetPlatform platform = TargetPlatform.windows,
}) {
  final bindings = <ShortcutActivator, VoidCallback>{
    SingleActivator(LogicalKeyboardKey.digit1, control: true): () => onTab(0),
    SingleActivator(LogicalKeyboardKey.digit2, control: true): () => onTab(1),
    SingleActivator(LogicalKeyboardKey.digit3, control: true): () => onTab(2),
    SingleActivator(LogicalKeyboardKey.digit4, control: true): () => onTab(3),
    SingleActivator(LogicalKeyboardKey.keyQ, control: true): onQr,
    SingleActivator(LogicalKeyboardKey.keyC, control: true): onClipboard,
    SingleActivator(LogicalKeyboardKey.keyR, control: true): onRefresh,
  };
  if (platform == TargetPlatform.macOS) {
    final meta = <ShortcutActivator, VoidCallback>{
      SingleActivator(LogicalKeyboardKey.digit1, meta: true): () => onTab(0),
      SingleActivator(LogicalKeyboardKey.digit2, meta: true): () => onTab(1),
      SingleActivator(LogicalKeyboardKey.digit3, meta: true): () => onTab(2),
      SingleActivator(LogicalKeyboardKey.digit4, meta: true): () => onTab(3),
      SingleActivator(LogicalKeyboardKey.keyQ, meta: true): onQr,
      SingleActivator(LogicalKeyboardKey.keyC, meta: true): onClipboard,
      SingleActivator(LogicalKeyboardKey.keyR, meta: true): onRefresh,
    };
    bindings.addAll(meta);
  }
  return bindings;
}
