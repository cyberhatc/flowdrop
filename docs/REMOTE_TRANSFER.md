# Remote transfer (different networks)

FlowDrop is **LAN-first**: discovery and transfer assume both devices can reach
each other over the local network. This is what makes it fast, private and
offline-capable. "Different networks" (home Wi-Fi vs. mobile data, two cities,
a corporate VPN) is not supported out of the box — but there are three
practical ways to make it work, from easiest to most flexible.

## 1. Hotspot (recommended, zero setup)

Put one device on the other's personal hotspot. Both are then on the same
LAN segment, so FlowDrop's normal discovery (UDP beacon + mDNS) and QR
pairing work unchanged. This is the path the app is optimized for and is
also the most private (no third party).

## 2. Manual connect over a public address

If one device has a public IP (or a port forwarded to it), use
**Manual connect** (IP : port + fingerprint) on the other device. The TLS
certificate fingerprint check still applies, so this is safe even over the
open internet. Discovery will not find it automatically — you paste the
address.

Caveats: most mobile networks use CGNAT, so a phone on cellular usually has
no reachable public address. Laptops behind a home router need port
forwarding (default port 53317/TCP).

## 3. Self-hosted relay (building block provided)

For two devices that are both behind NAT with no port forwarding, you need a
relay. `tool/relay_server.dart` is a minimal, dumb byte-forwarder:

```bash
dart run tool/relay_server.dart          # listens on :8080
PORT=9000 dart run tool/relay_server.dart
```

Two devices connect to the same `ws://host:port/tunnel` with the
subprotocol `flowdrop-relay-<CODE>`; the relay bridges them. Because the
forwarded bytes are the existing FlowDrop HTTPS stream, TLS and certificate
pinning stay end-to-end — the relay never sees plaintext.

**Status:** client tunneling is now wired in. Set the same relay URL on both
devices (Settings → Remote transfer). The receiving device keeps a background
connection to the relay under its own device id; the sending device opens a
local proxy to the relay under the receiver's device id, so the normal HTTPS
exchange (and certificate pinning) runs end to end through the relay. Verified
by a smoke test that pushes bytes through the relay. Limitations: the
receiver's agent only runs while the app is in the foreground (mobile
background execution is not implemented); and the relay URL must be reachable
by both devices.

## What will NOT work

- Bluetooth LE file transfer (not implemented; see `docs/ARCHITECTURE.md`).
- Automatic discovery across subnets/VLANs (mDNS does not cross routers).
- Peer-to-peer without any reachable endpoint or relay (CGNAT on both sides).

## Security note

Remote transfer never weakens the trust model: the receiving side still
verifies the sender's certificate fingerprint, pairing tokens are still
single-use and 2-minute, and unknown senders still require explicit
confirmation.
