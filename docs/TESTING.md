# Testing

## Automated

```sh
flutter analyze
flutter test
```

- `test/core/` — model validation, path sanitisation, duplicate names,
  fingerprints, QR payload expiry, pairing tokens, rate limiting, trust-store
  persistence, peer presence, clipboard loop prevention, folder scanning.
- `test/integration/` — in-process sender/receiver over loopback TLS: offer,
  accept, upload, checksum, decline, cancel, resume, path-traversal rejection,
  wrong fingerprint, and a 128 MiB streaming transfer.
- `test/share/`, `test/shell/` — share-intent parsing and keyboard shortcuts.

The transport tests start two real `FlowDropServer` instances with generated
certificates, so they exercise TLS, HTTP routing, streaming and hashing.

## Screenshots

The images in `docs/screenshots/` are golden files generated from the real
widgets:

```sh
# PowerShell
$env:FLOWDROP_SCREENSHOTS = "1"
flutter test --update-goldens test/screenshots_test.dart
```

The test is skipped unless that variable is set, so CI does not depend on
platform fonts. Regenerate them after any visible UI change and commit the
PNGs with the code.

## Benchmark

```sh
dart run tool/benchmark.dart
```

Runs a local sender/receiver pair and prints MB/s for the configured chunk
sizes. Use it before changing buffer sizes.

## Manual test matrix

Run each row on real hardware before a release.

| Pair | Network | Cases |
|---|---|---|
| Android ↔ Windows | same Wi-Fi | 10 MB photo, 500 small files, text |
| Android ↔ Windows | phone hotspot | 2 GB file, cancel + resume |
| Windows ↔ Linux | same Wi-Fi | folder tree, unicode names, duplicate names |
| macOS ↔ Android | same Wi-Fi | QR pairing, expired QR, wrong fingerprint |
| Linux ↔ macOS | ethernet | clipboard sync, history |
| iOS ↔ Windows | same Wi-Fi | QR pairing (iOS foreground only) |

## What "passes" means

- Checksums match and the received file opens.
- No `.part` file remains after success.
- Cancelling leaves no partial file in the download folder.
- Memory stays flat during a multi-GB transfer.
- UI keeps 60 fps; progress updates are throttled.
- A wrong fingerprint is rejected before any bytes are sent.
- `../` and absolute paths are rejected and no file is created outside the
  download folder.
