# FlowDrop Protocol v1

FlowDrop moves files and text directly between devices on the same network.
There is no cloud, no account and no relay. Every device runs a small HTTPS
server and advertises itself on the LAN.

Protocol version: `1` (`v=1` in every payload).

## Transport

- HTTPS only. Each device generates a self-signed certificate on first run.
- The certificate is pinned by its SHA-256 fingerprint (`fp`). A fingerprint is
  lowercase hex, no separators: `sha256(certificate DER)`.
- Default port: `53317`. If busy, the device picks the next free port and
  advertises the one it actually bound.
- Discovery beacon: UDP broadcast/multicast on port `53318`.
- mDNS service type: `_flowdrop._tcp.local`.

All request and response bodies are UTF-8 JSON unless stated otherwise.

## Device identity

```json
{
  "id": "8f43c2b5-...",
  "name": "Manu's laptop",
  "platform": "windows",
  "version": 1,
  "publicKey": "<base64 Ed25519 public key>",
  "fingerprint": "<sha256 of TLS certificate DER>",
  "addresses": ["192.168.1.24"],
  "port": 53317
}
```

`id` is a random UUID generated once per installation. `publicKey` signs the
pairing handshake. `fingerprint` is the TLS pin.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/v1/info` | Returns the device identity document. |
| POST | `/v1/pair` | Redeem a one-time pairing token. |
| POST | `/v1/offer` | Offer files/text. Metadata only. |
| POST | `/v1/accept` | Accept or decline an offer. Returns upload URLs. |
| PUT | `/v1/upload/{session}/{fileId}` | Stream bytes. Supports resume. |
| GET | `/v1/status/{session}` | Per-file received offsets and state. |
| POST | `/v1/cancel/{session}` | Cancel a session. |
| POST | `/v1/text` | Send a text/link payload. |
| POST | `/v1/clipboard` | Push clipboard text to a paired device. |
| WS | `/v1/events` | Live progress, incoming offers, clipboard events. |

### `POST /v1/pair`

```json
{
  "token": "6-digit-or-qr-token",
  "device": { /* DeviceIdentity */ },
  "signature": "<base64 Ed25519 signature over the token>",
  "alwaysTrust": false
}
```

The receiver verifies the token is known, unused and unexpired. Tokens are
single-use, valid for 120 seconds and rate limited to 5 attempts per minute per
IP. Success returns `{ "ok": true, "trusted": true, "device": {...} }`.

### `POST /v1/offer`

```json
{
  "sessionId": "uuid",
  "sender": { /* DeviceIdentity */ },
  "text": null,
  "files": [
    { "id": "uuid", "name": "photo.jpg", "size": 2481923,
      "mime": "image/jpeg", "relativePath": "trip/photo.jpg" }
  ],
  "totalSize": 2481923
}
```

The receiver responds after the user accepts or declines:

```json
{
  "accepted": true,
  "sessionId": "uuid",
  "uploadUrls": { "<fileId>": "/v1/upload/<session>/<fileId>" }
}
```

Declines return `{ "accepted": false, "reason": "declined" }`.

### `PUT /v1/upload/{session}/{fileId}`

- Body: raw file bytes starting at byte 0, or at `X-FlowDrop-Offset` for resume.
- `Content-Length` is required.
- Resume responses: `409` with `{ "offset": <received> }` when the offset does
  not match what the receiver already has.
- Success: `200 { "ok": true, "sha256": "<hex>", "size": <bytes> }`.
- Bytes are written to `<name>.part` and atomically renamed on success.
- The declared size is enforced; exceeding it aborts the upload.

### `GET /v1/status/{session}`

```json
{
  "sessionId": "uuid",
  "state": "receiving",
  "files": [
    { "id": "uuid", "received": 1048576, "size": 2481923, "state": "receiving" }
  ]
}
```

### `WS /v1/events`

Server → client messages:

```json
{ "type": "offer", "offer": { /* OfferRequest */ } }
{ "type": "progress", "sessionId": "...", "fileId": "...", "received": 123, "total": 456 }
{ "type": "completed", "sessionId": "..." }
{ "type": "cancelled", "sessionId": "..." }
{ "type": "text", "from": "...", "text": "..." }
{ "type": "clipboard", "from": "...", "data": "..." }
{ "type": "ping", "at": 1712345678901 }
```

## Pairing token

The QR payload is URL-style:

```
flowdrop://connect?v=1&id=<deviceId>&n=<name>&ip=<ip1,ip2>&p=<port>&fp=<sha256>&t=<token>&exp=<unix seconds>
```

Rules:

- `t` is one-time and expires after 120 seconds (`exp`).
- The client fetches `/v1/info` and rejects the connection if the presented
  certificate fingerprint differs from `fp`. This is the MITM defence.
- The client tries every listed IP in parallel and uses the first that answers.
- IPs that are virtual adapters (Docker, VPN, VirtualBox) are not listed.

## Transfer rules

- Stream from disk; never load whole files into memory.
- 1 MiB chunks, up to 3 concurrent files (single stream for one large file).
- SHA-256 computed incrementally while streaming; the receiver verifies before
  the `.part` file is renamed.
- Path traversal is rejected (`..`, absolute paths, drive letters, reserved
  Windows names, NUL bytes).
- Duplicate names become `name (1).ext`.

## Errors

Errors use the HTTP status plus `{ "error": "code", "message": "human text" }`.
Codes: `bad_request`, `unauthorized`, `token_expired`, `token_used`,
`rate_limited`, `declined`, `conflict`, `too_large`, `not_found`,
`unsupported_version`, `internal`.
