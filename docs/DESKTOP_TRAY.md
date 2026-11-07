# Desktop tray & hotkey — deferred

The tray + global hotkey (spec §7 desktop extras) was prototyped with
`window_manager` 0.6.0 (legacy API), `tray_manager` 0.8.3 and
`hotkey_manager` 0.3.0, and then reverted because their native build
hooks cannot run on this machine (no Android SDK, no Visual Studio,
Developer Mode disabled). Every `flutter test` run failed at the native
asset build step, breaking the green build the project requires.

Shortcuts + tray alternatives that DO ship today:

- In-app keyboard shortcuts (Ctrl/Cmd+1–4 tabs, +Q QR, +C push clipboard,
  +R refresh) — see `lib/features/shell/shell_shortcuts.dart`.
- The `minimizeToTray` setting was prototyped alongside; the pure-Dart
  `AppSettings` round-trip test in `test/core/settings_test.dart` already
  covers persistence of this kind of flag, so re-adding is mechanical.

How to enable once native builds work (CI runner, or a dev machine with
Visual Studio / Developer Mode):

1. `flutter pub add window_manager tray_manager hotkey_manager`
2. Re-create `lib/app/desktop/desktop_integration.dart`:
   - legacy `windowManager.waitUntilReadyToShow(WindowOptions(...))`,
     `setPreventClose(true)`, a `WindowListener.onWindowClose` that hides
     when `settings.minimizeToTray` is on.
   - `TrayManager.setIcon(...)` + context menu (Show window /
     Send clipboard to nearby / Quit); tray icon can be rendered at
     runtime with `dart:ui` (no bundled asset required).
   - `HotKeyManager.register(HotKey(key: LogicalKeyboardKey.keyV,
     modifiers: [control, shift] (meta on macOS), scope:
     HotKeyScope.inapp))` → `AppController.pushClipboardNow()`.
3. Wire a small `DesktopIntegration` in `app_shell.dart` next to the
   `ShareBridge` attach, gated by the same `Platform` checks.
4. `flutter analyze` + `flutter test` must stay green (plugin build
   hooks run on the same toolchain then).

Until then, closing the window quits the app (the HTTPS server stops
with it), and clipboard sending is one keystroke away in-app.
