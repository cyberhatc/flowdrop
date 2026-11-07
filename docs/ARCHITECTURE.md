# Architecture

FlowDrop is a Flutter application with a UI-free Dart core. The core can be
unit tested without a Flutter binding and is reused by the UI, the integration
tests and the benchmark tool.

```
lib/
  main.dart              bootstrap: init storage, identity, server, discovery
  app/                   theme, routing, app shell
  core/
    protocol/            wire models, versions, file-name sanitisation
    security/            identity, certificates, fingerprints, pairing tokens
    transport/           HTTPS server, HTTP client, upload streaming, events
    discovery/           UDP beacon, mDNS lookup, QR payload, network interfaces
    transfer/            session state, checksums, resumable-file bookkeeping
    storage/             settings, secure identity storage, history database
  features/              screens (home, send, receive, qr, history, settings)
  ui/                    reusable glow widgets and animations
test/                    unit + in-process integration tests
integration_test/        on-device UI tests
tool/                    benchmark and developer utilities
```

## Layers

1. **Protocol models** are plain Dart classes with `toJson`/`fromJson`. They
   validate input and never trust the network.
2. **Security** owns the device identity (Ed25519 key pair + self-signed TLS
   certificate) and the trust decisions. A fingerprint is the only thing that
   can grant trust; names and IPs are never trusted.
3. **Transport** is a shelf server plus an `HttpClient` client. TLS uses a
   `SecurityContext` built from the generated certificate and the client pins
   the certificate with `badCertificateCallback` (never blanket-accept).
4. **Discovery** runs the UDP beacon and mDNS lookup. Both feed the same peer
   registry so the UI does not care how a peer was found.
5. **UI** is Riverpod + Flutter. It listens to state exposed by the core; it
   never performs network I/O directly.

## Concurrency

Long-lived network work runs in isolates (server and discovery) or in async I/O,
so the UI isolate stays responsive. Progress notifications are throttled to
about 10 Hz before they reach Riverpod.

## Storage

- Settings: `shared_preferences`.
- Private key + certificate: `flutter_secure_storage` (DPAPI on Windows,
  Keychain on Apple platforms, Keystore on Android, libsecret on Linux).
- History: SQLite via `sqlite3` with a small hand-written repository (no
  code generation).

## Trust model

- The TLS certificate is self-signed. The client accepts it only if its SHA-256
  fingerprint matches the value received out of band (QR / pairing) or the
  fingerprint the user confirmed in the UI.
- Pairing tokens are single-use, expire after 2 minutes and are rate limited.
- Unknown senders always require an explicit accept. Auto-accept is opt-in per
  device.
- Received files are written inside the download folder only. Paths are
  sanitised and re-checked after joining.
