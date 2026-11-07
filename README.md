# FlowDrop

Fast, secure, LAN file and text transfer between any two devices — phone ↔ laptop, laptop ↔ laptop, phone ↔ phone — with **no account, no internet and no cloud**.

FlowDrop runs a small pinned-certificate HTTPS server on each device. Devices discover each other on the local network (mDNS + UDP fallback) or pair by QR code / manual address, and then stream files with SHA-256 verification, resume and parallel uploads.

- **Platforms:** Android, iOS, Windows, Linux, macOS
- **Stack:** Flutter (Dart), Riverpod, shelf HTTPS server, Ed25519 + self-signed TLS with fingerprint pinning
- **Security:** TLS everywhere, unknown senders always require explicit confirmation, path traversal is rejected, pairing tokens are single-use and expire in 2 minutes

## How to run

```bash
flutter pub get
flutter run            # desktop or mobile device
flutter test           # full unit + integration suite
```

## Connection methods

| Method | How | Notes |
|---|---|---|
| Same Wi-Fi / hotspot | UDP beacon + mDNS discovery (radar view) | No internet needed; hotspot = same code path |
| QR code | FlowDrop → **Show my QR** → scan/paste on the other device | Works even when discovery is blocked |
| Manual | IP : port + short fingerprint | Fallback for locked-down networks |

Large data always moves over the LAN. Bluetooth is not used for file transfer; see `docs/ARCHITECTURE.md` for why.

## Security model

- Each device generates an Ed25519 identity key and a self-signed TLS certificate on first run (private key in OS secure storage).
- Clients **pin** the certificate fingerprint — TLS verification is never blanket-disabled.
- Unknown devices always get an Accept / Decline prompt with file count, total size and a 4-word fingerprint phrase to verify out-of-band.
- Pairing tokens are 144-bit, single-use, expire after 2 minutes and are rate-limited per IP (5/min).
- Files are written to `.part` staging files and renamed only after size + SHA-256 verify; all names/paths are sanitized.

See `docs/PROTOCOL.md` for the wire protocol so others can build compatible clients.

## Build from source

- Requires Flutter 3.29+ / Dart 3.7+.
- Desktop builds: `flutter build windows|linux|macos`
- Mobile builds: `flutter build apk|appbundle|ios`

## Troubleshooting

- **Peers never appear:** allow the app through your firewall (default port 53317/TCP, 53318/UDP), avoid guest Wi-Fi with AP/client isolation, or use a phone hotspot + QR.
- **QR pairing fails:** check that both devices show the same 4-word phrase; codes expire after 2 minutes and can be used once.
- **iOS receiving:** the server only runs while the app is foregrounded (iOS suspends sockets in the background) — keep FlowDrop open during transfers.

## Contributing

See `CONTRIBUTING.md`. Please run `flutter analyze` and `flutter test` before submitting — CI fails on warnings.

## License

MIT — see `LICENSE`.
