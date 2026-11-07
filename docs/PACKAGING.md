# Packaging & release (Phase 10)

FlowDrop ships from GitHub Releases. Tag a commit `v*` (e.g. `v0.1.0`) and
`.github/workflows/release.yml` runs `flutter analyze` + `flutter test`,
then builds all desktop/mobile targets and attaches artifacts to the
GitHub Release automatically.

## What each job builds

| Job | Artifact | Notes |
|---|---|---|
| `android` | `app-release.apk`, `app-release.aab` | Unsigned release build; sign the AAB with your keystore before handing to Play |
| `windows` | `flowdrop-windows.zip` | Contents of `build/windows/x64/runner/Release/` |
| `linux` | `flowdrop-linux.tar.gz` | Bundle dir tarred; needs `libgtk-3-dev` + `libsecret-1-dev` on the runner (already in the workflow) |
| `macos` | `FlowDrop-macos.zip` | zipped `.app`; unsigned (see below) |
| `ios` | simulator build (compile check only) | Distribution builds require an Apple Developer account — sign with `flutter build ios --release` + Xcode |

## Unsigned desktop downloads

Windows/macOS binaries on GitHub Releases are unsigned. Users will see
SmartScreen (Windows) / Gatekeeper (macOS, right-click → Open the first
time). To ship signed builds, add a signing step to `release.yml` with
your certificate credentials as GitHub secrets — keep keys out of git.

## Publishing a release

```powershell
gh auth refresh -s workflow   # once: lets pushes include .github/*
git tag v0.1.0
git push origin v0.1.0
```

Then visit the GitHub Release page to add notes and any extra assets.
For README demo GIFs, run the app on two devices, record, and drop the
files into `assets/` (note: `assets/` must be declared in `pubspec.yaml`
before the same commit so the release build includes them).
