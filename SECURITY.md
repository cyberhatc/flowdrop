# Security policy

## Reporting a vulnerability

Please do not file a public issue. Email the maintainer or use GitHub's private
vulnerability reporting ("Security" tab → "Report a vulnerability").

Include:

- affected version / commit,
- platform and OS version,
- steps to reproduce,
- impact (what an attacker gains).

You should get an acknowledgement within 72 hours. Please give us a reasonable
window to ship a fix before disclosing.

## Design guarantees

- All traffic uses TLS with a self-signed per-device certificate.
- Certificates are accepted only when their SHA-256 fingerprint is pinned via QR
  or confirmed by the user. There is no "accept any certificate" path.
- Pairing tokens are single-use, expire in 120 seconds and are rate limited.
- Unknown senders require explicit user approval.
- Received files are confined to the download folder; traversal, absolute paths
  and Windows reserved names are rejected.
- Private keys live in the OS secure store, never in shared preferences or logs.

## Out of scope

- An attacker with code execution on your device.
- Network operators observing metadata (FlowDrop hides content, not the fact that
  two LAN hosts exchange packets).
- Denial of service by flooding the LAN with bogus discovery beacons.
