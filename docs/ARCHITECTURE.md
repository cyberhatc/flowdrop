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

The server, discovery and the UI share one isolate. Everything is async I/O:
file bytes are streamed in chunks straight from disk to socket, so a multi-GB
transfer does not allocate buffers proportional to the file size. SHA-256 is
computed incrementally on the same chunks. Progress notifications are
throttled to about 10 Hz before they reach Riverpod.

## Presence and reconnection

Paired devices are more than a trust decision; they are durable peers:

- `TrustedDevice` persists `addresses`, `port` and `lastSeen` alongside the
  fingerprint. A cold start can therefore try the last known endpoint before
  any discovery packet arrives.
- `PeerRegistry` marks paired peers as `pinned`. They are never pruned; the UI
  dims them when `lastSeen` is older than `peerTimeout` (30 s).
- A timer probes pinned-but-offline devices over pinned HTTPS every 10 s with
  a 30 s backoff. A successful probe refreshes the stored endpoint and flips
  the peer live.
- Sending files or clipboard data iterates every remembered address and the
  default port, so a device that roamed from Wi-Fi to hotspot still connects.
- Discovery-off / hidden visibility keeps a passive `DiscoveryService`
  (broadcast and mDNS disabled) so paired devices stay listed and reachable.

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
