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

**Status:** the relay server is provided as a building block. Wiring the
FlowDrop client to tunnel its HTTPS traffic through it (instead of opening a
direct socket) is the next step and is not yet implemented in the app. If
you need this, run the relay on a host both devices can reach (a cheap VPS,
a friend's machine, or your own) and open an issue/PR to finish the client
side.

## What will NOT work

- Bluetooth LE file transfer (not implemented; see `docs/ARCHITECTURE.md`).
- Automatic discovery across subnets/VLANs (mDNS does not cross routers).
- Peer-to-peer without any reachable endpoint or relay (CGNAT on both sides).

## Security note

Remote transfer never weakens the trust model: the receiving side still
verifies the sender's certificate fingerprint, pairing tokens are still
single-use and 2-minute, and unknown senders still require explicit
confirmation.
