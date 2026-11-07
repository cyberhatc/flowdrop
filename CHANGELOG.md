# Changelog

All notable changes to FlowDrop are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project skeleton for Android, iOS, Windows, Linux and macOS.
- Neon-glow design system (dark/light), radar home, navigation shell.
- Persistent device identity: Ed25519 key pair + self-signed TLS certificate,
  private material in OS secure storage.
- FlowDrop Protocol v1 models, QR payload, path sanitisation, pairing tokens.
- HTTPS transport: `/v1/info`, `/v1/offer`, `/v1/accept`, `/v1/upload`,
  `/v1/status`, `/v1/cancel`, `/v1/text`, `/v1/clipboard`, `/v1/events`.
- Streaming uploads with incremental SHA-256, `.part` files and resume offsets.
- Discovery: UDP beacon + mDNS lookup, manual connect.
- Send files/text UI, incoming request dialog, transfer progress, history.
- QR show/scan with fingerprint pinning and 2-minute one-time tokens.
- Unit and in-process integration tests, benchmark tool, CI workflow.
