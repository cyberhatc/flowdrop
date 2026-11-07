# Contributing to FlowDrop

Thanks for helping make file transfer between devices less annoying.

## Getting started

1. Install Flutter stable (3.24+ / Dart 3.5+).
2. Enable the desktop target you need, e.g. `flutter config --enable-windows-desktop`.
3. `flutter pub get`
4. `flutter run -d windows` (or `linux`, `macos`, an Android device, an iOS simulator).

## Before you open a PR

```sh
dart format .
flutter analyze
flutter test
```

CI runs the same commands and fails on analyzer warnings.

## Guidelines

- Keep `lib/core/` free of Flutter imports. It must stay testable in pure Dart.
- Prefer small files and small commits. Use conventional commit messages
  (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).
- Do not disable TLS verification, weaken the fingerprint check, or log file
  contents, tokens or private keys.
- Add a test for every protocol or security change. Security bugs get a test
  under `test/security/`.
- Platform workarounds need a short comment explaining why they exist, plus a
  note in `docs/DECISIONS.md` when they change behaviour.

## Reporting security issues

See [SECURITY.md](SECURITY.md). Do not open a public issue for a vulnerability.
