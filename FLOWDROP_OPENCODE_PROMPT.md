# FlowDrop — Master Build Prompt for OpenCode

> Paste this whole file into OpenCode (or save it as `PROMPT.md` / `AGENTS.md` in an empty repo and say: *"Read PROMPT.md and build the project phase by phase."*)
> "FlowDrop" is a working name. Rename it freely.

---

## 0. Your role

You are a senior cross-platform engineer. Build **FlowDrop**: a fast, secure, beautiful app that moves **files and text/clipboard** between any two devices (phone ↔ laptop, laptop ↔ laptop, phone ↔ phone) on **Android, iOS, Windows, Linux, macOS**.

Work **phase by phase** (Section 12). After each phase: build, run, test, commit. Never move on with a broken build. Explain any decision that deviates from this document.

---

## 1. Product goals

1. **Instant**: discovery < 2 s, transfer starts < 500 ms after tap, speed limited only by the network.
2. **Any device, any OS**: one codebase wherever possible.
3. **Zero setup**: no accounts, no internet, no server, no cloud.
4. **Three ways to connect**
   - Auto-discovery on the same Wi-Fi / hotspot (primary)
   - **QR code scan** (works even when discovery is blocked)
   - Manual IP / code entry (fallback)
5. **Send anything**: files, folders, photos, videos, text, links, clipboard.
6. **Secure by default**: encrypted, authenticated, user confirms incoming transfers.
7. **Beautiful**: dark theme with neon **glow** accents, smooth animations.
8. **Open source on GitHub** with CI building all platforms and releases.

---

## 2. Tech stack (decided — do not change without reason)

| Layer | Choice |
|---|---|
| UI + logic | **Flutter (Dart 3, stable)** for Android, iOS, Windows, Linux, macOS |
| State management | Riverpod |
| Local HTTP/WebSocket server | `dart:io` `HttpServer` + `shelf` (+ `shelf_web_socket`) |
| Discovery | mDNS/DNS-SD (`nsd` or `multicast_dns`) **plus** UDP broadcast fallback |
| TLS | Self-signed cert per device, **certificate fingerprint pinning** |
| QR generate / scan | `qr_flutter` / `mobile_scanner` (mobile); desktop shows QR, scans via phone |
| Files | `file_picker`, `path_provider`, `share_handler`/`receive_sharing_intent` (mobile share sheet) |
| Clipboard | `super_clipboard` or `clipboard` + platform polling |
| Storage | `drift` (SQLite) or `isar` for history/trusted devices |
| Crypto | `cryptography` package (X25519, AES-GCM/ChaCha20-Poly1305, SHA-256) |
| Desktop windowing | `window_manager`, `tray_manager`, `launch_at_startup` |
| Notifications | `flutter_local_notifications` |
| Permissions | `permission_handler` |
| Bluetooth | `flutter_blue_plus` (BLE) — **discovery/pairing assist only**, see Section 5.4 |
| CI | GitHub Actions |

Rust/native is only allowed for a measured performance bottleneck. Start pure Dart.

---

## 3. Architecture

```
lib/
  main.dart
  app/                 # theme, routing, app shell
  core/
    protocol/          # message models, versioning, constants
    discovery/         # mdns, udp_broadcast, qr_payload
    transport/         # server, client, websocket control channel, chunk streaming
    security/          # keys, certs, pairing, fingerprint pinning
    transfer/          # queue, progress, resume, checksum
    clipboard/         # watch + sync
    storage/           # db, settings, trusted devices, history
    platform/          # per-OS code (android multicast lock, windows firewall, etc.)
  features/
    home/              # nearby devices, big "Send" area
    send/              # pick files/text, choose target
    receive/           # incoming prompt, save location
    qr/                # show my QR, scan QR
    clipboard_sync/
    history/
    settings/
  ui/                  # glow widgets, animated components
test/                  # unit + integration
integration_test/
.github/workflows/
docs/
```

Rules:
- `core/` has **no Flutter UI imports**, so it can be unit-tested and reused.
- Everything network-related runs in **isolates** so the UI never janks.
- One `Device` identity: `deviceId` (UUID), `name`, `platform`, `publicKey`, `certFingerprint`.

---

## 4. Protocol (FlowDrop Protocol v1)

Every device runs a small **HTTPS server** on a random-but-remembered port (default try `53317`, fall back to a free port) and advertises it.

### 4.1 Endpoints (all over TLS)

| Method | Path | Purpose |
|---|---|---|
| GET | `/v1/info` | Device info: id, name, platform, protocol version, fingerprint |
| POST | `/v1/pair` | Pairing handshake (token from QR or PIN) |
| POST | `/v1/offer` | Sender offers files/text: metadata only (names, sizes, mime, total) |
| POST | `/v1/accept` | (or response of offer) Receiver accepts/declines; returns session id + per-file upload URLs |
| PUT | `/v1/upload/{session}/{fileId}` | Stream file bytes; supports `Range`/`offset` for **resume** |
| GET | `/v1/status/{session}` | Progress / resume offsets |
| POST | `/v1/cancel/{session}` | Cancel |
| WS | `/v1/events` | Control channel: live progress, clipboard push, ping, cancel |
| POST | `/v1/text` | Send text/link (shown in receiver as a card with Copy / Open) |
| POST | `/v1/clipboard` | Clipboard push (only for paired + clipboard-sync-enabled devices) |

### 4.2 Transfer rules (this is how we get **fast**)
- **Stream** files from disk to socket; never load a whole file in RAM.
- Chunk size **1–4 MiB**, tuned by testing.
- Send **multiple files in parallel** (default 3 streams), large single file = single stream with big buffer (parallel ranges optional later).
- Hash with **SHA-256 incrementally** while streaming; receiver verifies at the end; mismatch → retry that file.
- Write to `*.part` temp file, rename on success (never leave half-files looking complete).
- **Resume** interrupted transfers using offsets.
- Optional gzip only for compressible text; never compress media/zip.
- Folders: send as list of relative paths; recreate structure; **sanitize paths** (reject `..`, absolute paths, reserved Windows names).

### 4.3 Text & clipboard behavior
- "Send text" box: paste or type → pick device → arrives instantly as a card with **Copy**, **Open link** (if URL), **Save as .txt**.
- **Clipboard sync (opt-in per device)**: when enabled, copying on device A pushes to device B's clipboard within ~300 ms. Debounce, avoid loops (tag clipboard events with origin id + hash), and skip very large/sensitive content (> 1 MB; optionally skip content from password managers on Android/Windows which flag it as sensitive).
- "Paste to other device" quick action on desktop via tray menu and a global hotkey (default `Ctrl/Cmd+Shift+V`).

---

## 5. Connection methods

### 5.1 Same Wi-Fi / LAN (primary)
- Advertise `_flowdrop._tcp` via mDNS with TXT: `id`, `name`, `v`, `fp` (short fingerprint).
- **Fallback** if mDNS is blocked: UDP broadcast/multicast beacon on port 53318 every 1–2 s while the app is in foreground; listen for peers.
- Show nearby devices in a radar-style animated view; devices expire after ~6 s of silence.

### 5.2 Hotspot (no router needed)
- A phone hotspot or laptop hotspot is just a LAN: **same code path** as 5.1.
- Hotspot gateway IP is often `192.168.43.1` (Android) / `172.20.10.1` (iOS) / `192.168.137.1` (Windows) — scan these directly as part of discovery fallback.
- In the UI add a **"No Wi-Fi? Use hotspot"** guide screen with 3 steps and a QR that carries connection info.

### 5.3 QR code (instant connect — a core feature)
QR contains a **URL-style payload**:

```
flowdrop://connect?v=1&id=<deviceId>&n=<name>&ip=<ip1,ip2>&p=<port>&fp=<sha256 cert fingerprint>&t=<one-time token>&exp=<unix expiry>
```

Flow:
1. Device A taps **"Show my QR"** → creates a **one-time token valid 2 minutes**, shows QR (glowing frame, countdown ring).
2. Device B scans (or pastes the code on desktop) → connects directly to listed IPs, **verifies the cert fingerprint matches the QR** (this prevents man-in-the-middle), redeems token via `/v1/pair`.
3. Both devices now trust each other (optional "Always trust" switch). Session starts; B can immediately send or receive.
4. Also support **QR for a specific share**: A picks files → "Share via QR" → B scans → B downloads directly (A runs a temporary one-shot download session).
5. Include **all** local IPs in the QR (Wi-Fi, hotspot, ethernet); client tries them in parallel and uses the first that answers.

### 5.4 Bluetooth (be honest about limits)
- Bluetooth is **slow and inconsistent** across OSes (and iOS blocks most classic Bluetooth file transfer for third-party apps).
- Implement Bluetooth **LE only as a helper**: nearby wake-up, exchanging the QR payload / Wi-Fi hotspot credentials, and discovery when no network is shared.
- **Large data always moves over Wi-Fi/hotspot/LAN.** Optionally evaluate **Wi-Fi Direct** (Android↔Android/Windows) and Apple's peer-to-peer Wi-Fi later as an advanced phase — do not block the MVP on it.
- Document these limits in the README under "Connection methods".

### 5.5 Manual fallback
- Enter IP:port or a short 6-digit code (derived from device id) in "Connect manually".

---

## 6. Security (do this right from day 1)

- On first run generate: device keypair (Ed25519/X25519) and a **self-signed TLS certificate**; store private key in OS secure storage (`flutter_secure_storage`).
- **Never trust a cert unless**: it was pinned via QR/pairing, or the user confirmed the matching **short fingerprint / 4-word phrase** on both screens.
- Incoming request from an **unknown device** always requires explicit **Accept / Decline** with sender name, file count and total size. Trusted devices can be set to auto-accept (off by default).
- Tokens are **single-use** and short-lived; rate-limit pairing attempts (e.g., 5 / min / IP).
- Validate every incoming field: size caps, filename sanitization, mime sniffing not trusted, **no path traversal**, disk-space check before accepting.
- Don't log file contents or tokens. Provide a "Clear history" button.
- Receiver saves only into the chosen download folder; never auto-open/execute received files.
- Add a **"Visible to: Everyone / Trusted only / Hidden"** setting and a **quick toggle** to stop the server.

---

## 7. UI / UX spec — "Neon glow"

**Style**: dark, minimal, premium. Think glass cards + neon edge glow.

- Colors: background `#0B0D12`, surface `#141824`, primary glow cyan `#00E5FF`, secondary violet `#8B5CF6`, success `#22C55E`, danger `#FF4D6D`. Support light theme + system theme.
- **Glow** implementation: `BoxShadow` layers with the accent color (blur 16–40, low opacity), animated pulse on active elements, gradient borders (`SweepGradient` rotating slowly on the "Show QR" and active-transfer cards). Respect "reduce motion" accessibility setting and keep 60 fps (use `RepaintBoundary`, avoid heavy blur on long lists).
- Fonts: Inter / Space Grotesk (bundled, not fetched at runtime).

**Screens**
1. **Home**: top = my device name + status pill; center = **radar animation** with nearby devices as glowing bubbles; bottom = big buttons **Send files**, **Send text**, **Scan QR**, **Show my QR**. Drag-and-drop zone on desktop (whole window glows on hover).
2. **Send sheet**: selected items, target device picker, **Send** button with glowing progress ring.
3. **Incoming request dialog**: sender avatar, file list, size, Accept / Decline, "Always trust" toggle.
4. **Transfer screen**: per-file progress, speed (MB/s), ETA, pause/cancel, completion checkmark animation, "Open / Show in folder".
5. **QR screen**: giant QR in glowing frame, 2-minute countdown ring, "Copy link" button; scan mode with viewfinder and haptic on success.
6. **Clipboard sync**: toggle per device, last 20 items list with copy buttons.
7. **History**: sent/received list with search; tap to open.
8. **Settings**: device name, download folder, visibility, auto-accept, clipboard sync, theme, launch at startup, "About / licenses".

Microinteractions: haptics on mobile, subtle success sound (optional), skeleton loaders, smooth hero transitions. Make everything usable with keyboard on desktop. Add an **onboarding** (3 slides) explaining permissions.

**Desktop extras**: system tray icon (Windows/Linux/macOS) with "Send clipboard", "Show window", "Quit"; minimize to tray; drag files onto the tray/window; context-menu integration ("Send with FlowDrop") as a later phase.

**Mobile extras**: appears in the **system Share sheet** (Android share target, iOS Share Extension) so any app can share to FlowDrop; foreground service/notification on Android for ongoing transfers.

---

## 8. Platform-specific must-know list (common causes of "it doesn't work")

### Android
- Permissions: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `NEARBY_WIFI_DEVICES` (13+), `CAMERA` (QR), `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE` (+ type `dataSync`), Bluetooth `BLUETOOTH_SCAN/ADVERTISE/CONNECT` (12+).
- **Acquire a `MulticastLock`** or mDNS/UDP discovery silently fails on many phones.
- Use scoped storage / SAF correctly; save to Downloads via MediaStore on Android 10+.
- Run long transfers in a **foreground service** or Android kills them in the background.
- Set `usesCleartextTraffic=false`; we use TLS with pinned self-signed certs via a custom `SecurityContext`/`badCertificateCallback` that checks the fingerprint (never blanket-accept).

### iOS
- `Info.plist`: `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_flowdrop._tcp`), `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`.
- Server only runs while the app is foregrounded (iOS suspends sockets in background); use `beginBackgroundTask` for short grace period and tell users clearly.
- Share Extension needs an **App Group** to hand files to the main app.
- Needs a Mac + Xcode to build/sign; GitHub Actions `macos-latest` can build unsigned.

### Windows
- First run triggers Windows Firewall prompt: add an inbound rule programmatically at install (MSIX/Inno Setup script) or show a guided message.
- Public vs Private network profile can block discovery: detect and show a hint.
- Installer: **MSIX** and a portable `.zip`; optionally Inno Setup `.exe`.

### macOS
- Entitlements: `com.apple.security.network.server`, `com.apple.security.network.client`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.downloads.read-write`. Disable or properly configure App Sandbox. Add `NSLocalNetworkUsageDescription`, `NSBonjourServices`, camera description.
- Distribute `.dmg`; mention Gatekeeper/notarization steps in docs.

### Linux
- Build as **AppImage**, **.deb**, and optionally **Flatpak** / Snap.
- Needs `libgtk-3`, avahi (for mDNS) — fall back to the UDP beacon if avahi is missing.
- Firewall (`ufw`/`firewalld`): document `ufw allow 53317/tcp` and `53318/udp` and show an in-app hint if peers never appear.
- Wayland: clipboard monitoring can be restricted — degrade gracefully (manual "Send clipboard" button).

### Cross-cutting
- **AP/client isolation** on guest Wi-Fi blocks device-to-device traffic. Detect "I can see the network but no peers" and suggest hotspot or QR.
- Multiple network interfaces: advertise and bind on all, prefer private ranges, skip virtual adapters (Docker, VPN, VirtualBox) when listing IPs for the QR.
- IPv4 first; support IPv6 link-local later.
- Handle IP changes (Wi-Fi roam) by re-advertising and re-connecting.
- Use a **keep-awake** (wakelock) during transfers.
- Handle file names with unicode, very long paths, and duplicate names (`file (1).ext`).

---

## 9. Performance requirements

- Target: ≥ **80% of link speed** on 5 GHz Wi-Fi (e.g., 40+ MB/s on typical routers) for one large file.
- UI stays 60 fps during transfers: progress updates throttled to ~10–15 Hz, work in isolates.
- Memory: flat during a 10 GB transfer (< 150 MB growth).
- Cold start to usable < 1.5 s on mid-range phones.
- Build a **benchmark tool** (`tool/benchmark.dart`) that runs sender/receiver locally and prints MB/s for chunk sizes 256 KB, 1 MB, 4 MB, 8 MB so tuning is data-driven.

---

## 10. Testing

- **Unit tests**: protocol models, QR payload encode/decode/expiry, fingerprint verification, path sanitization, resume offsets, checksum, clipboard loop prevention.
- **Integration tests**: two in-process app instances send files/text to each other over loopback; tests for decline, cancel, resume after killed connection, expired token, wrong fingerprint (must fail), path traversal attempt (must be rejected).
- **Manual test matrix** in `docs/TESTING.md`: each OS pair (Android↔Windows, iOS↔macOS, Linux↔Android, etc.) × (Wi-Fi, hotspot, QR) × (small file, 2 GB file, 500 small files, text, clipboard).
- Lint with `flutter_lints` strict, `dart format`, CI fails on warnings.

---

## 11. GitHub deliverables

Create:
- `README.md` — hero banner, GIF demo, features, supported platforms table, install links, **how it works** diagram, connection methods and limits, security model, build-from-source, FAQ/troubleshooting (firewall, AP isolation, iOS background).
- `LICENSE` (MIT or Apache-2.0), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue/PR templates, `CHANGELOG.md`.
- `docs/PROTOCOL.md` (full protocol spec so others can build compatible clients), `docs/ARCHITECTURE.md`, `docs/TESTING.md`.
- **GitHub Actions**
  - `ci.yml`: analyze + test on every push/PR.
  - `release.yml`: on tag `v*`, build and attach artifacts:
    - Android `.apk` (+ `.aab`)
    - Windows `.zip` / MSIX
    - Linux `.AppImage` + `.deb`
    - macOS `.dmg` (unsigned OK)
    - iOS: build job (unsigned) + docs for signing
- Conventional commits; semantic versioning; small, meaningful commits per feature.

---

## 12. Build plan (do in this order)

**Phase 1 — Skeleton**: Flutter project for all 5 platforms, folder structure, theme with glow widgets, navigation, device identity, settings storage, CI analyze/test.

**Phase 2 — Core transport (desktop↔desktop on loopback/LAN)**: HTTPS server with self-signed cert, `/v1/info`, `/v1/offer`, `/v1/upload`, streaming + SHA-256 + `.part` files, progress events, unit/integration tests, benchmark tool.

**Phase 3 — Discovery**: mDNS + UDP fallback, radar UI, nearby devices list, manual IP connect, Android multicast lock, iOS Bonjour config.

**Phase 4 — Send/Receive UX**: file picker, drag & drop, incoming accept/decline, transfer screen, history, save location, notifications, foreground service on Android.

**Phase 5 — QR pairing**: payload format, token + fingerprint pinning, show/scan screens, QR "share via link" one-shot download, expiry handling, security tests.

**Phase 6 — Text & clipboard**: send text/link cards, clipboard sync with loop prevention, tray + global hotkey on desktop.

**Phase 7 — Mobile share targets**: Android share intent, iOS Share Extension (App Group), "Send to FlowDrop" from other apps.

**Phase 8 — Resume, folders, parallel streams, polish**: resumable uploads, folder transfers, retries, speed tuning, animations, onboarding, accessibility, localization scaffolding (ARB).

**Phase 9 — Bluetooth LE helper (optional)**: nearby wake-up + payload exchange; document limits. Evaluate Wi-Fi Direct.

**Phase 10 — Packaging & release**: installers, release workflow, README with GIFs, v0.1.0 tag.

After each phase output: what was built, how to run/test it, known issues, next phase.

---

## 13. Definition of done (MVP)

- [ ] Android ↔ Windows ↔ Linux ↔ macOS can send/receive files and text over the same Wi-Fi and over a phone hotspot.
- [ ] QR pairing works both directions, token expires after 2 minutes, wrong fingerprint is rejected.
- [ ] Unknown senders always need confirmation; paths can't escape the download folder.
- [ ] 2 GB file transfers with flat memory, correct checksum, and resumes after Wi-Fi drop.
- [ ] Clipboard sync works between at least two desktop OSes and Android.
- [ ] Glow UI is smooth (no dropped frames on a mid-range phone).
- [ ] CI is green and a tagged release produces downloadable builds.
- [ ] README explains setup, limits (iOS background, Bluetooth), and troubleshooting.

---

## 14. Rules for you (the coding agent)

1. Don't invent package APIs: check the package's docs/`pub.dev` and the installed version before using it. If a package fails on a platform, say so and propose an alternative.
2. Prefer small, tested increments. Run `flutter analyze` and `flutter test` before every commit.
3. Never hard-code secrets, IPs, or absolute paths. Never disable TLS verification globally.
4. Keep the protocol versioned (`v=1`) so future versions stay compatible.
5. If something in this spec is impossible on a platform (e.g., iOS background server, Bluetooth file transfer), implement the best honest alternative and document it — don't fake it.
6. Ask me only when a decision blocks progress; otherwise choose the sensible default and note it in `docs/DECISIONS.md`.
7. Keep the code readable: small files, clear names, comments for non-obvious platform workarounds.

**Start now with Phase 1.** Create the repo structure, then show me the plan for Phase 2 before coding it.
